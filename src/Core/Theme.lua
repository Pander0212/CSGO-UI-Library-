--[[
	Theme registry.

	Theme:Bind(instance, property, key, opts?)  – the property follows the theme key forever.
	    opts = function(value) -> propertyValue          (transform)
	        or { Transform = fn, Alpha = 0..1 (base transparency), NoAlpha = true,
	             Window = true (affected by WindowTransparency), Tween = true (animate this bind) }
	    Color bindings automatically drive the paired transparency property
	    (BackgroundColor3 -> BackgroundTransparency etc.) from the key "Alpha.<key>".
	Theme:BindGradient(uiGradient, key, opts?)  – gradient keys (colors, rotation, enabled, animated)
	Theme:Set(key, value)                       – tweens every bound instance live
]]
local Util = require("Core/Util")
local Signal = require("Core/Signal")
local Tween = require("Core/Tween")
local FS = require("Core/FS")
local Meta = require("Meta")
local BaseTheme = require("Skins/Base/Theme")

local RunService = Util.Services.RunService

local PAIR = {
	BackgroundColor3 = "BackgroundTransparency",
	TextColor3 = "TextTransparency",
	ImageColor3 = "ImageTransparency",
	Color = "Transparency", -- UIStroke
	TextStrokeColor3 = "TextStrokeTransparency",
	ScrollBarImageColor3 = "ScrollBarImageTransparency",
	PlaceholderColor3 = nil,
}

local Theme = {}
Theme.__index = Theme

function Theme.new(getSkinTheme)
	local self = setmetatable({}, Theme)
	self.GetSkinTheme = getSkinTheme
	self.Base = BaseTheme
	self.Meta = BaseTheme.Meta
	self.Order = BaseTheme.Order
	self.Sections = BaseTheme.Sections
	self.Values = Util.DeepCopy(BaseTheme.Defaults)
	self.Defaults = Util.DeepCopy(BaseTheme.Defaults)
	self.Overrides = { ["*"] = {} } -- ["*"] = global keys, [skinName] = per-skin overrides
	self.SkinName = nil
	self.Changed = Signal.new()
	self._binds = {} -- key -> weak{ inst -> { prop -> opts } }
	self._instKeys = setmetatable({}, { __mode = "k" }) -- inst -> { prop -> key }
	self._grads = setmetatable({}, { __mode = "k" }) -- UIGradient -> { Key, O }
	-- frames carrying a gradient: Roblox multiplies gradient colors with BackgroundColor3,
	-- so while the gradient is enabled the background is rendered white (gradient shows true colors)
	self._gradMask = setmetatable({}, { __mode = "k" }) -- GuiObject -> UIGradient
	self._animated = setmetatable({}, { __mode = "k" })
	self._animConn = nil
	self:_ensureAlpha()
	return self
end

function Theme:_ensureAlpha()
	for _, key in ipairs(self.Order) do
		if typeof(self.Defaults[key]) == "Color3" then
			local ak = "Alpha." .. key
			if self.Defaults[ak] == nil then
				self.Defaults[ak] = 0
			end
			if self.Values[ak] == nil then
				self.Values[ak] = self.Defaults[ak]
			end
		end
	end
end

function Theme:Get(key)
	return self.Values[key]
end

function Theme:IsColorKey(key)
	return typeof(self.Values[key]) == "Color3"
end

function Theme:MetaFor(key)
	if key:sub(1, 6) == "Alpha." then
		return { Section = "Colors", Type = "number", Min = 0, Max = 1 }
	end
	return self.Meta[key] or {}
end

---------------------------------------------------------------- coercion / serialization
function Theme:Coerce(key, value)
	local cur = self.Defaults[key]
	if cur == nil then
		cur = self.Values[key]
	end
	local t = typeof(cur)
	if t == "Color3" then
		if typeof(value) == "Color3" then
			return value
		end
		if type(value) == "string" then
			return Util.HexToColor(value)
		end
		if type(value) == "table" and value.__t then
			return Util.Deserialize(value)
		end
		return nil
	elseif t == "number" then
		return tonumber(value)
	elseif t == "boolean" then
		if type(value) == "boolean" then
			return value
		end
		return value == "true"
	elseif t == "string" then
		return value ~= nil and tostring(value) or nil
	elseif t == "table" then
		if type(value) ~= "table" then
			return nil
		end
		local g = Util.DeepCopy(type(self.Values[key]) == "table" and self.Values[key] or cur)
		for k, v in pairs(value) do
			g[k] = v
		end
		local colors = {}
		for i, c in ipairs(g.Colors or {}) do
			if typeof(c) == "Color3" then
				colors[i] = c
			elseif type(c) == "string" then
				if c:sub(1, 1) == "#" then
					colors[i] = Util.HexToColor(c) or Color3.new(1, 1, 1)
				else
					colors[i] = c -- key reference
				end
			elseif type(c) == "table" and c.__t then
				colors[i] = Util.Deserialize(c)
			end
		end
		g.Colors = colors
		return g
	end
	if cur == nil then
		return value
	end
	return nil
end

function Theme:SerializeValue(v)
	if typeof(v) == "Color3" then
		return Util.ColorToHex(v)
	elseif type(v) == "table" then
		local g = Util.DeepCopy(v)
		local colors = {}
		for i, c in ipairs(v.Colors or {}) do
			colors[i] = typeof(c) == "Color3" and Util.ColorToHex(c) or c
		end
		g.Colors = colors
		return g
	end
	return v
end

---------------------------------------------------------------- binding
function Theme:_apply(inst, prop, key, o, animate)
	local raw = self.Values[key]
	if raw == nil then
		return
	end
	local value = raw
	if typeof(raw) == "Color3" and type(raw) ~= "table" then
		value = raw
	end
	if o.Transform then
		local ok, v = pcall(o.Transform, raw, self)
		if not ok then
			return
		end
		value = v
	end
	if prop == "BackgroundColor3" and typeof(value) == "Color3" then
		local mask = self._gradMask[inst]
		if mask and mask.Parent == inst and mask.Enabled then
			value = Color3.new(1, 1, 1)
		end
	end
	local props = { [prop] = value }
	local pair = PAIR[prop]
	if pair and typeof(raw) == "Color3" and not o.NoAlpha then
		local a = self.Values["Alpha." .. key] or 0
		local base = o.Alpha or 0
		local g = 0
		if o.Window then
			g = self.Values.WindowTransparency or 0
		end
		props[pair] = 1 - (1 - a) * (1 - base) * (1 - g)
	end
	if animate then
		Tween.Play(inst, props, o.Duration or 0.18)
	else
		for p, v in pairs(props) do
			pcall(function()
				inst[p] = v
			end)
		end
	end
end

function Theme:Bind(inst, prop, key, opts)
	if not inst then
		return
	end
	local o
	if type(opts) == "function" then
		o = { Transform = opts }
	else
		o = opts or {}
	end
	local keys = self._instKeys[inst]
	if not keys then
		keys = {}
		self._instKeys[inst] = keys
	end
	local old = keys[prop]
	if old and old ~= key and self._binds[old] and self._binds[old][inst] then
		self._binds[old][inst][prop] = nil
	end
	keys[prop] = key
	local list = self._binds[key]
	if not list then
		list = setmetatable({}, { __mode = "k" })
		self._binds[key] = list
	end
	list[inst] = list[inst] or {}
	list[inst][prop] = o
	self:_apply(inst, prop, key, o, o.Tween)
	return inst
end

function Theme:Unbind(inst, prop)
	local keys = self._instKeys[inst]
	if not keys then
		return
	end
	local function drop(p, k)
		if self._binds[k] and self._binds[k][inst] then
			self._binds[k][inst][p] = nil
		end
		keys[p] = nil
	end
	if prop then
		if keys[prop] then
			drop(prop, keys[prop])
		end
	else
		for p, k in pairs(keys) do
			drop(p, k)
		end
	end
end

-- Bind several props at once: Theme:BindMany(inst, { BackgroundColor3 = "Panel", TextColor3 = {"Text", {Alpha=0.2}} })
function Theme:BindMany(inst, map)
	for prop, spec in pairs(map) do
		if type(spec) == "table" then
			self:Bind(inst, prop, spec[1], spec[2])
		else
			self:Bind(inst, prop, spec)
		end
	end
	return inst
end

function Theme:ResolveColor(c)
	if type(c) == "string" then
		local v = self.Values[c]
		if typeof(v) == "Color3" then
			return v
		end
		return Util.HexToColor(c) or Color3.new(1, 1, 1)
	end
	return c
end

function Theme:GradientColors(key)
	local g = self.Values[key]
	local out = {}
	if type(g) == "table" then
		for i, c in ipairs(g.Colors or {}) do
			out[i] = self:ResolveColor(c)
		end
	end
	return out
end

function Theme:_applyGradient(grad, key, o)
	local g = self.Values[key]
	if type(g) ~= "table" then
		return
	end
	local colors = self:GradientColors(key)
	pcall(function()
		grad.Color = Util.Sequence(colors)
		grad.Rotation = o.Rotation or g.Rotation or 0
		grad.Enabled = o.Force == true or g.Enabled ~= false
	end)
	self:ReapplyProp(grad.Parent, "BackgroundColor3")
	if g.Animated and (o.Force or g.Enabled ~= false) and not o.Static then
		self._animated[grad] = { Key = key, Colors = colors, Speed = g.Speed or 0.5 }
	else
		self._animated[grad] = nil
	end
	self:_updateAnimator()
end

-- re-apply the current binding of one property (e.g. after a gradient was toggled)
function Theme:ReapplyProp(inst, prop)
	if not inst then
		return
	end
	local keys = self._instKeys[inst]
	local key = keys and keys[prop]
	local list = key and self._binds[key]
	local o = list and list[inst] and list[inst][prop]
	if o then
		self:_apply(inst, prop, key, o, false)
	end
end

-- mark `inst` as the carrier of `grad` (see _gradMask)
function Theme:MaskGradient(inst, grad)
	self._gradMask[inst] = grad
	self:ReapplyProp(inst, "BackgroundColor3")
end

function Theme:BindGradient(grad, key, opts)
	local o = opts or {}
	self._grads[grad] = { Key = key, O = o }
	self:_applyGradient(grad, key, o)
	return grad
end

-- Only one RenderStepped connection, only while an animated gradient exists.
function Theme:_updateAnimator()
	local any = next(self._animated) ~= nil
	if any and not self._animConn and RunService then
		local acc, phase = 0, 0
		self._animConn = RunService.RenderStepped:Connect(function(dt)
			acc += dt
			if acc < 1 / 30 then
				return
			end
			local step = acc
			acc = 0
			local alive = false
			for grad, info in pairs(self._animated) do
				if grad.Parent == nil then
					self._animated[grad] = nil
				else
					alive = true
					info.Phase = ((info.Phase or 0) + step * info.Speed) % 1
					local parent = grad.Parent
					if not parent:IsA("GuiObject") or parent.Visible then
						local kps = {}
						local n = 8
						for i = 0, n do
							table.insert(kps, ColorSequenceKeypoint.new(i / n, Util.SampleCyclic(info.Colors, i / n * 0.999 + info.Phase)))
						end
						grad.Color = ColorSequence.new(kps)
					end
				end
			end
			phase += step
			if not alive then
				self._animConn:Disconnect()
				self._animConn = nil
			end
		end)
	elseif not any and self._animConn then
		self._animConn:Disconnect()
		self._animConn = nil
	end
end

---------------------------------------------------------------- setting values
local function gradRefs(g, key)
	if type(g) ~= "table" then
		return false
	end
	for _, c in ipairs(g.Colors or {}) do
		if c == key then
			return true
		end
	end
	return false
end

function Theme:_refresh(key, animate)
	local binds = self._binds[key]
	if binds then
		for inst, props in pairs(binds) do
			for prop, o in pairs(props) do
				self:_apply(inst, prop, key, o, animate)
			end
		end
	end
	if key:sub(1, 6) == "Alpha." then
		self:_refresh(key:sub(7), animate)
		return
	end
	if key == "WindowTransparency" then
		for k, list in pairs(self._binds) do
			for inst, props in pairs(list) do
				for prop, o in pairs(props) do
					if o.Window then
						self:_apply(inst, prop, k, o, animate)
					end
				end
			end
		end
	end
	for grad, info in pairs(self._grads) do
		if info.Key == key or gradRefs(self.Values[info.Key], key) then
			self:_applyGradient(grad, info.Key, info.O)
		end
	end
	if key == "AnimationsEnabled" or key == "AnimationSpeed" or key == "EasingStyle" or key == "EasingDirection" then
		self:_syncTween()
	end
end

function Theme:_syncTween()
	local v = self.Values
	Tween.Configure(v.AnimationsEnabled, v.AnimationSpeed, v.EasingStyle, v.EasingDirection)
end

function Theme:_overrideTable(key)
	local meta = self:MetaFor(key)
	local scope = meta.Global and "*" or (self.SkinName or "*")
	self.Overrides[scope] = self.Overrides[scope] or {}
	return self.Overrides[scope]
end

-- Theme:Set(key, value, { Instant = bool, NoOverride = bool, Silent = bool })
function Theme:Set(key, value, opts)
	opts = opts or {}
	local v = self:Coerce(key, value)
	if v == nil then
		warn(("[Theme] invalid value for key '%s'"):format(tostring(key)))
		return false
	end
	self.Values[key] = v
	if not opts.NoOverride then
		local ov = self:_overrideTable(key)
		if Util.DeepEqual(v, self.Defaults[key]) then
			ov[key] = nil
		else
			ov[key] = Util.DeepCopy(v)
		end
	end
	self:_refresh(key, not opts.Instant)
	if not opts.Silent then
		self.Changed:Fire(key, v)
	end
	return true
end

function Theme:SetMany(map, opts)
	for k, v in pairs(map) do
		self:Set(k, v, opts)
	end
end

function Theme:RefreshAll(animate)
	for key in pairs(self.Values) do
		self:_refresh(key, animate)
	end
end

---------------------------------------------------------------- skins & presets
function Theme:LoadSkin(name)
	self.SkinName = name
	local skinTheme = self.GetSkinTheme and self.GetSkinTheme(name) or {}
	local d = Util.DeepCopy(BaseTheme.Defaults)
	for k, v in pairs(skinTheme.Defaults or {}) do
		d[k] = Util.DeepCopy(v)
	end
	self.Defaults = d
	self.Values = Util.DeepCopy(d)
	self:_ensureAlpha()
	for k, v in pairs(self.Overrides["*"] or {}) do
		self.Values[k] = Util.DeepCopy(v)
	end
	for k, v in pairs(self.Overrides[name] or {}) do
		self.Values[k] = Util.DeepCopy(v)
	end
	self:_syncTween()
	self:RefreshAll(false)
	self.Changed:Fire("*", nil)
end

function Theme:Presets()
	local skinTheme = self.GetSkinTheme and self.GetSkinTheme(self.SkinName) or {}
	local list = {}
	for name in pairs(skinTheme.Presets or {}) do
		table.insert(list, name)
	end
	table.sort(list, function(a, b)
		if a == "Default" then
			return true
		elseif b == "Default" then
			return false
		end
		return a < b
	end)
	if not table.find(list, "Default") then
		table.insert(list, 1, "Default")
	end
	for _, f in ipairs(FS.List(Meta.Folder .. "/themes", ".json")) do
		table.insert(list, "custom: " .. f)
	end
	return list
end

-- apply a built-in preset ("Default", "Midnight"...) or a saved one ("custom: name")
function Theme:ApplyPreset(name)
	if name:sub(1, 8) == "custom: " then
		local data = FS.Read(Meta.Folder .. "/themes/" .. name:sub(9) .. ".json")
		if not data then
			return false, "preset not found"
		end
		local ok, t = pcall(Util.JSONDecode, data)
		if not ok or type(t) ~= "table" then
			return false, "preset file is corrupt"
		end
		return self:ImportTable(t)
	end
	local skinTheme = self.GetSkinTheme and self.GetSkinTheme(self.SkinName) or {}
	local preset = (skinTheme.Presets or {})[name] or {}
	self.Overrides[self.SkinName] = {}
	for k, v in pairs(preset) do
		self.Overrides[self.SkinName][k] = Util.DeepCopy(v)
	end
	local keepGlobal = self.Overrides["*"]
	self.Overrides["*"] = keepGlobal
	self:LoadSkin(self.SkinName)
	return true
end

function Theme:SavePreset(name)
	if type(name) ~= "string" or name == "" then
		return false, "invalid name"
	end
	name = name:gsub("[^%w%-%_ ]", "")
	FS.MakeFolder(Meta.Folder .. "/themes")
	local ok, json = pcall(Util.JSONEncode, self:ExportTable(true))
	if not ok then
		return false, "encode failed"
	end
	return FS.Write(Meta.Folder .. "/themes/" .. name .. ".json", json)
end

function Theme:DeletePreset(name)
	name = name:gsub("^custom: ", "")
	return FS.Delete(Meta.Folder .. "/themes/" .. name .. ".json")
end

-- Reset one section (e.g. "Colors") or everything when section == nil
function Theme:Reset(section)
	for _, scope in ipairs({ "*", self.SkinName }) do
		local ov = self.Overrides[scope]
		if ov then
			for k in pairs(ov) do
				local meta = self:MetaFor(k)
				if section == nil or meta.Section == section then
					ov[k] = nil
				end
			end
		end
	end
	self:LoadSkin(self.SkinName)
end

---------------------------------------------------------------- export / import
-- currentOnly: only overrides of the current skin + global
function Theme:ExportTable(currentOnly)
	local out = { skin = self.SkinName, overrides = {} }
	for scope, ov in pairs(self.Overrides) do
		if not currentOnly or scope == "*" or scope == self.SkinName then
			local t = {}
			for k, v in pairs(ov) do
				t[k] = self:SerializeValue(v)
			end
			out.overrides[scope] = t
		end
	end
	return out
end

function Theme:ImportTable(t, opts)
	if type(t) ~= "table" or type(t.overrides) ~= "table" then
		return false, "invalid theme data"
	end
	opts = opts or {}
	for scope, ov in pairs(t.overrides) do
		if type(ov) == "table" then
			local target = {}
			for k, v in pairs(ov) do
				local savedSkin = self.SkinName
				-- coerce against base defaults (skin defaults only differ in value, not type)
				local def = BaseTheme.Defaults[k]
				if def == nil and k:sub(1, 6) == "Alpha." then
					def = 0
				end
				if def ~= nil then
					local tmpDefaults = self.Defaults
					self.Defaults = BaseTheme.Defaults
					local cv = (k:sub(1, 6) == "Alpha.") and tonumber(v) or self:Coerce(k, v)
					self.Defaults = tmpDefaults
					if cv ~= nil then
						target[k] = cv
					end
				end
				self.SkinName = savedSkin
			end
			self.Overrides[scope] = target
		end
	end
	if not opts.NoReload then
		self:LoadSkin(self.SkinName)
	end
	return true
end

function Theme:ExportString()
	local ok, json = pcall(Util.JSONEncode, self:ExportTable(true))
	if not ok then
		return nil
	end
	return Meta.ExportPrefix .. "-THEME:" .. json
end

function Theme:ImportString(s)
	if type(s) ~= "string" then
		return false, "no string"
	end
	local prefix = Meta.ExportPrefix .. "-THEME:"
	if s:sub(1, #prefix) == prefix then
		s = s:sub(#prefix + 1)
	end
	local ok, t = pcall(Util.JSONDecode, s)
	if not ok then
		return false, "invalid theme string"
	end
	return self:ImportTable(t)
end

function Theme:Destroy()
	if self._animConn then
		self._animConn:Disconnect()
		self._animConn = nil
	end
	self.Changed:Destroy()
end

return Theme
