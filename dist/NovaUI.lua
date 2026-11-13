-- Nova UI v1.0.0 (bundled build – do not edit, edit /src and run build/build.py)
-- built 2026-11-13 20:46 UTC
local __MODULES, __CACHE, __LOADING = {}, {}, {}
local function __require(name)
	local cached = __CACHE[name]
	if cached ~= nil then
		return cached
	end
	local fn = __MODULES[name]
	if not fn then
		error("[bundle] module not found: " .. tostring(name), 2)
	end
	if __LOADING[name] then
		error("[bundle] circular require: " .. tostring(name), 2)
	end
	__LOADING[name] = true
	local result = fn(__require)
	__LOADING[name] = nil
	if result == nil then
		result = true
	end
	__CACHE[name] = result
	return result
end
__MODULES["Components/Element"] = function(require)
--[[
	Element: the ONE shared logic layer for every component kind.
	Skins only render; they receive the element and call element:Set(...) on interaction,
	and the element calls view:Update(value) whenever the value changes.

	Common options: Name/Text, Flag, Default, Callback, Tooltip, Disabled, Visible,
	                IgnoreConfig (load silently, no callback), NoSave (never saved), Pinnable (toggles)
	Common methods: :Set(v, {Silent, Instant}) :Get() :SetVisible(b) :SetDisabled(b) :SetTooltip(s)
	                :OnChanged(fn) :Destroy()
	Addons:         :AddColorPicker(opts) :AddKeybind(opts) :AddSubOptions(opts) -> Group-like
]]
local Signal = require("Core/Signal")
local Types = require("Components/Types")
local Util = require("Core/Util")

local Element = {}
Element.__index = Element

local orderCounter = 0

function Element.new(lib, kind, parent, opts)
	opts = opts or {}
	local def = Types[kind]
	assert(def, "unknown component kind " .. tostring(kind))
	orderCounter += 1
	local self = setmetatable({
		Kind = kind,
		Library = lib,
		Parent = parent, -- Group, or Element for addons
		Options = opts,
		Def = def,
		Flag = opts.Flag,
		Name = opts.Name or opts.Text or opts.Title or kind,
		Tooltip = opts.Tooltip,
		Visible = opts.Visible ~= false,
		Disabled = opts.Disabled == true,
		Savable = def.Savable == true and opts.Flag ~= nil,
		Addons = {},
		Order = orderCounter,
		Changed = Signal.new(),
	}, Element)
	if def.Init then
		def.Init(self, opts)
	end
	if def.Normalize then
		self.Value = def.Normalize(self, opts.Default)
	else
		self.Value = opts.Default
	end
	if self.Flag then
		lib.Flags:Register(self)
	end
	if kind == "Keybind" then
		lib:_registerKeybind(self)
	end
	if kind == "ColorPicker" and self.Value and self.Value.Rainbow then
		lib:_rainbow(self, true)
	end
	return self
end

function Element:Get()
	return self.Value
end

-- readable name outside of its group (pins, keybind list): "Enabled" -> "Triggerbot"
local GENERIC = { Enabled = true, Enable = true, Active = true, Toggle = true, On = true }
function Element:ShortName()
	if self.Options.PinLabel then
		return self.Options.PinLabel
	end
	local owner = self.Parent
	if owner and getmetatable(owner) == Element then
		return owner:ShortName()
	end
	if GENERIC[self.Name] and self.Group and self.Group.Name then
		return self.Group.Name
	end
	return self.Name
end

function Element:FireCallback(value)
	local cb = self.Options.Callback
	if type(cb) == "function" then
		task.spawn(function()
			local ok, err = pcall(cb, value)
			if not ok then
				warn(("[%s] callback error (%s): %s"):format(self.Library.Name or "UI", self.Name, tostring(err)))
			end
		end)
	end
end

-- Set(value, { Silent = no callback, Instant = no animation, Force = fire even if equal })
function Element:Set(value, opts)
	opts = opts or {}
	if self.Def.Normalize then
		value = self.Def.Normalize(self, value)
	end
	local changed = not Util.DeepEqual(self.Value, value)
	self.Value = value
	if self.Flag then
		self.Library.Flags.Values[self.Flag] = value
	end
	if self.View and self.View.Update then
		self.View:Update(value, opts.Instant)
	end
	if self.Kind == "ColorPicker" then
		self.Library:_rainbow(self, value.Rainbow)
	end
	if changed or opts.Force then
		self.Changed:Fire(value)
		if self.Flag then
			self.Library.Flags.Changed:Fire(self.Flag, value)
		end
		if not opts.Silent then
			self:FireCallback(value)
		end
	end
	return self
end

function Element:OnChanged(fn)
	return self.Changed:Connect(fn)
end

function Element:Serialize()
	return self.Def.Serialize(self, self.Value)
end

function Element:Deserialize(raw)
	return self.Def.Deserialize(self, raw)
end

function Element:SetVisible(v)
	self.Visible = v ~= false
	if self.View and self.View.Root then
		self.View.Root.Visible = self.Visible
	end
	return self
end

function Element:SetDisabled(v)
	self.Disabled = v == true
	if self.View and self.View.SetDisabled then
		self.View:SetDisabled(self.Disabled)
	end
	return self
end

function Element:SetTooltip(text)
	self.Tooltip = text
	return self
end

function Element:IsDisabled()
	if self.Disabled then
		return true
	end
	local p = self.Parent
	if p and getmetatable(p) == Element then
		return p:IsDisabled()
	end
	return false
end

---------------------------------------------------------------- kind specific helpers
function Element:SetText(text)
	self.Name = text
	self.Options.Text = text
	if self.View and self.View.SetText then
		self.View:SetText(text)
	end
	return self
end

function Element:SetContent(text) -- Paragraph
	self.Options.Content = text
	if self.View and self.View.SetContent then
		self.View:SetContent(text)
	end
	return self
end

-- Dropdown: replace the value list
function Element:Refresh(values, keepSelection)
	assert(self.Kind == "Dropdown", "Refresh is only available on dropdowns")
	self.Options.Values = values or {}
	local v = keepSelection == false and (self.Options.Multi and {} or nil) or self.Value
	self.Value = self.Def.Normalize(self, v)
	if self.View and self.View.Refresh then
		self.View:Refresh()
	end
	self:Set(self.Value, { Force = true, Silent = true })
	return self
end
Element.SetValues = Element.Refresh

function Element:SetMin(v)
	self.Options.Min = v
	self:Set(self.Value)
	return self
end

function Element:SetMax(v)
	self.Options.Max = v
	self:Set(self.Value)
	return self
end

-- Button: fire programmatically
function Element:Press()
	if self.Kind == "Button" then
		self:FireCallback(nil)
	elseif self.Kind == "Toggle" then
		self:Set(not self.Value)
	end
end

-- Keybind runtime state
function Element:SetState(state)
	self.State = state == true
	if self.Options.OnPress then
		task.spawn(pcall, self.Options.OnPress, self.State)
	end
	self.Library:_keybindStateChanged(self)
end

function Element:KeyText()
	local v = self.Value
	return Types.KeyDisplay(v and v.Key)
end

---------------------------------------------------------------- addons
function Element:_addon(kind, opts)
	opts = opts or {}
	opts.Inline = true
	local el = Element.new(self.Library, kind, self, opts)
	el.Group = self.Group
	table.insert(self.Addons, el)
	if self.View and self.Library.Renderer then
		self.Library.Renderer:RenderAddon(self, el)
	end
	return el
end

function Element:AddColorPicker(opts)
	opts = opts or {}
	opts.Name = opts.Name or opts.Title or (self.Name .. " color")
	self:_addon("ColorPicker", opts)
	return self -- chainable like skeet: Toggle:AddColorPicker():AddKeybind()
end

function Element:AddKeybind(opts)
	opts = opts or {}
	opts.Name = opts.Name or self.Name
	self:_addon("Keybind", opts)
	return self
end

-- returns the addon elements by kind (for direct access)
function Element:GetAddon(kind, index)
	local n = 0
	for _, a in ipairs(self.Addons) do
		if a.Kind == kind then
			n += 1
			if n == (index or 1) then
				return a
			end
		end
	end
	return nil
end

-- Gear icon + popout panel with more elements. Returns a Group-like container.
function Element:AddSubOptions(opts)
	opts = opts or {}
	local Group = require("Components/Group")
	opts.Name = opts.Name or (self.Name .. " settings")
	local sub = Group.new(self.Library, nil, opts)
	sub.IsPopout = true
	sub.Owner = self
	self.SubGroup = sub
	if self.View and self.View.SetHasSub then
		self.View:SetHasSub(true)
	end
	return sub
end

function Element:Pin(state)
	if self.Kind ~= "Toggle" then
		return
	end
	if self.Library.Mobile then
		if state == false then
			self.Library.Mobile:Unpin(self)
		else
			self.Library.Mobile:Pin(self)
		end
	end
end

function Element:Destroy()
	self.Library.Flags:Unregister(self)
	if self.Kind == "Keybind" then
		self.Library:_unregisterKeybind(self)
	end
	self.Changed:Destroy()
	if self.View and self.View.Root then
		self.View.Root:Destroy()
	end
	self.View = nil
end

return Element
end
__MODULES["Components/Group"] = function(require)
--[[
	Group (group box / section). Holds elements; every Add* returns the element logic object.
	Also used for sub-option popouts (Element:AddSubOptions()).
]]
local Element = require("Components/Element")

local Group = {}
Group.__index = Group

local counter = 0

function Group.new(lib, page, opts)
	opts = opts or {}
	counter += 1
	return setmetatable({
		Library = lib,
		Page = page, -- SubTab (nil for popouts)
		Name = opts.Name or opts.Title or "Group",
		Side = (opts.Side == "Right" or opts.Side == 2) and "Right" or "Left",
		Icon = opts.Icon,
		Options = opts,
		Elements = {},
		Order = counter,
		Visible = opts.Visible ~= false,
	}, Group)
end

function Group:_add(kind, opts)
	opts = opts or {}
	local el = Element.new(self.Library, kind, self, opts)
	el.Group = self
	table.insert(self.Elements, el)
	if self.View and self.Library.Renderer then
		self.Library.Renderer:RenderElement(el, self)
	end
	return el
end

function Group:AddToggle(opts)
	return self:_add("Toggle", opts)
end
Group.AddCheckbox = Group.AddToggle

function Group:AddSlider(opts)
	return self:_add("Slider", opts)
end

function Group:AddDropdown(opts)
	return self:_add("Dropdown", opts)
end

function Group:AddTextbox(opts)
	return self:_add("Textbox", opts)
end
Group.AddInput = Group.AddTextbox

function Group:AddKeybind(opts)
	return self:_add("Keybind", opts)
end

function Group:AddColorPicker(opts)
	return self:_add("ColorPicker", opts)
end

function Group:AddButton(opts, cb)
	if type(opts) == "string" then
		opts = { Name = opts, Callback = cb }
	end
	return self:_add("Button", opts)
end

function Group:AddLabel(opts)
	if type(opts) == "string" then
		opts = { Text = opts }
	end
	return self:_add("Label", opts)
end

function Group:AddParagraph(opts)
	return self:_add("Paragraph", opts)
end

function Group:AddDivider(opts)
	if type(opts) == "string" then
		opts = { Text = opts }
	end
	return self:_add("Divider", opts or {})
end

function Group:AddESPPreview(opts)
	return self:_add("ESPPreview", opts or {})
end

--[[
	Convenience: creates the standard ESP flags that the preview binds to
	(see ESPPreview.DefaultFlags). Returns a table of the created elements.
]]
function Group:AddESPSettings(opts)
	opts = opts or {}
	local ESP = require("ESPPreview")
	local F = ESP.ResolveFlags(opts.Flags)
	local C = Color3.fromRGB
	local out = {}
	out.Enabled = self:AddToggle({ Name = "Enabled", Flag = F.Enabled, Default = true, Pinnable = true })
	out.Box = self:AddToggle({ Name = "Bounding box", Flag = F.Box, Default = true }):AddColorPicker({ Flag = F.BoxColor, Default = C(255, 255, 255) })
	out.BoxType = self:AddDropdown({ Name = "Box type", Flag = F.BoxType, Values = { "2D", "Corner", "Filled" }, Default = "2D" })
	out.Name = self:AddToggle({ Name = "Name", Flag = F.Name, Default = true }):AddColorPicker({ Flag = F.NameColor, Default = C(255, 255, 255) })
	out.Distance = self:AddToggle({ Name = "Distance", Flag = F.Distance, Default = true })
	out.Health = self:AddToggle({ Name = "Health bar", Flag = F.HealthBar, Default = true })
	out.HealthSide = self:AddDropdown({ Name = "Health bar side", Flag = F.HealthSide, Values = { "Left", "Right", "Top", "Bottom" }, Default = "Left" })
	out.Tracer = self:AddToggle({ Name = "Tracer", Flag = F.Tracer, Default = false }):AddColorPicker({ Flag = F.TracerColor, Default = C(255, 255, 255) })
	out.Skeleton = self:AddToggle({ Name = "Skeleton", Flag = F.Skeleton, Default = false }):AddColorPicker({ Flag = F.SkeletonColor, Default = C(255, 255, 255) })
	out.Chams = self:AddToggle({ Name = "Chams", Flag = F.Chams, Default = false }):AddColorPicker({ Flag = F.ChamsColor, Default = C(160, 90, 255), Transparency = 0.3 })
	return out
end

function Group:SetVisible(v)
	self.Visible = v ~= false
	if self.View and self.View.Root then
		self.View.Root.Visible = self.Visible
	end
end

return Group
end
__MODULES["Components/Tab"] = function(require)
--[[
	Tab + SubTab logic. A tab always has at least one SubTab (created lazily);
	skins decide where sub-tab buttons are drawn and hide them when there is only one.
]]
local Group = require("Components/Group")

local SubTab = {}
SubTab.__index = SubTab

function SubTab.new(tab, opts)
	if type(opts) == "string" then
		opts = { Name = opts }
	end
	opts = opts or {}
	return setmetatable({ Tab = tab, Library = tab.Library, Name = opts.Name or "Main", Icon = opts.Icon, Groups = {} }, SubTab)
end

function SubTab:AddGroup(opts)
	if type(opts) == "string" then
		opts = { Name = opts }
	end
	local g = Group.new(self.Library, self, opts)
	table.insert(self.Groups, g)
	if self.PageView and self.Library.Renderer then
		self.Library.Renderer:RenderGroup(g)
	end
	return g
end
SubTab.AddSection = SubTab.AddGroup
SubTab.AddGroupbox = SubTab.AddGroup
function SubTab:AddLeftGroupbox(name)
	return self:AddGroup({ Name = name, Side = "Left" })
end
function SubTab:AddRightGroupbox(name)
	return self:AddGroup({ Name = name, Side = "Right" })
end

local Tab = {}
Tab.__index = Tab

function Tab.new(window, opts)
	if type(opts) == "string" then
		opts = { Name = opts }
	end
	opts = opts or {}
	return setmetatable({
		Window = window,
		Library = window.Library,
		Name = opts.Name or "Tab",
		Icon = opts.Icon or "dot",
		Category = opts.Category or opts.Section,
		Options = opts,
		SubTabs = {},
	}, Tab)
end

function Tab:AddSubTab(opts)
	local s = SubTab.new(self, opts)
	-- an implicit "Main" subtab that is still empty gets replaced by the first explicit one
	if #self.SubTabs == 1 and self.SubTabs[1].Implicit and #self.SubTabs[1].Groups == 0 then
		local old = self.SubTabs[1]
		self.SubTabs[1] = s
		if old.PageView and old.PageView.Root then
			old.PageView.Root:Destroy()
			old.PageView = nil
		end
	else
		table.insert(self.SubTabs, s)
	end
	if self.View and self.Library.Renderer then
		self.Library.Renderer:RenderSubTab(s)
	end
	return s
end

function Tab:_default()
	if #self.SubTabs == 0 then
		local s = SubTab.new(self, { Name = "Main" })
		s.Implicit = true
		table.insert(self.SubTabs, s)
		if self.View and self.Library.Renderer then
			self.Library.Renderer:RenderSubTab(s)
		end
	end
	return self.SubTabs[1]
end

function Tab:AddGroup(opts)
	return self:_default():AddGroup(opts)
end
Tab.AddSection = Tab.AddGroup
Tab.AddGroupbox = Tab.AddGroup
function Tab:AddLeftGroupbox(name)
	return self:AddGroup({ Name = name, Side = "Left" })
end
function Tab:AddRightGroupbox(name)
	return self:AddGroup({ Name = name, Side = "Right" })
end

function Tab:Select(sub)
	self.Window:SelectTab(self, sub)
end

Tab.SubTab = SubTab
return Tab
end
__MODULES["Components/Types"] = function(require)
--[[
	Types: the shared VALUE logic of every component kind (independent of any skin).
	  Init(el, opts)            normalise options
	  Normalize(el, value)      -> canonical value
	  Serialize(el, value)      -> JSON-safe value
	  Deserialize(el, raw)      -> value
	  Savable                   whether the value goes into configs
]]
local Util = require("Core/Util")

local Types = {}

local function identity(_, v)
	return v
end

---------------------------------------------------------------- Toggle
Types.Toggle = {
	Savable = true,
	Default = false,
	Normalize = function(_, v)
		return v == true
	end,
}

---------------------------------------------------------------- Slider
Types.Slider = {
	Savable = true,
	Init = function(el, o)
		o.Min = tonumber(o.Min) or 0
		o.Max = tonumber(o.Max) or 100
		if o.Max < o.Min then
			o.Min, o.Max = o.Max, o.Min
		end
		if o.Rounding and not o.Increment then
			o.Increment = 10 ^ -o.Rounding
		end
		o.Increment = tonumber(o.Increment) or 1
		el.Decimals = Util.Decimals(o.Increment)
		if o.Default == nil then
			o.Default = o.Min
		end
		o.Suffix = o.Suffix or ""
	end,
	Normalize = function(el, v)
		local o = el.Options
		v = tonumber(v) or o.Min
		return Util.Clamp(Util.Round(v, o.Increment), o.Min, o.Max)
	end,
	Format = function(el, v)
		local o = el.Options
		if o.Format then
			local ok, s = pcall(o.Format, v)
			if ok then
				return tostring(s)
			end
		end
		return Util.FormatNumber(v, el.Decimals) .. (o.Suffix or "")
	end,
}

---------------------------------------------------------------- Dropdown
Types.Dropdown = {
	Savable = true,
	Init = function(el, o)
		o.Values = o.Values or o.Options or o.Items or {}
		o.Multi = o.Multi == true
		if o.Default == nil then
			if o.Multi then
				o.Default = {}
			elseif o.AllowNull ~= true then
				o.Default = o.Values[1]
			end
		end
	end,
	Normalize = function(el, v)
		local o = el.Options
		local function valid(x)
			return o.AllowCustom or table.find(o.Values, x) ~= nil
		end
		if o.Multi then
			local set = {}
			if type(v) == "table" then
				for k, x in pairs(v) do
					if type(k) == "number" then
						set[x] = true
					elseif x == true then
						set[k] = true
					end
				end
			elseif v ~= nil then
				set[v] = true
			end
			local out = {}
			for _, x in ipairs(o.Values) do
				if set[x] then
					table.insert(out, x)
				end
			end
			return out
		end
		if type(v) == "table" then
			v = v[1]
		end
		if v ~= nil and valid(v) then
			return v
		end
		if o.AllowNull then
			return nil
		end
		return o.Values[1]
	end,
	Display = function(el, v)
		if el.Options.Multi then
			if type(v) ~= "table" or #v == 0 then
				return el.Options.Placeholder or "None"
			end
			return table.concat(v, ", ")
		end
		if v == nil then
			return el.Options.Placeholder or "None"
		end
		return tostring(v)
	end,
}

---------------------------------------------------------------- Textbox
Types.Textbox = {
	Savable = true,
	Init = function(_, o)
		if o.Default == nil then
			o.Default = ""
		end
	end,
	Normalize = function(el, v)
		v = v == nil and "" or tostring(v)
		if el.Options.Numeric then
			v = v:gsub("[^%d%.%-]", "")
		end
		if el.Options.MaxLength then
			v = v:sub(1, el.Options.MaxLength)
		end
		return v
	end,
}

---------------------------------------------------------------- Keybind
local SHORT = {
	LeftShift = "LSHIFT", RightShift = "RSHIFT", LeftControl = "LCTRL", RightControl = "RCTRL",
	LeftAlt = "LALT", RightAlt = "RALT", MB1 = "MB1", MB2 = "MB2", MB3 = "MB3", Return = "ENTER",
	Backspace = "BACK", CapsLock = "CAPS", Insert = "INS", Delete = "DEL", PageUp = "PGUP", PageDown = "PGDN",
	Space = "SPACE", Tab = "TAB", Escape = "ESC", Backquote = "`", LeftBracket = "[", RightBracket = "]",
	Semicolon = ";", Quote = "'", Comma = ",", Period = ".", Slash = "/", BackSlash = "\\", Minus = "-", Equals = "=",
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
}

local function keyName(k)
	if k == nil then
		return nil
	end
	if typeof(k) == "EnumItem" then
		if k.EnumType == Enum.UserInputType then
			if k == Enum.UserInputType.MouseButton1 then
				return "MB1"
			elseif k == Enum.UserInputType.MouseButton2 then
				return "MB2"
			elseif k == Enum.UserInputType.MouseButton3 then
				return "MB3"
			end
			return nil
		end
		return k.Name
	end
	if type(k) == "string" then
		if k == "" or k == "None" or k == "Unknown" then
			return nil
		end
		if k == "MouseButton1" then
			return "MB1"
		elseif k == "MouseButton2" then
			return "MB2"
		elseif k == "MouseButton3" then
			return "MB3"
		end
		return k
	end
	return nil
end

Types.KeyName = keyName
Types.Modes = { "Toggle", "Hold", "Always" }

function Types.KeyDisplay(key)
	if not key then
		return "-"
	end
	return SHORT[key] or string.upper(key)
end

Types.Keybind = {
	Savable = true,
	Init = function(el, o)
		o.Mode = o.Mode or "Toggle"
		if o.Default == nil then
			o.Default = { Key = nil, Mode = o.Mode }
		end
		el.State = false
	end,
	Normalize = function(el, v)
		local mode = el.Value and el.Value.Mode or el.Options.Mode or "Toggle"
		if type(v) == "table" and (v.Key ~= nil or v.Mode ~= nil) then
			return { Key = keyName(v.Key), Mode = table.find(Types.Modes, v.Mode) and v.Mode or mode }
		elseif type(v) == "table" then
			return { Key = nil, Mode = mode }
		end
		return { Key = keyName(v), Mode = mode }
	end,
	Serialize = function(_, v)
		return { Key = v.Key or "None", Mode = v.Mode }
	end,
	Deserialize = function(_, raw)
		return raw
	end,
}

-- does an InputObject match a key name?
function Types.MatchKey(input, key)
	if not key then
		return false
	end
	local t = input.UserInputType
	if key == "MB1" then
		return t == Enum.UserInputType.MouseButton1
	elseif key == "MB2" then
		return t == Enum.UserInputType.MouseButton2
	elseif key == "MB3" then
		return t == Enum.UserInputType.MouseButton3
	end
	return t == Enum.UserInputType.Keyboard and input.KeyCode.Name == key
end

---------------------------------------------------------------- ColorPicker
Types.ColorPicker = {
	Savable = true,
	Init = function(_, o)
		if o.Default == nil then
			o.Default = Color3.new(1, 1, 1)
		end
	end,
	Normalize = function(el, v)
		local cur = el.Value or {}
		if typeof(v) == "Color3" then
			return { Color = v, Transparency = cur.Transparency or el.Options.Transparency or 0, Rainbow = false }
		elseif type(v) == "string" then
			return { Color = Util.HexToColor(v) or Color3.new(1, 1, 1), Transparency = cur.Transparency or 0, Rainbow = false }
		elseif type(v) == "table" then
			local c = v.Color
			if type(c) == "string" then
				c = Util.HexToColor(c)
			end
			return {
				Color = typeof(c) == "Color3" and c or (cur.Color or Color3.new(1, 1, 1)),
				Transparency = Util.Clamp(tonumber(v.Transparency) or cur.Transparency or 0, 0, 1),
				Rainbow = v.Rainbow == true,
			}
		end
		return { Color = Color3.new(1, 1, 1), Transparency = 0, Rainbow = false }
	end,
	Serialize = function(_, v)
		return { Color = Util.ColorToHex(v.Color), Transparency = v.Transparency, Rainbow = v.Rainbow }
	end,
	Deserialize = function(_, raw)
		return raw
	end,
}

---------------------------------------------------------------- non-value components
Types.Button = { Savable = false }
Types.Label = { Savable = false }
Types.Paragraph = { Savable = false }
Types.Divider = { Savable = false }
Types.ESPPreview = { Savable = false }

for _, t in pairs(Types) do
	if type(t) == "table" then
		t.Serialize = t.Serialize or identity
		t.Deserialize = t.Deserialize or identity
	end
end

return Types
end
__MODULES["Components/Window"] = function(require)
--[[
	Window logic: tabs, categories, open state, position/size state, toggle key.
	The view (layout) is produced by the active skin; on UI:SetSkin the view is rebuilt from
	this logic tree so all values, the active tab and the window position survive.
]]
local Tab = require("Components/Tab")
local Signal = require("Core/Signal")
local Util = require("Core/Util")

local Types = require("Components/Types")

local Window = {}
Window.__index = Window

local function Types_keyName(k)
	return Types.KeyName(k)
end

function Window.new(lib, opts)
	opts = opts or {}
	local self = setmetatable({
		Library = lib,
		Options = opts,
		Title = opts.Title or opts.Name,
		Tabs = {},
		Categories = {},
		Open = true,
		ToggleKey = Types_keyName(opts.ToggleKey) or "RightShift",
		State = { Position = nil, Sizes = {}, Tab = nil, Sub = nil },
		VisibilityChanged = Signal.new(),
		TabChanged = Signal.new(),
	}, Window)
	if opts.Size and typeof(opts.Size) == "UDim2" then
		self.State.Sizes["*"] = { opts.Size.X.Offset, opts.Size.Y.Offset }
	elseif typeof(opts.Size) == "Vector2" then
		self.State.Sizes["*"] = { opts.Size.X, opts.Size.Y }
	end
	return self
end

function Window:AddCategory(name)
	if not table.find(self.Categories, name) then
		table.insert(self.Categories, name)
	end
	return name
end

function Window:AddTab(opts)
	local tab = Tab.new(self, opts)
	if tab.Category then
		self:AddCategory(tab.Category)
	end
	table.insert(self.Tabs, tab)
	if self.View and self.Library.Renderer then
		self.Library.Renderer:RenderTab(tab)
	end
	if not self.ActiveTab then
		self.ActiveTab = tab
	end
	return tab
end

function Window:GetTab(name)
	for _, t in ipairs(self.Tabs) do
		if t.Name == name then
			return t
		end
	end
	return nil
end

function Window:SelectTab(tab, sub)
	if type(tab) == "string" then
		tab = self:GetTab(tab)
	end
	if not tab then
		return
	end
	local subtab = sub
	if type(sub) == "string" then
		for _, s in ipairs(tab.SubTabs) do
			if s.Name == sub then
				subtab = s
			end
		end
	end
	tab:_default()
	subtab = subtab or tab.ActiveSub or tab.SubTabs[1]
	self.ActiveTab = tab
	tab.ActiveSub = subtab
	self.State.Tab = tab.Name
	self.State.Sub = subtab and subtab.Name
	if self.View and self.View.SelectTab then
		self.View:SelectTab(tab, subtab)
	end
	self.TabChanged:Fire(tab, subtab)
end

function Window:SetOpen(open, instant)
	self.Open = open ~= false
	if self.View and self.View.SetOpen then
		self.View:SetOpen(self.Open, instant)
	end
	self.VisibilityChanged:Fire(self.Open)
	if not self.Open then
		self.Library.Config:OnClose()
	end
end

function Window:Toggle()
	self:SetOpen(not self.Open)
end

function Window:SetToggleKey(key)
	self.ToggleKey = Types.KeyName(key)
end

-- size for the active skin: saved resize > CreateWindow size > theme default
function Window:GetSize()
	local lib = self.Library
	local s = self.State.Sizes[lib.SkinName] or self.State.Sizes["*"]
	local w, h
	if s then
		w, h = s[1], s[2]
	else
		w, h = lib.Theme:Get("WindowWidth"), lib.Theme:Get("WindowHeight")
	end
	-- fit the screen (mobile) below the top bar inset
	local vp = lib:ScreenSize()
	local top = Util.GuiInset().Y / (lib.CurrentScale or 1)
	w = math.min(w, vp.X - 16)
	h = math.min(h, vp.Y - top - 8)
	return Vector2.new(math.floor(w), math.floor(h))
end

function Window:SetSize(w, h)
	self.State.Sizes[self.Library.SkinName] = { w, h }
	if self.View and self.View.Root then
		self.View.Root.Size = UDim2.fromOffset(w, h)
	end
end

function Window:GetState()
	local pos = self.State.Position
	local size = self:GetSize()
	return {
		x = pos and pos.X or nil,
		y = pos and pos.Y or nil,
		w = size.X,
		h = size.Y,
		sizes = Util.DeepCopy(self.State.Sizes),
		tab = self.ActiveTab and self.ActiveTab.Name or nil,
		sub = self.ActiveTab and self.ActiveTab.ActiveSub and self.ActiveTab.ActiveSub.Name or nil,
		open = self.Open,
		key = self.ToggleKey,
	}
end

function Window:SetState(s)
	if type(s) ~= "table" then
		return
	end
	if tonumber(s.x) and tonumber(s.y) then
		self.State.Position = Vector2.new(s.x, s.y)
		if self.View and self.View.Root then
			self.View.Root.Position = UDim2.fromOffset(s.x, s.y)
		end
	end
	if type(s.sizes) == "table" then
		self.State.Sizes = s.sizes
		local cur = self:GetSize()
		if self.View and self.View.Root then
			self.View.Root.Size = UDim2.fromOffset(cur.X, cur.Y)
		end
	end
	if s.tab then
		self:SelectTab(s.tab, s.sub)
	end
end

-- position (top-left, in UI root space) – centered when never moved
function Window:GetPosition()
	if self.State.Position then
		return self.State.Position
	end
	local vp = self.Library:ScreenSize()
	local size = self:GetSize()
	-- centered in the area below the Roblox top bar (GuiService:GetGuiInset)
	local top = Util.GuiInset().Y / (self.Library.CurrentScale or 1)
	local y = top + math.max(0, (vp.Y - top - size.Y) / 2)
	return Vector2.new(math.floor((vp.X - size.X) / 2), math.floor(y))
end

function Window:AddThemeTab(opts)
	return require("Tabs/Appearance")(self, opts)
end

function Window:AddConfigTab(opts)
	return require("Tabs/ConfigTab")(self, opts)
end

function Window:Notify(opts)
	return self.Library:Notify(opts)
end

-- jump to an element (used by search)
function Window:Focus(element)
	local group = element.Group
	while group and group.IsPopout and group.Owner do
		group = group.Owner.Group
	end
	local sub = group and group.Page
	if not sub then
		return
	end
	self:SetOpen(true)
	self:SelectTab(sub.Tab, sub)
	if self.View and self.View.Focus then
		self.View:Focus(element)
	end
end

-- all searchable elements: { {Element, Path} }
function Window:Search(query)
	query = string.lower(query or "")
	local out = {}
	if query == "" then
		return out
	end
	for _, tab in ipairs(self.Tabs) do
		for _, sub in ipairs(tab.SubTabs) do
			for _, g in ipairs(sub.Groups) do
				for _, el in ipairs(g.Elements) do
					local name = tostring(el.Name or "")
					if el.Kind ~= "Divider" and string.find(string.lower(name), query, 1, true) then
						table.insert(out, { Element = el, Path = tab.Name .. " › " .. g.Name })
					end
				end
			end
		end
	end
	return out
end

return Window
end
__MODULES["Core/Config"] = function(require)
--[[
	Config system.
	  NovaUI/<PlaceId>/configs/<name>.json   – configs (flags, theme, skin, window, mobile)
	  NovaUI/themes/<name>.json               – theme presets (see Core/Theme.lua)
	  NovaUI/settings.json                    – autoload per place, autosave, misc settings

	API (UI.Config):
	  :Save(name, {Overwrite=bool})  :Load(name)  :Delete(name)  :Rename(old, new)  :Duplicate(name, new)
	  :List()  :Exists(name)  :SetAutoload(name|nil)  :GetAutoload()  :LoadAutoload()
	  :Export(name?) -> string   :Import(string, {Apply=true, SaveAs=name})
	  :SetAutoSave(enabled, intervalSeconds)  :SetSaveOnClose(bool)
	Everything is pcall'd; corrupt files raise a notification instead of an error.
]]
local Util = require("Core/Util")
local FS = require("Core/FS")
local Meta = require("Meta")
local Signal = require("Core/Signal")

local Config = {}
Config.__index = Config

-- Migrations: Migrations[n] upgrades data from version n to n + 1
Config.Migrations = {
	[1] = function(data)
		-- v1 stored flags under "values" and the theme as a flat table
		data.flags = data.flags or data.values or {}
		data.values = nil
		if data.theme and not data.theme.overrides then
			data.theme = { skin = data.skin, overrides = { [data.skin or Meta.DefaultSkin] = data.theme } }
		end
		data.version = 2
		return data
	end,
}

function Config.new(lib)
	local self = setmetatable({}, Config)
	self.Library = lib
	self.Root = Meta.Folder
	self.Folder = Meta.Folder .. "/" .. Util.PlaceId() .. "/configs"
	self.ThemeFolder = Meta.Folder .. "/themes"
	self.SettingsPath = Meta.Folder .. "/settings.json"
	self.Current = nil -- name of the last loaded / saved config
	self.Changed = Signal.new() -- (action, name)
	self.Settings = {
		version = Meta.SettingsVersion,
		autoload = {},
		autosave = { enabled = false, interval = 60 },
		saveOnClose = false,
		mobileMode = "Auto",
	}
	pcall(function()
		FS.MakeFolder(self.Folder)
		FS.MakeFolder(self.ThemeFolder)
	end)
	self:LoadSettings()
	return self
end

function Config:IsPersistent()
	return FS.Available()
end

---------------------------------------------------------------- settings.json
function Config:LoadSettings()
	local raw = FS.Read(self.SettingsPath)
	if not raw then
		return
	end
	local ok, data = pcall(Util.JSONDecode, raw)
	if ok and type(data) == "table" then
		for k, v in pairs(data) do
			self.Settings[k] = v
		end
	else
		self:_notify("Settings file is corrupt – using defaults", "Warning")
	end
end

function Config:SaveSettings()
	local ok, json = pcall(Util.JSONEncode, self.Settings)
	if ok then
		FS.Write(self.SettingsPath, json)
	end
end

---------------------------------------------------------------- helpers
local function cleanName(name)
	if type(name) ~= "string" then
		return nil
	end
	name = name:gsub("[^%w%-%_%. ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		return nil
	end
	return name
end
Config.CleanName = cleanName

function Config:Path(name)
	return self.Folder .. "/" .. name .. ".json"
end

function Config:_notify(text, kind)
	local lib = self.Library
	if lib and lib.Notify then
		pcall(lib.Notify, lib, { Title = "Config", Content = text, Type = kind or "Info" })
	end
end

function Config:List()
	return FS.List(self.Folder, ".json")
end

function Config:Exists(name)
	name = cleanName(name)
	return name ~= nil and FS.Exists(self:Path(name))
end

---------------------------------------------------------------- collect / apply
function Config:Collect(name)
	local lib = self.Library
	local flags = {}
	for flag, el in pairs(lib.Flags.Elements) do
		if el.Savable and not el.Options.NoSave then
			local ok, v = pcall(el.Serialize, el)
			if ok then
				flags[flag] = v
			end
		end
	end
	return {
		version = Meta.ConfigVersion,
		library = Meta.Name,
		name = name,
		saved = os.time(),
		skin = lib.SkinName,
		theme = lib.Theme:ExportTable(false),
		flags = flags,
		window = lib.Window and lib.Window:GetState() or nil,
		mobile = lib.Mobile and lib.Mobile:GetState() or nil,
		esp = lib.ESPState and Util.Serialize(lib.ESPState) or nil,
	}
end

function Config:Migrate(data)
	local v = tonumber(data.version) or 1
	while v < Meta.ConfigVersion do
		local m = Config.Migrations[v]
		if not m then
			break
		end
		data = m(data)
		v = tonumber(data.version) or (v + 1)
	end
	return data
end

function Config:Apply(data)
	local lib = self.Library
	data = self:Migrate(data)
	if type(data.theme) == "table" then
		lib.Theme:ImportTable(data.theme, { NoReload = true })
	end
	if type(data.skin) == "string" and lib.Skins:Get(data.skin) and data.skin ~= lib.SkinName then
		lib:SetSkin(data.skin, { Instant = true })
	else
		lib.Theme:LoadSkin(lib.SkinName)
	end
	if type(data.flags) == "table" then
		for flag, raw in pairs(data.flags) do
			local el = lib.Flags.Elements[flag]
			if el and el.Savable and not el.Options.NoSave then
				local ok, err = pcall(function()
					local value = el:Deserialize(raw)
					el:Set(value, { Silent = el.Options.IgnoreConfig == true, Force = el.Options.IgnoreConfig ~= true })
				end)
				if not ok then
					warn(("[Config] could not load flag %s: %s"):format(flag, tostring(err)))
				end
			end
		end
	end
	if data.window and lib.Window then
		lib.Window:SetState(data.window)
	end
	if data.mobile and lib.Mobile then
		lib.Mobile:SetState(data.mobile)
	end
	if type(data.esp) == "table" then
		lib.ESPState = Util.Deserialize(data.esp)
	end
end

---------------------------------------------------------------- public API
function Config:Save(name, opts)
	opts = opts or {}
	name = cleanName(name or self.Current)
	if not name then
		self:_notify("Enter a valid config name", "Error")
		return false, "invalid name"
	end
	if opts.Overwrite == false and self:Exists(name) then
		return false, "exists"
	end
	local ok, json = pcall(function()
		return Util.JSONEncode(self:Collect(name))
	end)
	if not ok then
		self:_notify("Saving failed: " .. tostring(json), "Error")
		return false, json
	end
	FS.MakeFolder(self.Folder)
	local _, where = FS.Write(self:Path(name), json)
	self.Current = name
	self.Changed:Fire("save", name)
	if not opts.Silent then
		self:_notify(("Saved '%s'%s"):format(name, where == "memory" and " (session only)" or ""), "Success")
	end
	return true
end

function Config:Load(name, opts)
	opts = opts or {}
	name = cleanName(name)
	if not name then
		return false, "invalid name"
	end
	local raw = FS.Read(self:Path(name))
	if not raw then
		self:_notify(("Config '%s' not found"):format(name), "Error")
		return false, "not found"
	end
	local ok, data = pcall(Util.JSONDecode, raw)
	if not ok or type(data) ~= "table" then
		self:_notify(("Config '%s' is corrupt and was not loaded"):format(name), "Error")
		return false, "corrupt"
	end
	local ok2, err = pcall(self.Apply, self, data)
	if not ok2 then
		self:_notify(("Config '%s' could not be applied: %s"):format(name, tostring(err)), "Error")
		return false, err
	end
	self.Current = name
	self.Changed:Fire("load", name)
	if not opts.Silent then
		self:_notify(("Loaded '%s'"):format(name), "Success")
	end
	return true
end

function Config:Delete(name)
	name = cleanName(name)
	if not name or not self:Exists(name) then
		return false, "not found"
	end
	FS.Delete(self:Path(name))
	if self:GetAutoload() == name then
		self:SetAutoload(nil)
	end
	if self.Current == name then
		self.Current = nil
	end
	self.Changed:Fire("delete", name)
	self:_notify(("Deleted '%s'"):format(name), "Info")
	return true
end

function Config:Rename(old, new)
	old, new = cleanName(old), cleanName(new)
	if not old or not new then
		return false, "invalid name"
	end
	local raw = FS.Read(self:Path(old))
	if not raw then
		return false, "not found"
	end
	if self:Exists(new) then
		return false, "exists"
	end
	FS.Write(self:Path(new), raw)
	FS.Delete(self:Path(old))
	if self:GetAutoload() == old then
		self:SetAutoload(new)
	end
	if self.Current == old then
		self.Current = new
	end
	self.Changed:Fire("rename", new)
	self:_notify(("Renamed '%s' → '%s'"):format(old, new), "Success")
	return true
end

function Config:Duplicate(name, new)
	name = cleanName(name)
	if not name then
		return false, "invalid name"
	end
	local raw = FS.Read(self:Path(name))
	if not raw then
		return false, "not found"
	end
	new = cleanName(new)
	if not new then
		local i = 1
		new = name .. " copy"
		while self:Exists(new) do
			i += 1
			new = name .. " copy " .. i
		end
	end
	FS.Write(self:Path(new), raw)
	self.Changed:Fire("duplicate", new)
	self:_notify(("Duplicated as '%s'"):format(new), "Success")
	return true, new
end

function Config:SetAutoload(name)
	self.Settings.autoload = self.Settings.autoload or {}
	self.Settings.autoload[Util.PlaceId()] = name and cleanName(name) or nil
	self:SaveSettings()
	self.Changed:Fire("autoload", name)
	return true
end

function Config:GetAutoload()
	return self.Settings.autoload and self.Settings.autoload[Util.PlaceId()] or nil
end

function Config:LoadAutoload()
	local name = self:GetAutoload()
	if name and self:Exists(name) then
		return self:Load(name)
	end
	return false
end

function Config:Export(name)
	local data
	if name then
		local raw = FS.Read(self:Path(cleanName(name) or ""))
		if not raw then
			return nil
		end
		data = raw
	else
		local ok, json = pcall(function()
			return Util.JSONEncode(self:Collect("export"))
		end)
		if not ok then
			return nil
		end
		data = json
	end
	local s = Meta.ExportPrefix .. "-CFG:" .. data
	Util.SetClipboard(s)
	return s
end

function Config:Import(s, opts)
	opts = opts or {}
	if type(s) ~= "string" or s == "" then
		return false, "empty"
	end
	local prefix = Meta.ExportPrefix .. "-CFG:"
	if s:sub(1, #prefix) == prefix then
		s = s:sub(#prefix + 1)
	end
	local ok, data = pcall(Util.JSONDecode, s)
	if not ok or type(data) ~= "table" then
		self:_notify("Import failed: invalid config string", "Error")
		return false, "invalid"
	end
	if opts.SaveAs then
		local name = cleanName(opts.SaveAs)
		if name then
			FS.Write(self:Path(name), s)
		end
	end
	if opts.Apply ~= false then
		local ok2, err = pcall(self.Apply, self, data)
		if not ok2 then
			self:_notify("Import failed: " .. tostring(err), "Error")
			return false, err
		end
	end
	self.Changed:Fire("import", opts.SaveAs)
	self:_notify("Config imported", "Success")
	return true
end

function Config:SetAutoSave(enabled, interval)
	self.Settings.autosave = { enabled = enabled == true, interval = math.max(10, tonumber(interval) or 60) }
	self:SaveSettings()
	if self._autoThread then
		pcall(task.cancel, self._autoThread)
		self._autoThread = nil
	end
	if enabled then
		self._autoThread = task.spawn(function()
			while true do
				task.wait(self.Settings.autosave.interval)
				if self.Current then
					self:Save(self.Current, { Silent = true })
				end
			end
		end)
	end
end

function Config:SetSaveOnClose(v)
	self.Settings.saveOnClose = v == true
	self:SaveSettings()
end

function Config:OnClose()
	if self.Settings.saveOnClose and self.Current then
		pcall(self.Save, self, self.Current, { Silent = true })
	end
end

function Config:Destroy()
	if self._autoThread then
		pcall(task.cancel, self._autoThread)
		self._autoThread = nil
	end
	self.Changed:Destroy()
end

return Config
end
__MODULES["Core/FS"] = function(require)
--[[
	File system wrapper around the executor file API. Every call is pcall'd.
	If the API is missing (or a call fails) a session-only in-memory store is used instead.
]]
local Util = require("Core/Util")

local FS = { Memory = {}, MemoryFolders = {} }

local function fn(name)
	return Util.HasFunc(name)
end

function FS.Available()
	return fn("writefile") ~= nil and fn("readfile") ~= nil and fn("isfile") ~= nil and fn("makefolder") ~= nil
		and fn("isfolder") ~= nil and fn("listfiles") ~= nil
end

local function call(name, ...)
	local f = fn(name)
	if not f then
		return false, "missing " .. name
	end
	return pcall(f, ...)
end

function FS.MakeFolder(path)
	-- create each segment
	local acc = ""
	for seg in string.gmatch(path, "[^/]+") do
		acc = acc == "" and seg or (acc .. "/" .. seg)
		FS.MemoryFolders[acc] = true
		if FS.Available() then
			local ok, exists = call("isfolder", acc)
			if not (ok and exists) then
				call("makefolder", acc)
			end
		end
	end
end

function FS.Write(path, content)
	if FS.Available() then
		local ok = call("writefile", path, content)
		if ok then
			FS.Memory[path] = nil
			return true, "disk"
		end
	end
	FS.Memory[path] = content
	return true, "memory"
end

function FS.Read(path)
	if FS.Memory[path] ~= nil then
		return FS.Memory[path]
	end
	if FS.Available() then
		local ok, exists = call("isfile", path)
		if ok and exists then
			local ok2, data = call("readfile", path)
			if ok2 then
				return data
			end
		end
	end
	return nil
end

function FS.Exists(path)
	if FS.Memory[path] ~= nil then
		return true
	end
	if FS.Available() then
		local ok, exists = call("isfile", path)
		return ok and exists == true
	end
	return false
end

function FS.Delete(path)
	FS.Memory[path] = nil
	if FS.Available() then
		local ok = call("delfile", path)
		return ok
	end
	return true
end

local function basename(p)
	p = p:gsub("\\", "/")
	return p:match("([^/]+)$") or p
end

-- list file names (without extension) inside folder with extension ext (e.g. ".json")
function FS.List(folder, ext)
	ext = ext or ".json"
	local seen, out = {}, {}
	local function add(name)
		if name:sub(-#ext) == ext then
			local n = name:sub(1, -#ext - 1)
			if not seen[n] then
				seen[n] = true
				table.insert(out, n)
			end
		end
	end
	if FS.Available() then
		local ok, files = call("listfiles", folder)
		if ok and type(files) == "table" then
			for _, f in ipairs(files) do
				add(basename(f))
			end
		end
	end
	local prefix = folder .. "/"
	for path in pairs(FS.Memory) do
		if path:sub(1, #prefix) == prefix and not path:sub(#prefix + 1):find("/") then
			add(path:sub(#prefix + 1))
		end
	end
	table.sort(out)
	return out
end

return FS
end
__MODULES["Core/Flags"] = function(require)
--[[
	Flags: global value store for every element that has a Flag.
	Library.Flags.Values[flag] always holds the current value.
]]
local Signal = require("Core/Signal")

local Flags = {}
Flags.__index = Flags

function Flags.new()
	local self = setmetatable({}, Flags)
	self.Values = {}
	self.Elements = {}
	self.Changed = Signal.new() -- (flag, value)
	return self
end

function Flags:Register(element)
	local flag = element.Flag
	if not flag then
		return
	end
	if self.Elements[flag] and self.Elements[flag] ~= element then
		warn(("[Flags] duplicate flag '%s' – the newer element replaces the older one"):format(flag))
	end
	self.Elements[flag] = element
	self.Values[flag] = element.Value
end

function Flags:Unregister(element)
	if element.Flag and self.Elements[element.Flag] == element then
		self.Elements[element.Flag] = nil
	end
end

function Flags:Get(flag)
	return self.Values[flag]
end

function Flags:Set(flag, value, opts)
	local el = self.Elements[flag]
	if el then
		el:Set(value, opts)
	else
		self.Values[flag] = value
		self.Changed:Fire(flag, value)
	end
end

function Flags:Element(flag)
	return self.Elements[flag]
end

return Flags
end
__MODULES["Core/Icons"] = function(require)
--[[
	Icons: a small vector icon set drawn with Frames (no external assets needed),
	so icons work in every executor and scale crisply. Any string that looks like an asset
	("rbxassetid://123", "rbxasset://...", "http...", or a plain number) is rendered as ImageLabel.

	Icons.Register(name, assetIdOrDefinition) lets you add / replace icons (branding).
	Definition primitives (coordinates in 0..1 of the icon box):
	  {"rect", x, y, w, h, radius?, rotation?}   {"ring", cx, cy, d, thickness}
	  {"dot", cx, cy, d}                         {"line", x1, y1, x2, y2, thickness}
]]
local Icons = { Defs = {} }

local D = Icons.Defs
D.crosshair = { { "ring", 0.5, 0.5, 0.62, 0.09 }, { "rect", 0.455, 0.02, 0.09, 0.3 }, { "rect", 0.455, 0.68, 0.09, 0.3 }, { "rect", 0.02, 0.455, 0.3, 0.09 }, { "rect", 0.68, 0.455, 0.3, 0.09 }, { "dot", 0.5, 0.5, 0.13 } }
D.target = { { "ring", 0.5, 0.5, 0.9, 0.08 }, { "ring", 0.5, 0.5, 0.5, 0.08 }, { "dot", 0.5, 0.5, 0.16 } }
D.eye = { { "ring", 0.5, 0.5, 0.86, 0.08, 0.55 }, { "dot", 0.5, 0.5, 0.3 } }
D.user = { { "dot", 0.5, 0.3, 0.36 }, { "rect", 0.18, 0.58, 0.64, 0.36, 0.5 } }
D.users = { { "dot", 0.36, 0.32, 0.3 }, { "rect", 0.1, 0.58, 0.52, 0.32, 0.5 }, { "dot", 0.7, 0.36, 0.24 }, { "rect", 0.56, 0.6, 0.38, 0.28, 0.5 } }
D.gear = { { "ring", 0.5, 0.5, 0.5, 0.14 }, { "rect", 0.42, 0.04, 0.16, 0.92, 0.2 }, { "rect", 0.42, 0.04, 0.16, 0.92, 0.2, 60 }, { "rect", 0.42, 0.04, 0.16, 0.92, 0.2, 120 }, { "dot", 0.5, 0.5, 0.5, "bg" }, { "ring", 0.5, 0.5, 0.52, 0.13 } }
D.settings = D.gear
D.palette = { { "ring", 0.5, 0.5, 0.88, 0.09 }, { "dot", 0.32, 0.36, 0.16 }, { "dot", 0.52, 0.26, 0.16 }, { "dot", 0.7, 0.4, 0.16 }, { "dot", 0.62, 0.66, 0.2 } }
D.folder = { { "rect", 0.08, 0.2, 0.36, 0.2, 0.3 }, { "rect", 0.08, 0.3, 0.84, 0.54, 0.15 } }
D.globe = { { "ring", 0.5, 0.5, 0.86, 0.08 }, { "ring", 0.5, 0.5, 0.4, 0.08, 2.1 }, { "rect", 0.08, 0.46, 0.84, 0.08 } }
D.shield = { { "rect", 0.2, 0.08, 0.6, 0.5, 0.15 }, { "rect", 0.29, 0.42, 0.42, 0.42, 0.15, 45 } }
D.sword = { { "rect", 0.46, 0.04, 0.1, 0.66, 0.4, 45 }, { "rect", 0.2, 0.6, 0.36, 0.09, 0.4, 45 }, { "rect", 0.12, 0.72, 0.14, 0.14, 0.4, 45 } }
D.home = { { "rect", 0.22, 0.46, 0.56, 0.44, 0.1 }, { "rect", 0.26, 0.2, 0.48, 0.48, 0.1, 45 } }
D.bell = { { "rect", 0.24, 0.2, 0.52, 0.56, 0.6 }, { "rect", 0.14, 0.66, 0.72, 0.1, 0.4 }, { "dot", 0.5, 0.85, 0.16 } }
D.search = { { "ring", 0.42, 0.42, 0.6, 0.11 }, { "line", 0.62, 0.62, 0.92, 0.92, 0.12 } }
D.list = { { "rect", 0.1, 0.18, 0.8, 0.11 }, { "rect", 0.1, 0.45, 0.8, 0.11 }, { "rect", 0.1, 0.72, 0.8, 0.11 } }
D.menu = D.list
D.star = { { "rect", 0.27, 0.27, 0.46, 0.46, 0.05, 0 }, { "rect", 0.27, 0.27, 0.46, 0.46, 0.05, 45 } }
D.zap = { { "rect", 0.44, 0.02, 0.14, 0.56, 0.2, 25 }, { "rect", 0.42, 0.42, 0.14, 0.56, 0.2, 25 }, { "rect", 0.3, 0.44, 0.4, 0.12, 0.2 } }
D.code = { { "line", 0.38, 0.22, 0.12, 0.5, 0.1 }, { "line", 0.12, 0.5, 0.38, 0.78, 0.1 }, { "line", 0.62, 0.22, 0.88, 0.5, 0.1 }, { "line", 0.88, 0.5, 0.62, 0.78, 0.1 } }
D.save = { { "ring", 0.5, 0.5, 0.84, 0.09, 0.12 }, { "rect", 0.3, 0.12, 0.4, 0.26, 0.1 }, { "rect", 0.28, 0.58, 0.44, 0.3, 0.1 } }
D.pin = { { "dot", 0.5, 0.34, 0.5 }, { "dot", 0.5, 0.34, 0.2, "bg" }, { "rect", 0.32, 0.5, 0.36, 0.3, 0.1, 45 } }
D.chevron = { { "line", 0.22, 0.38, 0.5, 0.66, 0.11 }, { "line", 0.5, 0.66, 0.78, 0.38, 0.11 } }
D["chevron-down"] = D.chevron
D["chevron-up"] = { { "line", 0.22, 0.62, 0.5, 0.34, 0.11 }, { "line", 0.5, 0.34, 0.78, 0.62, 0.11 } }
D["chevron-right"] = { { "line", 0.38, 0.22, 0.66, 0.5, 0.11 }, { "line", 0.66, 0.5, 0.38, 0.78, 0.11 } }
D["chevron-left"] = { { "line", 0.62, 0.22, 0.34, 0.5, 0.11 }, { "line", 0.34, 0.5, 0.62, 0.78, 0.11 } }
D.close = { { "line", 0.2, 0.2, 0.8, 0.8, 0.11 }, { "line", 0.8, 0.2, 0.2, 0.8, 0.11 } }
D.x = D.close
D.plus = { { "rect", 0.44, 0.12, 0.12, 0.76, 0.3 }, { "rect", 0.12, 0.44, 0.76, 0.12, 0.3 } }
D.minus = { { "rect", 0.12, 0.44, 0.76, 0.12, 0.3 } }
D.check = { { "line", 0.14, 0.52, 0.4, 0.76, 0.13 }, { "line", 0.4, 0.76, 0.86, 0.26, 0.13 } }
D.info = { { "ring", 0.5, 0.5, 0.88, 0.09 }, { "rect", 0.45, 0.42, 0.1, 0.32, 0.4 }, { "dot", 0.5, 0.28, 0.12 } }
D.warning = { { "rect", 0.45, 0.16, 0.1, 0.46, 0.4 }, { "dot", 0.5, 0.78, 0.13 } }
D.alert = D.warning
D.trash = { { "rect", 0.22, 0.3, 0.56, 0.6, 0.12 }, { "rect", 0.12, 0.16, 0.76, 0.1, 0.3 }, { "rect", 0.38, 0.06, 0.24, 0.12, 0.3 } }
D.copy = { { "ring", 0.42, 0.42, 0.56, 0.09, 0.15 }, { "ring", 0.6, 0.6, 0.56, 0.09, 0.15 } }
D.edit = { { "rect", 0.42, 0.08, 0.16, 0.78, 0.2, 45 }, { "dot", 0.18, 0.82, 0.14 } }
D.refresh = { { "ring", 0.5, 0.5, 0.7, 0.1 }, { "rect", 0.6, 0.08, 0.26, 0.26, 0.1, 45, "bg" }, { "line", 0.66, 0.12, 0.86, 0.26, 0.1 }, { "line", 0.86, 0.26, 0.66, 0.4, 0.1 } }
D.download = { { "rect", 0.45, 0.08, 0.1, 0.56, 0.3 }, { "line", 0.24, 0.42, 0.5, 0.68, 0.1 }, { "line", 0.5, 0.68, 0.76, 0.42, 0.1 }, { "rect", 0.12, 0.84, 0.76, 0.1, 0.3 } }
D.upload = { { "rect", 0.45, 0.3, 0.1, 0.5, 0.3 }, { "line", 0.24, 0.48, 0.5, 0.22, 0.1 }, { "line", 0.5, 0.22, 0.76, 0.48, 0.1 }, { "rect", 0.12, 0.86, 0.76, 0.1, 0.3 } }
D.lock = { { "rect", 0.2, 0.44, 0.6, 0.48, 0.15 }, { "ring", 0.5, 0.36, 0.42, 0.09, 0.9 } }
D.grid = { { "rect", 0.1, 0.1, 0.34, 0.34, 0.15 }, { "rect", 0.56, 0.1, 0.34, 0.34, 0.15 }, { "rect", 0.1, 0.56, 0.34, 0.34, 0.15 }, { "rect", 0.56, 0.56, 0.34, 0.34, 0.15 } }
D.sliders = { { "rect", 0.1, 0.24, 0.8, 0.08, 0.3 }, { "rect", 0.1, 0.68, 0.8, 0.08, 0.3 }, { "dot", 0.32, 0.28, 0.22 }, { "dot", 0.66, 0.72, 0.22 } }
D.play = { { "rect", 0.2, 0.25, 0.5, 0.5, 0.1, 45 }, { "rect", 0.0, 0.1, 0.45, 0.8, 0, 0, "bg" } }
D.power = { { "ring", 0.5, 0.54, 0.76, 0.1 }, { "rect", 0.4, 0.04, 0.2, 0.4, 0, 0, "bg" }, { "rect", 0.45, 0.06, 0.1, 0.44, 0.4 } }
D.clock = { { "ring", 0.5, 0.5, 0.86, 0.09 }, { "rect", 0.45, 0.2, 0.1, 0.34, 0.4 }, { "line", 0.5, 0.52, 0.7, 0.62, 0.1 } }
D.box = { { "ring", 0.5, 0.5, 0.8, 0.1, 0.1 } }
D.cube = { { "ring", 0.5, 0.5, 0.62, 0.09, 0.1, 45 }, { "dot", 0.5, 0.5, 0.14 } }
D.car = { { "rect", 0.06, 0.42, 0.88, 0.3, 0.3 }, { "rect", 0.22, 0.24, 0.56, 0.3, 0.3 }, { "dot", 0.28, 0.74, 0.2 }, { "dot", 0.72, 0.74, 0.2 } }
D.skull = { { "dot", 0.5, 0.42, 0.72 }, { "rect", 0.32, 0.62, 0.36, 0.28, 0.2 }, { "dot", 0.36, 0.44, 0.18, "bg" }, { "dot", 0.64, 0.44, 0.18, "bg" } }
D.map = { { "rect", 0.1, 0.16, 0.24, 0.68, 0.1, 6 }, { "rect", 0.38, 0.16, 0.24, 0.68, 0.1, -6 }, { "rect", 0.66, 0.16, 0.24, 0.68, 0.1, 6 } }
D.heart = { { "dot", 0.34, 0.38, 0.42 }, { "dot", 0.66, 0.38, 0.42 }, { "rect", 0.27, 0.3, 0.46, 0.46, 0.08, 45 } }
D.layers = { { "rect", 0.2, 0.12, 0.6, 0.6, 0.12, 45 }, { "rect", 0.24, 0.5, 0.52, 0.12, 0.3 } }
D.move = { { "rect", 0.45, 0.08, 0.1, 0.84, 0.3 }, { "rect", 0.08, 0.45, 0.84, 0.1, 0.3 }, { "dot", 0.5, 0.5, 0.24 } }
D.dot = { { "dot", 0.5, 0.5, 0.5 } }
D.logo = { { "rect", 0.2, 0.2, 0.6, 0.6, 0.15, 45 }, { "rect", 0.34, 0.34, 0.32, 0.32, 0.15, 45, "bg" }, { "dot", 0.5, 0.5, 0.16 } }

local function isAsset(s)
	if type(s) == "number" then
		return true
	end
	return type(s) == "string" and (s:find("^rbxasset") or s:find("^http") or s:match("^%d+$")) ~= nil
end

function Icons.IsAsset(s)
	return isAsset(s)
end

function Icons.Register(name, def)
	Icons.Defs[name] = def
end

function Icons.Has(name)
	return Icons.Defs[name] ~= nil or isAsset(name)
end

--[[
	Icons.Create(theme, name, size, colorKey, props?)
	Returns a Frame (or ImageLabel) whose drawing follows the theme color key.
	`bgKey` (props.BgKey) is used for "cut-out" primitives.
]]
function Icons.Create(theme, name, size, colorKey, props)
	props = props or {}
	colorKey = colorKey or "Text"
	local def = Icons.Defs[name]
	if def and type(def) ~= "table" then
		name = def
		def = nil
	end
	if not def and isAsset(name) then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(size, size)
		img.Image = type(name) == "number" and ("rbxassetid://" .. name) or (name:match("^%d+$") and "rbxassetid://" .. name or name)
		img.ScaleType = Enum.ScaleType.Fit
		theme:Bind(img, "ImageColor3", colorKey)
		for k, v in pairs(props) do
			if k ~= "BgKey" then
				img[k] = v
			end
		end
		return img
	end
	def = def or Icons.Defs.dot
	local box = Instance.new("Frame")
	box.Name = "Icon"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Size = UDim2.fromOffset(size, size)
	for k, v in pairs(props) do
		if k ~= "BgKey" then
			box[k] = v
		end
	end
	local bgKey = props.BgKey or "Background"
	for i, p in ipairs(def) do
		local kind = p[1]
		local f = Instance.new("Frame")
		f.Name = kind .. i
		f.BorderSizePixel = 0
		f.ZIndex = (props.ZIndex or 1) + (p[#p] == "bg" and 1 or 0)
		local key = p[#p] == "bg" and bgKey or colorKey
		if p[#p] ~= "bg" then
			f:SetAttribute("IconFg", true)
		end
		if kind == "rect" then
			f.Position = UDim2.fromScale(p[2], p[3])
			f.Size = UDim2.fromScale(p[4], p[5])
			f.Rotation = type(p[7]) == "number" and p[7] or 0
			local r = type(p[6]) == "number" and p[6] or 0
			if r > 0 then
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(r, 0)
				c.Parent = f
			end
			theme:Bind(f, "BackgroundColor3", key)
		elseif kind == "dot" then
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale(p[2], p[3])
			f.Size = UDim2.fromScale(p[4], p[4])
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = f
			theme:Bind(f, "BackgroundColor3", key)
		elseif kind == "ring" then
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale(p[2], p[3])
			local d = p[4]
			local squash = type(p[6]) == "number" and p[6] or nil
			if squash and squash > 1 then
				f.Size = UDim2.fromScale(d / squash, d)
			elseif squash and squash < 1 and squash > 0.3 then
				f.Size = UDim2.fromScale(d, d * squash)
			else
				f.Size = UDim2.fromScale(d, d)
			end
			f.Rotation = type(p[7]) == "number" and p[7] or 0
			f.BackgroundTransparency = 1
			local c = Instance.new("UICorner")
			c.CornerRadius = (squash and squash <= 0.3) and UDim.new(squash, 0) or UDim.new(1, 0)
			c.Parent = f
			local s = Instance.new("UIStroke")
			s.Thickness = math.max(1, math.floor(size * p[5] + 0.5))
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			s.Parent = f
			theme:Bind(s, "Color", key)
		elseif kind == "line" then
			local x1, y1, x2, y2 = p[2] * size, p[3] * size, p[4] * size, p[5] * size
			local dx, dy = x2 - x1, y2 - y1
			local len = math.sqrt(dx * dx + dy * dy)
			local th = math.max(1, math.floor(size * (p[6] or 0.1) + 0.5))
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
			f.Size = UDim2.fromOffset(len + th * 0.5, th)
			f.Rotation = math.deg(math.atan2(dy, dx))
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = f
			theme:Bind(f, "BackgroundColor3", key)
		end
		f.Parent = box
	end
	return box
end

-- Recolor an icon created by Icons.Create (rebinds every foreground primitive)
function Icons.SetColor(theme, icon, colorKey, tween)
	if not icon then
		return
	end
	if icon:IsA("ImageLabel") then
		theme:Bind(icon, "ImageColor3", colorKey, { Tween = tween })
		return
	end
	for _, f in ipairs(icon:GetChildren()) do
		if f:GetAttribute("IconFg") then
			local s = f:FindFirstChildOfClass("UIStroke")
			if s then
				theme:Bind(s, "Color", colorKey, { Tween = tween })
			else
				theme:Bind(f, "BackgroundColor3", colorKey, { Tween = tween })
			end
		end
	end
end

return Icons
end
__MODULES["Core/Input"] = function(require)
--[[
	Input: one set of UserInputService connections for the whole library,
	unified mouse + touch dragging (with threshold, tap, long-press) and helpers.
]]
local Util = require("Core/Util")
local Signal = require("Core/Signal")
local Maid = require("Core/Maid")

local UIS = Util.Services.UserInputService

local Input = {}
Input.__index = Input

local MB1 = Enum.UserInputType.MouseButton1
local TOUCH = Enum.UserInputType.Touch
local MOVE = Enum.UserInputType.MouseMovement

function Input.new()
	local self = setmetatable({}, Input)
	self.Maid = Maid.new()
	self.Began = Signal.new() -- (input, gameProcessed)
	self.Ended = Signal.new()
	self.Changed = Signal.new()
	if UIS then
		self.Maid:Give(UIS.InputBegan:Connect(function(i, gp)
			self.Began:Fire(i, gp)
		end))
		self.Maid:Give(UIS.InputEnded:Connect(function(i, gp)
			self.Ended:Fire(i, gp)
		end))
		self.Maid:Give(UIS.InputChanged:Connect(function(i, gp)
			self.Changed:Fire(i, gp)
		end))
	end
	return self
end

function Input.IsPress(input)
	return input.UserInputType == MB1 or input.UserInputType == TOUCH
end

function Input.Pos(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

-- InputObject positions exclude the top bar inset, AbsolutePosition (IgnoreGuiInset) does not
function Input.ToAbs(pos)
	return pos + Util.GuiInset()
end

function Input.MousePos()
	if UIS then
		local ok, p = pcall(function()
			return UIS:GetMouseLocation()
		end)
		if ok and p then
			return p
		end
	end
	return Vector2.new(0, 0)
end

--[[
	Input:Drag(handle, opts) -> Maid
	opts.Target       GuiObject to move (Position offset), optional
	opts.GetScale()   current UIScale (deltas are divided by it)
	opts.Threshold    pixels before a press becomes a drag (default 0)
	opts.Clamp(pos)   -> UDim2 clamp hook
	opts.Enabled()    -> bool
	opts.OnStart(), opts.OnMove(delta, pos), opts.OnEnd(moved), opts.OnTap()
	opts.LongPress()  fired after opts.LongPressTime (0.5s) without moving; cancels tap
]]
function Input:Drag(handle, opts)
	opts = opts or {}
	local maid = Maid.new()
	local active, startPos, startTarget, moved, lp
	local function finish(cancelled)
		local wasMoved = moved
		active = nil
		if lp then
			pcall(task.cancel, lp)
			lp = nil
		end
		if opts.OnEnd then
			opts.OnEnd(wasMoved, cancelled)
		end
		if not wasMoved and not cancelled and opts.OnTap then
			opts.OnTap()
		end
	end
	maid:Give(handle.InputBegan:Connect(function(input)
		if not Input.IsPress(input) then
			return
		end
		if opts.Enabled and not opts.Enabled() then
			return
		end
		active = input
		startPos = Input.Pos(input)
		moved = false
		if opts.OnStart then
			opts.OnStart(startPos)
		end
		startTarget = opts.Target and opts.Target.Position
		if opts.LongPress then
			lp = task.delay(opts.LongPressTime or 0.5, function()
				lp = nil
				if active == input and not moved then
					active = nil
					if opts.OnEnd then
						opts.OnEnd(false, true)
					end
					opts.LongPress()
				end
			end)
		end
	end))
	maid:Give(self.Changed:Connect(function(input)
		if not active then
			return
		end
		local t = input.UserInputType
		if not (t == MOVE or t == TOUCH) then
			return
		end
		if active.UserInputType == TOUCH and t ~= TOUCH then
			return
		end
		if active.UserInputType == MB1 and t ~= MOVE then
			return
		end
		local p = Input.Pos(input)
		local delta = p - startPos
		if not moved then
			if delta.Magnitude < (opts.Threshold or 0) then
				return
			end
			moved = true
			if lp then
				pcall(task.cancel, lp)
				lp = nil
			end
		end
		if opts.Target and startTarget then
			local s = opts.GetScale and opts.GetScale() or 1
			local pos = UDim2.new(
				startTarget.X.Scale,
				startTarget.X.Offset + delta.X / s,
				startTarget.Y.Scale,
				startTarget.Y.Offset + delta.Y / s
			)
			if opts.Clamp then
				pos = opts.Clamp(pos) or pos
			end
			opts.Target.Position = pos
		end
		if opts.OnMove then
			opts.OnMove(delta, p)
		end
	end))
	maid:Give(self.Ended:Connect(function(input)
		if not active then
			return
		end
		local t = input.UserInputType
		if t == active.UserInputType or input == active then
			finish(false)
		end
	end))
	maid:Give(function()
		active = nil
	end)
	return maid
end

function Input:Destroy()
	self.Maid:Clean()
end

return Input
end
__MODULES["Core/Maid"] = function(require)
--[[
	Maid: collects connections / instances / functions / objects and cleans them up together.
]]
local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid.CleanTask(job)
	local t = typeof(job)
	if t == "RBXScriptConnection" then
		job:Disconnect()
	elseif t == "Instance" then
		job:Destroy()
	elseif t == "function" then
		job()
	elseif t == "thread" then
		pcall(task.cancel, job)
	elseif t == "table" then
		if type(job.Destroy) == "function" then
			job:Destroy()
		elseif type(job.Disconnect) == "function" then
			job:Disconnect()
		elseif type(job.Clean) == "function" then
			job:Clean()
		end
	end
end

-- Add a task, returns it
function Maid:Give(job)
	if job ~= nil then
		table.insert(self._tasks, job)
	end
	return job
end

-- Named slot: cleans the previous task in that slot
function Maid:Set(name, job)
	local old = self._tasks[name]
	if old ~= nil and old ~= job then
		pcall(Maid.CleanTask, old)
	end
	self._tasks[name] = job
	return job
end

function Maid:Clean()
	local tasks = self._tasks
	self._tasks = {}
	for _, job in pairs(tasks) do
		local ok, err = pcall(Maid.CleanTask, job)
		if not ok then
			warn("[Maid] cleanup error: " .. tostring(err))
		end
	end
end

Maid.Destroy = Maid.Clean
Maid.DoCleaning = Maid.Clean

return Maid
end
__MODULES["Core/Registry"] = function(require)
--[[
	Skin registry. Skins register themselves here; UI:RegisterSkin(skin) adds custom ones.
]]
local Registry = { Skins = {}, Order = {} }

function Registry:Register(skin)
	assert(type(skin) == "table" and type(skin.Name) == "string", "skin needs a Name")
	if not self.Skins[skin.Name] then
		table.insert(self.Order, skin.Name)
	end
	self.Skins[skin.Name] = skin
	return skin
end

function Registry:Get(name)
	return self.Skins[name]
end

function Registry:List()
	return table.clone(self.Order)
end

return Registry
end
__MODULES["Core/Renderer"] = function(require)
--[[
	Renderer: bridges the logic tree (Window -> Tab -> SubTab -> Group -> Element) and the active skin.
	It owns the render context (ctx) that every skin function receives, and can tear the whole
	presentation down and rebuild it for another skin without touching any logic object.
]]
local Maid = require("Core/Maid")
local Util = require("Core/Util")
local Tween = require("Core/Tween")
local Icons = require("Core/Icons")
local Prim = require("Skins/Base/Prim")

local Renderer = {}
Renderer.__index = Renderer

function Renderer.new(lib)
	local self = setmetatable({}, Renderer)
	self.Library = lib
	self.Ctx = nil
	self.Notifications = {}
	return self
end

function Renderer:MakeContext(skin)
	local lib = self.Library
	local ctx = Prim.Attach({
		Library = lib,
		Theme = lib.Theme,
		Skin = skin,
		Style = skin.Style or {},
		Tween = Tween,
		Icons = Icons,
		Util = Util,
		Layers = lib.Layers,
		Input = lib.Input,
		Maid = Maid.new(),
		Renderer = self,
		IsMobile = lib.Mobile and lib.Mobile:IsMobile() or false,
		Scale = lib.CurrentScale or 1,
	})
	return ctx
end

---------------------------------------------------------------- full build / teardown
function Renderer:Build()
	local lib = self.Library
	self.Ctx = self:MakeContext(lib.Skin)
	local ctx = self.Ctx
	-- library level overlays
	local ok, err = pcall(function()
		self.TooltipView = ctx.Skin.Tooltip(ctx)
	end)
	if not ok then
		warn("[Renderer] tooltip: " .. tostring(err))
	end
	if lib.Window then
		self:RenderWindow(lib.Window)
	end
	self:RefreshWatermark()
	self:RefreshKeybindList()
	if lib.Mobile then
		lib.Mobile:Render(ctx)
	end
end

local function clearViews(lib)
	local function clearGroup(g)
		g.View = nil
		for _, el in ipairs(g.Elements) do
			el.View = nil
			for _, a in ipairs(el.Addons) do
				a.View = nil
			end
			if el.SubGroup then
				clearGroup(el.SubGroup)
			end
		end
	end
	local win = lib.Window
	if not win then
		return
	end
	win.View = nil
	for _, tab in ipairs(win.Tabs) do
		tab.View = nil
		for _, sub in ipairs(tab.SubTabs) do
			sub.PageView = nil
			for _, g in ipairs(sub.Groups) do
				clearGroup(g)
			end
		end
	end
end

function Renderer:Teardown()
	local lib = self.Library
	self:CloseOverlays()
	if self.Ctx then
		self.Ctx.Maid:Clean()
	end
	if lib.Window and lib.Window.View and lib.Window.View.Destroy then
		pcall(lib.Window.View.Destroy, lib.Window.View)
	end
	clearViews(lib)
	for _, layer in pairs(lib.Layers) do
		if layer ~= lib.Layers.Loader then
			for _, c in ipairs(layer:GetChildren()) do
				if not c:IsA("UIBase") and not c:IsA("UIListLayout") then
					c:Destroy()
				end
			end
		end
	end
	self.Notifications = {}
	self.NotifyHolders = nil
	self.TooltipView = nil
	self.WatermarkView = nil
	self.KeybindListView = nil
	if lib.Mobile then
		lib.Mobile:Teardown()
	end
end

-- Rebuild for the current skin. fade = true plays a fade transition over the window.
function Renderer:Rebuild(fade, between)
	local lib = self.Library
	local win = lib.Window
	if fade and win and win.View and win.Open and lib.Theme:Get("AnimationsEnabled") then
		local root = win.View.Root
		local fader = Instance.new("Frame")
		fader.Name = "SkinFade"
		fader.BorderSizePixel = 0
		fader.BackgroundColor3 = lib.Theme:Get("Background")
		fader.BackgroundTransparency = 1
		fader.Position = root.Position
		fader.AnchorPoint = root.AnchorPoint
		fader.Size = root.Size
		fader.ZIndex = 50
		fader.Parent = lib.Layers.Loader
		Tween.Play(fader, { BackgroundTransparency = 0 }, 0.15, Enum.EasingStyle.Quad)
		task.wait(Tween.Duration(0.15))
		if between then
			between()
		end
		self:Teardown()
		self:Build()
		local newRoot = lib.Window.View and lib.Window.View.Root
		if newRoot then
			fader.BackgroundColor3 = lib.Theme:Get("Background")
			fader.Position = newRoot.Position
			fader.AnchorPoint = newRoot.AnchorPoint
			fader.Size = newRoot.Size
		end
		Tween.Play(fader, { BackgroundTransparency = 1 }, 0.25, Enum.EasingStyle.Quad)
		task.delay(Tween.Duration(0.3), function()
			fader:Destroy()
		end)
	else
		if between then
			between()
		end
		self:Teardown()
		self:Build()
	end
end

---------------------------------------------------------------- tree rendering
function Renderer:RenderWindow(win)
	local ctx = self.Ctx
	local ok, view = pcall(ctx.Skin.Window, ctx, win)
	if not ok then
		error("[Renderer] skin window failed: " .. tostring(view))
	end
	win.View = view
	for _, tab in ipairs(win.Tabs) do
		self:RenderTab(tab, true)
	end
	local active = win.ActiveTab or win.Tabs[1]
	if win.State.Tab then
		active = win:GetTab(win.State.Tab) or active
	end
	if active then
		win:SelectTab(active, win.State.Sub or (active.ActiveSub and active.ActiveSub.Name))
	end
	if view.SetOpen then
		view:SetOpen(win.Open, true)
	end
end

function Renderer:RenderTab(tab, bulk)
	local win = tab.Window
	if not win.View then
		return
	end
	tab.View = win.View:AddTab(tab)
	for _, sub in ipairs(tab.SubTabs) do
		self:RenderSubTab(sub, true)
	end
	if win.View.SubTabsChanged then
		win.View:SubTabsChanged(tab)
	end
	if not bulk and (win.ActiveTab == tab or #win.Tabs == 1) then
		win:SelectTab(tab)
	end
end

function Renderer:RenderSubTab(sub, bulk)
	local tab = sub.Tab
	if not tab.View then
		return
	end
	sub.PageView = tab.View:AddPage(sub)
	for _, g in ipairs(sub.Groups) do
		self:RenderGroup(g)
	end
	if not bulk then
		if tab.Window.View and tab.Window.View.SubTabsChanged then
			tab.Window.View:SubTabsChanged(tab)
		end
		if tab.Window.ActiveTab == tab then
			tab.Window:SelectTab(tab, tab.ActiveSub)
		end
	end
end

function Renderer:RenderGroup(g)
	local ctx = self.Ctx
	local page = g.Page and g.Page.PageView
	if not page then
		return
	end
	local column = page:GetColumn(g.Side)
	local ok, view = pcall(ctx.Skin.Group, ctx, g, column)
	if not ok then
		warn("[Renderer] group '" .. g.Name .. "' failed: " .. tostring(view))
		return
	end
	g.View = view
	view.Root.LayoutOrder = g.Order
	view.Root.Visible = g.Visible
	for _, el in ipairs(g.Elements) do
		self:RenderElement(el, g)
	end
end

function Renderer:RenderElement(el, group)
	local ctx = self.Ctx
	group = group or el.Group
	if not group or not group.View then
		return
	end
	local comp = ctx.Skin.Components[el.Kind]
	if not comp then
		warn("[Renderer] skin has no component " .. el.Kind)
		return
	end
	local ok, view = pcall(comp, ctx, el, group.View.Container)
	if not ok then
		warn(("[Renderer] %s '%s' failed: %s"):format(el.Kind, tostring(el.Name), tostring(view)))
		return
	end
	el.View = view
	view.Root.LayoutOrder = el.Order
	view.Root.Visible = el.Visible
	for _, a in ipairs(el.Addons) do
		self:RenderAddon(el, a)
	end
	if view.Update then
		view:Update(el.Value, true)
	end
	if view.SetDisabled then
		view:SetDisabled(el:IsDisabled())
	end
	if el.SubGroup and view.SetHasSub then
		view:SetHasSub(true)
	end
	if el.Tooltip then
		ctx:Tooltip(view.Hit or view.Root, el)
	end
end

function Renderer:RenderAddon(owner, addon)
	local ctx = self.Ctx
	local holder = owner.View and owner.View.Addons
	if not holder then
		return
	end
	local comp = ctx.Skin.Components["Inline" .. addon.Kind]
	if not comp then
		return
	end
	local ok, view = pcall(comp, ctx, addon, holder)
	if not ok then
		warn("[Renderer] addon failed: " .. tostring(view))
		return
	end
	addon.View = view
	view.Root.LayoutOrder = addon.Order
	if view.Update then
		view:Update(addon.Value, true)
	end
end

---------------------------------------------------------------- overlays (dropdown lists, pickers, popouts)
-- ctx:OpenOverlay uses this stack so nested panels (picker inside popout) work.
function Renderer:PushOverlay(frame, onClose)
	self.OverlayStack = self.OverlayStack or {}
	local lib = self.Library
	local depth = #self.OverlayStack + 1
	local catcher = Instance.new("TextButton")
	catcher.Name = "OverlayCatcher"
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.BackgroundTransparency = 1
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.ZIndex = depth * 20
	catcher.Parent = lib.Layers.Overlay
	frame.ZIndex = depth * 20 + 1
	frame.Parent = lib.Layers.Overlay
	local entry = { Frame = frame, Catcher = catcher, OnClose = onClose }
	table.insert(self.OverlayStack, entry)
	catcher.MouseButton1Down:Connect(function()
		self:PopOverlay(entry)
	end)
	catcher.TouchTap:Connect(function()
		self:PopOverlay(entry)
	end)
	return entry
end

function Renderer:PopOverlay(entry)
	local stack = self.OverlayStack or {}
	local idx = table.find(stack, entry)
	if not idx then
		return
	end
	-- close everything above it as well
	for i = #stack, idx, -1 do
		local e = table.remove(stack, i)
		if e.OnClose then
			pcall(e.OnClose)
		end
		e.Catcher:Destroy()
		if e.Frame.Parent then
			e.Frame:Destroy()
		end
	end
end

function Renderer:CloseOverlays()
	local stack = self.OverlayStack or {}
	if stack[1] then
		self:PopOverlay(stack[1])
	end
end

-- sub-options popout (gear icon)
function Renderer:OpenPopout(owner, anchor)
	local ctx = self.Ctx
	local group = owner.SubGroup
	if not group then
		return
	end
	local view = ctx.Skin.Popout(ctx, group, anchor)
	group.View = view
	for _, el in ipairs(group.Elements) do
		self:RenderElement(el, group)
	end
	ctx:OpenOverlay(view.Root, function()
		for _, el in ipairs(group.Elements) do
			el.View = nil
			for _, a in ipairs(el.Addons) do
				a.View = nil
			end
		end
		group.View = nil
	end)
	if view.Opened then
		view:Opened()
	end
end

---------------------------------------------------------------- notifications
local POS = {
	TopLeft = { Vector2.new(0, 0), UDim2.new(0, 12, 0, 12), Enum.VerticalAlignment.Top },
	TopRight = { Vector2.new(1, 0), UDim2.new(1, -12, 0, 12), Enum.VerticalAlignment.Top },
	TopCenter = { Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 12), Enum.VerticalAlignment.Top },
	BottomLeft = { Vector2.new(0, 1), UDim2.new(0, 12, 1, -12), Enum.VerticalAlignment.Bottom },
	BottomRight = { Vector2.new(1, 1), UDim2.new(1, -12, 1, -12), Enum.VerticalAlignment.Bottom },
	BottomCenter = { Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -12), Enum.VerticalAlignment.Bottom },
}

function Renderer:NotifyHolder()
	local lib = self.Library
	local pos = lib.Theme:Get("NotifyPosition")
	self.NotifyHolders = self.NotifyHolders or {}
	local h = self.NotifyHolders[pos]
	if h and h.Parent then
		return h, pos
	end
	local p = POS[pos] or POS.BottomRight
	h = Instance.new("Frame")
	h.Name = "Notifications_" .. pos
	h.BackgroundTransparency = 1
	h.AnchorPoint = p[1]
	local inset = Util.GuiInset()
	h.Position = p[2] + UDim2.fromOffset(0, pos:find("Top") and inset.Y or 0)
	h.Size = UDim2.new(0, lib.Theme:Get("NotifyWidth"), 1, -24 - inset.Y)
	h.Parent = lib.Layers.Notify
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.VerticalAlignment = p[3]
	list.HorizontalAlignment = pos:find("Left") and Enum.HorizontalAlignment.Left
		or pos:find("Right") and Enum.HorizontalAlignment.Right
		or Enum.HorizontalAlignment.Center
	list.Parent = h
	self.NotifyHolders[pos] = h
	return h, pos
end

local notifyOrder = 0
function Renderer:Notify(opts)
	local ctx = self.Ctx
	if not ctx then
		return
	end
	local holder, pos = self:NotifyHolder()
	self.Library.History = self.Library.History or {}
	table.insert(self.Library.History, 1, { Title = opts.Title, Content = opts.Content, Type = opts.Type or "Info", Time = os.date("%H:%M") })
	if #self.Library.History > 12 then
		table.remove(self.Library.History)
	end
	self.Library.Unread = (self.Library.Unread or 0) + 1
	if self.Library.HistoryChanged then
		self.Library.HistoryChanged:Fire()
	end
	notifyOrder += 1
	opts.Order = pos:find("Bottom") and notifyOrder or -notifyOrder
	opts.Duration = opts.Duration or ctx:T("NotifyDuration")
	opts.Type = opts.Type or "Info"
	local ok, view = pcall(ctx.Skin.Notification, ctx, opts, holder)
	if not ok then
		warn("[Renderer] notification failed: " .. tostring(view))
		return
	end
	view.Root.LayoutOrder = opts.Order
	ctx:Sound("SoundNotify")
	table.insert(self.Notifications, view)
	-- cap the amount of visible notifications
	while #self.Notifications > 6 do
		local old = table.remove(self.Notifications, 1)
		pcall(old.Close, old, true)
	end
	local handle = {}
	function handle.Close()
		local i = table.find(self.Notifications, view)
		if i then
			table.remove(self.Notifications, i)
		end
		pcall(view.Close, view)
	end
	if opts.Duration and opts.Duration > 0 then
		task.delay(opts.Duration, handle.Close)
	end
	return handle
end

---------------------------------------------------------------- watermark / keybind list
function Renderer:RefreshWatermark()
	local lib = self.Library
	local ctx = self.Ctx
	if self.WatermarkView then
		self.WatermarkView.Root:Destroy()
		self.WatermarkView = nil
	end
	local st = lib.WatermarkState
	if not (ctx and st and st.Enabled) then
		return
	end
	self.WatermarkView = ctx.Skin.Watermark(ctx, st)
	local root = self.WatermarkView.Root
	if st.Position then
		root.AnchorPoint = Vector2.new(0, 0)
		root.Position = UDim2.fromOffset(st.Position[1], st.Position[2])
	end
	ctx.Maid:Give(lib.Input:Drag(root, {
		OnStart = function()
			-- convert to an absolute offset so dragging works from any anchor
			if root.AnchorPoint.X ~= 0 then
				local p = ctx:RectOf(root)
				root.AnchorPoint = Vector2.new(0, 0)
				root.Position = UDim2.fromOffset(p.X, p.Y)
			end
		end,
		Target = root,
		GetScale = function()
			return lib.CurrentScale
		end,
		OnEnd = function(moved)
			if moved then
				st.Position = { root.Position.X.Offset, root.Position.Y.Offset }
			end
		end,
	}))
	lib:_updateWatermarkText()
end

function Renderer:RefreshKeybindList()
	local lib = self.Library
	local ctx = self.Ctx
	if self.KeybindListView then
		self.KeybindListView.Root:Destroy()
		self.KeybindListView = nil
	end
	local st = lib.KeybindListState
	if not (ctx and st and st.Enabled) then
		return
	end
	self.KeybindListView = ctx.Skin.KeybindList(ctx, st)
	local root = self.KeybindListView.Root
	if st.Position then
		root.Position = UDim2.fromOffset(st.Position[1], st.Position[2])
	end
	ctx.Maid:Give(lib.Input:Drag(self.KeybindListView.Handle or root, {
		Target = root,
		GetScale = function()
			return lib.CurrentScale
		end,
		OnEnd = function(moved)
			if moved then
				st.Position = { root.Position.X.Offset, root.Position.Y.Offset }
			end
		end,
	}))
	lib:_updateKeybindList()
end

return Renderer
end
__MODULES["Core/Signal"] = function(require)
--[[
	Lightweight pure-Lua signal (no BindableEvent, so values are passed by reference).
]]
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local list = self._handlers
	local entry = { Fn = fn, Connected = true }
	function entry.Disconnect()
		if not entry.Connected then
			return
		end
		entry.Connected = false
		local i = table.find(list, entry)
		if i then
			table.remove(list, i)
		end
	end
	table.insert(list, entry)
	return entry
end

function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c.Disconnect()
		fn(...)
	end)
	return c
end

function Signal:Fire(...)
	for _, e in ipairs(table.clone(self._handlers)) do
		if e.Connected then
			local ok, err = pcall(e.Fn, ...)
			if not ok then
				warn("[Signal] handler error: " .. tostring(err))
			end
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Destroy()
	for _, e in ipairs(self._handlers) do
		e.Connected = false
	end
	self._handlers = {}
end

return Signal
end
__MODULES["Core/Theme"] = function(require)
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
end
__MODULES["Core/Tween"] = function(require)
--[[
	Central tween helper. Every animation in the library goes through Tween.Play so that
	the theme keys AnimationsEnabled / AnimationSpeed / EasingStyle / EasingDirection apply globally.
]]
local Util = require("Core/Util")
local TweenService = Util.Services.TweenService

local Tween = {
	Enabled = true,
	Speed = 1, -- multiplier: 2 = twice as fast
	Style = Enum.EasingStyle.Quint,
	Direction = Enum.EasingDirection.Out,
}

function Tween.Configure(enabled, speed, style, direction)
	Tween.Enabled = enabled ~= false
	Tween.Speed = math.max(tonumber(speed) or 1, 0.05)
	local ok, s = pcall(function()
		return Enum.EasingStyle[style]
	end)
	if ok and s then
		Tween.Style = s
	end
	local ok2, d = pcall(function()
		return Enum.EasingDirection[direction]
	end)
	if ok2 and d then
		Tween.Direction = d
	end
end

function Tween.Duration(d)
	return (d or 0.2) / Tween.Speed
end

-- Tween.Play(inst, {Prop = value}, duration?, style?, direction?)
function Tween.Play(inst, props, duration, style, direction)
	if not inst then
		return nil
	end
	if not Tween.Enabled or duration == 0 then
		for k, v in pairs(props) do
			inst[k] = v
		end
		return nil
	end
	local info = TweenInfo.new(
		Tween.Duration(duration),
		style or Tween.Style,
		direction or Tween.Direction
	)
	local ok, tw = pcall(TweenService.Create, TweenService, inst, info, props)
	if ok and tw then
		tw:Play()
		return tw
	end
	for k, v in pairs(props) do
		inst[k] = v
	end
	return nil
end

-- Tween a number value via callback (for counters, custom properties)
function Tween.Value(from, to, duration, onStep, onDone)
	if not Tween.Enabled then
		onStep(to)
		if onDone then
			onDone()
		end
		return
	end
	local nv = Instance.new("NumberValue")
	nv.Value = from
	local conn = nv.Changed:Connect(function(v)
		onStep(v)
	end)
	local tw = Tween.Play(nv, { Value = to }, duration)
	if tw then
		tw.Completed:Connect(function()
			conn:Disconnect()
			nv:Destroy()
			onStep(to)
			if onDone then
				onDone()
			end
		end)
	else
		conn:Disconnect()
		onStep(to)
		if onDone then
			onDone()
		end
	end
end

return Tween
end
__MODULES["Core/Util"] = function(require)
--[[
	Util: services, instance creation, colors, serialization, environment helpers.
]]
local Util = {}

local function svc(name)
	local ok, s = pcall(function()
		return game:GetService(name)
	end)
	return ok and s or nil
end

Util.Services = {
	Players = svc("Players"),
	RunService = svc("RunService"),
	UserInputService = svc("UserInputService"),
	TweenService = svc("TweenService"),
	HttpService = svc("HttpService"),
	GuiService = svc("GuiService"),
	TextService = svc("TextService"),
	CoreGui = svc("CoreGui"),
	Stats = svc("Stats"),
	SoundService = svc("SoundService"),
	Workspace = svc("Workspace") or workspace,
}

---------------------------------------------------------------- tables
function Util.DeepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local n = {}
	for k, v in pairs(t) do
		n[k] = Util.DeepCopy(v)
	end
	return n
end

-- fill missing keys of `opts` from `defaults` (shallow)
function Util.Defaults(opts, defaults)
	opts = opts or {}
	for k, v in pairs(defaults) do
		if opts[k] == nil then
			opts[k] = v
		end
	end
	return opts
end

function Util.Count(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

function Util.Keys(t)
	local out = {}
	for k in pairs(t) do
		table.insert(out, k)
	end
	table.sort(out, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return out
end

function Util.DeepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in pairs(a) do
		if not Util.DeepEqual(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

---------------------------------------------------------------- math
function Util.Clamp(v, a, b)
	return math.max(a, math.min(b, v))
end

function Util.Round(v, inc)
	inc = inc or 1
	if inc <= 0 then
		return v
	end
	local r = math.floor(v / inc + 0.5) * inc
	-- kill float noise
	local decimals = Util.Decimals(inc)
	local m = 10 ^ decimals
	return math.floor(r * m + 0.5) / m
end

function Util.Decimals(inc)
	local s = tostring(inc)
	local dot = string.find(s, "%.")
	if not dot then
		return 0
	end
	return math.min(#s - dot, 6)
end

function Util.FormatNumber(v, decimals)
	if decimals and decimals > 0 then
		return string.format("%." .. decimals .. "f", v)
	end
	return tostring(math.floor(v + 0.5))
end

function Util.Lerp(a, b, t)
	return a + (b - a) * t
end

---------------------------------------------------------------- colors
function Util.ColorToHex(c)
	return string.format(
		"#%02x%02x%02x",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5)
	)
end

function Util.HexToColor(s)
	if type(s) ~= "string" then
		return nil
	end
	s = s:gsub("#", ""):gsub("%s", "")
	if #s == 3 then
		s = s:sub(1, 1):rep(2) .. s:sub(2, 2):rep(2) .. s:sub(3, 3):rep(2)
	end
	if #s ~= 6 or s:find("[^%x]") then
		return nil
	end
	return Color3.fromRGB(tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16))
end

function Util.Darken(c, f)
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v * (1 - f), 0, 1))
end

function Util.Lighten(c, f)
	return c:Lerp(Color3.new(1, 1, 1), f)
end

-- Build a ColorSequence from a list of colors (evenly spaced)
function Util.Sequence(colors)
	if #colors == 0 then
		colors = { Color3.new(1, 1, 1) }
	end
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local kps = {}
	local n = math.min(#colors, 20)
	for i = 1, n do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (n - 1), colors[i]))
	end
	return ColorSequence.new(kps)
end

-- sample a cyclic palette at t (0..1, wraps)
function Util.SampleCyclic(colors, t)
	local n = #colors
	if n == 0 then
		return Color3.new(1, 1, 1)
	end
	if n == 1 then
		return colors[1]
	end
	t = t % 1
	local f = t * n
	local i = math.floor(f)
	local a = colors[i + 1]
	local b = colors[(i + 1) % n + 1]
	return a:Lerp(b, f - i)
end

function Util.HealthColor(t)
	-- red -> yellow -> green
	t = Util.Clamp(t, 0, 1)
	if t < 0.5 then
		return Color3.fromRGB(230, 60, 60):Lerp(Color3.fromRGB(240, 200, 50), t * 2)
	end
	return Color3.fromRGB(240, 200, 50):Lerp(Color3.fromRGB(80, 220, 100), (t - 0.5) * 2)
end

---------------------------------------------------------------- instances
function Util.Create(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Util.FontEnum(name)
	if typeof(name) == "EnumItem" then
		return name
	end
	local ok, f = pcall(function()
		return Enum.Font[name]
	end)
	return ok and f or Enum.Font.Gotham
end

function Util.TextWidth(text, size, font)
	local ts = Util.Services.TextService
	if ts then
		local ok, v = pcall(function()
			return ts:GetTextSize(text, size, Util.FontEnum(font), Vector2.new(10000, 10000))
		end)
		if ok and v then
			return v.X
		end
	end
	return #text * size * 0.55
end

-- position a rotated frame as a line between two 2D points (in parent offset space)
function Util.SetLine(frame, a, b, thickness)
	local d = b - a
	local len = d.Magnitude
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	frame.Size = UDim2.fromOffset(len, thickness or 1)
	frame.Rotation = math.deg(math.atan2(d.Y, d.X))
end

function Util.IsVisible(gui)
	local g = gui
	while g and g:IsA("GuiObject") do
		if not g.Visible then
			return false
		end
		g = g.Parent
	end
	if g and g:IsA("ScreenGui") and not g.Enabled then
		return false
	end
	return g ~= nil
end

---------------------------------------------------------------- environment (executor)
function Util.GetEnv()
	local ok, env = pcall(function()
		return getgenv and getgenv()
	end)
	if ok and type(env) == "table" then
		return env
	end
	return shared or _G
end

function Util.HasFunc(name)
	local env = Util.GetEnv()
	local f = env[name]
	if f == nil then
		local ok, g = pcall(function()
			return getfenv(0)[name]
		end)
		f = ok and g or nil
	end
	return type(f) == "function" and f or nil
end

function Util.SetClipboard(text)
	local f = Util.HasFunc("setclipboard") or Util.HasFunc("toclipboard") or Util.HasFunc("set_clipboard")
	if f then
		local ok = pcall(f, text)
		return ok
	end
	return false
end

function Util.GetClipboard()
	local f = Util.HasFunc("getclipboard")
	if f then
		local ok, v = pcall(f)
		if ok then
			return v
		end
	end
	return nil
end

-- gethui() -> CoreGui -> PlayerGui
function Util.ParentGui(gui)
	local hui = Util.HasFunc("gethui")
	if hui then
		local ok, container = pcall(hui)
		if ok and container then
			local ok2 = pcall(function()
				gui.Parent = container
			end)
			if ok2 and gui.Parent then
				return "gethui"
			end
		end
	end
	local env = Util.GetEnv()
	if env.syn and type(env.syn.protect_gui) == "function" then
		pcall(env.syn.protect_gui, gui)
	end
	local ok = pcall(function()
		gui.Parent = Util.Services.CoreGui
	end)
	if ok and gui.Parent then
		return "CoreGui"
	end
	local lp = Util.Services.Players and Util.Services.Players.LocalPlayer
	if lp then
		gui.Parent = lp:WaitForChild("PlayerGui")
		return "PlayerGui"
	end
	return nil
end

function Util.LocalPlayer()
	return Util.Services.Players and Util.Services.Players.LocalPlayer
end

function Util.PlaceId()
	local ok, id = pcall(function()
		return game.PlaceId
	end)
	return ok and tostring(id) or "0"
end

---------------------------------------------------------------- JSON + value serialization
function Util.JSONEncode(t)
	return Util.Services.HttpService:JSONEncode(t)
end

function Util.JSONDecode(s)
	return Util.Services.HttpService:JSONDecode(s)
end

-- Convert Roblox datatypes into JSON safe values
function Util.Serialize(v)
	local t = typeof(v)
	if t == "Color3" then
		return { __t = "Color3", v = Util.ColorToHex(v) }
	elseif t == "EnumItem" then
		return { __t = "Enum", e = tostring(v.EnumType), v = v.Name }
	elseif t == "Vector2" then
		return { __t = "Vector2", v = { v.X, v.Y } }
	elseif t == "UDim2" then
		return { __t = "UDim2", v = { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } }
	elseif t == "table" then
		local out = {}
		for k, x in pairs(v) do
			out[k] = Util.Serialize(x)
		end
		return out
	end
	return v
end

function Util.Deserialize(v)
	if type(v) ~= "table" then
		return v
	end
	if v.__t == "Color3" then
		return Util.HexToColor(v.v) or Color3.new(1, 1, 1)
	elseif v.__t == "Enum" then
		local ok, e = pcall(function()
			return Enum[v.e][v.v]
		end)
		return ok and e or nil
	elseif v.__t == "Vector2" then
		return Vector2.new(v.v[1], v.v[2])
	elseif v.__t == "UDim2" then
		return UDim2.new(v.v[1], v.v[2], v.v[3], v.v[4])
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = Util.Deserialize(x)
	end
	return out
end

function Util.Viewport()
	local cam = Util.Services.Workspace and Util.Services.Workspace.CurrentCamera
	if cam then
		return cam.ViewportSize
	end
	return Vector2.new(1280, 720)
end

function Util.GuiInset()
	local gs = Util.Services.GuiService
	if gs then
		local ok, a = pcall(function()
			return gs:GetGuiInset()
		end)
		if ok and a then
			return a
		end
	end
	return Vector2.new(0, 36)
end

return Util
end
__MODULES["ESPPreview/Rig"] = function(require)
--[[
	Rig: returns a model for the ESP preview. Tries to clone the local character
	(Archivable = true, scripts stripped, anchored); otherwise builds a blocky R15-proportioned rig.
	Returns model, parts (name -> BasePart), base CFrames (part -> CFrame relative to origin)
]]
local Util = require("Core/Util")

local Rig = {}

-- name, size, position (feet on y = 0)
local R15 = {
	{ "Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 5.2, 0) },
	{ "UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 3.8, 0) },
	{ "LowerTorso", Vector3.new(2, 0.4, 1), Vector3.new(0, 2.8, 0) },
	{ "LeftUpperArm", Vector3.new(1, 1.1, 1), Vector3.new(-1.5, 4.05, 0) },
	{ "LeftLowerArm", Vector3.new(1, 0.9, 1), Vector3.new(-1.5, 3.05, 0) },
	{ "LeftHand", Vector3.new(1, 0.4, 1), Vector3.new(-1.5, 2.4, 0) },
	{ "RightUpperArm", Vector3.new(1, 1.1, 1), Vector3.new(1.5, 4.05, 0) },
	{ "RightLowerArm", Vector3.new(1, 0.9, 1), Vector3.new(1.5, 3.05, 0) },
	{ "RightHand", Vector3.new(1, 0.4, 1), Vector3.new(1.5, 2.4, 0) },
	{ "LeftUpperLeg", Vector3.new(1, 1.2, 1), Vector3.new(-0.5, 2.0, 0) },
	{ "LeftLowerLeg", Vector3.new(1, 1.1, 1), Vector3.new(-0.5, 0.85, 0) },
	{ "LeftFoot", Vector3.new(1, 0.3, 1), Vector3.new(-0.5, 0.15, 0) },
	{ "RightUpperLeg", Vector3.new(1, 1.2, 1), Vector3.new(0.5, 2.0, 0) },
	{ "RightLowerLeg", Vector3.new(1, 1.1, 1), Vector3.new(0.5, 0.85, 0) },
	{ "RightFoot", Vector3.new(1, 0.3, 1), Vector3.new(0.5, 0.15, 0) },
}

Rig.Bones = {
	{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}

local function default()
	local model = Instance.new("Model")
	model.Name = "PreviewRig"
	local parts = {}
	for _, d in ipairs(R15) do
		local p = Instance.new("Part")
		p.Name = d[1]
		p.Size = d[2]
		p.CFrame = CFrame.new(d[3])
		p.Anchored = true
		p.CanCollide = false
		p.Color = d[1] == "Head" and Color3.fromRGB(245, 205, 160) or (d[1]:find("Torso") and Color3.fromRGB(40, 110, 210) or (d[1]:find("Leg") or d[1]:find("Foot")) and Color3.fromRGB(45, 45, 60) or Color3.fromRGB(245, 205, 160))
		p.Parent = model
		parts[d[1]] = p
	end
	return model, parts
end

local function cloneCharacter()
	local lp = Util.LocalPlayer()
	local char = lp and lp.Character
	if not char then
		return nil
	end
	local ok, clone = pcall(function()
		local old = char.Archivable
		char.Archivable = true
		local c = char:Clone()
		char.Archivable = old
		return c
	end)
	if not ok or not clone then
		return nil
	end
	local parts = {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Sound") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			if d.Name == "HumanoidRootPart" then
				d.Transparency = 1
			end
		end
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	for _, d in ipairs(R15) do
		local p = clone:FindFirstChild(d[1])
		if not p then
			clone:Destroy()
			return nil -- not R15, use the default rig
		end
		parts[d[1]] = p
	end
	-- move feet to y = 0, centered
	local cf, size = clone:GetBoundingBox()
	local offset = CFrame.new(-cf.Position.X, -(cf.Position.Y - size.Y / 2), -cf.Position.Z)
	local rot = CFrame.new(cf.Position) * (cf - cf.Position):Inverse() * CFrame.new(-cf.Position)
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = offset * rot * d.CFrame
		end
	end
	return clone, parts
end

function Rig.Build()
	local model, parts = cloneCharacter()
	if not model then
		model, parts = default()
	end
	local all, base = {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(all, d)
			base[d] = d.CFrame
		end
	end
	return model, parts, all, base
end

return Rig
end
__MODULES["ESPPreview"] = function(require)
--[[
	ESP preview component: ViewportFrame with an R15 dummy (local character clone or default rig),
	drag to rotate, scroll / pinch to zoom, idle rotation. Overlays (box 2D/corner/filled, name,
	distance, health bar with selectable side + animated demo value, tracer, skeleton, chams) are bound
	live to flags and styled with the active skin's theme.

	UI:GetESPSettings() returns the current values so your own ESP code can use them.
	RenderStepped runs only while the preview is actually visible on screen.
]]
local Util = require("Core/Util")
local Input = require("Core/Input")
local Rig = require("ESPPreview/Rig")

local RunService = Util.Services.RunService
local UIS = Util.Services.UserInputService

local ESP = {}

ESP.DefaultFlags = {
	Enabled = "esp_enabled",
	Box = "esp_box",
	BoxType = "esp_box_type",
	BoxColor = "esp_box_color",
	Name = "esp_name",
	NameColor = "esp_name_color",
	Distance = "esp_distance",
	HealthBar = "esp_health",
	HealthSide = "esp_health_side",
	Tracer = "esp_tracer",
	TracerColor = "esp_tracer_color",
	Skeleton = "esp_skeleton",
	SkeletonColor = "esp_skeleton_color",
	Chams = "esp_chams",
	ChamsColor = "esp_chams_color",
}

function ESP.ResolveFlags(map)
	local out = {}
	for k, v in pairs(ESP.DefaultFlags) do
		out[k] = (map and map[k]) or v
	end
	return out
end

local function col(v, default)
	if type(v) == "table" and typeof(v.Color) == "Color3" then
		return v.Color, v.Transparency or 0
	end
	if typeof(v) == "Color3" then
		return v, 0
	end
	return default, 0
end

function ESP.GetSettings(lib, map)
	local F = ESP.ResolveFlags(map)
	local V = lib.Flags.Values
	local function bool(k, d)
		local v = V[F[k]]
		if v == nil then
			return d
		end
		return v == true
	end
	local white = Color3.new(1, 1, 1)
	local s = {
		Enabled = bool("Enabled", true),
		Box = bool("Box", true),
		BoxType = V[F.BoxType] or "2D",
		Name = bool("Name", true),
		Distance = bool("Distance", true),
		HealthBar = bool("HealthBar", true),
		HealthSide = V[F.HealthSide] or "Left",
		Tracer = bool("Tracer", false),
		Skeleton = bool("Skeleton", false),
		Chams = bool("Chams", false),
	}
	s.BoxColor, s.BoxTransparency = col(V[F.BoxColor], white)
	s.NameColor = col(V[F.NameColor], white)
	s.TracerColor, s.TracerTransparency = col(V[F.TracerColor], white)
	s.SkeletonColor, s.SkeletonTransparency = col(V[F.SkeletonColor], white)
	s.ChamsColor, s.ChamsTransparency = col(V[F.ChamsColor], Color3.fromRGB(160, 90, 255))
	return s
end

local function line(ctx, parent, z)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.ZIndex = z
	f.Parent = parent
	return f
end

function ESP.Render(ctx, el, parent)
	local lib = ctx.Library
	local o = el.Options
	local h = o.Height or 280
	local root = ctx:Frame(parent, { Name = "ESPPreview", Size = UDim2.new(1, 0, 0, h) })
	local view = { Root = root }
	local box = ctx:Frame(root, { Size = UDim2.fromScale(1, 1), ClipsDescendants = true }, "BackgroundSecondary")
	ctx:Corner(box, "SmallCornerRadius")
	ctx:Stroke(box, ctx.Style.ControlStroke or "Border", 1)
	ctx:Grad(box, "BackgroundGradient")
	-- floor grid for depth
	for i = 1, 5 do
		ctx:Frame(box, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.62 + i * 0.075, 0), Size = UDim2.new(0.25 + i * 0.15, 0, 0, 1) }, "Border", { Alpha = 0.3 + i * 0.08 })
	end

	local vf = Instance.new("ViewportFrame")
	vf.Name = "Viewport"
	vf.BackgroundTransparency = 1
	vf.Size = UDim2.fromScale(1, 1)
	vf.Ambient = Color3.fromRGB(170, 170, 180)
	vf.LightColor = Color3.fromRGB(255, 255, 255)
	vf.LightDirection = Vector3.new(-1, -1, -1)
	vf.Parent = box
	local world = Instance.new("WorldModel")
	world.Parent = vf
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vf
	vf.CurrentCamera = cam
	local model, parts, allParts, base = Rig.Build()
	model.Parent = world
	local original = {}
	for _, p in ipairs(allParts) do
		original[p] = { Color = p.Color, Transparency = p.Transparency, Material = p.Material }
	end

	local overlay = ctx:Frame(box, { Name = "Overlay", Size = UDim2.fromScale(1, 1), ZIndex = box.ZIndex + 5 })
	local Z = overlay.ZIndex + 1
	-- box variants
	local boxOutline = Instance.new("Frame")
	boxOutline.BackgroundTransparency = 1
	boxOutline.ZIndex = Z
	boxOutline.Parent = overlay
	local outlineStroke = Instance.new("UIStroke")
	outlineStroke.Thickness = 3
	outlineStroke.Color = Color3.new(0, 0, 0)
	outlineStroke.Transparency = 0.4
	outlineStroke.Parent = boxOutline
	local boxFrame = Instance.new("Frame")
	boxFrame.BackgroundTransparency = 1
	boxFrame.BorderSizePixel = 0
	boxFrame.ZIndex = Z + 1
	boxFrame.Parent = overlay
	local boxStroke = Instance.new("UIStroke")
	boxStroke.Thickness = 1
	boxStroke.Parent = boxFrame
	local corners = {}
	for i = 1, 8 do
		local c = line(ctx, overlay, Z + 1)
		c.AnchorPoint = Vector2.new(0, 0)
		table.insert(corners, c)
	end
	-- texts
	local nameLabel = ctx:Text(overlay, { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(160, 14), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, ZIndex = Z + 2, Text = o.PlayerName or ctx:Username() }, "Text", "FontMono", "SmallTextSize")
	local distLabel = ctx:Text(overlay, { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(100, 14), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, ZIndex = Z + 2 }, "TextDim", "FontMono", "SmallTextSize")
	-- health bar
	local hpBg = Instance.new("Frame")
	hpBg.BorderSizePixel = 0
	hpBg.BackgroundColor3 = Color3.new(0, 0, 0)
	hpBg.BackgroundTransparency = 0.3
	hpBg.ZIndex = Z + 1
	hpBg.Parent = overlay
	local hpFill = Instance.new("Frame")
	hpFill.BorderSizePixel = 0
	hpFill.ZIndex = Z + 2
	hpFill.Parent = hpBg
	local hpText = ctx:Text(overlay, { Size = UDim2.fromOffset(30, 12), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3, ZIndex = Z + 3, TextSize = 10 }, "Text", "FontMono", 10)
	-- tracer + skeleton
	local tracer = line(ctx, overlay, Z)
	local bones = {}
	for i = 1, #Rig.Bones do
		bones[i] = line(ctx, overlay, Z + 1)
	end
	-- hint + hit area
	local hint = ctx:Text(box, { Text = ctx.IsMobile and "drag to rotate · pinch to zoom" or "drag to rotate · scroll to zoom", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -12, 0, 12), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = Z + 4 }, "TextDisabled", "FontBody", "SmallTextSize")
	local _ = hint
	local hit = ctx:Hitbox(box, { ZIndex = Z + 5 })

	local state = lib.ESPState or { Yaw = 0.5, Distance = 15 }
	lib.ESPState = state
	local dragging = false
	local startYaw = state.Yaw
	ctx.Maid:Give(ctx.Input:Drag(hit, {
		OnStart = function()
			dragging = true
			startYaw = state.Yaw
		end,
		OnMove = function(delta)
			state.Yaw = startYaw + delta.X * 0.012
		end,
		OnEnd = function()
			dragging = false
		end,
	}))
	hit.InputChanged:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseWheel then
			state.Distance = Util.Clamp(state.Distance - io.Position.Z * 1.2, 8, 26)
		end
	end)
	if UIS then
		ctx.Maid:Give(UIS.TouchPinch:Connect(function(positions, scale, _, st)
			if not Util.IsVisible(box) or not positions[1] then
				return
			end
			local p = Input.ToAbs(positions[1])
			local a, s = box.AbsolutePosition, box.AbsoluteSize
			if p.X < a.X or p.Y < a.Y or p.X > a.X + s.X or p.Y > a.Y + s.Y then
				return
			end
			if st == Enum.UserInputState.Begin then
				view._pinchStart = state.Distance
			end
			state.Distance = Util.Clamp((view._pinchStart or state.Distance) / math.max(scale, 0.2), 8, 26)
		end))
	end

	local chamsOn = nil
	local function applyChams(on, c, t)
		if on then
			for _, p in ipairs(allParts) do
				if p.Name ~= "HumanoidRootPart" then
					p.Color = c
					p.Transparency = t
					p.Material = Enum.Material.SmoothPlastic
				end
			end
		elseif chamsOn ~= false then
			for p, d in pairs(original) do
				p.Color = d.Color
				p.Transparency = d.Transparency
				p.Material = d.Material
			end
		end
		chamsOn = on
	end

	local function project(camCF, fov, w, hh, pos)
		local rel = camCF:PointToObjectSpace(pos)
		local depth = -rel.Z
		if depth <= 0.01 then
			depth = 0.01
		end
		local f = (hh / 2) / math.tan(math.rad(fov / 2))
		return Vector2.new(w / 2 + rel.X * f / depth, hh / 2 - rel.Y * f / depth)
	end

	local t0 = os.clock()
	function view:Step(dt)
		local s = ESP.GetSettings(lib, o.Flags)
		if not dragging and o.IdleRotation ~= false then
			state.Yaw += (dt or 0) * (o.IdleSpeed or 0.5)
		end
		local rot = CFrame.Angles(0, state.Yaw, 0)
		for _, p in ipairs(allParts) do
			p.CFrame = rot * base[p]
		end
		local camPos = Vector3.new(0, 2.8, state.Distance)
		local camCF = CFrame.new(camPos, Vector3.new(0, 2.8, 0))
		cam.CFrame = camCF
		local sc = lib.CurrentScale or 1
		local w, hh = box.AbsoluteSize.X / sc, box.AbsoluteSize.Y / sc
		if w <= 1 then
			w, hh = 300, h
		end
		applyChams(s.Enabled and s.Chams, s.ChamsColor, s.ChamsTransparency)
		-- bounding box from the R15 parts
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
		for _, p in pairs(parts) do
			local cf, size = p.CFrame, p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local v = project(camCF, cam.FieldOfView, w, hh, cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz))
						minX, minY = math.min(minX, v.X), math.min(minY, v.Y)
						maxX, maxY = math.max(maxX, v.X), math.max(maxY, v.Y)
					end
				end
			end
		end
		local bw, bh = maxX - minX, maxY - minY
		local on = s.Enabled
		local showBox = on and s.Box
		local filled = s.BoxType == "Filled"
		local corner = s.BoxType == "Corner"
		boxFrame.Visible = showBox and not corner
		boxOutline.Visible = showBox and not corner
		boxFrame.Position = UDim2.fromOffset(minX, minY)
		boxFrame.Size = UDim2.fromOffset(bw, bh)
		boxOutline.Position = boxFrame.Position
		boxOutline.Size = boxFrame.Size
		boxStroke.Color = s.BoxColor
		boxStroke.Transparency = s.BoxTransparency
		boxFrame.BackgroundTransparency = filled and 0.8 or 1
		boxFrame.BackgroundColor3 = s.BoxColor
		local cl = math.min(bw, bh) * 0.25
		local cdef = {
			{ minX, minY, cl, 1 }, { minX, minY, 1, cl },
			{ maxX - cl, minY, cl, 1 }, { maxX - 1, minY, 1, cl },
			{ minX, maxY - 1, cl, 1 }, { minX, maxY - cl, 1, cl },
			{ maxX - cl, maxY - 1, cl, 1 }, { maxX - 1, maxY - cl, 1, cl },
		}
		for i, c in ipairs(corners) do
			c.Visible = showBox and corner
			c.Position = UDim2.fromOffset(cdef[i][1], cdef[i][2])
			c.Size = UDim2.fromOffset(cdef[i][3], cdef[i][4])
			c.BackgroundColor3 = s.BoxColor
			c.BackgroundTransparency = s.BoxTransparency
		end
		nameLabel.Visible = on and s.Name
		nameLabel.Position = UDim2.fromOffset((minX + maxX) / 2, minY - 3)
		nameLabel.TextColor3 = s.NameColor
		distLabel.Visible = on and s.Distance
		distLabel.Position = UDim2.fromOffset((minX + maxX) / 2, maxY + 3)
		distLabel.Text = string.format("%dm", math.floor(state.Distance * 1.4))
		-- health (animated demo value)
		local hp = 0.55 + 0.45 * math.sin((os.clock() - t0) * 1.3)
		local side = s.HealthSide
		hpBg.Visible = on and s.HealthBar
		hpText.Visible = hpBg.Visible
		local th = 3
		if side == "Left" or side == "Right" then
			local x = side == "Left" and (minX - 6) or (maxX + 3)
			hpBg.Position = UDim2.fromOffset(x, minY)
			hpBg.Size = UDim2.fromOffset(th, bh)
			hpFill.AnchorPoint = Vector2.new(0, 1)
			hpFill.Position = UDim2.fromScale(0, 1)
			hpFill.Size = UDim2.fromScale(1, hp)
			hpText.Position = UDim2.fromOffset(x - 14 + th / 2, minY + bh * (1 - hp) - 6)
		else
			local y = side == "Top" and (minY - 6 - (s.Name and 14 or 0)) or (maxY + 3 + (s.Distance and 14 or 0))
			hpBg.Position = UDim2.fromOffset(minX, y)
			hpBg.Size = UDim2.fromOffset(bw, th)
			hpFill.AnchorPoint = Vector2.new(0, 0)
			hpFill.Position = UDim2.fromScale(0, 0)
			hpFill.Size = UDim2.fromScale(hp, 1)
			hpText.Position = UDim2.fromOffset(minX + bw * hp - 15, y - 12)
		end
		hpFill.BackgroundColor3 = Util.HealthColor(hp)
		hpText.Text = tostring(math.floor(hp * 100))
		-- tracer
		tracer.Visible = on and s.Tracer
		Util.SetLine(tracer, Vector2.new(w / 2, hh), Vector2.new((minX + maxX) / 2, maxY), 1)
		tracer.BackgroundColor3 = s.TracerColor
		tracer.BackgroundTransparency = s.TracerTransparency
		-- skeleton
		for i, b in ipairs(Rig.Bones) do
			local a, c = parts[b[1]], parts[b[2]]
			local fr = bones[i]
			fr.Visible = on and s.Skeleton
			if fr.Visible and a and c then
				local pa = a.Position
				local pc = c.Position
				if b[1] == "Head" then
					pc = (c.CFrame * Vector3.new(0, c.Size.Y / 2, 0))
				end
				Util.SetLine(fr, project(camCF, cam.FieldOfView, w, hh, pa), project(camCF, cam.FieldOfView, w, hh, pc), 1)
				fr.BackgroundColor3 = s.SkeletonColor
				fr.BackgroundTransparency = s.SkeletonTransparency
			end
		end
	end

	view:Step(0)
	if RunService then
		local conn = RunService.RenderStepped:Connect(function(dt)
			if not root.Parent or not Util.IsVisible(root) then
				return
			end
			view:Step(dt)
		end)
		ctx.Maid:Give(conn)
		root.Destroying:Connect(function()
			conn:Disconnect()
		end)
	end
	-- flags changed while hidden: refresh once
	ctx.Maid:Give(lib.Flags.Changed:Connect(function()
		if root.Parent then
			view:Step(0)
		end
	end))
	function view:SetDisabled() end
	return view
end

return ESP
end
__MODULES["Meta"] = function(require)
--[[
	Meta.lua
	THE single place to rename / rebrand the library.
	Everything (folder names, export prefixes, window defaults, global keys) reads from here.
]]
return {
	Name = "Nova UI", -- display name
	Folder = "NovaUI", -- root folder used by the config system
	Version = "1.0.0",
	ConfigVersion = 2, -- bump + add a migration in Core/Config.lua when the format changes
	SettingsVersion = 1,
	GlobalKey = "__NOVA_UI_INSTANCE", -- used to destroy the previous instance on re-execute
	ExportPrefix = "NOVA", -- prefix for exported config / theme strings
	DefaultSkin = "Classic",
}
end
__MODULES["Mobile/FloatingButton"] = function(require)
--[[
	Floating open button: draggable (mouse + touch, drag threshold), snaps to the nearest screen edge,
	avoids the default touch controls, position saved in config, look provided by the skin.
]]
local Util = require("Core/Util")
local Tween = require("Core/Tween")

local FB = {}

function FB.Render(mobile, ctx)
	local lib = mobile.Library
	local view = ctx.Skin.FloatingButton(ctx)
	local b = view.Root
	b.Parent = ctx.Layers.Notify
	b.ZIndex = 50
	local size = Vector2.new(b.Size.X.Offset, b.Size.Y.Offset)
	local screen = lib:ScreenSize()
	local inset = Util.GuiInset()
	local x = mobile.Button.X or (screen.X - size.X - 10)
	local y = mobile.Button.Y or (inset.Y + 70)
	local p = mobile:Resolve(Vector2.new(x, y), size)
	b.Position = UDim2.fromOffset(p.X, p.Y)
	local sc = Instance.new("UIScale")
	sc.Parent = b
	local function snap()
		local sc2 = lib:ScreenSize()
		local cur = Vector2.new(b.Position.X.Offset, b.Position.Y.Offset)
		local left = cur.X + size.X / 2 < sc2.X / 2
		local target = Vector2.new(left and 8 or (sc2.X - size.X - 8), cur.Y)
		target = mobile:Resolve(target, size)
		Tween.Play(b, { Position = UDim2.fromOffset(target.X, target.Y) }, 0.25, Enum.EasingStyle.Back)
		mobile.Button.X, mobile.Button.Y = target.X, target.Y
	end
	ctx.Maid:Give(lib.Input:Drag(b, {
		Target = b,
		Threshold = 10,
		GetScale = function()
			return lib.CurrentScale
		end,
		OnStart = function()
			Tween.Play(sc, { Scale = 0.92 }, 0.1)
		end,
		OnEnd = function(moved)
			Tween.Play(sc, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
			if moved then
				snap()
			end
		end,
		OnTap = function()
			ctx:Sound("SoundClick")
			if lib.Window then
				lib.Window:Toggle()
			end
		end,
		LongPress = function()
			-- long press: quick menu for quick toggles
			ctx.Skin.ContextMenu(ctx, b, {
				{ Text = lib.Window and lib.Window.Open and "Close menu" or "Open menu", Callback = function()
					lib.Window:Toggle()
				end },
				{ Text = mobile.EditMode and "Finish editing" or "Edit quick toggles", Callback = function()
					mobile:SetEditMode(not mobile.EditMode)
				end },
			})
		end,
	}))
	return view
end

return FB
end
__MODULES["Mobile/QuickToggles"] = function(require)
--[[
	Quick toggles: Pinnable toggles can be pinned to the screen as small buttons.
	Tap = toggle (bounce), drag = move (threshold), long-press = menu (size S/M/L, transparency, unpin,
	edit mode). Edit mode shows a grid and snaps positions to it. Synced with the menu both ways.
]]
local Util = require("Core/Util")

local QT = {}
local GRID = 16

local function sizeOf(view)
	return Vector2.new(view.Root.Size.X.Offset, view.Root.Size.Y.Offset)
end

function QT.Render(mobile, ctx, el)
	local lib = mobile.Library
	local flag = el.Flag
	local data = mobile.Pins[flag]
	if not data then
		return
	end
	QT.Remove(mobile, flag, true)
	local view = ctx.Skin.QuickToggle(ctx, el, data.size or "M")
	local b = view.Root
	b.Parent = ctx.Layers.Mobile
	b.ZIndex = 4
	local p = mobile:Resolve(Vector2.new(data.x, data.y), sizeOf(view))
	b.Position = UDim2.fromOffset(p.X, p.Y)
	view:Update(el.Value, true)
	if data.alpha and data.alpha > 0 then
		view:SetAlpha(data.alpha)
	end
	local conn = el.Changed:Connect(function(v)
		view:Update(v)
		view:Bounce()
	end)
	local function clampSnap(pos)
		local x, y = pos.X.Offset, pos.Y.Offset
		if mobile.EditMode then
			x = math.floor(x / GRID + 0.5) * GRID
			y = math.floor(y / GRID + 0.5) * GRID
		end
		local r = mobile:Resolve(Vector2.new(x, y), sizeOf(view))
		if mobile.EditMode then
			return UDim2.fromOffset(r.X, r.Y)
		end
		return UDim2.fromOffset(x, y)
	end
	local drag = lib.Input:Drag(b, {
		Target = b,
		Threshold = 10,
		GetScale = function()
			return lib.CurrentScale
		end,
		Clamp = clampSnap,
		OnEnd = function(moved)
			if moved then
				local r = mobile:Resolve(Vector2.new(b.Position.X.Offset, b.Position.Y.Offset), sizeOf(view))
				b.Position = UDim2.fromOffset(r.X, r.Y)
				data.x, data.y = r.X, r.Y
			end
		end,
		OnTap = function()
			if mobile.EditMode or el:IsDisabled() then
				return
			end
			ctx:Sound("SoundToggle")
			el:Set(not el.Value)
		end,
		LongPress = function()
			local function setSize(s)
				data.size = s
				QT.Render(mobile, ctx, el)
			end
			ctx.Skin.ContextMenu(ctx, b, {
				{ Text = "Size: Small", Selected = data.size == "S", Callback = function()
					setSize("S")
				end },
				{ Text = "Size: Medium", Selected = data.size == "M", Callback = function()
					setSize("M")
				end },
				{ Text = "Size: Large", Selected = data.size == "L", Callback = function()
					setSize("L")
				end },
				{ Text = "Opacity: " .. math.floor((1 - (data.alpha or 0)) * 100) .. "%", Callback = function()
					local steps = { 0, 0.25, 0.5 }
					local i = (table.find(steps, data.alpha or 0) or 1) % #steps + 1
					data.alpha = steps[i]
					view:SetAlpha(data.alpha)
				end },
				{ Text = mobile.EditMode and "Finish editing" or "Edit layout", Callback = function()
					mobile:SetEditMode(not mobile.EditMode)
				end },
				{ Text = "Unpin", Danger = true, Callback = function()
					el:Pin(false)
				end },
			})
		end,
	})
	mobile.Views[flag] = { View = view, Conn = conn, Drag = drag }
	if mobile.EditMode then
		view:SetEditing(true)
	end
	return view
end

function QT.Remove(mobile, flag)
	local v = mobile.Views[flag]
	if v then
		v.Conn.Disconnect()
		v.Drag:Clean()
		v.View.Root:Destroy()
		mobile.Views[flag] = nil
	end
end

function QT.RenderAll(mobile, ctx)
	for flag in pairs(mobile.Pins) do
		local el = mobile.Library.Flags.Elements[flag]
		if el then
			QT.Render(mobile, ctx, el)
		end
	end
	if mobile.EditMode then
		QT.SetEditMode(mobile, true)
	end
end

function QT.Teardown(mobile)
	for flag in pairs(mobile.Views) do
		QT.Remove(mobile, flag)
	end
	if mobile.GridView then
		mobile.GridView:Destroy()
		mobile.GridView = nil
	end
end

-- edit mode: grid overlay + "Done" button, positions snap to the grid
function QT.SetEditMode(mobile, on)
	local ctx = mobile.Ctx
	if mobile.GridView then
		mobile.GridView:Destroy()
		mobile.GridView = nil
	end
	for _, v in pairs(mobile.Views) do
		v.View:SetEditing(on)
	end
	if not (on and ctx) then
		return
	end
	local screen = mobile.Library:ScreenSize()
	local grid = ctx:Frame(ctx.Layers.Mobile, { Name = "EditGrid", Size = UDim2.fromScale(1, 1), ZIndex = 1 })
	for x = 0, screen.X, GRID * 4 do
		ctx:Frame(grid, { Position = UDim2.fromOffset(x, 0), Size = UDim2.new(0, 1, 1, 0), ZIndex = 1 }, "Accent", { Alpha = 0.85 })
	end
	for y = 0, screen.Y, GRID * 4 do
		ctx:Frame(grid, { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 1), ZIndex = 1 }, "Accent", { Alpha = 0.85 })
	end
	for _, z in ipairs(mobile:SafeZones()) do
		local f = ctx:Frame(grid, { Position = UDim2.fromOffset(z.Min.X, z.Min.Y), Size = UDim2.fromOffset(z.Max.X - z.Min.X, z.Max.Y - z.Min.Y), ZIndex = 2 }, "Error", { Alpha = 0.85 })
		ctx:Text(f, { Text = "reserved (touch controls)", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center }, "Error", "FontBody", "SmallTextSize")
	end
	local done = ctx:New("TextButton", {
		Parent = grid,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Util.GuiInset().Y + 10),
		Size = UDim2.fromOffset(160, 40),
		Text = "Done editing",
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		ZIndex = 3,
	}, { BackgroundColor3 = "Accent", TextColor3 = "TextOnAccent", Font = "FontTitle", TextSize = "TextSize" })
	ctx:Corner(done, "SmallCornerRadius")
	done.Activated:Connect(function()
		mobile:SetEditMode(false)
	end)
	mobile.GridView = grid
end

return QT
end
__MODULES["Mobile"] = function(require)
--[[
	Mobile support: detection (+ manual override), automatic scale, floating open button and
	pinned quick toggles. State (button position, pins) is saved in configs.
]]
local Util = require("Core/Util")
local FloatingButton = require("Mobile/FloatingButton")
local QuickToggles = require("Mobile/QuickToggles")

local UIS = Util.Services.UserInputService

local Mobile = {}
Mobile.__index = Mobile

function Mobile.new(lib)
	local self = setmetatable({}, Mobile)
	self.Library = lib
	self.Mode = (lib.Config and lib.Config.Settings.mobileMode) or "Auto" -- Auto | Mobile | Desktop
	self.ForceButton = nil -- nil = auto (mobile only)
	self.Button = { X = nil, Y = nil }
	self.Pins = {} -- flag -> { x, y, size, alpha }
	self.EditMode = false
	self.Views = {}
	return self
end

function Mobile:Detect()
	if not UIS then
		return false
	end
	local touch = UIS.TouchEnabled
	local keyboard = UIS.KeyboardEnabled
	local vp = Util.Viewport()
	return touch and (not keyboard or math.min(vp.X, vp.Y) < 600)
end

function Mobile:IsMobile()
	if self.Mode == "Mobile" then
		return true
	elseif self.Mode == "Desktop" then
		return false
	end
	return self:Detect()
end

function Mobile:SetMode(mode)
	if mode ~= "Auto" and mode ~= "Mobile" and mode ~= "Desktop" then
		return
	end
	self.Mode = mode
	local cfg = self.Library.Config
	if cfg then
		cfg.Settings.mobileMode = mode
		cfg:SaveSettings()
	end
	self.Library:ApplyScale()
	self.Library.Renderer:Rebuild(false)
end

-- scale so that the window fits on small screens
function Mobile:AutoScale()
	-- scale by width only (text stays readable); the window height then shrinks to the space
	-- below the Roblox top bar (Window:GetSize) and the pages scroll
	local vp = Util.Viewport()
	local w = self.Library.Theme:Get("WindowWidth") + 24
	return Util.Clamp(vp.X / w, 0.75, 1)
end

-- areas covered by the default touch controls (thumbstick bottom-left, jump bottom-right)
function Mobile:SafeZones()
	local screen = self.Library:ScreenSize()
	return {
		{ Min = Vector2.new(0, screen.Y * 0.55), Max = Vector2.new(screen.X * 0.36, screen.Y) },
		{ Min = Vector2.new(screen.X * 0.74, screen.Y * 0.62), Max = Vector2.new(screen.X, screen.Y) },
	}
end

-- push a rect out of the safe zones / screen edges (moves upward)
function Mobile:Resolve(pos, size)
	local screen = self.Library:ScreenSize()
	local inset = Util.GuiInset()
	local x = Util.Clamp(pos.X, 4, math.max(4, screen.X - size.X - 4))
	local y = Util.Clamp(pos.Y, inset.Y + 4, math.max(inset.Y + 4, screen.Y - size.Y - 4))
	for _, z in ipairs(self:SafeZones()) do
		local overlap = x < z.Max.X and x + size.X > z.Min.X and y < z.Max.Y and y + size.Y > z.Min.Y
		if overlap then
			y = z.Min.Y - size.Y - 6
		end
	end
	return Vector2.new(x, y)
end

function Mobile:ShowButton()
	if self.ForceButton ~= nil then
		return self.ForceButton
	end
	return self:IsMobile()
end

---------------------------------------------------------------- render lifecycle
function Mobile:Render(ctx)
	self.Ctx = ctx
	if self.Library.Window and self:ShowButton() then
		self.ButtonView = FloatingButton.Render(self, ctx)
	end
	QuickToggles.RenderAll(self, ctx)
end

function Mobile:Teardown()
	if self.ButtonView then
		self.ButtonView.Root:Destroy()
		self.ButtonView = nil
	end
	QuickToggles.Teardown(self)
end

---------------------------------------------------------------- pins
function Mobile:IsPinned(el)
	return el.Flag ~= nil and self.Pins[el.Flag] ~= nil
end

function Mobile:Pin(el, data)
	if not el.Flag then
		warn("[Mobile] only toggles with a Flag can be pinned")
		return
	end
	local inset = Util.GuiInset()
	local n = Util.Count(self.Pins)
	-- default: a row along the top (clear of the Roblox top bar, the floating button and the touch controls)
	self.Pins[el.Flag] = data or { x = 140 + n * 104, y = inset.Y + 14, size = "M", alpha = 0 }
	if self.Ctx then
		QuickToggles.Render(self, self.Ctx, el)
	end
	if el.View and el.View.RefreshPin then
		el.View.RefreshPin()
	end
end

function Mobile:Unpin(el)
	if not el.Flag then
		return
	end
	self.Pins[el.Flag] = nil
	QuickToggles.Remove(self, el.Flag)
	if el.View and el.View.RefreshPin then
		el.View.RefreshPin()
	end
end

function Mobile:SetEditMode(on)
	self.EditMode = on == true
	QuickToggles.SetEditMode(self, self.EditMode)
end

---------------------------------------------------------------- config state
function Mobile:GetState()
	return {
		mode = self.Mode,
		button = { x = self.Button.X, y = self.Button.Y },
		pins = Util.DeepCopy(self.Pins),
	}
end

function Mobile:SetState(s)
	if type(s) ~= "table" then
		return
	end
	if type(s.button) == "table" and tonumber(s.button.x) then
		self.Button.X, self.Button.Y = s.button.x, s.button.y
	end
	if type(s.pins) == "table" then
		QuickToggles.Teardown(self)
		self.Pins = {}
		for flag, p in pairs(s.pins) do
			if type(p) == "table" then
				self.Pins[flag] = { x = tonumber(p.x) or 100, y = tonumber(p.y) or 100, size = p.size or "M", alpha = tonumber(p.alpha) or 0 }
			end
		end
	end
	if self.Ctx then
		self:Teardown()
		self:Render(self.Ctx)
	end
	for _, el in pairs(self.Library.Flags.Elements) do
		if el.View and el.View.RefreshPin then
			el.View.RefreshPin()
		end
	end
end

return Mobile
end
__MODULES["Skins/Base/Components"] = function(require)
--[[
	Base component renderers. Every skin inherits these and overrides what looks different.
	Each renderer: function(ctx, element, parent) -> view
	  view.Root               GuiObject (row)
	  view.Update(self, value, instant)
	  view.SetDisabled(self, disabled)
	  view.Addons             frame for inline color pickers / keybinds (optional)
	  view.SetHasSub(self, b) shows the gear (sub-options) button (optional)

	ctx.Style switches read here (all optional):
	  ToggleStyle "Checkbox"|"Pill"   CheckSize   CheckCorner (theme key / number)  CheckGradient (bool)
	  PillW, PillH                    ToggleLabelActive (label brightens when on)
	  LabelAbove (slider/dropdown/textbox label on its own line)   InlineWidth (0..1 control width when inline)
	  SliderTrack (px)  SliderKnob (px, 0 = none)  SliderValue "Right"|"Center"|"Bubble"  SliderGradient (bool)
	  KeyStyle "Brackets"|"Chip"      SwatchW, SwatchH, SwatchCorner
	  ControlCorner (key)             ControlStroke (key|nil)  ControlGradient (bool)
	  RowDividers (bool)              ButtonStyle "Outline"|"Filled"|"Primary"   ButtonHeight (mult)
	  LabelCase "upper"|nil
]]
local Util = require("Core/Util")
local Tween = require("Core/Tween")
local Types = require("Components/Types")
local Input = require("Core/Input")

local C = {}

local function S(ctx, key, default)
	local v = ctx.Style[key]
	if v == nil then
		return default
	end
	return v
end

local function caseText(ctx, text)
	if S(ctx, "LabelCase") == "upper" then
		return string.upper(text)
	end
	return text
end
C.CaseText = caseText

---------------------------------------------------------------- shared bits
function C.Row(ctx, parent, el, height)
	local root = ctx:Frame(parent, { Name = el.Kind .. "_" .. tostring(el.Name), Size = UDim2.new(1, 0, 0, height) })
	if S(ctx, "RowDividers") then
		local d = ctx:Frame(root, { Name = "Divider", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, math.floor(ctx:T("Spacing") / 2)), Size = UDim2.new(1, 0, 0, 1) }, "Divider")
		d.ZIndex = root.ZIndex
	end
	return root
end

function C.Label(ctx, parent, el, props)
	props = props or {}
	props.Text = caseText(ctx, tostring(el.Name))
	props.Size = props.Size or UDim2.fromScale(1, 1)
	props.TextTruncate = Enum.TextTruncate.AtEnd
	return ctx:Text(parent, props, props.ColorKey or S(ctx, "LabelColor", "Text"))
end

-- right aligned horizontal holder for addons / gear / pin
function C.AddonHolder(ctx, parent, rightInset)
	local h = ctx:Frame(parent, {
		Name = "Addons",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(rightInset or 0), 0.5, 0),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = parent.ZIndex + 10,
	})
	ctx:List(h, { Dir = "H", Pad = 4, HA = "Right", VA = "Center" })
	return h
end

-- small icon button (gear, pin)
function C.IconButton(ctx, parent, icon, order, size)
	size = size or 14
	local t = ctx:Touch(size + 4)
	local b = ctx:New("TextButton", { Parent = parent, Name = icon .. "Btn", Size = UDim2.fromOffset(t, t), BackgroundTransparency = 1, LayoutOrder = order, ZIndex = parent.ZIndex + 1 })
	local i = ctx:Icon(b, icon, size, "TextDim", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = b.ZIndex + 1, BgKey = S(ctx, "IconBg", "Panel") })
	ctx:Hover(b, function(st)
		ctx:IconColor(i, (st == "Hover" or st == "Press") and "Text" or (b:GetAttribute("Active") and "Accent" or "TextDim"), true)
	end)
	return b, i
end

-- gear + pin support shared by every element view
function C.Extras(ctx, el, view, holder)
	function view:SetHasSub(has)
		if has and not view.Gear then
			local g = C.IconButton(ctx, holder, "gear", 900, S(ctx, "GearSize", 13))
			view.Gear = g
			g.Activated:Connect(function()
				if el:IsDisabled() then
					return
				end
				ctx.Renderer:OpenPopout(el, g)
			end)
		end
		if view.Gear then
			view.Gear.Visible = has
		end
	end
	if el.Kind == "Toggle" and el.Options.Pinnable then
		local p, icon = C.IconButton(ctx, holder, "pin", 950, 12)
		view.PinButton = p
		local function refresh()
			local pinned = ctx.Library.Mobile:IsPinned(el)
			p:SetAttribute("Active", pinned)
			ctx:IconColor(icon, pinned and "Accent" or "TextDim", true)
			p.Visible = pinned or ctx.IsMobile or view._hover == true
		end
		view.RefreshPin = refresh
		p.Activated:Connect(function()
			el:Pin(not ctx.Library.Mobile:IsPinned(el))
			refresh()
		end)
		refresh()
	end
end

-- Control box (dropdown / textbox / keybind chip)
function C.Box(ctx, parent, props)
	props = props or {}
	local class = props.Class or "TextButton"
	props.Class = nil
	props.Parent = parent
	local b = ctx:New(class, props)
	ctx.Theme:Bind(b, "BackgroundColor3", "Element")
	ctx:Corner(b, S(ctx, "ControlCorner", "SmallCornerRadius"))
	local stroke
	if S(ctx, "ControlStroke") then
		stroke = ctx:Stroke(b, S(ctx, "ControlStroke"), 1)
	end
	if S(ctx, "ControlGradient") then
		ctx:Grad(b, "ElementGradient", { Force = true })
	end
	return b, stroke
end

function C.BoxState(ctx, box, stroke, st)
	local key = (st == "Hover" and "ElementHover") or (st == "Press" and "ElementActive") or "Element"
	ctx.Theme:Bind(box, "BackgroundColor3", key, { Tween = true, Duration = 0.12 })
	if stroke then
		ctx.Theme:Bind(stroke, "Color", (st == "Hover" or st == "Press") and S(ctx, "ControlStrokeHover", "BorderLight") or S(ctx, "ControlStroke"), { Tween = true })
	end
end

---------------------------------------------------------------- Toggle
function C.Toggle(ctx, el, parent)
	local h = ctx:RowH(S(ctx, "ToggleHeight", 1))
	local root = C.Row(ctx, parent, el, h)
	local view = { Root = root }
	local pill = S(ctx, "ToggleStyle", "Checkbox") == "Pill"
	local hit = ctx:Hitbox(root, { ZIndex = root.ZIndex + 1 })
	view.Hit = hit
	local addons = C.AddonHolder(ctx, root)
	view.Addons = addons
	local box, knob, label, check
	if pill then
		local pw, ph = S(ctx, "PillW", 30), S(ctx, "PillH", 16)
		box = ctx:Frame(addons, { Name = "Switch", Size = UDim2.fromOffset(pw, ph), LayoutOrder = 1000 }, "Element")
		ctx:Corner(box, "full")
		if S(ctx, "PillStroke") then
			ctx:Stroke(box, S(ctx, "PillStroke"), 1)
		end
		local k = ph - 6
		knob = ctx:Frame(box, { Size = UDim2.fromOffset(k, k), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0) }, "TextDim")
		ctx:Corner(knob, "full")
		label = C.Label(ctx, root, el, { Size = UDim2.new(1, -pw - 8, 1, 0) })
	else
		-- the whole row is the touch target, so the box keeps its visual size on mobile
		local cs = S(ctx, "CheckSize", 12)
		box = ctx:Frame(root, { Name = "Check", Size = UDim2.fromOffset(cs, cs), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) }, "Element")
		ctx:Corner(box, S(ctx, "CheckCorner", "SmallCornerRadius"))
		if S(ctx, "CheckStroke") then
			ctx:Stroke(box, S(ctx, "CheckStroke"), 1)
		end
		view.Gradient = ctx:Grad(box, S(ctx, "CheckGradientKey", "AccentGradient"), { Force = S(ctx, "CheckGradient", false) })
		if S(ctx, "CheckMark", true) then
			check = ctx:Icon(box, "check", math.floor(cs * 0.8), "TextOnAccent", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
			check.Visible = false
		end
		label = C.Label(ctx, root, el, { Position = UDim2.fromOffset(cs + S(ctx, "CheckGap", 8), 0), Size = UDim2.new(1, -cs - 8, 1, 0) })
	end
	view.Label = label
	view.Box = box
	local hovered = false
	local function paint(instant)
		local on = el.Value
		local dis = el:IsDisabled()
		local tw = not instant
		if pill then
			local pw, ph = S(ctx, "PillW", 30), S(ctx, "PillH", 16)
			local k = ph - 6
			ctx.Theme:Bind(box, "BackgroundColor3", on and "Accent" or (hovered and "ElementHover" or "Element"), { Tween = tw, Alpha = dis and 0.5 or 0 })
			ctx.Theme:Bind(knob, "BackgroundColor3", on and "Knob" or "TextDim", { Tween = tw })
			local pos = on and UDim2.new(0, pw - k - 3, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
			if instant then
				knob.Position = pos
			else
				Tween.Play(knob, { Position = pos }, 0.2)
			end
		else
			if view.Gradient then
				view.Gradient.Enabled = S(ctx, "CheckGradient", false) or (on and ctx:T("AccentGradient").Enabled)
				if not on and S(ctx, "CheckGradient", false) then
					ctx.Theme:BindGradient(view.Gradient, "ElementGradient", { Force = true })
				elseif S(ctx, "CheckGradient", false) then
					ctx.Theme:BindGradient(view.Gradient, S(ctx, "CheckGradientKey", "AccentGradient"), { Force = true })
				end
			end
			ctx.Theme:Bind(box, "BackgroundColor3", on and "Accent" or (hovered and "ElementHover" or "Element"), { Tween = tw, Alpha = dis and 0.5 or 0 })
			if check then
				check.Visible = on
			end
		end
		local labelKey = dis and "TextDisabled" or ((on or hovered or not S(ctx, "ToggleLabelActive", false)) and "Text" or "TextDim")
		ctx.Theme:Bind(label, "TextColor3", labelKey, { Tween = tw })
	end
	ctx:Hover(hit, function(st)
		hovered = st == "Hover" or st == "Press"
		view._hover = hovered
		if view.RefreshPin then
			view.RefreshPin()
		end
		paint(false)
	end, el)
	ctx.Maid:Give(ctx.Input:Drag(hit, {
		Threshold = 8,
		OnTap = function()
			if el:IsDisabled() then
				return
			end
			ctx:Sound("SoundToggle")
			el:Set(not el.Value)
		end,
		LongPress = el.Options.Pinnable and function()
			el:Pin(not ctx.Library.Mobile:IsPinned(el))
			if view.RefreshPin then
				view.RefreshPin()
			end
		end or nil,
	}))
	C.Extras(ctx, el, view, addons)
	function view:Update(_, instant)
		paint(instant)
	end
	function view:SetDisabled()
		paint(true)
	end
	function view:SetText(t)
		label.Text = caseText(ctx, t)
	end
	return view
end

---------------------------------------------------------------- Slider
function C.Slider(ctx, el, parent)
	local o = el.Options
	local above = S(ctx, "LabelAbove", true)
	local trackH = S(ctx, "SliderTrack", 6)
	local valueMode = S(ctx, "SliderValue", "Right")
	local rowH = ctx:RowH()
	local h = above and math.floor(rowH * S(ctx, "SliderRows", 1.55)) or rowH
	local root = C.Row(ctx, parent, el, h)
	local view = { Root = root }
	local labelH = above and (h - trackH - S(ctx, "SliderBottom", 4)) or h
	local label = C.Label(ctx, root, el, { Size = above and UDim2.new(1, -60, 0, labelH) or UDim2.new(1 - S(ctx, "InlineWidth", 0.5), -8, 1, 0) })
	local valueText = ctx:Text(root, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 70, 0, above and labelH or h),
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = valueMode == "Right",
	}, S(ctx, "SliderValueColor", "TextDim"), "FontMono", "SmallTextSize")
	local track = ctx:Frame(root, {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 1),
		Position = above and UDim2.new(0, 0, 1, -S(ctx, "SliderBottom", 4)) or UDim2.new(1 - S(ctx, "InlineWidth", 0.5), 0, 0.5, trackH / 2),
		Size = above and UDim2.new(1, 0, 0, trackH) or UDim2.new(S(ctx, "InlineWidth", 0.5), (valueMode == "Right" or valueMode == "Bubble") and -48 or 0, 0, trackH),
	}, "Element")
	if not above and (valueMode == "Right" or valueMode == "Bubble") then
		valueText.Size = UDim2.new(0, 42, 1, 0)
	end
	ctx:Corner(track, S(ctx, "TrackCorner", "full"))
	if S(ctx, "TrackStroke") then
		ctx:Stroke(track, S(ctx, "TrackStroke"), 1)
	end
	if S(ctx, "ControlGradient") then
		ctx:Grad(track, "ElementGradient", { Force = true })
	end
	local fill = ctx:Frame(track, { Name = "Fill", Size = UDim2.fromScale(0, 1) }, "Accent")
	ctx:Corner(fill, S(ctx, "TrackCorner", "full"))
	ctx:Grad(fill, "AccentGradient", { Force = S(ctx, "SliderGradient", false) })
	local knob
	local ks = S(ctx, "SliderKnob", 0)
	if ks > 0 then
		knob = ctx:Frame(track, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(ks, ks), Position = UDim2.fromScale(0, 0.5), ZIndex = track.ZIndex + 2 }, "Knob")
		ctx:Corner(knob, "full")
		if S(ctx, "KnobStroke") then
			ctx:Stroke(knob, S(ctx, "KnobStroke"), 2)
		end
	end
	local center
	if valueMode == "Center" then
		center = ctx:Text(track, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 60, 0, 12),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = track.ZIndex + 3,
			TextStrokeTransparency = 0.3,
		}, "Text", "FontMono", "SmallTextSize")
	end
	local bubble, bubbleText
	if valueMode == "Bubble" then
		bubble = ctx:Frame(track, { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(38, 18), Position = UDim2.new(0, 0, 0, -6), ZIndex = track.ZIndex + 5, Visible = false }, "Accent")
		ctx:Corner(bubble, "SmallCornerRadius")
		bubbleText = ctx:Text(bubble, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = bubble.ZIndex + 1 }, "TextOnAccent", "FontMono", "SmallTextSize")
		valueText.Visible = true
	end
	local hit = ctx:Hitbox(root, { Size = UDim2.new(track.Size.X.Scale, track.Size.X.Offset, 0, math.max(trackH + 14, ctx:Touch(trackH + 10))), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(track.Position.X.Scale, track.Position.X.Offset, track.Position.Y.Scale, track.Position.Y.Offset - trackH / 2) })
	view.Hit = hit
	local dragging, hovered = false, false
	local function setFromX(x)
		local abs = track.AbsolutePosition.X
		local w = math.max(track.AbsoluteSize.X, 1)
		local t = Util.Clamp((x - abs) / w, 0, 1)
		el:Set(o.Min + (o.Max - o.Min) * t)
	end
	ctx.Maid:Give(ctx.Input:Drag(hit, {
		Enabled = function()
			return not el:IsDisabled()
		end,
		OnStart = function(p)
			dragging = true
			setFromX(Input.ToAbs(p).X)
			view:Paint()
		end,
		OnMove = function(_, p)
			setFromX(Input.ToAbs(p).X)
		end,
		OnEnd = function()
			dragging = false
			view:Paint()
		end,
	}))
	ctx:Hover(hit, function(st)
		hovered = st ~= "Idle" and st ~= "Disabled"
		view:Paint()
	end, el)
	function view:Paint()
		local dis = el:IsDisabled()
		ctx.Theme:Bind(fill, "BackgroundColor3", dis and "TextDisabled" or "Accent", { Tween = true })
		ctx.Theme:Bind(label, "TextColor3", dis and "TextDisabled" or "Text", { Tween = true })
		ctx.Theme:Bind(track, "BackgroundColor3", (hovered or dragging) and "ElementHover" or "Element", { Tween = true })
		if bubble then
			bubble.Visible = (hovered or dragging) and not dis
		end
		if knob then
			Tween.Play(knob, { Size = UDim2.fromOffset(ks + ((hovered or dragging) and 2 or 0), ks + ((hovered or dragging) and 2 or 0)) }, 0.12)
		end
	end
	function view:Update(v, instant)
		local t = (v - o.Min) / math.max(o.Max - o.Min, 1e-9)
		local text = Types.Slider.Format(el, v)
		valueText.Text = text
		if center then
			center.Text = text
			center.Position = UDim2.new(Util.Clamp(t, 0.06, 0.94), 0, 0.5, 0)
		end
		if bubbleText then
			bubbleText.Text = text
			bubble.Size = UDim2.fromOffset(math.max(30, Util.TextWidth(text, ctx:T("SmallTextSize"), ctx:T("FontMono")) + 12), 18)
			bubble.Position = UDim2.new(t, 0, 0, -6)
		end
		local d = (instant or dragging) and 0 or 0.12
		Tween.Play(fill, { Size = UDim2.fromScale(t, 1) }, d)
		if knob then
			Tween.Play(knob, { Position = UDim2.fromScale(t, 0.5) }, d)
		end
	end
	function view:SetDisabled()
		view:Paint()
	end
	function view:SetText(t)
		label.Text = caseText(ctx, t)
	end
	view:Paint()
	return view
end

---------------------------------------------------------------- Dropdown
function C.Dropdown(ctx, el, parent)
	local above = S(ctx, "LabelAbove", true)
	local rowH = ctx:RowH()
	local boxH = math.floor(rowH * S(ctx, "BoxHeight", 0.9))
	local h = above and (rowH + boxH - S(ctx, "AboveOverlap", 4)) or rowH
	local root = C.Row(ctx, parent, el, h)
	local view = { Root = root }
	local iw = S(ctx, "InlineWidth", 0.5)
	local label = C.Label(ctx, root, el, { Size = above and UDim2.new(1, 0, 0, h - boxH) or UDim2.new(1 - iw, -8, 1, 0) })
	local addons = C.AddonHolder(ctx, root)
	if above then
		addons.AnchorPoint = Vector2.new(1, 0)
		addons.Position = UDim2.new(1, 0, 0, 0)
		addons.Size = UDim2.new(0, 0, 0, h - boxH)
	end
	view.Addons = addons
	local box, stroke = C.Box(ctx, root, {
		AnchorPoint = Vector2.new(1, 1),
		Position = above and UDim2.new(1, 0, 1, 0) or UDim2.new(1, 0, 0.5, boxH / 2),
		Size = above and UDim2.new(1, 0, 0, boxH) or UDim2.new(iw, 0, 0, boxH),
	})
	if not above then
		addons.Position = UDim2.new(1 - iw, -6, 0.5, 0)
	end
	view.Hit = box
	local text = ctx:Text(box, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -26, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd }, "TextDim", "FontBody", "SmallTextSize")
	local arrow = ctx:Icon(box, "chevron", S(ctx, "ArrowSize", 10), "TextDim", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0) })
	ctx:Hover(box, function(st)
		C.BoxState(ctx, box, stroke, st)
	end, el)
	local entry
	box.Activated:Connect(function()
		if el:IsDisabled() then
			return
		end
		ctx:Sound("SoundClick")
		if entry then
			ctx:CloseOverlay(entry)
			return
		end
		local list = ctx.Skin.DropdownList(ctx, el, box)
		Tween.Play(arrow, { Rotation = 180 }, 0.15)
		entry = ctx:OpenOverlay(list.Root, function()
			entry = nil
			view.List = nil
			Tween.Play(arrow, { Rotation = 0 }, 0.15)
		end)
		view.List = list
	end)
	C.Extras(ctx, el, view, addons)
	function view:Update(v)
		text.Text = Types.Dropdown.Display(el, v)
		if view.List and view.List.Refresh then
			view.List:Refresh()
		end
	end
	function view:Refresh()
		view:Update(el.Value)
	end
	function view:SetDisabled(d)
		ctx.Theme:Bind(label, "TextColor3", d and "TextDisabled" or "Text")
		ctx.Theme:Bind(text, "TextColor3", d and "TextDisabled" or "TextDim")
	end
	function view:SetText(t)
		label.Text = caseText(ctx, t)
	end
	return view
end

---------------------------------------------------------------- Textbox
function C.Textbox(ctx, el, parent)
	local above = S(ctx, "LabelAbove", true)
	local rowH = ctx:RowH()
	local boxH = math.floor(rowH * S(ctx, "BoxHeight", 0.9))
	local h = above and (rowH + boxH - S(ctx, "AboveOverlap", 4)) or rowH
	local root = C.Row(ctx, parent, el, h)
	local view = { Root = root }
	local iw = S(ctx, "InlineWidth", 0.5)
	local label = C.Label(ctx, root, el, { Size = above and UDim2.new(1, 0, 0, h - boxH) or UDim2.new(1 - iw, -8, 1, 0) })
	local frame, stroke = C.Box(ctx, root, {
		Class = "Frame",
		AnchorPoint = Vector2.new(1, 1),
		Position = above and UDim2.new(1, 0, 1, 0) or UDim2.new(1, 0, 0.5, boxH / 2),
		Size = above and UDim2.new(1, 0, 0, boxH) or UDim2.new(iw, 0, 0, boxH),
	})
	local box = ctx:Text(frame, {
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -16, 1, 0),
		PlaceholderText = el.Options.Placeholder or "...",
		ClearTextOnFocus = el.Options.ClearTextOnFocus == true,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, "Text", "FontBody", "SmallTextSize", "TextBox")
	ctx.Theme:Bind(box, "PlaceholderColor3", "TextDisabled")
	view.Hit = box
	local focused = false
	box.Focused:Connect(function()
		if el:IsDisabled() then
			box:ReleaseFocus()
			return
		end
		focused = true
		if stroke then
			ctx.Theme:Bind(stroke, "Color", "Accent", { Tween = true })
		end
		ctx.Theme:Bind(frame, "BackgroundColor3", "ElementActive", { Tween = true })
	end)
	box.FocusLost:Connect(function(enter)
		focused = false
		C.BoxState(ctx, frame, stroke, "Idle")
		if el.Options.Finished and not enter then
			box.Text = el.Value
			return
		end
		el:Set(box.Text)
		box.Text = el.Value
	end)
	if el.Options.Numeric then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local clean = box.Text:gsub("[^%d%.%-]", "")
			if clean ~= box.Text then
				box.Text = clean
			end
		end)
	end
	ctx:Hover(frame, function(st)
		if not focused then
			C.BoxState(ctx, frame, stroke, st)
		end
	end, el)
	function view:Update(v)
		if not focused then
			box.Text = v
		end
	end
	function view:SetDisabled(d)
		ctx.Theme:Bind(label, "TextColor3", d and "TextDisabled" or "Text")
		box.TextEditable = not d
	end
	function view:SetText(t)
		label.Text = caseText(ctx, t)
	end
	return view
end

---------------------------------------------------------------- keybind
-- key display (shared by row keybind and inline keybind)
function C.KeyDisplay(ctx, el, parent, props)
	local style = S(ctx, "KeyStyle", "Chip")
	props = props or {}
	local b
	if style == "Brackets" then
		b = ctx:Text(parent, {
			Size = UDim2.fromOffset(40, 14),
			AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Right,
			LayoutOrder = props.LayoutOrder,
			AnchorPoint = props.AnchorPoint,
			Position = props.Position,
			ZIndex = parent.ZIndex + 1,
		}, "TextDisabled", "FontMono", "SmallTextSize", "TextButton")
	else
		b = ctx:New("TextButton", {
			Parent = parent,
			Size = UDim2.fromOffset(28, math.floor(ctx:RowH() * 0.7)),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = props.LayoutOrder,
			AnchorPoint = props.AnchorPoint,
			Position = props.Position,
			ZIndex = parent.ZIndex + 1,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, { BackgroundColor3 = "Element", TextColor3 = "TextDim", Font = "FontMono", TextSize = "SmallTextSize" })
		b.BackgroundTransparency = 0
		ctx:Corner(b, "SmallCornerRadius")
		ctx:Pad(b, 0, 6, 0, 6)
		if S(ctx, "ControlStroke") then
			ctx:Stroke(b, S(ctx, "ControlStroke"), 1)
		end
	end
	local listening = false
	local function render()
		if listening then
			b.Text = style == "Brackets" and "[...]" or "..."
		else
			local k = el:KeyText()
			b.Text = style == "Brackets" and ("[" .. k .. "]") or k
		end
	end
	ctx:Hover(b, function(st)
		ctx.Theme:Bind(b, "TextColor3", listening and "Accent" or (st == "Hover" and "Text" or (style == "Brackets" and "TextDisabled" or "TextDim")), { Tween = true })
		if style ~= "Brackets" then
			ctx.Theme:Bind(b, "BackgroundColor3", st == "Hover" and "ElementHover" or "Element", { Tween = true })
		end
	end, el)
	b.Activated:Connect(function()
		if el:IsDisabled() or listening then
			return
		end
		listening = true
		render()
		ctx.Theme:Bind(b, "TextColor3", "Accent")
		ctx.Library:CaptureKey(function(key)
			listening = false
			el:Set({ Key = key, Mode = el.Value.Mode })
			render()
			ctx.Theme:Bind(b, "TextColor3", style == "Brackets" and "TextDisabled" or "TextDim")
		end)
	end)
	-- right click / long press: mode menu
	local function modeMenu()
		if el:IsDisabled() then
			return
		end
		local items = {}
		for _, m in ipairs(Types.Modes) do
			table.insert(items, { Text = m, Selected = el.Value.Mode == m, Callback = function()
				el:Set({ Key = el.Value.Key, Mode = m })
			end })
		end
		ctx.Skin.ContextMenu(ctx, b, items)
	end
	b.MouseButton2Click:Connect(modeMenu)
	ctx.Maid:Give(ctx.Input:Drag(b, { Threshold = 10, LongPress = modeMenu, LongPressTime = 0.55 }))
	return b, render
end

function C.Keybind(ctx, el, parent)
	local root = C.Row(ctx, parent, el, ctx:RowH())
	local view = { Root = root }
	local label = C.Label(ctx, root, el, { Size = UDim2.new(1, -80, 1, 0) })
	local addons = C.AddonHolder(ctx, root)
	view.Addons = addons
	local key, render = C.KeyDisplay(ctx, el, addons, { LayoutOrder = 1000 })
	view.Hit = key
	C.Extras(ctx, el, view, addons)
	function view:Update()
		render()
	end
	function view:SetDisabled(d)
		ctx.Theme:Bind(label, "TextColor3", d and "TextDisabled" or "Text")
	end
	function view:SetText(t)
		label.Text = caseText(ctx, t)
	end
	return view
end

function C.InlineKeybind(ctx, el, holder)
	local key, render = C.KeyDisplay(ctx, el, holder, {})
	local view = { Root = key }
	function view:Update()
		render()
	end
	return view
end

---------------------------------------------------------------- color picker
function C.Swatch(ctx, el, parent, props)
	props = props or {}
	local w, h = S(ctx, "SwatchW", 18), S(ctx, "SwatchH", 10)
	-- transparent button sized for touch, the visible swatch sits centered inside it
	local hw, hh = ctx:Touch(w), ctx.IsMobile and ctx:Touch(h) or h
	local b = ctx:New("TextButton", {
		Parent = parent,
		Name = "Swatch",
		Size = UDim2.fromOffset(hw, hh),
		LayoutOrder = props.LayoutOrder,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		ZIndex = parent.ZIndex + 1,
		BackgroundTransparency = 1,
	})
	local sw = ctx:New("Frame", { Parent = b, Name = "Color", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, h), ZIndex = b.ZIndex + 1 })
	ctx:Corner(sw, S(ctx, "SwatchCorner", "SmallCornerRadius"))
	local stroke = ctx:Stroke(sw, S(ctx, "SwatchStroke", "BorderDark"), 1)
	if S(ctx, "SwatchShade", false) then
		local shade = ctx:Shade(sw, 90, 0, 0)
		shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	end
	ctx:Hover(b, function(st)
		ctx.Theme:Bind(stroke, "Color", st == "Idle" and S(ctx, "SwatchStroke", "BorderDark") or "Accent", { Tween = true })
	end, el)
	local entry
	b.Activated:Connect(function()
		if el:IsDisabled() then
			return
		end
		ctx:Sound("SoundClick")
		if entry then
			ctx:CloseOverlay(entry)
			return
		end
		local panel = ctx.Skin.ColorPanel(ctx, el, b)
		entry = ctx:OpenOverlay(panel.Root, function()
			entry = nil
		end)
	end)
	local function update(v)
		sw.BackgroundColor3 = v.Color
		sw.BackgroundTransparency = v.Transparency * 0.8
	end
	return b, update
end

function C.ColorPicker(ctx, el, parent)
	local root = C.Row(ctx, parent, el, ctx:RowH())
	local view = { Root = root }
	local label = C.Label(ctx, root, el, { Size = UDim2.new(1, -60, 1, 0) })
	local addons = C.AddonHolder(ctx, root)
	view.Addons = addons
	local sw, update = C.Swatch(ctx, el, addons, { LayoutOrder = 1000 })
	view.Hit = sw
	C.Extras(ctx, el, view, addons)
	function view:Update(v)
		update(v)
	end
	function view:SetDisabled(d)
		ctx.Theme:Bind(label, "TextColor3", d and "TextDisabled" or "Text")
	end
	function view:SetText(t)
		label.Text = caseText(ctx, t)
	end
	return view
end

function C.InlineColorPicker(ctx, el, holder)
	local sw, update = C.Swatch(ctx, el, holder, {})
	local view = { Root = sw }
	function view:Update(v)
		update(v)
	end
	return view
end

---------------------------------------------------------------- button
function C.Button(ctx, el, parent)
	local h = ctx:RowH(S(ctx, "ButtonHeight", 1))
	local root = C.Row(ctx, parent, el, h)
	local view = { Root = root }
	local style = el.Options.Style or S(ctx, "ButtonStyle", "Filled")
	local inset = S(ctx, "ButtonInset", 2)
	local b = ctx:New("TextButton", {
		Parent = root,
		Size = UDim2.new(1, 0, 1, -inset * 2),
		Position = UDim2.fromOffset(0, inset),
		Text = caseText(ctx, el.Name),
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		ClipsDescendants = true,
	}, { Font = S(ctx, "ButtonFont", "FontBody"), TextSize = "TextSize" })
	ctx:Corner(b, S(ctx, "ButtonCorner", S(ctx, "ControlCorner", "SmallCornerRadius")))
	local stroke
	if style == "Outline" or S(ctx, "ButtonStroke") then
		stroke = ctx:Stroke(b, S(ctx, "ButtonStroke", "Border"), 1)
	end
	local grad
	if S(ctx, "ControlGradient") and style ~= "Primary" then
		grad = ctx:Grad(b, "ElementGradient", { Force = true })
	elseif style == "Primary" then
		grad = ctx:Grad(b, "AccentGradient")
	end
	view.Hit = b
	local confirming = false
	local function paint(st)
		local dis = el:IsDisabled()
		if style == "Primary" then
			ctx.Theme:Bind(b, "BackgroundColor3", "Accent", { Tween = true, Alpha = dis and 0.6 or (st == "Hover" and 0.12 or (st == "Press" and 0.25 or 0)) })
			ctx.Theme:Bind(b, "TextColor3", dis and "TextDisabled" or "TextOnAccent", { Tween = true })
		elseif style == "Outline" then
			ctx.Theme:Bind(b, "BackgroundColor3", st == "Press" and "ElementActive" or "ElementHover", { Tween = true, Alpha = st == "Idle" and 1 or 0 })
			ctx.Theme:Bind(b, "TextColor3", dis and "TextDisabled" or (st == "Idle" and "TextDim" or "Text"), { Tween = true })
		else
			ctx.Theme:Bind(b, "BackgroundColor3", (st == "Hover" and "ElementHover") or (st == "Press" and "ElementActive") or "Element", { Tween = true, Duration = 0.1 })
			ctx.Theme:Bind(b, "TextColor3", dis and "TextDisabled" or (confirming and "Warning" or (st == "Idle" and S(ctx, "ButtonText", "Text") or "Text")), { Tween = true })
		end
		if stroke then
			ctx.Theme:Bind(stroke, "Color", (st == "Hover" or st == "Press") and (S(ctx, "ButtonStrokeHover", "Accent")) or S(ctx, "ButtonStroke", "Border"), { Tween = true })
		end
		if S(ctx, "ButtonPressScale", true) then
			Tween.Play(b, { Size = UDim2.new(1, st == "Press" and -4 or 0, 1, -inset * 2 - (st == "Press" and 2 or 0)), Position = UDim2.fromOffset(st == "Press" and 2 or 0, inset + (st == "Press" and 1 or 0)) }, 0.08)
		end
	end
	local refresh = ctx:Hover(b, paint, el)
	b.Activated:Connect(function()
		if el:IsDisabled() then
			return
		end
		ctx:Sound("SoundClick")
		if el.Options.Confirm and not confirming then
			confirming = true
			b.Text = caseText(ctx, el.Options.ConfirmText or "Are you sure?")
			refresh()
			task.delay(2.5, function()
				if confirming then
					confirming = false
					b.Text = caseText(ctx, el.Name)
					refresh()
				end
			end)
			return
		end
		if confirming then
			confirming = false
			b.Text = caseText(ctx, el.Name)
			refresh()
		end
		el:FireCallback(nil)
	end)
	function view:SetDisabled()
		refresh()
	end
	function view:SetText(t)
		b.Text = caseText(ctx, t)
	end
	paint("Idle")
	return view
end

---------------------------------------------------------------- label / paragraph / divider
function C.LabelElement(ctx, el, parent)
	local root = C.Row(ctx, parent, el, ctx:RowH(S(ctx, "LabelHeight", 0.85)))
	local view = { Root = root }
	local label = ctx:Text(root, {
		Size = UDim2.new(1, -40, 1, 0),
		Text = el.Options.Text or el.Name,
		TextWrapped = el.Options.Wrap == true,
		RichText = el.Options.RichText == true,
	}, el.Options.Color or "TextDim")
	local addons = C.AddonHolder(ctx, root)
	view.Addons = addons
	C.Extras(ctx, el, view, addons)
	function view:SetText(t)
		label.Text = t
	end
	function view:SetDisabled(d)
		ctx.Theme:Bind(label, "TextColor3", d and "TextDisabled" or (el.Options.Color or "TextDim"))
	end
	return view
end

function C.Paragraph(ctx, el, parent)
	local root = ctx:Frame(parent, { Name = "Paragraph", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	ctx:List(root, { Pad = 3 })
	ctx:Pad(root, 2, 0, 4, 0)
	local view = { Root = root }
	local title = ctx:Text(root, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = caseText(ctx, el.Options.Title or el.Name), TextWrapped = true, LayoutOrder = 1 }, "Text", "FontTitle", "TextSize")
	local body = ctx:Text(root, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = el.Options.Content or "",
		TextWrapped = true,
		RichText = el.Options.RichText == true,
		LayoutOrder = 2,
	}, "TextDim", "FontBody", "SmallTextSize")
	function view:SetText(t)
		title.Text = caseText(ctx, t)
	end
	function view:SetContent(t)
		body.Text = t
	end
	return view
end

function C.Divider(ctx, el, parent)
	local text = el.Options.Text
	local root = C.Row(ctx, parent, el, text and ctx:RowH(0.8) or math.max(6, ctx:T("Spacing")))
	local view = { Root = root }
	if text then
		local t = ctx:Text(root, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = caseText(ctx, text),
			TextXAlignment = Enum.TextXAlignment.Center,
		}, "TextDim", "FontBody", "SmallTextSize")
		local w = Util.TextWidth(t.Text, ctx:T("SmallTextSize"), ctx:T("FontBody")) / 2 + 8
		ctx:Frame(root, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0.5, -w, 0, 1) }, "Divider")
		ctx:Frame(root, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.new(0.5, -w, 0, 1) }, "Divider")
	else
		ctx:Frame(root, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 1) }, "Divider")
	end
	return view
end

function C.ESPPreview(ctx, el, parent)
	return require("ESPPreview").Render(ctx, el, parent)
end

-- map element kinds to renderers
return {
	Toggle = C.Toggle,
	Slider = C.Slider,
	Dropdown = C.Dropdown,
	Textbox = C.Textbox,
	Keybind = C.Keybind,
	ColorPicker = C.ColorPicker,
	Button = C.Button,
	Label = C.LabelElement,
	Paragraph = C.Paragraph,
	Divider = C.Divider,
	ESPPreview = C.ESPPreview,
	InlineColorPicker = C.InlineColorPicker,
	InlineKeybind = C.InlineKeybind,
	_ = C, -- helpers for skins
}
end
__MODULES["Skins/Base/Overlays"] = function(require)
--[[
	Base floating / overlay renderers: dropdown list, color panel, sub-option popout, context menu,
	notifications, dialog, tooltip, watermark, keybind list, mobile floating button, quick toggle,
	group box and a generic loader. Skins override any of these.
]]
local Util = require("Core/Util")
local Tween = require("Core/Tween")
local Input = require("Core/Input")
local Types = require("Components/Types")

local O = {}

local function S(ctx, key, default)
	local v = ctx.Style[key]
	if v == nil then
		return default
	end
	return v
end

-- standard floating panel frame
function O.Panel(ctx, props)
	props = props or {}
	local f = ctx:New("Frame", props, { BackgroundColor3 = S(ctx, "PanelKey", "Panel") })
	ctx:Corner(f, S(ctx, "PanelCorner", "SmallCornerRadius"))
	ctx:Stroke(f, S(ctx, "PanelStroke", "Border"), 1)
	return f
end

---------------------------------------------------------------- group box
function O.Group(ctx, group, column)
	local root = ctx:Frame(column, { Name = "Group_" .. group.Name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, "Panel")
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "Border", "BorderThickness")
	ctx:List(root, {})
	local header = ctx:Frame(root, { Size = UDim2.new(1, 0, 0, ctx:RowH(0.95)), LayoutOrder = 1 })
	ctx:Text(header, { Text = group.Name, Position = UDim2.fromOffset(ctx:T("Padding"), 0), Size = UDim2.new(1, -ctx:T("Padding") * 2, 1, 0) }, "Text", "FontTitle", "TextSize")
	ctx:Frame(header, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1) }, "Divider")
	local container = ctx:Frame(root, { Name = "Container", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	local p = ctx:T("Padding")
	ctx:Pad(container, p * 0.6, p, p * 0.8, p)
	ctx:List(container, { Pad = ctx:T("Spacing") })
	return { Root = root, Container = container }
end

---------------------------------------------------------------- dropdown list
function O.DropdownList(ctx, el, anchor)
	local o = el.Options
	local itemH = ctx:RowH(S(ctx, "ListItemH", 0.85))
	local searchable = o.Searchable or #o.Values > 10
	local count = math.min(#o.Values, S(ctx, "ListMaxItems", 8))
	local height = count * itemH + (searchable and (itemH + 6) or 0) + 8
	local width = math.max(anchor.AbsoluteSize.X / ctx.Library.CurrentScale, 140)
	local root = O.Panel(ctx, { Name = "DropdownList", ClipsDescendants = true })
	ctx:PlaceNear(root, anchor, width, math.max(height, itemH + 8), S(ctx, "ListGap", 3))
	local finalSize = root.Size
	root.Size = UDim2.fromOffset(width, 0)
	Tween.Play(root, { Size = finalSize }, 0.16)
	local y = 4
	local search
	if searchable then
		local sf = ctx:Frame(root, { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0, itemH) }, "Element")
		ctx:Corner(sf, "SmallCornerRadius")
		ctx:Icon(sf, "search", 11, "TextDim", { Position = UDim2.new(0, 6, 0.5, -5) })
		search = ctx:Text(sf, { Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -26, 1, 0), PlaceholderText = "Search...", ClearTextOnFocus = false }, "Text", "FontBody", "SmallTextSize", "TextBox")
		ctx.Theme:Bind(search, "PlaceholderColor3", "TextDisabled")
		y = itemH + 10
	end
	local scroll = ctx:New("ScrollingFrame", { Parent = root, Position = UDim2.fromOffset(4, y), Size = UDim2.new(1, -8, 1, -y - 4) }, { ScrollBarImageColor3 = "Accent" })
	ctx:List(scroll, {})
	local items = {}
	local function selected(v)
		if o.Multi then
			return table.find(el.Value, v) ~= nil
		end
		return el.Value == v
	end
	local view = { Root = root }
	local function build()
		for _, it in ipairs(items) do
			it.Button:Destroy()
		end
		items = {}
		for i, v in ipairs(o.Values) do
			local b = ctx:New("TextButton", { Parent = scroll, Size = UDim2.new(1, 0, 0, itemH), LayoutOrder = i, BackgroundTransparency = 1 })
			ctx:Corner(b, "SmallCornerRadius")
			local t = ctx:Text(b, { Text = tostring(v), Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -30, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd }, "TextDim", "FontBody", "SmallTextSize")
			local mark = ctx:Icon(b, "check", 10, "Accent", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0) })
			local it = { Button = b, Text = t, Mark = mark, Value = v }
			function it.Paint(hover)
				local sel = selected(v)
				mark.Visible = sel
				ctx.Theme:Bind(t, "TextColor3", sel and "Accent" or (hover and "Text" or "TextDim"), { Tween = true })
				ctx.Theme:Bind(b, "BackgroundColor3", "ElementHover", { Alpha = hover and 0 or 1, Tween = true })
				if S(ctx, "ListBoldSelected", false) then
					ctx.Theme:Bind(t, "Font", sel and "FontTitle" or "FontBody", Util.FontEnum)
				end
			end
			ctx:Hover(b, function(st)
				it.Paint(st ~= "Idle")
			end)
			b.Activated:Connect(function()
				ctx:Sound("SoundClick")
				if o.Multi then
					local list = table.clone(el.Value)
					local idx = table.find(list, v)
					if idx then
						table.remove(list, idx)
					else
						table.insert(list, v)
					end
					el:Set(list)
				else
					el:Set(v)
					ctx:CloseOverlay()
				end
			end)
			it.Paint(false)
			table.insert(items, it)
		end
	end
	build()
	if search then
		search:GetPropertyChangedSignal("Text"):Connect(function()
			local q = string.lower(search.Text)
			for _, it in ipairs(items) do
				it.Button.Visible = q == "" or string.find(string.lower(tostring(it.Value)), q, 1, true) ~= nil
			end
		end)
	end
	function view:Refresh()
		if #items ~= #o.Values then
			build()
		else
			for _, it in ipairs(items) do
				it.Paint(false)
			end
		end
	end
	return view
end

---------------------------------------------------------------- color panel (HSV + alpha + hex + rainbow)
function O.ColorPanel(ctx, el, anchor)
	local W, H = 236, 252
	local root = O.Panel(ctx, { Name = "ColorPanel" })
	ctx:PlaceNear(root, anchor, W, H)
	local v = el.Value
	local hue, sat, val = v.Color:ToHSV()
	local alpha = 1 - (v.Transparency or 0)
	local rainbow = v.Rainbow
	-- saturation / value square
	local sv = ctx:New("Frame", { Parent = root, Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -46, 0, 150), BackgroundColor3 = Color3.fromHSV(hue, 1, 1) })
	ctx:Corner(sv, 3)
	local white = ctx:New("Frame", { Parent = sv, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) })
	ctx:Corner(white, 3)
	local wg = Instance.new("UIGradient")
	wg.Transparency = NumberSequence.new(0, 1)
	wg.Parent = white
	local black = ctx:New("Frame", { Parent = sv, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0) })
	ctx:Corner(black, 3)
	local bg = Instance.new("UIGradient")
	bg.Rotation = 90
	bg.Transparency = NumberSequence.new(1, 0)
	bg.Parent = black
	local svCursor = ctx:New("Frame", { Parent = sv, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, ZIndex = 5 })
	ctx:Corner(svCursor, "full")
	local cs = Instance.new("UIStroke")
	cs.Color = Color3.new(1, 1, 1)
	cs.Thickness = 2
	cs.Parent = svCursor
	-- hue bar
	local hueBar = ctx:New("Frame", { Parent = root, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(16, 150), BackgroundColor3 = Color3.new(1, 1, 1) })
	ctx:Corner(hueBar, 3)
	local hg = Instance.new("UIGradient")
	hg.Rotation = 90
	local kps = {}
	for i = 0, 6 do
		table.insert(kps, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6 % 1, 1, 1)))
	end
	hg.Color = ColorSequence.new(kps)
	hg.Parent = hueBar
	local hueCursor = ctx:New("Frame", { Parent = hueBar, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 4, 0, 4), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 5 })
	ctx:Corner(hueCursor, 2)
	-- alpha bar
	local alphaBar = ctx:New("Frame", { Parent = root, Position = UDim2.fromOffset(10, 168), Size = UDim2.new(1, -20, 0, 12), BackgroundColor3 = v.Color })
	ctx:Corner(alphaBar, 3)
	local ag = Instance.new("UIGradient")
	ag.Transparency = NumberSequence.new(0.9, 0)
	ag.Parent = alphaBar
	local alphaCursor = ctx:New("Frame", { Parent = alphaBar, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, 4, 1, 4), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 5 })
	ctx:Corner(alphaCursor, 2)
	-- hex + rainbow + preview
	local hexFrame = ctx:Frame(root, { Position = UDim2.fromOffset(10, 190), Size = UDim2.new(0.5, -14, 0, 24) }, "Element")
	ctx:Corner(hexFrame, "SmallCornerRadius")
	local hex = ctx:Text(hexFrame, { Position = UDim2.fromOffset(6, 0), Size = UDim2.new(1, -12, 1, 0), ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Center }, "Text", "FontMono", "SmallTextSize", "TextBox")
	local rb = ctx:New("TextButton", { Parent = root, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 190), Size = UDim2.new(0.5, -14, 0, 24), Text = "Rainbow", TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0 }, { Font = "FontBody", TextSize = "SmallTextSize" })
	ctx:Corner(rb, "SmallCornerRadius")
	local preview = ctx:New("Frame", { Parent = root, Position = UDim2.fromOffset(10, 222), Size = UDim2.new(1, -20, 0, 20) })
	ctx:Corner(preview, "SmallCornerRadius")
	local previewText = ctx:Text(preview, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.5 }, "Text", "FontMono", "SmallTextSize")

	local function paint()
		local c = Color3.fromHSV(hue, sat, val)
		sv.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
		svCursor.Position = UDim2.fromScale(sat, 1 - val)
		hueCursor.Position = UDim2.fromScale(0.5, hue)
		alphaBar.BackgroundColor3 = c
		alphaCursor.Position = UDim2.fromScale(alpha, 0.5)
		hex.Text = string.upper(Util.ColorToHex(c))
		preview.BackgroundColor3 = c
		preview.BackgroundTransparency = (1 - alpha) * 0.8
		previewText.Text = string.format("%d, %d, %d  ·  %d%%", c.R * 255, c.G * 255, c.B * 255, math.floor(alpha * 100 + 0.5))
		ctx.Theme:Bind(rb, "BackgroundColor3", rainbow and "Accent" or "Element")
		ctx.Theme:Bind(rb, "TextColor3", rainbow and "TextOnAccent" or "TextDim")
	end
	local function commit()
		el:Set({ Color = Color3.fromHSV(hue, sat, val), Transparency = 1 - alpha, Rainbow = rainbow })
	end
	local function rel(gui, p)
		local a = Input.ToAbs(p)
		local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
		return Util.Clamp((a.X - pos.X) / math.max(size.X, 1), 0, 1), Util.Clamp((a.Y - pos.Y) / math.max(size.Y, 1), 0, 1)
	end
	local function dragger(gui, fn)
		local hit = ctx:Hitbox(gui, { ZIndex = 6 })
		ctx.Maid:Give(ctx.Input:Drag(hit, {
			OnStart = function(p)
				fn(rel(gui, p))
				rainbow = false
				paint()
				commit()
			end,
			OnMove = function(_, p)
				fn(rel(gui, p))
				paint()
				commit()
			end,
		}))
	end
	dragger(sv, function(x, y)
		sat, val = x, 1 - y
	end)
	dragger(hueBar, function(_, y)
		hue = y
	end)
	dragger(alphaBar, function(x)
		alpha = x
	end)
	hex.FocusLost:Connect(function()
		local c = Util.HexToColor(hex.Text)
		if c then
			hue, sat, val = c:ToHSV()
			rainbow = false
			commit()
		end
		paint()
	end)
	rb.Activated:Connect(function()
		rainbow = not rainbow
		commit()
		paint()
	end)
	local conn = el.Changed:Connect(function(nv)
		if nv.Rainbow then
			hue, sat, val = nv.Color:ToHSV()
			paint()
		end
	end)
	root.Destroying:Connect(function()
		conn.Disconnect()
	end)
	paint()
	return { Root = root }
end

---------------------------------------------------------------- sub-options popout
function O.Popout(ctx, group, anchor)
	local W = S(ctx, "PopoutWidth", 240)
	local root = O.Panel(ctx, { Name = "Popout", Size = UDim2.fromOffset(W, 0), AutomaticSize = Enum.AutomaticSize.Y })
	local p, s = ctx:RectOf(anchor)
	local screen = ctx.Library:ScreenSize()
	local x = p.X + s.X + 8
	if x + W > screen.X - 8 then
		x = p.X - W - 8
	end
	root.Position = UDim2.fromOffset(Util.Clamp(x, 8, screen.X - W - 8), Util.Clamp(p.Y - 10, 8, screen.Y - 120))
	ctx:List(root, {})
	local header = ctx:Frame(root, { Size = UDim2.new(1, 0, 0, ctx:RowH(0.9)), LayoutOrder = 1 })
	ctx:Text(header, { Text = group.Name, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0) }, "Text", "FontTitle", "SmallTextSize")
	ctx:Frame(header, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1) }, "Divider")
	local container = ctx:Frame(root, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	ctx:Pad(container, 8, 10, 10, 10)
	ctx:List(container, { Pad = ctx:T("Spacing") })
	local sc = Instance.new("UIScale")
	sc.Scale = 0.96
	sc.Parent = root
	Tween.Play(sc, { Scale = 1 }, 0.15)
	return { Root = root, Container = container }
end

---------------------------------------------------------------- context menu
function O.ContextMenu(ctx, anchor, items)
	local itemH = ctx:RowH(0.85)
	local W = 140
	local root = O.Panel(ctx, { Name = "ContextMenu" })
	ctx:PlaceNear(root, anchor, W, #items * itemH + 8)
	local list = ctx:Frame(root, { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8) })
	ctx:List(list, {})
	local entry
	for i, it in ipairs(items) do
		local b = ctx:New("TextButton", { Parent = list, Size = UDim2.new(1, 0, 0, itemH), LayoutOrder = i, BackgroundTransparency = 1 })
		ctx:Corner(b, "SmallCornerRadius")
		local key = it.Danger and "Error" or (it.Selected and "Accent" or "TextDim")
		local t = ctx:Text(b, { Text = it.Text, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0) }, key, "FontBody", "SmallTextSize")
		ctx:Hover(b, function(st)
			ctx.Theme:Bind(b, "BackgroundColor3", "ElementHover", { Alpha = st == "Idle" and 1 or 0, Tween = true })
			ctx.Theme:Bind(t, "TextColor3", st == "Idle" and key or (it.Danger and "Error" or "Text"), { Tween = true })
		end)
		b.Activated:Connect(function()
			ctx:CloseOverlay(entry)
			if it.Callback then
				task.spawn(it.Callback)
			end
		end)
	end
	entry = ctx:OpenOverlay(root)
	return entry
end

---------------------------------------------------------------- notification
local TYPE_KEY = { Info = "Accent", Success = "Success", Warning = "Warning", Error = "Error" }
local TYPE_ICON = { Info = "info", Success = "check", Warning = "warning", Error = "close" }
O.TypeKey = TYPE_KEY
O.TypeIcon = TYPE_ICON

function O.Notification(ctx, opts, holder)
	local W = ctx:T("NotifyWidth")
	local key = TYPE_KEY[opts.Type] or "Accent"
	local root = ctx:Frame(holder, { Name = "Notification", Size = UDim2.fromOffset(W, 0), AutomaticSize = Enum.AutomaticSize.Y })
	local card = ctx:Frame(root, { Size = UDim2.fromOffset(W, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(W + 30, 0) }, "Panel")
	ctx:Corner(card, "CornerRadius")
	ctx:Stroke(card, "Border", 1)
	ctx:Frame(card, { Name = "Stripe", Size = UDim2.new(0, 3, 1, 0) }, key)
	local body = ctx:Frame(card, { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	ctx:Pad(body, 10, 12, 10, 14)
	ctx:List(body, { Pad = 3 })
	card = body
	local head = ctx:Frame(card, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 1 })
	ctx:Icon(head, opts.Icon or TYPE_ICON[opts.Type] or "info", 12, key, { Position = UDim2.fromOffset(0, 2) })
	ctx:Text(head, { Text = opts.Title or "", Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -18, 1, 0) }, "Text", "FontTitle", "TextSize")
	ctx:Text(card, { Text = opts.Content or "", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 2 }, "TextDim", "FontBody", "SmallTextSize")
	local bar = ctx:Frame(card, { Size = UDim2.new(1, 0, 0, 2), LayoutOrder = 3 }, "Element")
	local fill = ctx:Frame(bar, { Size = UDim2.fromScale(1, 1) }, key)
	card = card.Parent
	Tween.Play(card, { Position = UDim2.fromOffset(0, 0) }, 0.3)
	if opts.Duration and opts.Duration > 0 then
		Tween.Play(fill, { Size = UDim2.fromScale(0, 1) }, opts.Duration * Tween.Speed, Enum.EasingStyle.Linear)
	end
	local view = { Root = root }
	function view:Close(instant)
		if instant then
			root:Destroy()
			return
		end
		Tween.Play(card, { Position = UDim2.fromOffset(W + 30, 0) }, 0.25)
		task.delay(Tween.Duration(0.25), function()
			root:Destroy()
		end)
	end
	return view
end

---------------------------------------------------------------- dialog
function O.Dialog(ctx, opts)
	local layer = ctx.Layers.Dialog
	local backdrop = ctx:New("TextButton", { Parent = layer, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Name = "Dialog" }, {})
	ctx.Theme:Bind(backdrop, "BackgroundColor3", "Overlay", { Alpha = 1 })
	ctx.Theme:Bind(backdrop, "BackgroundColor3", "Overlay", { Alpha = 0.45, Tween = true })
	local W = math.min(S(ctx, "DialogWidth", 340), ctx.Library:ScreenSize().X - 32)
	local box = ctx:Frame(backdrop, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, 0), AutomaticSize = Enum.AutomaticSize.Y }, "Panel")
	ctx:Corner(box, "CornerRadius")
	ctx:Stroke(box, S(ctx, "DialogStroke", "Border"), 1)
	ctx:Pad(box, 16, 16, 14, 16)
	ctx:List(box, { Pad = 8 })
	local sc = Instance.new("UIScale")
	sc.Scale = 0.9
	sc.Parent = box
	Tween.Play(sc, { Scale = 1 }, 0.2, Enum.EasingStyle.Back)
	ctx:Text(box, { Text = opts.Title or "", Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1 }, "Text", "FontTitle", "TitleSize")
	ctx:Text(box, { Text = opts.Content or "", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 2 }, "TextDim", "FontBody", "TextSize")
	local row = ctx:Frame(box, { Size = UDim2.new(1, 0, 0, ctx:RowH()), LayoutOrder = 3 })
	ctx:List(row, { Dir = "H", Pad = 8, HA = "Right" })
	for i, b in ipairs(opts.Buttons) do
		local btn = ctx:New("TextButton", {
			Parent = row,
			Size = UDim2.new(0, 0, 1, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = b.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			LayoutOrder = i,
			BackgroundTransparency = 0,
		}, { Font = "FontTitle", TextSize = "SmallTextSize" })
		ctx:Pad(btn, 0, 16, 0, 16)
		ctx:Corner(btn, "SmallCornerRadius")
		local key = b.Primary and "Accent" or "Element"
		ctx.Theme:Bind(btn, "BackgroundColor3", key)
		ctx.Theme:Bind(btn, "TextColor3", b.Primary and "TextOnAccent" or "Text")
		ctx:Hover(btn, function(st)
			ctx.Theme:Bind(btn, "BackgroundColor3", b.Primary and "Accent" or (st == "Idle" and "Element" or "ElementHover"), { Tween = true, Alpha = (b.Primary and st ~= "Idle") and 0.15 or 0 })
		end)
		btn.Activated:Connect(b._click)
	end
	local view = {}
	function view:Close()
		Tween.Play(sc, { Scale = 0.92 }, 0.12)
		ctx.Theme:Bind(backdrop, "BackgroundColor3", "Overlay", { Alpha = 1, Tween = true })
		box.Visible = false
		task.delay(Tween.Duration(0.15), function()
			backdrop:Destroy()
		end)
	end
	return view
end

---------------------------------------------------------------- tooltip
function O.Tooltip(ctx)
	local root = ctx:Frame(ctx.Layers.Tooltip, { Name = "Tooltip", Visible = false, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY }, "Tooltip")
	ctx:Corner(root, "SmallCornerRadius")
	ctx:Stroke(root, "Border", 1)
	ctx:Pad(root, 5, 8, 5, 8)
	local t = ctx:Text(root, { AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0), TextWrapped = false }, "Text", "FontBody", "SmallTextSize")
	local sizeC = Instance.new("UISizeConstraint")
	sizeC.MaxSize = Vector2.new(260, 400)
	sizeC.Parent = root
	local view = { Root = root }
	function view:Show(text, gui)
		t.Text = text
		local p, s = ctx:RectOf(gui)
		root.Position = UDim2.fromOffset(p.X, p.Y + s.Y + 4)
		root.Visible = true
	end
	function view:Hide()
		root.Visible = false
	end
	return view
end

---------------------------------------------------------------- watermark
function O.Watermark(ctx)
	local inset = Util.GuiInset()
	local root = ctx:Frame(ctx.Layers.Notify, { Name = "Watermark", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, inset.Y + 8), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X }, "Panel")
	ctx:Corner(root, "SmallCornerRadius")
	ctx:Stroke(root, "Border", 1)
	ctx:Pad(root, 0, 10, 0, 10)
	local accent = ctx:Frame(root, { Size = UDim2.new(1, 20, 0, 2), Position = UDim2.fromOffset(-10, 0) }, "Accent")
	ctx:Grad(accent, S(ctx, "WatermarkGradient", "AccentGradient"))
	local t = ctx:Text(root, { Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X }, "Text", "FontMono", "SmallTextSize")
	local view = { Root = root }
	function view:SetText(s)
		t.Text = s
	end
	return view
end

---------------------------------------------------------------- keybind list
function O.KeybindList(ctx)
	local root = ctx:Frame(ctx.Layers.Notify, { Name = "KeybindList", Position = UDim2.new(0, 12, 0.4, 0), Size = UDim2.fromOffset(190, 0), AutomaticSize = Enum.AutomaticSize.Y }, "Panel")
	ctx:Corner(root, "SmallCornerRadius")
	ctx:Stroke(root, "Border", 1)
	ctx:List(root, {})
	local head = ctx:Frame(root, { Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 0 })
	local accent = ctx:Frame(head, { Size = UDim2.new(1, 0, 0, 2) }, "Accent")
	ctx:Grad(accent, S(ctx, "WatermarkGradient", "AccentGradient"))
	ctx:Text(head, { Text = "Keybinds", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center }, "Text", "FontTitle", "SmallTextSize")
	local list = ctx:Frame(root, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
	ctx:Pad(list, 2, 8, 6, 8)
	ctx:List(list, { Pad = 2 })
	local view = { Root = root, Handle = head }
	function view:SetItems(items)
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		for i, it in ipairs(items) do
			local row = ctx:Frame(list, { Size = UDim2.new(1, 0, 0, 16), LayoutOrder = i })
			ctx:Text(row, { Text = it.Name, Size = UDim2.new(1, -70, 1, 0) }, "Text", "FontBody", "SmallTextSize")
			ctx:Text(row, { Text = "[" .. it.Key .. "] " .. string.lower(it.Mode), AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 70, 1, 0), TextXAlignment = Enum.TextXAlignment.Right }, "TextDim", "FontMono", "SmallTextSize")
		end
	end
	return view
end

---------------------------------------------------------------- mobile: floating button + quick toggle
function O.FloatingButton(ctx)
	local size = ctx:T("MobileButtonSize")
	local shape = ctx:T("MobileButtonShape")
	local b = ctx:New("TextButton", { Name = "FloatingButton", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 0 }, { BackgroundColor3 = "Panel" })
	if shape == "Circle" then
		ctx:Corner(b, "full")
	elseif shape == "Rounded" then
		ctx:Corner(b, math.floor(size * 0.28))
	end
	ctx:Stroke(b, "Accent", 2)
	ctx:Logo(b, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.8), TextXAlignment = Enum.TextXAlignment.Center, TextScaled = true }, "Accent")
	return { Root = b }
end

O.QuickSizes = { S = 44, M = 56, L = 72 }

function O.QuickToggle(ctx, el, sizeName)
	local px = O.QuickSizes[sizeName] or 56
	local shape = ctx:T("QuickToggleShape")
	local b = ctx:New("TextButton", { Name = "Quick_" .. tostring(el.Flag), Size = UDim2.fromOffset(px * 1.6, px), BackgroundTransparency = 0 }, { BackgroundColor3 = "Panel" })
	if shape == "Circle" then
		b.Size = UDim2.fromOffset(px, px)
		ctx:Corner(b, "full")
	elseif shape == "Rounded" then
		ctx:Corner(b, math.floor(px * 0.25))
	end
	local stroke = ctx:Stroke(b, "Border", 2)
	local dot = ctx:Frame(b, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, px * 0.16), Size = UDim2.fromOffset(px * 0.16, px * 0.16) }, "TextDim")
	ctx:Corner(dot, "full")
	local t = ctx:Text(b, {
		Text = el:ShortName(),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -px * 0.12),
		Size = UDim2.new(1, -8, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		TextScaled = true,
	}, "TextDim", "FontTitle", "SmallTextSize")
	local sc = Instance.new("UIScale")
	sc.Parent = b
	local view = { Root = b }
	function view:Update(on, instant)
		local d = instant and 0 or 0.15
		ctx.Theme:Bind(b, "BackgroundColor3", on and "Accent" or "Panel", { Tween = not instant, Alpha = view.Alpha or 0, Duration = d })
		ctx.Theme:Bind(stroke, "Color", on and "Accent" or "Border", { Tween = not instant })
		ctx.Theme:Bind(dot, "BackgroundColor3", on and "TextOnAccent" or "TextDim", { Tween = not instant })
		ctx.Theme:Bind(t, "TextColor3", on and "TextOnAccent" or "TextDim", { Tween = not instant })
	end
	function view:SetAlpha(a)
		view.Alpha = a
		view:Update(el.Value, true)
	end
	function view:Bounce()
		sc.Scale = 0.86
		Tween.Play(sc, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
	end
	function view:SetEditing(on)
		ctx.Theme:Bind(stroke, "Color", on and "Warning" or (el.Value and "Accent" or "Border"))
	end
	return view
end

---------------------------------------------------------------- generic loader (skins override)
function O.Loader(ctx, opts, handle)
	local layer = ctx.Layers.Loader
	local W, H = 380, 260
	local root = ctx:Frame(layer, { Name = "Loader", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H) }, "Background")
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "Border", 1)
	ctx:Text(root, { Text = opts.Title or ctx:T("Title"), Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 22) }, "Text", "FontTitle", "TitleSize")
	local status = ctx:Text(root, { Text = (opts.Subtitle or ctx:T("LoaderSubtitle")) .. ", " .. ctx:Username(), Position = UDim2.fromOffset(16, 36), Size = UDim2.new(1, -32, 0, 16) }, "TextDim", "FontBody", "SmallTextSize")
	local bar = ctx:Frame(root, { Position = UDim2.new(0, 16, 1, -64), Size = UDim2.new(1, -32, 0, 6) }, "Element")
	ctx:Corner(bar, "full")
	local fill = ctx:Frame(bar, { Size = UDim2.fromScale(0, 1) }, "Accent")
	ctx:Corner(fill, "full")
	local btn = ctx:New("TextButton", { Parent = root, Position = UDim2.new(0, 16, 1, -46), Size = UDim2.new(1, -32, 0, 32), Text = "Load", TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0 }, { BackgroundColor3 = "Accent", TextColor3 = "TextOnAccent", Font = "FontTitle", TextSize = "TextSize" })
	ctx:Corner(btn, "SmallCornerRadius")
	btn.Activated:Connect(function()
		handle.Start(1)
	end)
	local view = { Root = root }
	function view:SetProgress(p, text)
		Tween.Play(fill, { Size = UDim2.fromScale(p, 1) }, 0.3)
		status.Text = text
	end
	function view:SetStatus(text)
		status.Text = text
	end
	function view:OnStart()
		btn.Visible = false
	end
	function view:Close(cb)
		root:Destroy()
		if cb then
			cb()
		end
	end
	return view
end

return O
end
__MODULES["Skins/Base/Prim"] = function(require)
--[[
	Prim: drawing primitives available on every render context (ctx:New, ctx:Text, ctx:Corner ...).
	All colors / fonts / sizes are bound to theme keys – renderers pass KEYS, never raw values.
]]
local Util = require("Core/Util")
local Icons = require("Core/Icons")

local Prim = {}
Prim.__index = Prim

function Prim.Attach(ctx)
	return setmetatable(ctx, Prim)
end

local TEXT = { TextLabel = true, TextButton = true, TextBox = true }

function Prim:T(key)
	return self.Theme.Values[key]
end

local function fontT(v)
	return Util.FontEnum(v)
end
Prim.FontT = fontT

local function udimT(v)
	return UDim.new(0, v)
end
Prim.UDimT = udimT

-- ctx:New(class, props, binds) binds = { Prop = "Key" | {"Key", opts} }
function Prim:New(class, props, binds)
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	if TEXT[class] then
		inst.BackgroundTransparency = 1
		inst.Text = ""
		inst.TextXAlignment = Enum.TextXAlignment.Left
	end
	if class == "TextButton" or class == "ImageButton" then
		inst.AutoButtonColor = false
	end
	if class == "ImageLabel" or class == "ImageButton" then
		inst.BackgroundTransparency = 1
	end
	if class == "ScrollingFrame" then
		inst.BackgroundTransparency = 1
		inst.ScrollBarThickness = 2
		inst.CanvasSize = UDim2.new()
		inst.AutomaticCanvasSize = Enum.AutomaticSize.Y
		inst.ScrollingDirection = Enum.ScrollingDirection.Y
		inst.ScrollBarImageColor3 = Color3.new(1, 1, 1)
		inst.ScrollBarImageTransparency = 0.6
		inst.ElasticBehavior = Enum.ElasticBehavior.Never
	end
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	if binds then
		for prop, spec in pairs(binds) do
			if type(spec) == "table" then
				self.Theme:Bind(inst, prop, spec[1], spec[2])
			else
				if prop == "Font" then
					self.Theme:Bind(inst, prop, spec, fontT)
				else
					self.Theme:Bind(inst, prop, spec)
				end
			end
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- plain frame with a theme background color
function Prim:Frame(parent, props, colorKey, bopts)
	props = props or {}
	props.Parent = parent
	local f = self:New("Frame", props)
	if colorKey then
		self.Theme:Bind(f, "BackgroundColor3", colorKey, bopts)
	else
		f.BackgroundTransparency = 1
	end
	return f
end

-- text label bound to color / font / size keys
function Prim:Text(parent, props, colorKey, fontKey, sizeKey, class)
	props = props or {}
	props.Parent = parent
	local t = self:New(class or "TextLabel", props)
	self.Theme:Bind(t, "TextColor3", colorKey or "Text")
	self.Theme:Bind(t, "Font", fontKey or "FontBody", fontT)
	if type(sizeKey) == "number" then
		t.TextSize = sizeKey
	else
		self.Theme:Bind(t, "TextSize", sizeKey or "TextSize")
	end
	return t
end

-- invisible full-size click catcher
function Prim:Hitbox(parent, props)
	props = props or {}
	props.Parent = parent
	props.Size = props.Size or UDim2.fromScale(1, 1)
	props.BackgroundTransparency = 1
	props.ZIndex = props.ZIndex or (parent and parent:IsA("GuiObject") and parent.ZIndex + 5 or 5)
	local b = self:New("TextButton", props)
	return b
end

-- key: theme key (string), fixed offset (number) or "full" (pill/circle)
function Prim:Corner(inst, key)
	local c = Instance.new("UICorner")
	if key == "full" then
		c.CornerRadius = UDim.new(1, 0)
	elseif type(key) == "number" then
		c.CornerRadius = UDim.new(0, key)
	else
		self.Theme:Bind(c, "CornerRadius", key or "CornerRadius", udimT)
	end
	c.Parent = inst
	return c
end

-- thickness: number or theme key
function Prim:Stroke(inst, colorKey, thickness, opts)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Miter
	if type(thickness) == "string" then
		self.Theme:Bind(s, "Thickness", thickness)
	else
		s.Thickness = thickness or 1
	end
	self.Theme:Bind(s, "Color", colorKey or "Border", opts)
	s.Parent = inst
	return s
end

function Prim:Pad(inst, t, r, b, l)
	local p = Instance.new("UIPadding")
	t = t or 0
	p.PaddingTop = UDim.new(0, t)
	p.PaddingRight = UDim.new(0, r or t)
	p.PaddingBottom = UDim.new(0, b or t)
	p.PaddingLeft = UDim.new(0, l or r or t)
	p.Parent = inst
	return p
end

-- opts: Dir "V"|"H", Pad number, HA "Left"|"Center"|"Right", VA "Top"|"Center"|"Bottom"
function Prim:List(inst, opts)
	opts = opts or {}
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = opts.Dir == "H" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, opts.Pad or 0)
	if opts.HA then
		l.HorizontalAlignment = Enum.HorizontalAlignment[opts.HA]
	end
	if opts.VA then
		l.VerticalAlignment = Enum.VerticalAlignment[opts.VA]
	end
	l.Parent = inst
	return l
end

-- gradient bound to a theme gradient key. While enabled, the carrier's background renders white so the
-- gradient shows its real colors (Roblox multiplies them). opts.NoMask keeps the tinted (multiplied) look.
function Prim:Grad(inst, key, opts)
	local g = Instance.new("UIGradient")
	g.Parent = inst
	if not (opts and opts.NoMask) and inst:IsA("GuiObject") then
		self.Theme._gradMask[inst] = g
		g:GetPropertyChangedSignal("Enabled"):Connect(function()
			self.Theme:ReapplyProp(inst, "BackgroundColor3")
		end)
	end
	self.Theme:BindGradient(g, key, opts)
	return g
end

-- static gradient from explicit theme color keys (top -> bottom by default)
function Prim:Shade(inst, rotation, transparencyFrom, transparencyTo)
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 90
	g.Transparency = NumberSequence.new(transparencyFrom or 0, transparencyTo or 0)
	g.Parent = inst
	return g
end

function Prim:Icon(parent, name, size, colorKey, props)
	props = props or {}
	local icon = Icons.Create(self.Theme, name, size, colorKey, props)
	icon.Parent = parent
	return icon
end

function Prim:IconColor(icon, colorKey, tween)
	Icons.SetColor(self.Theme, icon, colorKey, tween)
end

-- hover/press state machine. cb(state) with state = "Idle" | "Hover" | "Press" | "Disabled"
function Prim:Hover(gui, cb, el)
	local hovered, pressed = false, false
	local function update()
		if el and el:IsDisabled() then
			cb("Disabled")
		elseif pressed then
			cb("Press")
		elseif hovered then
			cb("Hover")
		else
			cb("Idle")
		end
	end
	gui.MouseEnter:Connect(function()
		hovered = true
		update()
	end)
	gui.MouseLeave:Connect(function()
		hovered = false
		pressed = false
		update()
	end)
	gui.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			pressed = true
			update()
		end
	end)
	gui.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			pressed = false
			if i.UserInputType == Enum.UserInputType.Touch then
				hovered = false
			end
			update()
		end
	end)
	return update
end

-- click (mouse or tap), ignored while el is disabled
function Prim:OnClick(gui, fn, el)
	gui.Activated:Connect(function()
		if el and el:IsDisabled() then
			return
		end
		self:Sound("SoundClick")
		fn()
	end)
end

function Prim:Sound(key)
	if not self:T("SoundsEnabled") then
		return
	end
	local id = self:T(key)
	if not id or id == "" then
		return
	end
	pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = self:T("SoundVolume")
		local ss = Util.Services.SoundService
		if ss and ss.PlayLocalSound then
			s.Parent = ss
			ss:PlayLocalSound(s)
			task.delay(3, function()
				s:Destroy()
			end)
		end
	end)
end

-- row height respecting the mobile touch target
function Prim:RowH(mult)
	local h = self:T("ElementHeight") * (mult or 1)
	if self.IsMobile then
		h = math.max(h, self:T("TouchTarget") / math.max(self.Scale, 0.1))
	end
	return math.floor(h + 0.5)
end

-- size for small hit targets (checkbox, swatch …) – grows on mobile
function Prim:Touch(px)
	if self.IsMobile then
		return math.max(px, math.floor(self:T("TouchTarget") * 0.6 / math.max(self.Scale, 0.1)))
	end
	return px
end

-- soft drop shadow made from stacked strokes (no assets)
function Prim:Shadow(inst, cornerKey, layers)
	if not self:T("ShadowEnabled") then
		return nil
	end
	local holder = Instance.new("Frame")
	holder.Name = "Shadow"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = math.max(inst.ZIndex - 1, 0)
	layers = layers or 4
	for i = 1, layers do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0.5, 0, 0.5, 2 + i)
		f.Size = UDim2.new(1, i * 4, 1, i * 4)
		f.ZIndex = holder.ZIndex
		local base = self:T("ShadowTransparency")
		self.Theme:Bind(f, "BackgroundColor3", "Shadow", { Alpha = 1 - (1 - base) * (0.5 / i) })
		local c = Instance.new("UICorner")
		if cornerKey then
			self.Theme:Bind(c, "CornerRadius", cornerKey, function(v)
				return UDim.new(0, v + i * 2)
			end)
		else
			c.CornerRadius = UDim.new(0, i * 2)
		end
		c.Parent = f
		f.Parent = holder
	end
	holder.Parent = inst.Parent
	-- follow the target
	local function sync()
		holder.Position = inst.Position
		holder.Size = inst.Size
		holder.AnchorPoint = inst.AnchorPoint
		holder.Visible = inst.Visible
	end
	sync()
	inst:GetPropertyChangedSignal("Position"):Connect(sync)
	inst:GetPropertyChangedSignal("Size"):Connect(sync)
	inst:GetPropertyChangedSignal("Visible"):Connect(sync)
	inst.Destroying:Connect(function()
		holder:Destroy()
	end)
	return holder
end

-- colored glow around a frame (stacked rounded frames behind it). Returns the holder.
function Prim:Glow(inst, colorKey, cornerKey, layers, strength)
	local holder = Instance.new("Frame")
	holder.Name = "Glow"
	holder.BackgroundTransparency = 1
	holder.ZIndex = math.max(inst.ZIndex - 1, 0)
	layers = layers or 4
	strength = strength or 0.35
	for i = 1, layers do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.new(1, i * 4, 1, i * 4)
		f.ZIndex = holder.ZIndex
		self.Theme:Bind(f, "BackgroundColor3", colorKey or "Glow", { Alpha = 1 - strength / (i * 1.6) })
		local c = Instance.new("UICorner")
		if cornerKey then
			self.Theme:Bind(c, "CornerRadius", cornerKey, function(v)
				return UDim.new(0, v + i * 2)
			end)
		else
			c.CornerRadius = UDim.new(0, i * 2)
		end
		c.Parent = f
		f.Parent = holder
	end
	holder.Parent = inst.Parent
	local function sync()
		holder.Position = inst.Position
		holder.Size = inst.Size
		holder.AnchorPoint = inst.AnchorPoint
		holder.Visible = inst.Visible
	end
	sync()
	inst:GetPropertyChangedSignal("Position"):Connect(sync)
	inst:GetPropertyChangedSignal("Size"):Connect(sync)
	inst:GetPropertyChangedSignal("Visible"):Connect(sync)
	inst.Destroying:Connect(function()
		holder:Destroy()
	end)
	return holder
end

-- background texture (theme: BackgroundTexture / TextureTransparency / BackgroundImage)
function Prim:Texture(inst, colorKey)
	local kind = self:T("BackgroundTexture")
	local holder = Instance.new("Frame")
	holder.Name = "Texture"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ClipsDescendants = true
	holder.ZIndex = inst.ZIndex
	holder.Parent = inst
	local img = self:New("ImageLabel", {
		Parent = holder,
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = inst.ZIndex,
	})
	self.Theme:Bind(img, "Image", "BackgroundImage")
	self.Theme:Bind(img, "ImageTransparency", "BackgroundImageTransparency")
	if kind == "None" then
		return holder
	end
	local spacing = math.max(2, self:T("TextureSpacing"))
	-- textures are generated once for a generous area (window can be resized up to ~1.4x)
	local w = math.floor(self:T("WindowWidth") * 1.4)
	local h = math.floor(self:T("WindowHeight") * 1.4)
	local function line(x, y, sw, sh, rot)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(sw, sh)
		f.Rotation = rot or 0
		f.ZIndex = inst.ZIndex
		self.Theme:Bind(f, "BackgroundColor3", colorKey or "Highlight", function(v)
			return v
		end)
		self.Theme:Bind(f, "BackgroundTransparency", "TextureTransparency")
		f.Parent = holder
	end
	if kind == "Grid" then
		local step = spacing * 2
		for x = 0, w, step do
			line(x, 0, 1, h)
		end
		for y = 0, h, step do
			line(0, y, w, 1)
		end
	elseif kind == "Scanlines" then
		for y = 0, h, spacing do
			line(0, y, w, 1)
		end
	elseif kind == "Diagonal" then
		local step = spacing * 3
		for x = -h, w, step do
			line(x + h / 2, h / 2, h * 1.5, 1, -45)
		end
	end
	return holder
end

-- tooltip on hover (desktop) / long-press on non-pinnable elements (touch)
function Prim:Tooltip(gui, el)
	local r = self.Renderer
	local thread
	gui.MouseEnter:Connect(function()
		if not el.Tooltip or el.Tooltip == "" then
			return
		end
		thread = task.delay(0.45, function()
			thread = nil
			if r.TooltipView and gui.Parent then
				r.TooltipView:Show(el.Tooltip, gui)
			end
		end)
	end)
	gui.MouseLeave:Connect(function()
		if thread then
			pcall(task.cancel, thread)
			thread = nil
		end
		if r.TooltipView then
			r.TooltipView:Hide()
		end
	end)
end

-- convert an absolute screen position into UI-root space (accounts for UIScale)
function Prim:ToRoot(v)
	local s = self.Library.CurrentScale or 1
	local rootPos = self.Library.Root.AbsolutePosition
	return Vector2.new((v.X - rootPos.X) / s, (v.Y - rootPos.Y) / s)
end

-- absolute rect of a gui in root space
function Prim:RectOf(gui)
	local s = self.Library.CurrentScale or 1
	local p = self:ToRoot(gui.AbsolutePosition)
	return p, gui.AbsoluteSize / s
end

-- place a floating frame under (or above) an anchor, clamped to the screen
function Prim:PlaceNear(frame, anchor, width, height, gap)
	local p, s = self:RectOf(anchor)
	local screen = self.Library:ScreenSize()
	gap = gap or 4
	local x = p.X
	local y = p.Y + s.Y + gap
	if y + height > screen.Y - 8 then
		y = p.Y - height - gap
	end
	x = Util.Clamp(x, 8, math.max(8, screen.X - width - 8))
	y = Util.Clamp(y, 8, math.max(8, screen.Y - height - 8))
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(width, height)
end

function Prim:OpenOverlay(frame, onClose)
	return self.Renderer:PushOverlay(frame, onClose)
end

function Prim:CloseOverlay(entry)
	if entry then
		self.Renderer:PopOverlay(entry)
	else
		self.Renderer:CloseOverlays()
	end
end

-- user name / avatar helpers (branding keys fall back to the LocalPlayer)
function Prim:Username()
	local u = self:T("Username")
	if u and u ~= "" then
		return u
	end
	local lp = Util.LocalPlayer()
	return lp and lp.DisplayName or "user"
end

function Prim:Avatar()
	local a = self:T("AvatarImage")
	if a and a ~= "" then
		return a
	end
	local lp = Util.LocalPlayer()
	local players = Util.Services.Players
	if lp and players then
		local ok, url = pcall(function()
			return players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok then
			return url
		end
	end
	return ""
end

-- avatar circle (image + initial fallback)
function Prim:AvatarCircle(parent, size, props)
	props = props or {}
	local holder = self:Frame(parent, {
		Size = UDim2.fromOffset(size, size),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Name = "Avatar",
	}, "ElementActive")
	self:Corner(holder, "full")
	local initial = self:Text(holder, {
		Size = UDim2.fromScale(1, 1),
		Text = string.upper(string.sub(self:Username(), 1, 1)),
		TextXAlignment = Enum.TextXAlignment.Center,
	}, "Accent", "FontTitle", "TitleSize")
	local img = self:New("ImageLabel", { Parent = holder, Size = UDim2.fromScale(1, 1), Image = self:Avatar() })
	self:Corner(img, "full")
	initial.Visible = img.Image == ""
	if props.Stroke then
		self:Stroke(holder, props.Stroke, 1.5)
	end
	return holder
end

-- logo: image if LogoImage is set, else LogoText
function Prim:Logo(parent, props, colorKey, sizeKey)
	props = props or {}
	local img = self:T("LogoImage")
	if img and img ~= "" then
		props.Parent = parent
		props.Image = Util.HexToColor and (img:match("^%d+$") and "rbxassetid://" .. img or img)
		props.ScaleType = Enum.ScaleType.Fit
		local i = self:New("ImageLabel", props)
		return i
	end
	props.Text = self:T("LogoText")
	local t = self:Text(parent, props, colorKey or "Accent", "FontTitle", sizeKey or "TitleSize")
	self.Theme:Bind(t, "Text", "LogoText")
	return t
end

return Prim
end
__MODULES["Skins/Base/Theme"] = function(require)
--[[
	Base theme: the complete list of theme keys with metadata + neutral default values.
	Every skin only overrides values (Skins/<Name>/Theme.lua). Renderer code never hardcodes
	colors/fonts/sizes – it always reads/binds these keys.

	Entry format: { Key, DefaultValue, Section, Extra }
	Extra: Min/Max/Step for numbers, Options for strings (dropdowns), Rebuild = true when a change
	requires the window to be rebuilt (structural layout keys), Global = true when the value is shared
	across skins (branding etc.).
]]
local C = Color3.fromRGB
local Meta = require("Meta")

local FONTS = {
	"Code", "RobotoMono", "Gotham", "GothamMedium", "GothamBold", "GothamBlack", "SourceSans",
	"SourceSansSemibold", "SourceSansBold", "Ubuntu", "Roboto", "RobotoCondensed", "Arial", "ArialBold",
	"Nunito", "Montserrat", "BuilderSans", "BuilderSansMedium", "BuilderSansBold", "Jura", "Michroma",
	"Oswald", "Arimo", "ArimoBold", "Highway", "SciFi", "Zekton", "Sarpanch", "TitilliumWeb",
}

local EASING = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back", "Bounce", "Elastic" }

local function grad(colors, rotation, enabled, animated, speed)
	return { Enabled = enabled ~= false, Colors = colors, Rotation = rotation or 0, Animated = animated == true, Speed = speed or 0.5 }
end

local Entries = {
	-- Colors ---------------------------------------------------------------------------
	{ "Accent", C(0, 170, 255), "Colors" },
	{ "AccentDark", C(0, 110, 190), "Colors" },
	{ "Background", C(16, 16, 20), "Colors" },
	{ "BackgroundSecondary", C(12, 12, 16), "Colors" },
	{ "Topbar", C(20, 20, 26), "Colors" },
	{ "Panel", C(22, 22, 28), "Colors" },
	{ "PanelHeader", C(26, 26, 33), "Colors" },
	{ "Border", C(40, 40, 50), "Colors" },
	{ "BorderDark", C(0, 0, 0), "Colors" },
	{ "BorderLight", C(60, 60, 72), "Colors" },
	{ "Element", C(30, 30, 38), "Colors" },
	{ "ElementHover", C(38, 38, 48), "Colors" },
	{ "ElementActive", C(46, 46, 58), "Colors" },
	{ "Text", C(235, 235, 240), "Colors" },
	{ "TextDim", C(150, 150, 165), "Colors" },
	{ "TextDisabled", C(85, 85, 95), "Colors" },
	{ "TextOnAccent", C(255, 255, 255), "Colors" },
	{ "Divider", C(34, 34, 42), "Colors" },
	{ "Knob", C(255, 255, 255), "Colors" },
	{ "Shadow", C(0, 0, 0), "Colors" },
	{ "Glow", C(0, 170, 255), "Colors" },
	{ "Success", C(60, 200, 120), "Colors" },
	{ "Warning", C(240, 180, 40), "Colors" },
	{ "Error", C(230, 70, 80), "Colors" },
	{ "Info", C(0, 170, 255), "Colors" },
	{ "Tooltip", C(14, 14, 18), "Colors" },
	{ "Overlay", C(0, 0, 0), "Colors" },
	{ "Highlight", C(255, 255, 255), "Colors" },

	-- Gradients (Colors may be Color3 values or names of color keys) --------------------
	{ "AccentGradient", grad({ "Accent", "AccentDark" }, 90), "Gradients" },
	{ "RainbowBar", grad({ C(59, 175, 222), C(202, 70, 205), C(201, 227, 58) }, 0, true, false, 0.35), "Gradients" },
	{ "BackgroundGradient", grad({ "Background", "BackgroundSecondary" }, 90, false), "Gradients" },
	{ "ElementGradient", grad({ "ElementHover", "Element" }, 90, false), "Gradients" },
	{ "HeaderGradient", grad({ "Accent", "AccentDark" }, 0, false), "Gradients" },

	-- Background ------------------------------------------------------------------------
	{ "BackgroundImage", "", "Background" },
	{ "BackgroundImageTransparency", 0.85, "Background", { Min = 0, Max = 1, Step = 0.01 } },
	{ "BackgroundTexture", "None", "Background", { Options = { "None", "Grid", "Scanlines", "Diagonal" }, Rebuild = true } },
	{ "TextureTransparency", 0.93, "Background", { Min = 0.5, Max = 1, Step = 0.01 } },
	{ "TextureSpacing", 6, "Background", { Min = 2, Max = 32, Step = 1, Rebuild = true } },
	{ "WindowTransparency", 0, "Background", { Min = 0, Max = 0.9, Step = 0.01 } },

	-- Fonts -----------------------------------------------------------------------------
	{ "FontTitle", "GothamBold", "Fonts", { Options = FONTS } },
	{ "FontBody", "Gotham", "Fonts", { Options = FONTS } },
	{ "FontMono", "Code", "Fonts", { Options = FONTS } },
	{ "TextSize", 13, "Fonts", { Min = 8, Max = 22, Step = 1 } },
	{ "TitleSize", 14, "Fonts", { Min = 8, Max = 28, Step = 1 } },
	{ "SmallTextSize", 11, "Fonts", { Min = 7, Max = 18, Step = 1 } },

	-- Layout ----------------------------------------------------------------------------
	{ "CornerRadius", 6, "Layout", { Min = 0, Max = 20, Step = 1 } },
	{ "SmallCornerRadius", 4, "Layout", { Min = 0, Max = 14, Step = 1 } },
	{ "BorderThickness", 1, "Layout", { Min = 0, Max = 4, Step = 1 } },
	{ "ShadowEnabled", true, "Layout" },
	{ "ShadowTransparency", 0.55, "Layout", { Min = 0, Max = 1, Step = 0.01 } },
	{ "WindowWidth", 760, "Layout", { Min = 420, Max = 1400, Step = 10 } },
	{ "WindowHeight", 540, "Layout", { Min = 320, Max = 1000, Step = 10 } },
	{ "UIScale", 1, "Layout", { Min = 0.5, Max = 1.6, Step = 0.05 } },
	{ "SidebarWidth", 180, "Layout", { Min = 56, Max = 320, Step = 2, Rebuild = true } },
	{ "Spacing", 8, "Layout", { Min = 0, Max = 24, Step = 1, Rebuild = true } },
	{ "Padding", 12, "Layout", { Min = 0, Max = 32, Step = 1, Rebuild = true } },
	{ "ElementHeight", 30, "Layout", { Min = 14, Max = 56, Step = 1, Rebuild = true } },
	{ "GroupSpacing", 10, "Layout", { Min = 0, Max = 30, Step = 1, Rebuild = true } },

	-- Animation -------------------------------------------------------------------------
	{ "AnimationsEnabled", true, "Animation" },
	{ "AnimationSpeed", 1, "Animation", { Min = 0.25, Max = 4, Step = 0.05 } },
	{ "EasingStyle", "Quint", "Animation", { Options = EASING } },
	{ "EasingDirection", "Out", "Animation", { Options = { "In", "Out", "InOut" } } },

	-- Branding (shared by every skin) ----------------------------------------------------
	{ "Title", Meta.Name, "Branding", { Global = true } },
	{ "Subtitle", "", "Branding", { Global = true } },
	{ "LogoText", "NOVA", "Branding", { Global = true } },
	{ "LogoImage", "", "Branding", { Global = true } },
	{ "Username", "", "Branding", { Global = true } }, -- empty = LocalPlayer.DisplayName
	{ "UserInfo", "Expires: never", "Branding", { Global = true } },
	{ "AvatarImage", "", "Branding", { Global = true } }, -- empty = LocalPlayer thumbnail
	{ "LoaderTitle", "", "Branding", { Global = true } }, -- empty = Title
	{ "LoaderSubtitle", "Welcome back", "Branding", { Global = true } },
	{ "LoaderStatus", "Ready", "Branding", { Global = true } },

	-- Notifications ---------------------------------------------------------------------
	{ "NotifyPosition", "BottomRight", "Notifications", { Global = true, Options = { "TopLeft", "TopRight", "TopCenter", "BottomLeft", "BottomRight", "BottomCenter" } } },
	{ "NotifyDuration", 4, "Notifications", { Global = true, Min = 1, Max = 15, Step = 0.5 } },
	{ "NotifyWidth", 260, "Notifications", { Min = 180, Max = 420, Step = 10 } },

	-- Sounds ----------------------------------------------------------------------------
	{ "SoundsEnabled", false, "Sounds", { Global = true } },
	{ "SoundVolume", 0.5, "Sounds", { Global = true, Min = 0, Max = 1, Step = 0.05 } },
	{ "SoundClick", "rbxasset://sounds/electronicpingshort.wav", "Sounds", { Global = true } },
	{ "SoundToggle", "rbxasset://sounds/electronicpingshort.wav", "Sounds", { Global = true } },
	{ "SoundNotify", "rbxasset://sounds/electronicpingshort.wav", "Sounds", { Global = true } },

	-- Mobile ----------------------------------------------------------------------------
	{ "MobileButtonSize", 52, "Mobile", { Min = 36, Max = 90, Step = 1 } },
	{ "MobileButtonShape", "Circle", "Mobile", { Options = { "Circle", "Rounded", "Square" } } },
	{ "TouchTarget", 44, "Mobile", { Min = 32, Max = 64, Step = 1, Rebuild = true } },
	{ "QuickToggleShape", "Rounded", "Mobile", { Options = { "Circle", "Rounded", "Square" } } },
}

local Defaults, Meta_, Order, Sections = {}, {}, {}, {}
for _, e in ipairs(Entries) do
	local key, value, section, extra = e[1], e[2], e[3], e[4] or {}
	Defaults[key] = value
	extra.Section = section
	extra.Type = typeof(value) == "table" and "Gradient" or typeof(value)
	Meta_[key] = extra
	table.insert(Order, key)
	Sections[section] = Sections[section] or {}
	table.insert(Sections[section], key)
end

return {
	Defaults = Defaults,
	Meta = Meta_,
	Order = Order,
	Sections = Sections,
	SectionOrder = { "Colors", "Gradients", "Background", "Fonts", "Layout", "Animation", "Branding", "Notifications", "Sounds", "Mobile" },
	Fonts = FONTS,
}
end
__MODULES["Skins/Base/Window"] = function(require)
--[[
	Window kit: reusable building blocks for skin windows
	(root, drag, resize, pages with two columns, tab/sub-tab system, open/close animation, focus).
	Base.Window (bottom of file) is the reference layout: sidebar + content.
]]
local Util = require("Core/Util")
local Tween = require("Core/Tween")
local Input = require("Core/Input")

local Kit = {}

---------------------------------------------------------------- root / drag / resize
function Kit.Root(ctx, win, props)
	local size = win:GetSize()
	local pos = win:GetPosition()
	props = props or {}
	props.Name = props.Name or "Window"
	props.Position = UDim2.fromOffset(pos.X, pos.Y)
	props.Size = UDim2.fromOffset(size.X, size.Y)
	props.Parent = ctx.Layers.Window
	local root = ctx:New("Frame", props)
	local scale = Instance.new("UIScale")
	scale.Name = "OpenScale"
	scale.Parent = root
	return root
end

function Kit.ClampPos(ctx, root)
	return function(pos)
		local screen = ctx.Library:ScreenSize()
		local w, h = root.AbsoluteSize.X / ctx.Library.CurrentScale, root.AbsoluteSize.Y / ctx.Library.CurrentScale
		local x = Util.Clamp(pos.X.Offset, -w + 60, screen.X - 60)
		local y = Util.Clamp(pos.Y.Offset, 0, screen.Y - 40)
		return UDim2.fromOffset(x, y)
	end
end

function Kit.Draggable(ctx, win, root, handle)
	ctx.Maid:Give(ctx.Input:Drag(handle, {
		Target = root,
		Threshold = 2,
		GetScale = function()
			return ctx.Library.CurrentScale
		end,
		Clamp = Kit.ClampPos(ctx, root),
		OnEnd = function(moved)
			if moved then
				win.State.Position = Vector2.new(root.Position.X.Offset, root.Position.Y.Offset)
			end
		end,
	}))
end

-- bottom-right resize grip
function Kit.Resizer(ctx, win, root, colorKey, minW, minH)
	local size = ctx:Touch(14)
	local grip = ctx:New("TextButton", {
		Name = "Resize",
		Parent = root,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = 40,
	})
	for i = 0, 2 do
		for j = 0, 2 - i do
			ctx:Frame(grip, {
				Size = UDim2.fromOffset(2, 2),
				Position = UDim2.new(1, -3 - j * 4, 1, -3 - i * 4),
				ZIndex = 41,
			}, colorKey or "TextDisabled")
		end
	end
	local start
	ctx.Maid:Give(ctx.Input:Drag(grip, {
		OnStart = function()
			start = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
		end,
		OnMove = function(delta)
			local s = ctx.Library.CurrentScale
			local w = math.max(minW or 420, start.X + delta.X / s)
			local h = math.max(minH or 320, start.Y + delta.Y / s)
			root.Size = UDim2.fromOffset(w, h)
		end,
		OnEnd = function()
			win.State.Sizes[ctx.Library.SkinName] = { root.Size.X.Offset, root.Size.Y.Offset }
		end,
	}))
	return grip
end

-- style: "Scale" (smooth) | "Instant"
function Kit.SetOpen(ctx, root, open, instant, style)
	local sc = root:FindFirstChild("OpenScale")
	if instant or style == "Instant" or not ctx:T("AnimationsEnabled") then
		root.Visible = open
		if sc then
			sc.Scale = 1
		end
		return
	end
	if open then
		root.Visible = true
		if sc then
			sc.Scale = 0.94
			Tween.Play(sc, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
		end
	else
		if sc then
			Tween.Play(sc, { Scale = 0.94 }, 0.12, Enum.EasingStyle.Quad)
		end
		task.delay(Tween.Duration(0.12), function()
			if root.Parent and not ctx.Library.Window.Open then
				root.Visible = false
			end
		end)
	end
end

---------------------------------------------------------------- pages
--[[
	Kit.Page(ctx, parent, opts) -> PageView { Root, Scroll, Left, Right, GetColumn(side) }
	opts.Padding, opts.Gap, opts.Single (one column), opts.ScrollKey (scrollbar color key)
]]
function Kit.Page(ctx, parent, opts)
	opts = opts or {}
	local pad = opts.Padding or ctx:T("Padding")
	local gap = opts.Gap or ctx:T("GroupSpacing")
	local single = opts.Single
	if single == nil then
		local w = ctx.Library.Window and ctx.Library.Window:GetSize().X or 800
		single = ctx.IsMobile and w < 600
	end
	local scroll = ctx:New("ScrollingFrame", {
		Name = "Page",
		Parent = parent,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ScrollBarThickness = ctx.IsMobile and 0 or 3,
	}, { ScrollBarImageColor3 = opts.ScrollKey or "Accent" })
	ctx:Pad(scroll, pad, pad, pad, pad)
	local cols = ctx:Frame(scroll, { Name = "Columns", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	if opts.Header then
		-- optional page header (e.g. Dashboard status cards) stacked above the columns
		ctx:List(scroll, { Pad = gap })
		opts.Header(scroll, opts.Sub)
	end
	ctx:List(cols, { Dir = "H", Pad = gap })
	local function column(name, order)
		local c = ctx:Frame(cols, {
			Name = name,
			LayoutOrder = order,
			Size = single and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -gap / 2, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		})
		ctx:List(c, { Pad = gap })
		return c
	end
	local left = column("Left", 1)
	local right = single and left or column("Right", 2)
	local view = { Root = scroll, Scroll = scroll, Columns = cols, Left = left, Right = right }
	function view:GetColumn(side)
		return side == "Right" and right or left
	end
	return view
end

-- scroll an element into view and flash it
function Kit.Focus(ctx, pageView, el)
	local root = el.View and el.View.Root
	if not root or not pageView then
		return
	end
	local scroll = pageView.Scroll
	task.defer(function()
		local y = root.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
		local target = math.max(0, y / ctx.Library.CurrentScale - 40)
		Tween.Play(scroll, { CanvasPosition = Vector2.new(0, target) }, 0.3)
		local flash = ctx:Frame(root, { Size = UDim2.new(1, 8, 1, 4), Position = UDim2.fromOffset(-4, -2), ZIndex = root.ZIndex + 20 }, "Accent", { Alpha = 0.75 })
		ctx:Corner(flash, "SmallCornerRadius")
		task.delay(Tween.Duration(0.3), function()
			Tween.Play(flash, { BackgroundTransparency = 1 }, 0.8)
			task.delay(Tween.Duration(0.9), function()
				flash:Destroy()
			end)
		end)
	end)
end

---------------------------------------------------------------- tab system
--[[
	Kit.Tabs(ctx, win, spec) -> partial WindowView
	spec.TabHolder            frame where tab buttons go (needs a layout)
	spec.PageHolder           frame where pages go
	spec.TabButton(tab, holder) -> { Root, SetSelected(sel, instant), Hit }
	spec.SubTabHolder         optional frame for sub-tab buttons (hidden when <= 1 sub-tab)
	spec.SubTabButton(sub, holder) -> { Root, SetSelected(sel, instant), Hit }
	spec.PageOpts             passed to Kit.Page
	spec.OnSelect(tab, sub)   hook
	spec.PageAnim             "Slide" | "None"
]]
function Kit.Tabs(ctx, win, spec)
	local view = { Tabs = {} }
	local subButtons = {}

	function view:AddTab(tab)
		local tv = { Pages = {}, Tab = tab }
		local btn = spec.TabButton(tab, spec.TabHolder)
		tv.Button = btn
		btn.Root.LayoutOrder = btn.Order or table.find(win.Tabs, tab) or 0
		local hit = btn.Hit or btn.Root
		hit.Activated:Connect(function()
			ctx:Sound("SoundClick")
			win:SelectTab(tab)
		end)
		function tv:AddPage(sub)
			local popts = {}
			for k, v in pairs(spec.PageOpts or {}) do
				popts[k] = v
			end
			popts.Sub = sub
			local pv = Kit.Page(ctx, spec.PageHolder, popts)
			pv.Sub = sub
			tv.Pages[sub] = pv
			return pv
		end
		function tv:SetSelected(sel, instant)
			btn.SetSelected(sel, instant)
		end
		view.Tabs[tab] = tv
		return tv
	end

	local function buildSubTabs(tab)
		if not spec.SubTabHolder then
			return
		end
		for _, b in ipairs(subButtons) do
			b.Root:Destroy()
		end
		subButtons = {}
		local show = #tab.SubTabs > 1
		spec.SubTabHolder.Visible = show
		if spec.OnSubTabVisibility then
			spec.OnSubTabVisibility(show)
		end
		if not show then
			return
		end
		for i, sub in ipairs(tab.SubTabs) do
			local b = spec.SubTabButton(sub, spec.SubTabHolder)
			b.Root.LayoutOrder = i
			b.Sub = sub
			local hit = b.Hit or b.Root
			hit.Activated:Connect(function()
				ctx:Sound("SoundClick")
				win:SelectTab(tab, sub)
			end)
			b.SetSelected(tab.ActiveSub == sub, true)
			table.insert(subButtons, b)
		end
	end

	function view:SubTabsChanged(tab)
		if win.ActiveTab == tab then
			buildSubTabs(tab)
		end
	end

	local currentTab
	function view:SelectTab(tab, sub)
		local changedTab = currentTab ~= tab
		currentTab = tab
		for t, tv in pairs(view.Tabs) do
			tv:SetSelected(t == tab, false)
			for s, pv in pairs(tv.Pages) do
				local vis = (t == tab and s == sub)
				if vis and not pv.Root.Visible and spec.PageAnim == "Slide" and ctx:T("AnimationsEnabled") then
					pv.Root.Position = UDim2.fromOffset(0, 10)
					Tween.Play(pv.Root, { Position = UDim2.fromOffset(0, 0) }, 0.25)
				end
				pv.Root.Visible = vis
			end
		end
		if changedTab then
			buildSubTabs(tab)
		end
		for _, b in ipairs(subButtons) do
			b.SetSelected(b.Sub == sub, false)
		end
		if spec.OnSelect then
			spec.OnSelect(tab, sub)
		end
	end

	function view:Focus(el)
		local group = el.Group
		while group and group.IsPopout and group.Owner do
			group = group.Owner.Group
		end
		local sub = group and group.Page
		local tv = sub and view.Tabs[sub.Tab]
		Kit.Focus(ctx, tv and tv.Pages[sub], el)
	end

	return view
end

---------------------------------------------------------------- reference window (sidebar layout)
function Kit.Window(ctx, win)
	local root = Kit.Root(ctx, win, { ClipsDescendants = false })
	ctx:Frame(root, { Size = UDim2.fromScale(1, 1) })
	ctx.Theme:Bind(root, "BackgroundColor3", "Background", { Window = true })
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "Border", "BorderThickness")
	ctx:Shadow(root, "CornerRadius")
	local sw = ctx:T("SidebarWidth")
	local side = ctx:Frame(root, { Size = UDim2.new(0, sw, 1, 0) }, "BackgroundSecondary", { Window = true })
	ctx:Corner(side, "CornerRadius")
	local title = ctx:Text(side, { Size = UDim2.new(1, -24, 0, 50), Position = UDim2.fromOffset(16, 0) }, "Text", "FontTitle", "TitleSize")
	ctx.Theme:Bind(title, "Text", "Title")
	local tabs = ctx:Frame(side, { Position = UDim2.fromOffset(8, 56), Size = UDim2.new(1, -16, 1, -64) })
	ctx:List(tabs, { Pad = 2 })
	local content = ctx:Frame(root, { Position = UDim2.fromOffset(sw, 0), Size = UDim2.new(1, -sw, 1, 0), ClipsDescendants = true })
	Kit.Draggable(ctx, win, root, side)
	Kit.Resizer(ctx, win, root)
	local view = Kit.Tabs(ctx, win, {
		TabHolder = tabs,
		PageHolder = content,
		PageAnim = "Slide",
		TabButton = function(tab, holder)
			local b = ctx:New("TextButton", { Parent = holder, Size = UDim2.new(1, 0, 0, ctx:RowH()) }, { BackgroundColor3 = { "Accent", { Alpha = 1 } } })
			ctx:Corner(b, "SmallCornerRadius")
			local icon = ctx:Icon(b, tab.Icon, 14, "TextDim", { Position = UDim2.new(0, 10, 0.5, -7) })
			local t = ctx:Text(b, { Text = tab.Name, Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -36, 1, 0) }, "TextDim")
			return {
				Root = b,
				SetSelected = function(sel)
					ctx.Theme:Bind(t, "TextColor3", sel and "Text" or "TextDim", { Tween = true })
					ctx:IconColor(icon, sel and "Accent" or "TextDim", true)
					ctx.Theme:Bind(b, "BackgroundColor3", "Accent", { Alpha = sel and 0.85 or 1, Tween = true })
				end,
			}
		end,
	})
	view.Root = root
	function view:SetOpen(open, instant)
		Kit.SetOpen(ctx, root, open, instant, "Scale")
	end
	function view:Destroy()
		root:Destroy()
	end
	return view
end

return Kit
end
__MODULES["Skins/Base"] = function(require)
--[[
	Base skin: the complete reference implementation of the skin interface.
	Custom skins are created with Base.Extend{ ... } and only override what differs:

	local MySkin = UI.SkinBase.Extend({
		Name = "MySkin",
		Theme = { Defaults = { Accent = Color3.fromRGB(255, 0, 0) }, Presets = { Default = {} } },
		Style = { ToggleStyle = "Pill" },
		Window = function(ctx, window) ... end,      -- optional
		Components = { Toggle = function(ctx, el, parent) ... end }, -- optional
		Loader = function(ctx, opts, handle) ... end, -- optional
	})
	UI:RegisterSkin(MySkin)
]]
local Components = require("Skins/Base/Components")
local Overlays = require("Skins/Base/Overlays")
local Kit = require("Skins/Base/Window")

local Base = {
	Name = "Base",
	Description = "Reference skin",
	Theme = { Defaults = {}, Presets = { Default = {} } },
	Style = {},
	Components = Components,
	Window = Kit.Window,
	Group = Overlays.Group,
	DropdownList = Overlays.DropdownList,
	ColorPanel = Overlays.ColorPanel,
	Popout = Overlays.Popout,
	ContextMenu = Overlays.ContextMenu,
	Notification = Overlays.Notification,
	Dialog = Overlays.Dialog,
	Tooltip = Overlays.Tooltip,
	Watermark = Overlays.Watermark,
	KeybindList = Overlays.KeybindList,
	FloatingButton = Overlays.FloatingButton,
	QuickToggle = Overlays.QuickToggle,
	Loader = Overlays.Loader,
	-- helper namespaces for skin authors
	Kit = Kit,
	C = Components._,
	O = Overlays,
}

local SKIP = { Extend = true, Kit = true, C = true, O = true }

function Base.Extend(def)
	local skin = {}
	for k, v in pairs(Base) do
		if not SKIP[k] then
			skin[k] = v
		end
	end
	for k, v in pairs(def) do
		if k ~= "Components" and k ~= "Style" then
			skin[k] = v
		end
	end
	local comps = {}
	for k, v in pairs(Base.Components) do
		comps[k] = v
	end
	for k, v in pairs(def.Components or {}) do
		comps[k] = v
	end
	skin.Components = comps
	local style = {}
	for k, v in pairs(Base.Style) do
		style[k] = v
	end
	for k, v in pairs(def.Style or {}) do
		style[k] = v
	end
	skin.Style = style
	skin.Theme = def.Theme or { Defaults = {}, Presets = { Default = {} } }
	skin.Theme.Presets = skin.Theme.Presets or { Default = {} }
	skin.Theme.Presets.Default = skin.Theme.Presets.Default or {}
	return skin
end

return Base
end
__MODULES["Skins/Classic/Components"] = function(require)
--[[
	Classic component overrides: checkbox sits in the group's left gutter (like the reference menu),
	everything else uses the Base renderers driven by the Classic Style table.
]]
local Base = require("Skins/Base")
local Tween = require("Core/Tween")
local C = Base.C

local M = {}

function M.Toggle(ctx, el, parent)
	local view = C.Toggle(ctx, el, parent)
	view.Box.Position = UDim2.new(0, -20, 0.5, 0)
	view.Label.Position = UDim2.fromOffset(0, 0)
	view.Label.Size = UDim2.new(1, -60, 1, 0)
	-- the checkbox is outside the row: give it its own hit target
	local hit = ctx:Hitbox(view.Box, { Size = UDim2.new(1, 8, 1, 8), Position = UDim2.fromOffset(-4, -4) })
	hit.Activated:Connect(function()
		if not el:IsDisabled() then
			el:Set(not el.Value)
		end
	end)
	return view
end

-- skeet style notification: square box, rainbow line, mono text
function M.Notification(ctx, opts, holder)
	local W = ctx:T("NotifyWidth")
	local key = Base.O.TypeKey[opts.Type] or "Accent"
	local root = ctx:Frame(holder, { Name = "Notification", Size = UDim2.fromOffset(W, 0), AutomaticSize = Enum.AutomaticSize.Y })
	local card = ctx:Frame(root, { Size = UDim2.fromOffset(W, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(-W - 30, 0) }, "Panel")
	ctx:Stroke(card, "BorderDark", 1)
	local bar = ctx:Frame(card, { Size = UDim2.new(1, 0, 0, 2) }, "Highlight")
	ctx:Grad(bar, "RainbowBar", { Force = true, Static = true })
	local body = ctx:Frame(card, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	ctx:Pad(body, 8, 10, 8, 10)
	ctx:List(body, { Pad = 2 })
	local t = ctx:Text(body, { Text = "[" .. string.lower(opts.Title or "") .. "] ", Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 1 }, key, "FontMono", "TextSize")
	t.RichText = false
	ctx:Text(body, { Text = opts.Content or "", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 2 }, "Text", "FontMono", "SmallTextSize")
	Tween.Play(card, { Position = UDim2.fromOffset(0, 0) }, 0.2)
	local view = { Root = root }
	function view:Close(instant)
		if instant then
			root:Destroy()
			return
		end
		Tween.Play(card, { Position = UDim2.fromOffset(-W - 30, 0) }, 0.15)
		task.delay(Tween.Duration(0.15), function()
			root:Destroy()
		end)
	end
	return view
end

return M
end
__MODULES["Skins/Classic/Loader"] = function(require)
--[[
	Classic loader: small window in the layered border style with the rainbow bar,
	username + status line, a list of scripts/games, a "Load" button and a simple progress bar.
]]
local Tween = require("Core/Tween")
local W = require("Skins/Classic/Window")

return function(ctx, opts, handle)
	local layer = ctx.Layers.Loader
	local Wd, Ht = 360, 330
	local root = ctx:New("Frame", { Parent = layer, Name = "Loader", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(Wd, Ht) })
	local inner = W.Layered(ctx, root, 4)
	W.RainbowBar(ctx, inner, 2)
	ctx:Texture(inner)
	local pad = 14
	local title = ctx:Text(inner, { Text = opts.Title or (ctx:T("LoaderTitle") ~= "" and ctx:T("LoaderTitle") or ctx:T("Title")), Position = UDim2.fromOffset(pad, 12), Size = UDim2.new(1, -pad * 2, 0, 16) }, "Text", "FontTitle", "TitleSize")
	ctx:Text(inner, { Text = "v" .. ctx.Library.Version, Position = UDim2.fromOffset(pad, 12), Size = UDim2.new(1, -pad * 2, 0, 16), TextXAlignment = Enum.TextXAlignment.Right }, "TextDisabled", "FontMono", "SmallTextSize")
	local _ = title
	ctx:Text(inner, { Text = (opts.Subtitle or ctx:T("LoaderSubtitle")) .. ", " .. (opts.Username or ctx:Username()), Position = UDim2.fromOffset(pad, 32), Size = UDim2.new(1, -pad * 2, 0, 14) }, "TextDim", "FontBody", "SmallTextSize")
	local status = ctx:Text(inner, { Text = "status: " .. string.lower(ctx:T("LoaderStatus")), Position = UDim2.fromOffset(pad, 48), Size = UDim2.new(1, -pad * 2, 0, 14) }, "Accent", "FontMono", "SmallTextSize")

	-- scripts list (group box look)
	local box = ctx:Frame(inner, { Position = UDim2.fromOffset(pad, 76), Size = UDim2.new(1, -pad * 2, 1, -76 - 84) }, "BorderDark")
	local boxInner = ctx:Frame(box, { Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2) }, "Border")
	local list = ctx:Frame(boxInner, { Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2) }, "Panel")
	ctx:Pad(list, 10, 8, 6, 8)
	ctx:List(list, { Pad = 2 })
	local t = ctx:Text(box, { Text = "scripts", Position = UDim2.fromOffset(10, -7), Size = UDim2.fromOffset(0, 13), AutomaticSize = Enum.AutomaticSize.X, ZIndex = box.ZIndex + 5 }, "Text", "FontTitle", "TextSize")
	t.BackgroundTransparency = 0
	ctx.Theme:Bind(t, "BackgroundColor3", "Background")
	ctx:Pad(t, 0, 3, 0, 3)
	local selected = 1
	local rows = {}
	local function paintRows()
		for i, r in ipairs(rows) do
			ctx.Theme:Bind(r.Name, "TextColor3", i == selected and "Accent" or "Text", { Tween = true })
			ctx.Theme:Bind(r.Root, "BackgroundColor3", "ElementHover", { Alpha = i == selected and 0.7 or 1, Tween = true })
		end
	end
	for i, p in ipairs(opts.Products) do
		local row = ctx:New("TextButton", { Parent = list, Size = UDim2.new(1, 0, 0, ctx:Touch(20)), LayoutOrder = i, BackgroundTransparency = 1 })
		local name = ctx:Text(row, { Text = p.Name, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0.55, 0, 1, 0) }, "Text", "FontBody", "TextSize")
		local okStatus = (p.Status or "Undetected")
		local key = (okStatus:lower():find("undetect") or okStatus:lower():find("online")) and "Success" or (okStatus:lower():find("updat") and "Warning" or "Error")
		ctx:Text(row, { Text = string.lower(okStatus), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Size = UDim2.new(0.45, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right }, key, "FontMono", "SmallTextSize")
		table.insert(rows, { Root = row, Name = name })
		row.Activated:Connect(function()
			if handle.Running then
				return
			end
			selected = i
			paintRows()
		end)
	end
	paintRows()

	-- progress + button
	local barOuter = ctx:Frame(inner, { Position = UDim2.new(0, pad, 1, -74), Size = UDim2.new(1, -pad * 2, 0, 6) }, "BorderDark")
	local bar = ctx:Frame(barOuter, { Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2) }, "Element")
	local fill = ctx:Frame(bar, { Size = UDim2.fromScale(0, 1) }, "Accent")
	ctx:Grad(fill, "AccentGradient")
	local step = ctx:Text(inner, { Text = "", Position = UDim2.new(0, pad, 1, -64), Size = UDim2.new(1, -pad * 2, 0, 14) }, "TextDim", "FontMono", "SmallTextSize")
	local btnOuter = ctx:Frame(inner, { Position = UDim2.new(0, pad, 1, -44), Size = UDim2.new(1, -pad * 2, 0, 30) }, "BorderDark")
	local btn = ctx:New("TextButton", { Parent = btnOuter, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), Text = "load", TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0 }, { BackgroundColor3 = "Element", TextColor3 = "Text", Font = "FontTitle", TextSize = "TextSize" })
	ctx:Grad(btn, "ElementGradient", { Force = true })
	ctx:Hover(btn, function(st)
		ctx.Theme:Bind(btn, "BackgroundColor3", st == "Idle" and "Element" or (st == "Press" and "ElementActive" or "ElementHover"), { Tween = true })
		ctx.Theme:Bind(btn, "TextColor3", st == "Idle" and "Text" or "Accent", { Tween = true })
	end)
	btn.Activated:Connect(function()
		ctx:Sound("SoundClick")
		handle.Start(selected)
	end)

	local view = { Root = root }
	function view:OnStart(product)
		btn.Text = "loading " .. string.lower(product.Name) .. "..."
		status.Text = "status: injecting"
	end
	function view:SetProgress(p, text)
		Tween.Play(fill, { Size = UDim2.fromScale(p, 1) }, 0.25)
		step.Text = string.lower(text or "")
	end
	function view:SetStatus(text)
		status.Text = "status: " .. string.lower(text)
	end
	function view:Close(cb)
		status.Text = "status: done"
		task.delay(Tween.Duration(0.1), function()
			root:Destroy()
			if cb then
				cb()
			end
		end)
	end
	return view
end
end
__MODULES["Skins/Classic/Theme"] = function(require)
--[[ Classic skin – default theme values + presets (styled after the classic "gamesense" look) ]]
local C = Color3.fromRGB

return {
	Defaults = {
		Accent = C(154, 205, 50),
		AccentDark = C(96, 136, 24),
		Background = C(17, 17, 17),
		BackgroundSecondary = C(12, 12, 12),
		Topbar = C(12, 12, 12),
		Panel = C(23, 23, 23),
		PanelHeader = C(23, 23, 23),
		Border = C(40, 40, 40),
		BorderDark = C(0, 0, 0),
		BorderLight = C(60, 60, 60),
		Element = C(52, 52, 52),
		ElementHover = C(64, 64, 64),
		ElementActive = C(74, 74, 74),
		Text = C(205, 205, 205),
		TextDim = C(140, 140, 140),
		TextDisabled = C(88, 88, 88),
		TextOnAccent = C(16, 16, 16),
		Divider = C(36, 36, 36),
		Knob = C(220, 220, 220),
		Glow = C(154, 205, 50),
		Info = C(154, 205, 50),
		Tooltip = C(17, 17, 17),
		Highlight = C(255, 255, 255),
		AccentGradient = { Enabled = true, Colors = { "Accent", "AccentDark" }, Rotation = 90, Animated = false, Speed = 0.5 },
		ElementGradient = { Enabled = true, Colors = { C(70, 70, 70), C(46, 46, 46) }, Rotation = 90, Animated = false, Speed = 0.5 },
		RainbowBar = { Enabled = true, Colors = { C(59, 175, 222), C(202, 70, 205), C(201, 227, 58) }, Rotation = 0, Animated = false, Speed = 0.35 },
		BackgroundTexture = "Grid",
		TextureSpacing = 2,
		TextureTransparency = 0.975,
		FontTitle = "Code",
		FontBody = "Code",
		FontMono = "Code",
		TextSize = 13,
		TitleSize = 13,
		SmallTextSize = 12,
		CornerRadius = 0,
		SmallCornerRadius = 0,
		BorderThickness = 1,
		ShadowEnabled = false,
		WindowWidth = 660,
		WindowHeight = 560,
		SidebarWidth = 76,
		Spacing = 6,
		Padding = 10,
		ElementHeight = 18,
		GroupSpacing = 18,
		AnimationSpeed = 2.5,
		EasingStyle = "Quad",
		NotifyPosition = "TopLeft",
		NotifyWidth = 250,
		MobileButtonShape = "Square",
		QuickToggleShape = "Square",
	},
	Presets = {
		Default = {},
		Ocean = { Accent = C(80, 150, 255), AccentDark = C(40, 90, 190), Info = C(80, 150, 255), Glow = C(80, 150, 255) },
		Rose = { Accent = C(235, 95, 150), AccentDark = C(160, 50, 95), Info = C(235, 95, 150), Glow = C(235, 95, 150) },
		Gold = { Accent = C(232, 182, 62), AccentDark = C(160, 118, 28), Info = C(232, 182, 62), Glow = C(232, 182, 62) },
		["Rainbow animated"] = { RainbowBar = { Enabled = true, Colors = { C(59, 175, 222), C(202, 70, 205), C(201, 227, 58) }, Rotation = 0, Animated = true, Speed = 0.35 } },
		Flat = { BackgroundTexture = "None", ElementGradient = { Enabled = false, Colors = { C(70, 70, 70), C(46, 46, 46) }, Rotation = 90 } },
	},
}
end
__MODULES["Skins/Classic/Window"] = function(require)
--[[
	Classic window: compact square window, layered 1px borders, 2px rainbow bar on top,
	vertical icon tab column on the left (active tab "opens" into the content), textured content.
]]
local Kit = require("Skins/Base/Window")
local Tween = require("Core/Tween")

local W = {}

-- layered border: black / light / rim / light / content. Returns the inner frame.
function W.Layered(ctx, root, rim)
	rim = rim or 4
	ctx.Theme:Bind(root, "BackgroundColor3", "BorderDark", { Window = true })
	local l1 = ctx:Frame(root, { Name = "L1", Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2) }, "BorderLight", { Window = true })
	local l2 = ctx:Frame(l1, { Name = "Rim", Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2) }, "Border", { Window = true })
	local l3 = ctx:Frame(l2, { Name = "L3", Position = UDim2.fromOffset(rim, rim), Size = UDim2.new(1, -rim * 2, 1, -rim * 2) }, "BorderLight", { Window = true })
	local inner = ctx:Frame(l3, { Name = "Inner", Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), ClipsDescendants = true }, "Background", { Window = true })
	return inner, l2
end

function W.RainbowBar(ctx, parent, height)
	local bar = ctx:Frame(parent, { Name = "RainbowBar", Size = UDim2.new(1, 0, 0, height or 2), ZIndex = parent.ZIndex + 5 }, "Highlight")
	ctx:Grad(bar, "RainbowBar", { Force = true })
	local shade = ctx:Frame(bar, { Size = UDim2.new(1, 0, 0.5, 0), Position = UDim2.fromScale(0, 0.5), ZIndex = bar.ZIndex + 1 }, "BorderDark", { Alpha = 0.55 })
	local line = ctx:Frame(parent, { Name = "BarLine", Position = UDim2.fromOffset(0, height or 2), Size = UDim2.new(1, 0, 0, 1), ZIndex = parent.ZIndex + 5 }, "BorderDark")
	return bar, shade, line
end

function W.Window(ctx, win)
	local root = Kit.Root(ctx, win)
	local inner = W.Layered(ctx, root, 4)
	local barH = 2
	W.RainbowBar(ctx, inner, barH)
	local top = barH + 1
	local sw = ctx:T("SidebarWidth")

	-- tab column
	local column = ctx:Frame(inner, { Name = "Tabs", Position = UDim2.fromOffset(0, top), Size = UDim2.new(0, sw, 1, -top) }, "BackgroundSecondary", { Window = true })
	-- right edge of the column (hidden under the active tab)
	ctx:Frame(column, { Name = "EdgeDark", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 1, 1, 0), ZIndex = 2 }, "BorderDark")
	ctx:Frame(column, { Name = "EdgeLight", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0), ZIndex = 2 }, "Border")
	local tabList = ctx:Frame(column, { Name = "List", Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 1, -16), ZIndex = 3 })
	ctx:List(tabList, {})

	-- content
	local content = ctx:Frame(inner, { Name = "Content", Position = UDim2.fromOffset(sw, top), Size = UDim2.new(1, -sw, 1, -top), ClipsDescendants = true })
	ctx:Texture(content)
	local subBar = ctx:Frame(content, { Name = "SubTabs", Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(20, 10), Visible = false, ZIndex = 4 })
	ctx:List(subBar, { Dir = "H", Pad = 0 })
	local pages = ctx:Frame(content, { Name = "Pages", Size = UDim2.fromScale(1, 1), ZIndex = 3 })
	local dragStrip = ctx:Frame(inner, { Name = "DragStrip", Position = UDim2.fromOffset(sw, top), Size = UDim2.new(1, -sw, 0, 12), ZIndex = 6 })

	Kit.Draggable(ctx, win, root, column)
	Kit.Draggable(ctx, win, root, dragStrip)
	Kit.Resizer(ctx, win, root, "BorderLight", 520, 400)

	local iconSize = math.floor(math.min(sw * 0.42, 34))
	local view = Kit.Tabs(ctx, win, {
		TabHolder = tabList,
		PageHolder = pages,
		PageAnim = "None",
		PageOpts = { Padding = 20 },
		SubTabHolder = subBar,
		OnSubTabVisibility = function(show)
			pages.Position = UDim2.fromOffset(0, show and 34 or 0)
			pages.Size = UDim2.new(1, 0, 1, show and -34 or 0)
		end,
		TabButton = function(tab, holder)
			local h = math.max(ctx:Touch(64), 64)
			local b = ctx:New("TextButton", { Parent = holder, Name = "Tab_" .. tab.Name, Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, ZIndex = 4 })
			local bg = ctx:Frame(b, { Size = UDim2.new(1, 0, 1, 0), Visible = false, ZIndex = 4 }, "Background", { Window = true })
			-- top + bottom borders of the active tab (black + gray)
			ctx:Frame(bg, { Size = UDim2.new(1, 0, 0, 1), ZIndex = 5 }, "BorderDark")
			ctx:Frame(bg, { Position = UDim2.fromOffset(0, 1), Size = UDim2.new(1, 0, 0, 1), ZIndex = 5 }, "Border")
			ctx:Frame(bg, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 1), ZIndex = 5 }, "BorderDark")
			ctx:Frame(bg, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), ZIndex = 5 }, "Border")
			local icon = ctx:Icon(b, tab.Icon, iconSize, "TextDisabled", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 6, BgKey = "BackgroundSecondary" })
			local selected = false
			local function paint(st)
				local key = selected and "Text" or ((st == "Hover" or st == "Press") and "TextDim" or "TextDisabled")
				ctx:IconColor(icon, key, true)
			end
			ctx:Hover(b, paint)
			return {
				Root = b,
				SetSelected = function(sel)
					selected = sel
					bg.Visible = sel
					-- icon cut-outs follow the tab background
					for _, f in ipairs(icon:GetChildren()) do
						if f:IsA("Frame") and not f:GetAttribute("IconFg") then
							ctx.Theme:Bind(f, "BackgroundColor3", sel and "Background" or "BackgroundSecondary")
						end
					end
					paint("Idle")
				end,
			}
		end,
		SubTabButton = function(sub, holder)
			local w = math.max(70, #sub.Name * 8 + 24)
			local b = ctx:New("TextButton", { Parent = holder, Size = UDim2.new(0, w, 1, 0), BackgroundTransparency = 0, Text = sub.Name, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, { BackgroundColor3 = "Panel", Font = "FontBody", TextSize = "TextSize" })
			ctx:Stroke(b, "BorderDark", 1)
			local sel = false
			local function paint(st)
				ctx.Theme:Bind(b, "TextColor3", sel and "Accent" or (st ~= "Idle" and "Text" or "TextDim"), { Tween = true })
				ctx.Theme:Bind(b, "BackgroundColor3", sel and "Background" or "Panel", { Tween = true })
			end
			ctx:Hover(b, paint)
			return {
				Root = b,
				SetSelected = function(s)
					sel = s
					paint("Idle")
				end,
			}
		end,
	})
	view.Root = root
	function view:SetOpen(open, instant)
		Kit.SetOpen(ctx, root, open, instant, "Instant")
	end
	function view:Destroy()
		root:Destroy()
	end
	return view
end

-- group box with the title embedded in the top border
function W.Group(ctx, group, column)
	local root = ctx:Frame(column, { Name = "Group_" .. group.Name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, "BorderDark")
	local inner = ctx:Frame(root, { Name = "Inner", Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, "Border")
	local body = ctx:Frame(inner, { Name = "Body", Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, "Panel")
	local spacer = ctx:New("UIPadding", { Parent = root, PaddingBottom = UDim.new(0, 2) })
	local _ = spacer
	ctx:New("UIPadding", { Parent = inner, PaddingBottom = UDim.new(0, 1) })
	local container = ctx:Frame(body, { Name = "Container", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	ctx:Pad(container, 14, 14, 10, 32)
	ctx:List(container, { Pad = ctx:T("Spacing") })
	-- title cut into the border
	local title = ctx:Text(root, {
		Text = group.Name,
		Position = UDim2.fromOffset(10, -7),
		Size = UDim2.fromOffset(0, 13),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = root.ZIndex + 5,
	}, "Text", "FontTitle", "TextSize")
	title.BackgroundTransparency = 0
	ctx.Theme:Bind(title, "BackgroundColor3", "Background")
	ctx:Pad(title, 0, 3, 0, 3)
	return { Root = root, Container = container, Title = title }
end

return W
end
__MODULES["Skins/Classic"] = function(require)
--[[
	Skin "Classic" – compact square window with layered borders, rainbow bar, icon tab column,
	group boxes with embedded titles, tiny mono font and a light green accent.
]]
local Base = require("Skins/Base")
local W = require("Skins/Classic/Window")
local Comp = require("Skins/Classic/Components")

return Base.Extend({
	Name = "Classic",
	Description = "Compact square menu, layered borders, rainbow bar, icon tabs",
	Theme = require("Skins/Classic/Theme"),
	Style = {
		ToggleStyle = "Checkbox",
		CheckSize = 8,
		CheckCorner = 0,
		CheckStroke = "BorderDark",
		CheckGradient = true,
		CheckGradientKey = "AccentGradient",
		CheckMark = false,
		ToggleLabelActive = false,
		LabelAbove = true,
		SliderTrack = 7,
		SliderKnob = 0,
		SliderValue = "Center",
		SliderGradient = true,
		SliderRows = 1.6,
		SliderBottom = 2,
		TrackCorner = 0,
		TrackStroke = "BorderDark",
		ControlCorner = 0,
		ControlStroke = "BorderDark",
		ControlStrokeHover = "BorderLight",
		ControlGradient = true,
		BoxHeight = 1.15,
		AboveOverlap = 0,
		KeyStyle = "Brackets",
		SwatchW = 14,
		SwatchH = 8,
		SwatchCorner = 0,
		SwatchStroke = "BorderDark",
		SwatchShade = true,
		ButtonStyle = "Filled",
		ButtonStroke = "BorderDark",
		ButtonStrokeHover = "BorderDark",
		ButtonHeight = 1.5,
		ButtonFont = "FontTitle",
		ButtonText = "Text",
		ButtonInset = 1,
		ListItemH = 1.1,
		ListBoldSelected = true,
		ListGap = 1,
		PanelCorner = 0,
		PanelStroke = "BorderDark",
		ArrowSize = 8,
		GearSize = 11,
		IconBg = "Panel",
		WatermarkGradient = "RainbowBar",
		PopoutWidth = 230,
	},
	Window = W.Window,
	Group = W.Group,
	Components = { Toggle = Comp.Toggle },
	Notification = Comp.Notification,
	Loader = require("Skins/Classic/Loader"),
})
end
__MODULES["Skins/Dashboard/Loader"] = function(require)
--[[
	Dashboard loader: logo animation (Back easing), typewriter title, product cards,
	gradient progress bar with a moving shimmer, percentage counter and step labels with checkmarks.
]]
local Tween = require("Core/Tween")

return function(ctx, opts, handle)
	local Wd, Ht = 520, 420
	local root = ctx:Frame(ctx.Layers.Loader, { Name = "Loader", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(Wd, Ht) }, "Panel")
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "Border", 1)
	ctx:Shadow(root, "CornerRadius", 5)

	-- logo: scale in with Back easing
	local mark = ctx:Frame(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 28), Size = UDim2.fromOffset(56, 56) }, "Highlight")
	ctx:Corner(mark, 16)
	ctx:Grad(mark, "HeaderGradient", { Force = true, Rotation = 45 })
	ctx:Icon(mark, "logo", 30, "TextOnAccent", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BgKey = "Accent" })
	local msc = Instance.new("UIScale")
	msc.Scale = 0
	msc.Parent = mark
	Tween.Play(msc, { Scale = 1 }, 0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	-- typewriter title
	local fullTitle = opts.Title or (ctx:T("LoaderTitle") ~= "" and ctx:T("LoaderTitle") or ctx:T("Title"))
	local title = ctx:Text(root, { Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center }, "Text", "FontTitle", "TitleSize")
	title.TextSize = 22
	task.spawn(function()
		for i = 1, #fullTitle do
			if not title.Parent then
				return
			end
			title.Text = string.sub(fullTitle, 1, i) .. (i < #fullTitle and "▍" or "")
			task.wait(Tween.Enabled and 0.05 or 0)
		end
		title.Text = fullTitle
	end)
	ctx:Text(root, { Text = (opts.Subtitle or ctx:T("LoaderSubtitle")) .. ", " .. (opts.Username or ctx:Username()), Position = UDim2.fromOffset(0, 126), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center }, "TextDim", "FontBody", "SmallTextSize")

	-- product cards (horizontal)
	local selected = 1
	local cards = ctx:Frame(root, { Position = UDim2.fromOffset(24, 158), Size = UDim2.new(1, -48, 0, 92) })
	ctx:List(cards, { Dir = "H", Pad = 10 })
	local n = math.min(#opts.Products, 3)
	local strokes = {}
	local function paint()
		for i, s in ipairs(strokes) do
			ctx.Theme:Bind(s, "Color", i == selected and "Accent" or "Border", { Tween = true })
			s.Thickness = i == selected and 2 or 1
		end
	end
	for i = 1, n do
		local p = opts.Products[i]
		local c = ctx:New("TextButton", { Parent = cards, Size = UDim2.new(1 / n, -(10 * (n - 1)) / n, 1, 0), LayoutOrder = i, BackgroundTransparency = 0 }, { BackgroundColor3 = "Element" })
		ctx:Corner(c, "SmallCornerRadius")
		table.insert(strokes, ctx:Stroke(c, "Border", 1))
		ctx:Icon(c, p.Icon or "zap", 16, "Accent", { Position = UDim2.fromOffset(12, 12) })
		ctx:Text(c, { Text = p.Name, Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd }, "Text", "FontTitle", "TextSize")
		local s = string.lower(p.Status or "")
		local key = (s:find("undetect") or s:find("online")) and "Success" or (s:find("updat") and "Warning" or "Error")
		local dot = ctx:Frame(c, { Position = UDim2.fromOffset(12, 64), Size = UDim2.fromOffset(7, 7) }, key)
		ctx:Corner(dot, "full")
		ctx:Text(c, { Text = (p.Status or "Undetected") .. " · " .. (p.Expires or "Never"), Position = UDim2.fromOffset(24, 58), Size = UDim2.new(1, -30, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd }, "TextDim", "FontBody", "SmallTextSize")
		c.Activated:Connect(function()
			if not handle.Running then
				selected = i
				paint()
			end
		end)
	end
	paint()

	-- progress with shimmer + percentage
	local bar = ctx:Frame(root, { Position = UDim2.new(0, 24, 0, 272), Size = UDim2.new(1, -48, 0, 8), ClipsDescendants = true }, "Element")
	ctx:Corner(bar, "full")
	local fill = ctx:Frame(bar, { Size = UDim2.fromScale(0, 1), ClipsDescendants = true }, "Highlight")
	ctx:Corner(fill, "full")
	ctx:Grad(fill, "HeaderGradient", { Force = true })
	local shimmer = ctx:New("Frame", { Parent = fill, Size = UDim2.new(0, 60, 1, 0), Position = UDim2.new(0, -60, 0, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.2 })
	local sg = Instance.new("UIGradient")
	sg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1) })
	sg.Parent = shimmer
	local pct = ctx:Text(root, { Position = UDim2.new(0, 24, 0, 286), Size = UDim2.new(1, -48, 0, 18), TextXAlignment = Enum.TextXAlignment.Right }, "Text", "FontTitle", "TextSize")
	pct.Text = "0%"
	local stepText = ctx:Text(root, { Position = UDim2.new(0, 24, 0, 286), Size = UDim2.new(1, -100, 0, 18) }, "TextDim", "FontBody", "SmallTextSize")
	stepText.Text = ctx:T("LoaderStatus")

	-- step labels
	local steps = ctx:Frame(root, { Position = UDim2.fromOffset(24, 312), Size = UDim2.new(1, -48, 0, 50) })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.333, -6, 0, 20)
	grid.CellPadding = UDim2.fromOffset(8, 4)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = steps
	local stepRows = {}
	for i, s in ipairs(opts.Steps) do
		local text = type(s) == "table" and s.Text or tostring(s)
		local row = ctx:Frame(steps, { Size = UDim2.new(0.333, -6, 0, 20), LayoutOrder = i })
		local ring = ctx:Frame(row, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(12, 12) }, "Element")
		ctx:Corner(ring, "full")
		local chk = ctx:Icon(ring, "check", 8, "TextOnAccent", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		chk.Visible = false
		local t = ctx:Text(row, { Text = text, Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -18, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd }, "TextDisabled", "FontBody", "SmallTextSize")
		stepRows[i] = { Ring = ring, Check = chk, Text = t }
	end

	local btn = ctx:New("TextButton", { Parent = root, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(1, -48, 0, 40), Text = "Launch", TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0 }, { BackgroundColor3 = "Highlight", TextColor3 = "TextOnAccent", Font = "FontTitle", TextSize = "TextSize" })
	ctx:Corner(btn, "SmallCornerRadius")
	ctx:Grad(btn, "HeaderGradient", { Force = true })
	ctx:Hover(btn, function(st)
		ctx.Theme:Bind(btn, "BackgroundColor3", "Highlight", { Alpha = st == "Hover" and 0.1 or (st == "Press" and 0.2 or 0), Tween = true })
	end)
	btn.Activated:Connect(function()
		ctx:Sound("SoundClick")
		handle.Start(selected)
	end)

	local shimmerOn = false
	local current = 0
	local view = { Root = root }
	function view:OnStart()
		btn.Visible = false
		shimmerOn = true
		task.spawn(function()
			while shimmerOn and shimmer.Parent do
				shimmer.Position = UDim2.new(0, -60, 0, 0)
				Tween.Play(shimmer, { Position = UDim2.new(1, 0, 0, 0) }, 0.9, Enum.EasingStyle.Sine)
				task.wait(Tween.Duration(1.1))
			end
		end)
	end
	function view:SetProgress(p, text, index)
		Tween.Play(fill, { Size = UDim2.fromScale(p, 1) }, 0.35)
		local from = current
		current = p
		Tween.Value(from * 100, p * 100, 0.35, function(v)
			pct.Text = math.floor(v + 0.5) .. "%"
		end)
		stepText.Text = text or ""
		for i, r in ipairs(stepRows) do
			local done = index and (i < index or p >= 1)
			local active = index and i == index and p < 1
			ctx.Theme:Bind(r.Ring, "BackgroundColor3", done and "Success" or (active and "Accent" or "Element"), { Tween = true })
			r.Check.Visible = done == true
			ctx.Theme:Bind(r.Text, "TextColor3", done and "Text" or (active and "Accent" or "TextDisabled"), { Tween = true })
		end
	end
	function view:SetStatus(text)
		stepText.Text = text
	end
	function view:Close(cb)
		shimmerOn = false
		local sc = Instance.new("UIScale")
		sc.Parent = root
		Tween.Play(sc, { Scale = 0.9 }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(Tween.Duration(0.25), function()
			root:Destroy()
			if cb then
				cb()
			end
		end)
	end
	return view
end
end
__MODULES["Skins/Dashboard/Theme"] = function(require)
--[[ Dashboard skin – default theme values + presets (original modern dashboard look) ]]
local C = Color3.fromRGB

return {
	Defaults = {
		Accent = C(116, 98, 255),
		AccentDark = C(0, 196, 220),
		Background = C(14, 16, 22),
		BackgroundSecondary = C(19, 22, 30),
		Topbar = C(19, 22, 30),
		Panel = C(23, 27, 37),
		PanelHeader = C(27, 32, 44),
		Border = C(34, 39, 52),
		BorderDark = C(9, 10, 14),
		BorderLight = C(52, 59, 78),
		Element = C(32, 37, 50),
		ElementHover = C(40, 46, 62),
		ElementActive = C(48, 55, 74),
		Text = C(238, 241, 247),
		TextDim = C(139, 147, 167),
		TextDisabled = C(78, 85, 104),
		TextOnAccent = C(255, 255, 255),
		Divider = C(31, 36, 48),
		Knob = C(255, 255, 255),
		Glow = C(116, 98, 255),
		Info = C(116, 98, 255),
		Success = C(52, 211, 153),
		Warning = C(251, 191, 36),
		Error = C(248, 82, 96),
		Tooltip = C(12, 14, 19),
		AccentGradient = { Enabled = true, Colors = { "Accent", "AccentDark" }, Rotation = 0, Animated = false, Speed = 0.5 },
		HeaderGradient = { Enabled = true, Colors = { "Accent", "AccentDark" }, Rotation = 0, Animated = false, Speed = 0.4 },
		FontTitle = "GothamBold",
		FontBody = "GothamMedium",
		FontMono = "RobotoMono",
		TextSize = 13,
		TitleSize = 15,
		SmallTextSize = 11,
		CornerRadius = 12,
		SmallCornerRadius = 8,
		ShadowEnabled = true,
		ShadowTransparency = 0.45,
		WindowWidth = 940,
		WindowHeight = 610,
		SidebarWidth = 210,
		Spacing = 10,
		Padding = 16,
		ElementHeight = 32,
		GroupSpacing = 16,
		AnimationSpeed = 1,
		EasingStyle = "Quint",
		NotifyPosition = "TopRight",
		NotifyWidth = 290,
		MobileButtonShape = "Rounded",
		QuickToggleShape = "Rounded",
	},
	Presets = {
		Default = {},
		Ocean = { Accent = C(56, 140, 255), AccentDark = C(0, 214, 190), Glow = C(56, 140, 255), Info = C(56, 140, 255) },
		Sunset = { Accent = C(255, 112, 67), AccentDark = C(255, 64, 129), Glow = C(255, 112, 67), Info = C(255, 112, 67) },
		Emerald = { Accent = C(16, 185, 129), AccentDark = C(59, 130, 246), Glow = C(16, 185, 129), Info = C(16, 185, 129) },
		Light = {
			Background = C(244, 246, 251), BackgroundSecondary = C(255, 255, 255), Topbar = C(255, 255, 255), Panel = C(255, 255, 255),
			PanelHeader = C(248, 249, 252), Border = C(226, 230, 240), BorderLight = C(206, 212, 226), Element = C(238, 241, 248),
			ElementHover = C(229, 233, 243), ElementActive = C(218, 223, 236), Text = C(24, 28, 40), TextDim = C(102, 110, 130),
			TextDisabled = C(170, 176, 192), Divider = C(234, 237, 244), Tooltip = C(255, 255, 255), Shadow = C(120, 130, 160),
		},
	},
}
end
__MODULES["Skins/Dashboard/Window"] = function(require)
--[[
	Dashboard window (original design): top bar (logo, page tabs, search, notification bell with badge,
	avatar), sidebar with collapsible categories, page header with status cards, card groups.
]]
local Kit = require("Skins/Base/Window")
local Tween = require("Core/Tween")
local Modern = require("Skins/Modern/Window")

local W = {}

-- small status card used in the page header
local function statusCard(ctx, parent, order, icon, label, valueFn, key)
	local card = ctx:Frame(parent, { Size = UDim2.new(0.25, -9, 0, 64), LayoutOrder = order }, "Panel")
	ctx:Corner(card, "CornerRadius")
	ctx:Stroke(card, "Border", 1)
	local iconBox = ctx:Frame(card, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(36, 36) }, key or "Accent", { Alpha = 0.82 })
	ctx:Corner(iconBox, "SmallCornerRadius")
	ctx:Icon(iconBox, icon, 16, key or "Accent", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BgKey = "Panel" })
	ctx:Text(card, { Text = label, Position = UDim2.new(0, 58, 0.5, -16), Size = UDim2.new(1, -64, 0, 14) }, "TextDim", "FontBody", "SmallTextSize")
	local value = ctx:Text(card, { Position = UDim2.new(0, 58, 0.5, 0), Size = UDim2.new(1, -64, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd }, "Text", "FontTitle", "TitleSize")
	value.TextSize = 17
	local function refresh()
		local ok, v = pcall(valueFn)
		value.Text = ok and tostring(v) or "-"
	end
	refresh()
	return refresh
end

function W.Window(ctx, win)
	local lib = ctx.Library
	local root = Kit.Root(ctx, win)
	ctx.Theme:Bind(root, "BackgroundColor3", "Background", { Window = true })
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "Border", 1)
	ctx:Shadow(root, "CornerRadius", 5)
	local sw = ctx:T("SidebarWidth")
	local size = win:GetSize()
	local compact = ctx.IsMobile and size.X * ctx.Scale < 760
	local topH = 60

	-- top bar --------------------------------------------------------------
	local top = ctx:Frame(root, { Name = "Topbar", Size = UDim2.new(1, 0, 0, topH), ZIndex = 4 }, "Topbar", { Window = true })
	ctx:Corner(top, "CornerRadius")
	ctx:Frame(top, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 12), ZIndex = 4 }, "Topbar", { Window = true })
	ctx:Frame(top, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), ZIndex = 5 }, "Border")
	local brand = ctx:Frame(top, { Size = UDim2.new(0, compact and 60 or sw, 1, 0), ZIndex = 5 })
	local mark = ctx:Frame(brand, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 18, 0.5, 0), Size = UDim2.fromOffset(30, 30), ZIndex = 6 }, "Highlight")
	ctx:Corner(mark, "SmallCornerRadius")
	ctx:Grad(mark, "HeaderGradient", { Force = true, Rotation = 45 })
	ctx:Icon(mark, "logo", 16, "TextOnAccent", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 7, BgKey = "Accent" })
	if not compact then
		local title = ctx:Text(brand, { Position = UDim2.fromOffset(58, 0), Size = UDim2.new(1, -62, 1, 0), ZIndex = 6 }, "Text", "FontTitle", "TitleSize")
		title.TextSize = 17
		ctx.Theme:Bind(title, "Text", "Title")
	end
	local tabsX = compact and 64 or sw + 8
	local subBar = ctx:Frame(top, { Name = "PageTabs", Position = UDim2.fromOffset(tabsX, 0), Size = UDim2.new(1, -tabsX - 330, 1, 0), ZIndex = 5 })
	ctx:List(subBar, { Dir = "H", Pad = 6, VA = "Center" })
	local pageTitle = ctx:Text(top, { Position = UDim2.fromOffset(tabsX + 8, 0), Size = UDim2.new(0, 200, 1, 0), ZIndex = 5 }, "Text", "FontTitle", "TitleSize")
	local tools = ctx:Frame(top, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 5 })
	ctx:List(tools, { Dir = "H", Pad = 10, VA = "Center", HA = "Right" })
	Modern.SearchBox(ctx, win, tools, { Size = UDim2.fromOffset(compact and 130 or 200, 34), LayoutOrder = 1, ZIndex = 6 })
	-- bell with unread badge
	local bell = ctx:New("TextButton", { Parent = tools, Size = UDim2.fromOffset(34, 34), LayoutOrder = 2, BackgroundTransparency = 0, ZIndex = 6 }, { BackgroundColor3 = "Element" })
	ctx:Corner(bell, "SmallCornerRadius")
	ctx:Icon(bell, "bell", 15, "TextDim", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 7, BgKey = "Element" })
	local badge = ctx:Frame(bell, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(16, 16), ZIndex = 9 }, "Error")
	ctx:Corner(badge, "full")
	local badgeText = ctx:Text(badge, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 10 }, "TextOnAccent", "FontTitle", 10)
	local function refreshBadge()
		local n = lib.Unread or 0
		badge.Visible = n > 0
		badgeText.Text = n > 9 and "9+" or tostring(n)
	end
	refreshBadge()
	ctx.Maid:Give(lib.HistoryChanged:Connect(refreshBadge))
	ctx:Hover(bell, function(st)
		ctx.Theme:Bind(bell, "BackgroundColor3", st == "Idle" and "Element" or "ElementHover", { Tween = true })
	end)
	bell.Activated:Connect(function()
		lib.Unread = 0
		refreshBadge()
		local items = {}
		for i, h in ipairs(lib.History or {}) do
			if i > 8 then
				break
			end
			table.insert(items, { Text = h.Time .. "  " .. tostring(h.Title) .. ": " .. tostring(h.Content) })
		end
		if #items == 0 then
			items = { { Text = "No notifications" } }
		end
		ctx.Skin.ContextMenu(ctx, bell, items)
	end)
	ctx:AvatarCircle(tools, 34, { LayoutOrder = 3, Stroke = "Accent" })

	-- sidebar -----------------------------------------------------------------
	local side = ctx:Frame(root, { Name = "Sidebar", Position = UDim2.fromOffset(0, topH), Size = UDim2.new(0, sw, 1, -topH), ZIndex = 6 }, "BackgroundSecondary", { Window = true })
	ctx:Corner(side, "CornerRadius")
	ctx:Frame(side, { Size = UDim2.new(1, 0, 0, 14), ZIndex = 6 }, "BackgroundSecondary", { Window = true })
	ctx:Frame(side, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 14, 1, 0), ZIndex = 6 }, "BackgroundSecondary", { Window = true })
	ctx:Frame(side, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0), ZIndex = 7 }, "Border")
	local tabScroll = ctx:New("ScrollingFrame", { Parent = side, Size = UDim2.new(1, 0, 1, -70), ZIndex = 7, ScrollBarThickness = 0 })
	ctx:Pad(tabScroll, 12, 12, 12, 12)
	ctx:List(tabScroll, { Pad = 3 })
	-- upgrade / info card at the bottom
	local infoCard = ctx:Frame(side, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 50), ZIndex = 7 }, "Highlight")
	ctx:Corner(infoCard, "SmallCornerRadius")
	ctx:Grad(infoCard, "HeaderGradient", { Force = true })
	ctx:Text(infoCard, { Text = ctx:Username(), Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 16), ZIndex = 8 }, "TextOnAccent", "FontTitle", "TextSize")
	local infoLine = ctx:Text(infoCard, { Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -24, 0, 14), ZIndex = 8 }, "TextOnAccent", "FontBody", "SmallTextSize")
	ctx.Theme:Bind(infoLine, "Text", "UserInfo")

	local contentX = compact and 0 or sw
	local pages = ctx:Frame(root, { Name = "Pages", Position = UDim2.fromOffset(contentX, topH), Size = UDim2.new(1, -contentX, 1, -topH), ClipsDescendants = true, ZIndex = 2 })

	Kit.Draggable(ctx, win, root, top)
	Kit.Resizer(ctx, win, root, "TextDisabled", 680, 440)

	local drawerOpen = false
	local function setDrawer(open)
		drawerOpen = open
		Tween.Play(side, { Position = UDim2.fromOffset(open and 0 or -sw - 10, topH) }, 0.25)
	end
	if compact then
		root.ClipsDescendants = true -- the parked drawer must not show outside the window
		side.Position = UDim2.fromOffset(-sw - 10, topH)
		local burger = ctx:New("TextButton", { Parent = brand, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 8 })
		burger.Activated:Connect(function()
			setDrawer(not drawerOpen)
		end)
	end

	-- collapsible categories
	local cats = {}
	local function category(name)
		if cats[name] then
			return cats[name]
		end
		local idx = (table.find(win.Categories, name) or 0) + 1
		local head = ctx:New("TextButton", { Parent = tabScroll, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = idx * 1000, BackgroundTransparency = 1, ZIndex = 8 })
		ctx:Text(head, { Text = string.upper(name), Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -30, 1, 0), ZIndex = 9 }, "TextDisabled", "FontTitle", "SmallTextSize")
		local chev = ctx:Icon(head, "chevron", 9, "TextDisabled", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), ZIndex = 9 })
		local c = { Head = head, Open = true, Buttons = {} }
		head.Activated:Connect(function()
			c.Open = not c.Open
			Tween.Play(chev, { Rotation = c.Open and 0 or -90 }, 0.2)
			for _, b in ipairs(c.Buttons) do
				b.Visible = c.Open
			end
		end)
		cats[name] = c
		return c
	end

	local refreshers = {}
	local function header(scroll, sub)
		local tab = sub and sub.Tab
		local h = ctx:Frame(scroll, { Name = "PageHeader", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 })
		ctx:List(h, { Pad = 12 })
		local t = ctx:Text(h, { Text = tab and tab.Name or "", Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1 }, "Text", "FontTitle", "TitleSize")
		t.TextSize = 22
		ctx:Text(h, { Text = (tab and tab.Options.Description) or ("Manage your " .. string.lower(tab and tab.Name or "") .. " settings"), Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 2 }, "TextDim", "FontBody", "SmallTextSize")
		if sub and sub == (tab and tab.SubTabs[1]) and not (tab.Options.StatusCards == false) then
			local row = ctx:Frame(h, { Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 3 })
			ctx:List(row, { Dir = "H", Pad = 12 })
			local function activeCount()
				local n = 0
				for _, el in pairs(lib.Flags.Elements) do
					if el.Kind == "Toggle" and el.Value == true and not tostring(el.Flag):find("^__") then
						n += 1
					end
				end
				return n
			end
			table.insert(refreshers, statusCard(ctx, row, 1, "zap", "Active features", activeCount, "Accent"))
			table.insert(refreshers, statusCard(ctx, row, 2, "folder", "Config", function()
				return lib.Config.Current or "default"
			end, "Info"))
			table.insert(refreshers, statusCard(ctx, row, 3, "clock", "Ping", function()
				return lib:GetPing() .. " ms"
			end, "Success"))
			table.insert(refreshers, statusCard(ctx, row, 4, "shield", "Status", function()
				return "Online"
			end, "Warning"))
		end
	end
	ctx.Maid:Give(lib.Flags.Changed:Connect(function()
		for _, r in ipairs(refreshers) do
			r()
		end
	end))

	local view = Kit.Tabs(ctx, win, {
		TabHolder = tabScroll,
		PageHolder = pages,
		PageAnim = "Slide",
		PageOpts = { Header = header, Padding = 22 },
		SubTabHolder = subBar,
		OnSubTabVisibility = function(show)
			pageTitle.Visible = not show
		end,
		OnSelect = function(tab)
			pageTitle.Text = tab.Name
			for _, r in ipairs(refreshers) do
				r()
			end
			if compact and drawerOpen then
				setDrawer(false)
			end
		end,
		TabButton = function(tab, holder)
			local catName = tab.Category or "General"
			if not table.find(win.Categories, catName) then
				table.insert(win.Categories, 1, catName)
			end
			local c = category(catName)
			local b = ctx:New("TextButton", { Parent = holder, Name = "Tab_" .. tab.Name, Size = UDim2.new(1, 0, 0, ctx:RowH(1.15)), BackgroundTransparency = 0, ZIndex = 8 }, { BackgroundColor3 = "Accent" })
			ctx:Corner(b, "SmallCornerRadius")
			local grad = ctx:Grad(b, "AccentGradient", { Force = true })
			local icon = ctx:Icon(b, tab.Icon, 15, "TextDim", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), ZIndex = 9, BgKey = "BackgroundSecondary" })
			local t = ctx:Text(b, { Text = tab.Name, Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -44, 1, 0), ZIndex = 9 }, "TextDim", "FontBody", "TextSize")
			table.insert(c.Buttons, b)
			local sel = false
			local function paint(st)
				grad.Enabled = sel
				ctx.Theme:Bind(b, "BackgroundColor3", sel and "Highlight" or "ElementHover", { Alpha = sel and 0 or (st ~= "Idle" and 0 or 1), Tween = true })
				ctx.Theme:Bind(t, "TextColor3", sel and "TextOnAccent" or (st ~= "Idle" and "Text" or "TextDim"), { Tween = true })
				ctx:IconColor(icon, sel and "TextOnAccent" or (st ~= "Idle" and "Text" or "TextDim"), true)
			end
			ctx:Hover(b, paint)
			return {
				Root = b,
				Order = ((table.find(win.Categories, catName) or 0) + 1) * 1000 + (table.find(win.Tabs, tab) or 0),
				SetSelected = function(s)
					sel = s
					paint("Idle")
				end,
			}
		end,
		SubTabButton = function(sub, holder)
			local b = ctx:New("TextButton", { Parent = holder, Size = UDim2.new(0, 0, 0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, Text = sub.Name, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, { Font = "FontBody", TextSize = "TextSize", TextColor3 = "TextDim", BackgroundColor3 = "Element" })
			ctx:Pad(b, 0, 16, 0, 16)
			ctx:Corner(b, "full")
			local grad = ctx:Grad(b, "AccentGradient", { Force = true })
			local sel = false
			local function paint(st)
				grad.Enabled = sel
				ctx.Theme:Bind(b, "BackgroundColor3", sel and "Highlight" or (st ~= "Idle" and "ElementHover" or "Element"), { Alpha = sel and 0 or (st ~= "Idle" and 0 or 1), Tween = true })
				ctx.Theme:Bind(b, "TextColor3", sel and "TextOnAccent" or (st ~= "Idle" and "Text" or "TextDim"), { Tween = true })
			end
			ctx:Hover(b, paint)
			return {
				Root = b,
				SetSelected = function(s)
					sel = s
					paint("Idle")
				end,
			}
		end,
	})
	view.Root = root
	function view:SetOpen(open, instant)
		Kit.SetOpen(ctx, root, open, instant, "Scale")
	end
	function view:Destroy()
		root:Destroy()
	end
	return view
end

-- card group with icon badge header
function W.Group(ctx, group, column)
	local root = ctx:Frame(column, { Name = "Group_" .. group.Name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, "Panel")
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "Border", 1)
	ctx:List(root, {})
	local header = ctx:Frame(root, { Size = UDim2.new(1, 0, 0, 50), LayoutOrder = 1 })
	local badge = ctx:Frame(header, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0), Size = UDim2.fromOffset(28, 28) }, "Accent", { Alpha = 0.82 })
	ctx:Corner(badge, "SmallCornerRadius")
	ctx:Icon(badge, group.Icon or "layers", 13, "Accent", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BgKey = "Panel" })
	ctx:Text(header, { Text = group.Name, Position = UDim2.fromOffset(54, 0), Size = UDim2.new(1, -110, 1, 0) }, "Text", "FontTitle", "TextSize")
	ctx:Text(header, { Text = tostring(#group.Elements) .. " items", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 0), Size = UDim2.new(0, 70, 1, 0), TextXAlignment = Enum.TextXAlignment.Right }, "TextDisabled", "FontBody", "SmallTextSize")
	ctx:Frame(header, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1) }, "Divider")
	local container = ctx:Frame(root, { Name = "Container", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	ctx:Pad(container, 12, 16, 14, 16)
	ctx:List(container, { Pad = ctx:T("Spacing") })
	return { Root = root, Container = container }
end

return W
end
__MODULES["Skins/Dashboard"] = function(require)
--[[
	Skin "Dashboard" – original design: top bar with page tabs, search, notification bell and avatar,
	sidebar with collapsible categories, page header with status cards, card groups, large primary buttons.
]]
local Base = require("Skins/Base")
local W = require("Skins/Dashboard/Window")

return Base.Extend({
	Name = "Dashboard",
	Description = "Modern dashboard: cards, status cards, collapsible sidebar",
	Theme = require("Skins/Dashboard/Theme"),
	Style = {
		ToggleStyle = "Pill",
		PillW = 38,
		PillH = 21,
		ToggleLabelActive = false,
		LabelAbove = false,
		InlineWidth = 0.5,
		SliderValue = "Bubble",
		SliderTrack = 6,
		SliderKnob = 14,
		KnobStroke = "Accent",
		SliderGradient = true,
		TrackCorner = "full",
		ControlCorner = "SmallCornerRadius",
		ControlStroke = "Border",
		ControlStrokeHover = "Accent",
		KeyStyle = "Chip",
		SwatchW = 22,
		SwatchH = 22,
		SwatchCorner = "SmallCornerRadius",
		SwatchStroke = "BorderLight",
		ButtonStyle = "Primary",
		ButtonHeight = 1.25,
		ButtonFont = "FontTitle",
		ButtonCorner = "SmallCornerRadius",
		BoxHeight = 1,
		ListItemH = 1,
		PanelStroke = "Border",
		IconBg = "Panel",
		GearSize = 14,
		PopoutWidth = 270,
		DialogWidth = 380,
	},
	Window = W.Window,
	Group = W.Group,
	Loader = require("Skins/Dashboard/Loader"),
})
end
__MODULES["Skins/Fatal/Components"] = function(require)
--[[ Fatal component overrides: glowing checkboxes, glowing notifications ]]
local Base = require("Skins/Base")
local Tween = require("Core/Tween")
local C = Base.C

local M = {}

function M.Toggle(ctx, el, parent)
	local view = C.Toggle(ctx, el, parent)
	local glow = Instance.new("UIStroke")
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	glow.Thickness = 2
	glow.Parent = view.Box
	local update = view.Update
	function view:Update(v, instant)
		update(view, v, instant)
		ctx.Theme:Bind(glow, "Color", el.Value and "Glow" or "BorderDark", { Alpha = el.Value and 0.45 or 0, Tween = not instant })
	end
	return view
end

function M.Notification(ctx, opts, holder)
	local view = Base.O.Notification(ctx, opts, holder)
	local card = view.Root:FindFirstChildOfClass("Frame")
	if card then
		local key = Base.O.TypeKey[opts.Type] or "Accent"
		local s = card:FindFirstChildOfClass("UIStroke")
		if s then
			ctx.Theme:Bind(s, "Color", key, { Alpha = 0.35 })
			s.Thickness = 1.5
		end
		local stripe = card:FindFirstChild("Stripe")
		if stripe then
			ctx:Grad(stripe, "AccentGradient", { Force = true, Rotation = 90 })
		end
	end
	return view
end

-- pulsing glow helper used by the loader
function M.Pulse(stroke, minA, maxA, period)
	local running = true
	task.spawn(function()
		local up = true
		while running and stroke.Parent do
			Tween.Play(stroke, { Transparency = up and minA or maxA }, period / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			up = not up
			task.wait(Tween.Duration(period / 2))
		end
	end)
	return function()
		running = false
	end
end

return M
end
__MODULES["Skins/Fatal/Loader"] = function(require)
--[[
	Fatal loader: glowing logo intro with a pulse, product list and a gradient progress bar.
]]
local Tween = require("Core/Tween")
local Comp = require("Skins/Fatal/Components")

return function(ctx, opts, handle)
	local Wd, Ht = 470, 320
	local root = ctx:Frame(ctx.Layers.Loader, { Name = "Loader", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(Wd, Ht) }, "Background")
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "Border", 1)
	ctx:Grad(root, "BackgroundGradient")
	ctx:Glow(root, "Glow", "CornerRadius", 6, 0.3)

	-- logo intro: scale in + pulsing glow
	local logo = ctx:Logo(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.new(1, -40, 0, 48), TextXAlignment = Enum.TextXAlignment.Center }, "Highlight", 40)
	local stop
	if logo:IsA("TextLabel") then
		logo.TextSize = 40
		logo.Text = string.upper(logo.Text)
		ctx:Grad(logo, "HeaderGradient", { Force = true })
		local glow = Instance.new("UIStroke")
		glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		glow.Thickness = 3
		glow.Parent = logo
		ctx.Theme:Bind(glow, "Color", "Glow", { Alpha = 0.5 })
		stop = Comp.Pulse(glow, 0.25, 0.8, 1.6)
		local sc = Instance.new("UIScale")
		sc.Scale = 0.6
		sc.Parent = logo
		Tween.Play(sc, { Scale = 1 }, 0.6, Enum.EasingStyle.Back)
	end
	ctx:Text(root, { Text = string.upper((opts.Subtitle or ctx:T("LoaderSubtitle")) .. ", " .. (opts.Username or ctx:Username())), Position = UDim2.fromOffset(0, 82), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center }, "TextDim", "FontTitle", "SmallTextSize")

	-- products
	local list = ctx:Frame(root, { Position = UDim2.fromOffset(24, 112), Size = UDim2.new(1, -48, 0, 116) })
	ctx:List(list, { Pad = 6 })
	local selected = 1
	local rows = {}
	local function paint()
		for i, r in ipairs(rows) do
			ctx.Theme:Bind(r.Stroke, "Color", i == selected and "Accent" or "Border", { Tween = true })
			ctx.Theme:Bind(r.Name, "TextColor3", i == selected and "Text" or "TextDim", { Tween = true })
		end
	end
	for i, p in ipairs(opts.Products) do
		if i > 3 then
			break
		end
		local row = ctx:New("TextButton", { Parent = list, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = i, BackgroundTransparency = 0 }, { BackgroundColor3 = "Panel" })
		ctx:Corner(row, "SmallCornerRadius")
		local stroke = ctx:Stroke(row, "Border", 1)
		local name = ctx:Text(row, { Text = string.upper(p.Name), Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.5, 0, 1, 0) }, "TextDim", "FontTitle", "SmallTextSize")
		local s = string.lower(p.Status or "")
		local key = (s:find("undetect") or s:find("online")) and "Success" or (s:find("updat") and "Warning" or "Error")
		ctx:Text(row, { Text = string.upper(p.Status or "Undetected") .. "  ·  " .. (p.Expires or "Never"), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0.5, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right }, key, "FontBody", "SmallTextSize")
		table.insert(rows, { Stroke = stroke, Name = name })
		row.Activated:Connect(function()
			if not handle.Running then
				selected = i
				paint()
			end
		end)
	end
	paint()

	-- gradient progress bar + button
	local bar = ctx:Frame(root, { Position = UDim2.new(0, 24, 1, -72), Size = UDim2.new(1, -48, 0, 6) }, "Element")
	ctx:Corner(bar, "full")
	local fill = ctx:Frame(bar, { Size = UDim2.fromScale(0, 1) }, "Highlight")
	ctx:Corner(fill, "full")
	ctx:Grad(fill, "AccentGradient", { Force = true })
	ctx:Glow(fill, "Glow", nil, 2, 0.35)
	local status = ctx:Text(root, { Position = UDim2.new(0, 24, 1, -62), Size = UDim2.new(1, -48, 0, 16) }, "TextDim", "FontBody", "SmallTextSize")
	status.Text = string.upper(ctx:T("LoaderStatus"))
	local pct = ctx:Text(root, { Position = UDim2.new(0, 24, 1, -62), Size = UDim2.new(1, -48, 0, 16), TextXAlignment = Enum.TextXAlignment.Right }, "Accent", "FontMono", "SmallTextSize")
	local btn = ctx:New("TextButton", { Parent = root, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(160, 30), Text = "INJECT", TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0 }, { BackgroundColor3 = "Highlight", TextColor3 = "TextOnAccent", Font = "FontTitle", TextSize = "SmallTextSize" })
	ctx:Corner(btn, "full")
	ctx:Grad(btn, "AccentGradient", { Force = true })
	ctx:Glow(btn, "Glow", nil, 3, 0.35)
	ctx:Hover(btn, function(st)
		ctx.Theme:Bind(btn, "BackgroundColor3", "Highlight", { Alpha = st == "Hover" and 0.12 or (st == "Press" and 0.25 or 0), Tween = true })
	end)
	btn.Activated:Connect(function()
		ctx:Sound("SoundClick")
		handle.Start(selected)
	end)
	local view = { Root = root }
	function view:OnStart()
		btn.Text = "INJECTING..."
	end
	function view:SetProgress(p, text)
		Tween.Play(fill, { Size = UDim2.fromScale(math.max(p, 0.02), 1) }, 0.3)
		status.Text = string.upper(text or "")
		pct.Text = math.floor(p * 100 + 0.5) .. "%"
	end
	function view:SetStatus(text)
		status.Text = string.upper(text)
	end
	function view:Close(cb)
		if stop then
			stop()
		end
		Tween.Play(root, { Position = UDim2.new(0.5, 0, 0.5, -20) }, 0.25)
		task.delay(Tween.Duration(0.25), function()
			root:Destroy()
			if cb then
				cb()
			end
		end)
	end
	return view
end
end
__MODULES["Skins/Fatal/Theme"] = function(require)
--[[ Fatal skin – default theme values + presets (violet-black, pink/magenta accent, gradients + glow) ]]
local C = Color3.fromRGB

return {
	Defaults = {
		Accent = C(224, 33, 126),
		AccentDark = C(122, 44, 222),
		Background = C(19, 14, 33),
		BackgroundSecondary = C(13, 9, 24),
		Topbar = C(14, 10, 26),
		Panel = C(26, 19, 45),
		PanelHeader = C(30, 22, 52),
		Border = C(44, 32, 74),
		BorderDark = C(9, 6, 17),
		BorderLight = C(70, 52, 110),
		Element = C(37, 28, 63),
		ElementHover = C(47, 36, 80),
		ElementActive = C(58, 44, 98),
		Text = C(238, 230, 248),
		TextDim = C(150, 136, 178),
		TextDisabled = C(86, 74, 112),
		TextOnAccent = C(255, 255, 255),
		Divider = C(36, 27, 62),
		Knob = C(255, 255, 255),
		Glow = C(224, 33, 126),
		Info = C(224, 33, 126),
		Tooltip = C(14, 10, 26),
		AccentGradient = { Enabled = true, Colors = { "Accent", "AccentDark" }, Rotation = 0, Animated = false, Speed = 0.5 },
		HeaderGradient = { Enabled = true, Colors = { "Accent", "AccentDark" }, Rotation = 0, Animated = true, Speed = 0.25 },
		BackgroundGradient = { Enabled = true, Colors = { C(22, 15, 40), C(14, 10, 26) }, Rotation = 90, Animated = false, Speed = 0.5 },
		FontTitle = "GothamBlack",
		FontBody = "GothamMedium",
		FontMono = "RobotoMono",
		TextSize = 13,
		TitleSize = 14,
		SmallTextSize = 11,
		CornerRadius = 5,
		SmallCornerRadius = 3,
		ShadowEnabled = true,
		ShadowTransparency = 0.4,
		WindowWidth = 780,
		WindowHeight = 550,
		SidebarWidth = 160,
		Spacing = 8,
		Padding = 13,
		ElementHeight = 26,
		GroupSpacing = 13,
		AnimationSpeed = 1.1,
		EasingStyle = "Quart",
		NotifyPosition = "TopRight",
		NotifyWidth = 270,
		MobileButtonShape = "Circle",
		QuickToggleShape = "Rounded",
	},
	Presets = {
		Default = {},
		Cyber = { Accent = C(0, 220, 255), AccentDark = C(130, 60, 255), Glow = C(0, 220, 255), Info = C(0, 220, 255) },
		Inferno = { Accent = C(255, 90, 40), AccentDark = C(220, 30, 80), Glow = C(255, 90, 40), Info = C(255, 90, 40) },
		Toxic = { Accent = C(120, 255, 90), AccentDark = C(20, 180, 130), Glow = C(120, 255, 90), Info = C(120, 255, 90) },
		["No glow"] = { ShadowEnabled = false },
	},
}
end
__MODULES["Skins/Fatal/Window"] = function(require)
--[[
	Fatal window: violet-black window, gradient logo with glow, top tabs with an animated underline
	that slides between tabs, gradient header line, glowing group boxes.
]]
local Kit = require("Skins/Base/Window")
local Tween = require("Core/Tween")

local W = {}

function W.Window(ctx, win)
	local root = Kit.Root(ctx, win)
	ctx.Theme:Bind(root, "BackgroundColor3", "Background", { Window = true })
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "Border", 1)
	ctx:Grad(root, "BackgroundGradient")
	ctx:Glow(root, "Glow", "CornerRadius", 5, 0.22)
	local headerH = 54
	local header = ctx:Frame(root, { Name = "Header", Size = UDim2.new(1, 0, 0, headerH), ZIndex = 3 }, "Topbar", { Window = true })
	ctx:Corner(header, "CornerRadius")
	ctx:Frame(header, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 8), ZIndex = 3 }, "Topbar", { Window = true })
	local line = ctx:Frame(root, { Position = UDim2.fromOffset(0, headerH), Size = UDim2.new(1, 0, 0, 1), ZIndex = 4 }, "Highlight")
	ctx:Grad(line, "HeaderGradient", { Force = true })
	-- gradient logo with glow
	local logo = ctx:Logo(header, { Position = UDim2.fromOffset(18, 0), Size = UDim2.new(0, 160, 1, 0), ZIndex = 5 }, "Highlight", 22)
	if logo:IsA("TextLabel") then
		logo.TextSize = 22
		logo.Text = string.upper(logo.Text)
		ctx.Theme:Bind(logo, "Text", "LogoText", function(v)
			return string.upper(v)
		end)
		ctx:Grad(logo, "HeaderGradient", { Force = true })
		local glow = Instance.new("UIStroke")
		glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		glow.Thickness = 2
		glow.Parent = logo
		ctx.Theme:Bind(glow, "Color", "Glow", { Alpha = 0.65 })
	end
	local tabBar = ctx:New("ScrollingFrame", { Parent = header, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(1, -190, 1, 0), ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollBarThickness = 0, ZIndex = 5 })
	ctx:List(tabBar, { Dir = "H", Pad = 4, HA = "Right", VA = "Center" })
	-- single underline that slides to the active tab
	local underline = ctx:Frame(header, { Name = "Underline", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.fromOffset(0, 2), ZIndex = 7 }, "Highlight")
	ctx:Grad(underline, "AccentGradient", { Force = true })
	local underGlow = ctx:Glow(underline, "Glow", nil, 2, 0.4)
	local _ = underGlow

	local body = ctx:Frame(root, { Name = "Body", Position = UDim2.fromOffset(0, headerH + 1), Size = UDim2.new(1, 0, 1, -headerH - 1), ClipsDescendants = true })
	ctx:Texture(body)
	local subBar = ctx:Frame(body, { Name = "SubTabs", Position = UDim2.fromOffset(13, 10), Size = UDim2.new(1, -26, 0, 28), Visible = false, ZIndex = 3 })
	ctx:List(subBar, { Dir = "H", Pad = 6 })
	local pages = ctx:Frame(body, { Name = "Pages", Size = UDim2.fromScale(1, 1), ZIndex = 2 })

	Kit.Draggable(ctx, win, root, header)
	Kit.Resizer(ctx, win, root, "Accent", 600, 400)

	local buttons = {}
	local function moveUnderline(btn, instant)
		if not btn then
			return
		end
		task.defer(function()
			local hp = header.AbsolutePosition
			local bp, bs = btn.AbsolutePosition, btn.AbsoluteSize
			local s = ctx.Library.CurrentScale
			local x = (bp.X - hp.X) / s + 10
			local w = math.max(bs.X / s - 20, 8)
			Tween.Play(underline, { Position = UDim2.new(0, x, 1, 0), Size = UDim2.fromOffset(w, 2) }, instant and 0 or 0.3, Enum.EasingStyle.Quart)
		end)
	end

	local view = Kit.Tabs(ctx, win, {
		TabHolder = tabBar,
		PageHolder = pages,
		PageAnim = "Slide",
		SubTabHolder = subBar,
		OnSubTabVisibility = function(show)
			pages.Position = UDim2.fromOffset(0, show and 40 or 0)
			pages.Size = UDim2.new(1, 0, 1, show and -40 or 0)
		end,
		OnSelect = function(tab)
			moveUnderline(buttons[tab])
		end,
		TabButton = function(tab, holder)
			local b = ctx:New("TextButton", { Parent = holder, Name = "Tab_" .. tab.Name, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Text = string.upper(tab.Name), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, { Font = "FontTitle", TextSize = "SmallTextSize", TextColor3 = "TextDim" })
			ctx:Pad(b, 0, 10, 0, 10)
			buttons[tab] = b
			local sel = false
			local function paint(st)
				ctx.Theme:Bind(b, "TextColor3", sel and "Text" or (st ~= "Idle" and "Accent" or "TextDim"), { Tween = true })
			end
			ctx:Hover(b, paint)
			return {
				Root = b,
				SetSelected = function(s)
					sel = s
					paint("Idle")
				end,
			}
		end,
		SubTabButton = function(sub, holder)
			local b = ctx:New("TextButton", { Parent = holder, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, Text = string.upper(sub.Name), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 }, { Font = "FontTitle", TextSize = "SmallTextSize", TextColor3 = "TextDim", BackgroundColor3 = "Element" })
			ctx:Pad(b, 0, 14, 0, 14)
			ctx:Corner(b, "full")
			local grad = ctx:Grad(b, "AccentGradient", { Force = true })
			local sel = false
			local function paint(st)
				grad.Enabled = sel
				ctx.Theme:Bind(b, "BackgroundColor3", sel and "Highlight" or (st ~= "Idle" and "ElementHover" or "Element"), { Tween = true })
				ctx.Theme:Bind(b, "TextColor3", sel and "TextOnAccent" or (st ~= "Idle" and "Text" or "TextDim"), { Tween = true })
			end
			ctx:Hover(b, paint)
			return {
				Root = b,
				SetSelected = function(s)
					sel = s
					paint("Idle")
				end,
			}
		end,
	})
	view.Root = root
	function view:SetOpen(open, instant)
		Kit.SetOpen(ctx, root, open, instant, "Scale")
		if open and win.ActiveTab then
			moveUnderline(buttons[win.ActiveTab], true)
		end
	end
	function view:Destroy()
		root:Destroy()
	end
	return view
end

function W.Group(ctx, group, column)
	local root = ctx:Frame(column, { Name = "Group_" .. group.Name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, "Panel")
	ctx:Corner(root, "CornerRadius")
	local stroke = ctx:Stroke(root, "Border", 1)
	ctx:List(root, {})
	local header = ctx:Frame(root, { Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 1 })
	local dot = ctx:Frame(header, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(6, 6) }, "Accent")
	ctx:Corner(dot, "full")
	ctx:Text(header, { Text = string.upper(group.Name), Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -36, 1, 0) }, "Accent", "FontTitle", "SmallTextSize")
	local line = ctx:Frame(header, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, 0), Size = UDim2.new(1, -24, 0, 1) }, "Highlight")
	ctx:Grad(line, "AccentGradient", { Force = true })
	local container = ctx:Frame(root, { Name = "Container", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	ctx:Pad(container, 9, 12, 12, 12)
	ctx:List(container, { Pad = ctx:T("Spacing") })
	ctx:Hover(root, function(st)
		ctx.Theme:Bind(stroke, "Color", st == "Idle" and "Border" or "BorderLight", { Tween = true })
	end)
	return { Root = root, Container = container }
end

return W
end
__MODULES["Skins/Fatal"] = function(require)
--[[
	Skin "Fatal" – violet-black, pink/magenta accent with gradients and glow,
	top tabs with an animated sliding underline, glowing controls.
]]
local Base = require("Skins/Base")
local W = require("Skins/Fatal/Window")
local Comp = require("Skins/Fatal/Components")

return Base.Extend({
	Name = "Fatal",
	Description = "Violet-black, pink glow, animated tab underline",
	Theme = require("Skins/Fatal/Theme"),
	Style = {
		ToggleStyle = "Checkbox",
		CheckSize = 13,
		CheckCorner = "SmallCornerRadius",
		CheckStroke = "Border",
		CheckGradient = false,
		CheckMark = true,
		CheckGap = 9,
		ToggleLabelActive = true,
		LabelAbove = true,
		SliderTrack = 5,
		SliderKnob = 11,
		KnobStroke = "Accent",
		SliderValue = "Right",
		SliderValueColor = "Accent",
		SliderGradient = true,
		SliderRows = 1.6,
		TrackCorner = "full",
		ControlCorner = "SmallCornerRadius",
		ControlStroke = "Border",
		ControlStrokeHover = "Accent",
		KeyStyle = "Chip",
		SwatchW = 20,
		SwatchH = 12,
		SwatchCorner = "SmallCornerRadius",
		SwatchStroke = "BorderLight",
		ButtonStyle = "Filled",
		ButtonStroke = "Border",
		ButtonStrokeHover = "Accent",
		ButtonHeight = 1.15,
		ButtonFont = "FontTitle",
		LabelCase = nil,
		BoxHeight = 1,
		AboveOverlap = 2,
		ListItemH = 1,
		PanelStroke = "Accent",
		IconBg = "Panel",
		WatermarkGradient = "AccentGradient",
		PopoutWidth = 240,
		DialogStroke = "Accent",
	},
	Window = W.Window,
	Group = W.Group,
	Components = { Toggle = Comp.Toggle },
	Notification = Comp.Notification,
	Loader = require("Skins/Fatal/Loader"),
})
end
__MODULES["Skins/Modern/Loader"] = function(require)
--[[
	Modern loader: rounded screen with avatar + greeting, product cards (name, status badge,
	expiry date, "Load" button) and an animated loading spinner with a progress bar.
]]
local Tween = require("Core/Tween")

local function greeting()
	local h = tonumber(os.date("%H")) or 12
	if h < 5 then
		return "Good night"
	elseif h < 12 then
		return "Good morning"
	elseif h < 18 then
		return "Good afternoon"
	end
	return "Good evening"
end

local function statusKey(s)
	s = string.lower(s or "")
	if s:find("undetect") or s:find("online") or s:find("working") then
		return "Success"
	elseif s:find("updat") or s:find("risk") then
		return "Warning"
	end
	return "Error"
end

-- rotating arc spinner (two half rings + gradient), animated with a light loop
local function spinner(ctx, parent, size)
	local holder = ctx:Frame(parent, { Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	local ring = ctx:Frame(holder, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	ctx:Corner(ring, "full")
	local st = ctx:Stroke(ring, "Accent", 3)
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.9), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = st
	local track = ctx:Frame(holder, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = holder.ZIndex - 1 })
	ctx:Corner(track, "full")
	ctx:Stroke(track, "Element", 3)
	local running = true
	task.spawn(function()
		while running and holder.Parent do
			g.Rotation = (g.Rotation + 12) % 360
			task.wait(1 / 30)
		end
	end)
	holder.Destroying:Connect(function()
		running = false
	end)
	return holder
end

return function(ctx, opts, handle)
	local Wd, Ht = 600, 380
	local root = ctx:Frame(ctx.Layers.Loader, { Name = "Loader", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(Wd, Ht) }, "Background")
	ctx:Corner(root, 14)
	ctx:Stroke(root, "Border", 1)
	ctx:Shadow(root, nil, 5)
	local sc = Instance.new("UIScale")
	sc.Scale = 0.94
	sc.Parent = root
	Tween.Play(sc, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)

	-- left: profile
	local left = ctx:Frame(root, { Size = UDim2.new(0, 210, 1, 0) }, "BackgroundSecondary")
	ctx:Corner(left, 14)
	ctx:Frame(left, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 16, 1, 0) }, "BackgroundSecondary")
	ctx:Frame(left, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0) }, "Border")
	ctx:Logo(left, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center }, "Text", 24).TextSize = 24
	ctx:AvatarCircle(left, 64, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Stroke = "Accent" })
	ctx:Text(left, { Text = greeting() .. ",", Position = UDim2.fromOffset(0, 168), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center }, "TextDim", "FontBody", "SmallTextSize")
	ctx:Text(left, { Text = opts.Username or ctx:Username(), Position = UDim2.fromOffset(0, 186), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center }, "Text", "FontTitle", "TitleSize")
	local info = ctx:Text(left, { Position = UDim2.fromOffset(0, 210), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center }, "Accent", "FontBody", "SmallTextSize")
	ctx.Theme:Bind(info, "Text", "UserInfo")
	ctx:Text(left, { Text = "v" .. ctx.Library.Version, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -14), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center }, "TextDisabled", "FontMono", "SmallTextSize")

	-- right: products
	local right = ctx:Frame(root, { Position = UDim2.fromOffset(210, 0), Size = UDim2.new(1, -210, 1, 0) })
	ctx:Text(right, { Text = opts.Title or "Products", Position = UDim2.fromOffset(22, 18), Size = UDim2.new(1, -44, 0, 22) }, "Text", "FontTitle", "TitleSize").TextSize = 18
	ctx:Text(right, { Text = (opts.Subtitle or "Select a product to load"), Position = UDim2.fromOffset(22, 42), Size = UDim2.new(1, -44, 0, 16) }, "TextDim", "FontBody", "SmallTextSize")
	local list = ctx:New("ScrollingFrame", { Parent = right, Position = UDim2.fromOffset(16, 70), Size = UDim2.new(1, -32, 1, -86) }, { ScrollBarImageColor3 = "Accent" })
	ctx:List(list, { Pad = 8 })
	ctx:Pad(list, 2, 6, 2, 6)
	for i, p in ipairs(opts.Products) do
		local card = ctx:Frame(list, { Size = UDim2.new(1, 0, 0, 70), LayoutOrder = i }, "Panel")
		ctx:Corner(card, "CornerRadius")
		local stroke = ctx:Stroke(card, "Border", 1)
		local iconBox = ctx:Frame(card, { Position = UDim2.new(0, 12, 0.5, -20), Size = UDim2.fromOffset(40, 40) }, "Accent", { Alpha = 0.85 })
		ctx:Corner(iconBox, "SmallCornerRadius")
		ctx:Icon(iconBox, p.Icon or "zap", 18, "Accent", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		ctx:Text(card, { Text = p.Name, Position = UDim2.fromOffset(64, 13), Size = UDim2.new(1, -170, 0, 18) }, "Text", "FontTitle", "TextSize")
		local key = statusKey(p.Status)
		local meta = ctx:Frame(card, { Position = UDim2.fromOffset(64, 36), Size = UDim2.new(1, -170, 0, 18), ClipsDescendants = true })
		ctx:List(meta, { Dir = "H", Pad = 8, VA = "Center" })
		local badge = ctx:Frame(meta, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1 }, key, { Alpha = 0.85 })
		ctx:Corner(badge, "full")
		ctx:Pad(badge, 0, 8, 0, 8)
		ctx:Text(badge, { Text = p.Status or "Undetected", Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X }, key, "FontTitle", 11)
		ctx:Text(meta, { Text = "until " .. (p.Expires or "never"), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 }, "TextDim", "FontBody", "SmallTextSize")
		local btn = ctx:New("TextButton", { Parent = card, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(84, 32), Text = "Load", TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0 }, { BackgroundColor3 = "Accent", TextColor3 = "TextOnAccent", Font = "FontTitle", TextSize = "SmallTextSize" })
		ctx:Corner(btn, "SmallCornerRadius")
		ctx:Grad(btn, "AccentGradient")
		ctx:Hover(btn, function(st)
			ctx.Theme:Bind(btn, "BackgroundColor3", "Accent", { Alpha = st == "Hover" and 0.15 or (st == "Press" and 0.3 or 0), Tween = true })
			ctx.Theme:Bind(stroke, "Color", st == "Idle" and "Border" or "Accent", { Tween = true })
		end)
		btn.Activated:Connect(function()
			ctx:Sound("SoundClick")
			handle.Start(i)
		end)
	end

	-- loading overlay
	local loading = ctx:Frame(right, { Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20 }, "Background")
	ctx:Corner(loading, 14)
	local spinHolder = ctx:Frame(loading, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -30), Size = UDim2.fromOffset(56, 56), ZIndex = 21 })
	local title = ctx:Text(loading, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 14), Size = UDim2.new(1, -60, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21 }, "Text", "FontTitle", "TitleSize")
	local step = ctx:Text(loading, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 38), Size = UDim2.new(1, -60, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21 }, "TextDim", "FontBody", "SmallTextSize")
	local bar = ctx:Frame(loading, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 66), Size = UDim2.new(0.6, 0, 0, 4), ZIndex = 21 }, "Element")
	ctx:Corner(bar, "full")
	local fill = ctx:Frame(bar, { Size = UDim2.fromScale(0, 1), ZIndex = 22 }, "Accent")
	ctx:Corner(fill, "full")
	ctx:Grad(fill, "HeaderGradient", { Force = true })

	local view = { Root = root }
	function view:OnStart(product)
		loading.Visible = true
		title.Text = "Loading " .. product.Name
		spinner(ctx, spinHolder, 56)
	end
	function view:SetProgress(p, text)
		Tween.Play(fill, { Size = UDim2.fromScale(p, 1) }, 0.3)
		step.Text = text or ""
	end
	function view:SetStatus(text)
		step.Text = text
	end
	function view:Close(cb)
		Tween.Play(sc, { Scale = 0.94 }, 0.2)
		task.delay(Tween.Duration(0.2), function()
			root:Destroy()
			if cb then
				cb()
			end
		end)
	end
	return view
end
end
__MODULES["Skins/Modern/Theme"] = function(require)
--[[ Modern skin – default theme values + presets (wide, blue-black, light blue accent) ]]
local C = Color3.fromRGB

return {
	Defaults = {
		Accent = C(30, 160, 255),
		AccentDark = C(18, 108, 205),
		Background = C(13, 19, 29),
		BackgroundSecondary = C(7, 11, 18),
		Topbar = C(11, 16, 25),
		Panel = C(16, 23, 35),
		PanelHeader = C(19, 27, 41),
		Border = C(27, 37, 54),
		BorderDark = C(5, 8, 13),
		BorderLight = C(44, 58, 82),
		Element = C(23, 32, 48),
		ElementHover = C(30, 42, 62),
		ElementActive = C(38, 53, 78),
		Text = C(226, 233, 243),
		TextDim = C(122, 137, 160),
		TextDisabled = C(66, 79, 100),
		TextOnAccent = C(255, 255, 255),
		Divider = C(22, 31, 46),
		Knob = C(255, 255, 255),
		Glow = C(30, 160, 255),
		Info = C(30, 160, 255),
		Tooltip = C(9, 14, 22),
		Highlight = C(255, 255, 255),
		AccentGradient = { Enabled = true, Colors = { "Accent", "AccentDark" }, Rotation = 0, Animated = false, Speed = 0.5 },
		HeaderGradient = { Enabled = true, Colors = { "Accent", C(110, 90, 255) }, Rotation = 0, Animated = false, Speed = 0.5 },
		FontTitle = "BuilderSansBold",
		FontBody = "BuilderSansMedium",
		FontMono = "RobotoMono",
		TextSize = 14,
		TitleSize = 15,
		SmallTextSize = 12,
		CornerRadius = 10,
		SmallCornerRadius = 6,
		ShadowEnabled = true,
		ShadowTransparency = 0.45,
		WindowWidth = 880,
		WindowHeight = 590,
		SidebarWidth = 196,
		Spacing = 9,
		Padding = 14,
		ElementHeight = 30,
		GroupSpacing = 14,
		AnimationSpeed = 1,
		EasingStyle = "Quint",
		NotifyPosition = "BottomRight",
		NotifyWidth = 280,
		MobileButtonShape = "Circle",
		QuickToggleShape = "Rounded",
	},
	Presets = {
		Default = {},
		Violet = { Accent = C(140, 92, 255), AccentDark = C(96, 56, 210), Glow = C(140, 92, 255), Info = C(140, 92, 255) },
		Mint = { Accent = C(40, 214, 168), AccentDark = C(22, 150, 118), Glow = C(40, 214, 168), Info = C(40, 214, 168) },
		Crimson = { Accent = C(240, 64, 88), AccentDark = C(170, 36, 58), Glow = C(240, 64, 88), Info = C(240, 64, 88) },
		Midnight = { Background = C(8, 10, 14), BackgroundSecondary = C(4, 5, 8), Panel = C(12, 14, 19), Element = C(19, 22, 30), ElementHover = C(26, 30, 40), Border = C(24, 28, 37), Divider = C(18, 21, 28) },
	},
}
end
__MODULES["Skins/Modern/Window"] = function(require)
--[[
	Modern window: wide rounded window. Left sidebar (logo, gray category headings, icon tabs,
	user card at the bottom). Content top bar with sub-tabs, config selector, save button and a
	search field that searches every element and jumps to it. On mobile the sidebar becomes a drawer.
]]
local Kit = require("Skins/Base/Window")
local Tween = require("Core/Tween")
local Util = require("Core/Util")
local Overlays = require("Skins/Base/Overlays")

local W = {}

-- search field + results overlay (shared with the Dashboard skin)
function W.SearchBox(ctx, win, parent, props)
	local box = ctx:Frame(parent, props, "Element")
	ctx:Corner(box, "SmallCornerRadius")
	local stroke = ctx:Stroke(box, "Border", 1)
	ctx:Icon(box, "search", 12, "TextDim", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0) })
	local input = ctx:Text(box, { Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -34, 1, 0), PlaceholderText = "Search...", ClearTextOnFocus = false, TextTruncate = Enum.TextTruncate.AtEnd }, "Text", "FontBody", "SmallTextSize", "TextBox")
	ctx.Theme:Bind(input, "PlaceholderColor3", "TextDisabled")
	local entry
	local function close()
		if entry then
			ctx:CloseOverlay(entry)
			entry = nil
		end
	end
	local function show()
		close()
		local results = win:Search(input.Text)
		if input.Text == "" then
			return
		end
		local itemH = ctx:RowH(1.15)
		local count = math.max(1, math.min(#results, 7))
		local panel = Overlays.Panel(ctx, { Name = "SearchResults" })
		ctx:PlaceNear(panel, box, math.max(260, box.AbsoluteSize.X / ctx.Library.CurrentScale), count * itemH + 8, 4)
		local list = ctx:Frame(panel, { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8) })
		ctx:List(list, {})
		if #results == 0 then
			ctx:Text(list, { Text = "No results", Size = UDim2.new(1, 0, 0, itemH), TextXAlignment = Enum.TextXAlignment.Center }, "TextDim", "FontBody", "SmallTextSize")
		end
		for i, r in ipairs(results) do
			if i > 7 then
				break
			end
			local b = ctx:New("TextButton", { Parent = list, Size = UDim2.new(1, 0, 0, itemH), LayoutOrder = i, BackgroundTransparency = 1 })
			ctx:Corner(b, "SmallCornerRadius")
			ctx:Text(b, { Text = tostring(r.Element.Name), Position = UDim2.fromOffset(10, 3), Size = UDim2.new(1, -20, 0.5, 0) }, "Text", "FontBody", "SmallTextSize")
			ctx:Text(b, { Text = r.Path .. "  ·  " .. string.lower(r.Element.Kind), Position = UDim2.new(0, 10, 0.5, -1), Size = UDim2.new(1, -20, 0.5, 0) }, "TextDim", "FontBody", 11)
			ctx:Hover(b, function(st)
				ctx.Theme:Bind(b, "BackgroundColor3", "ElementHover", { Alpha = st == "Idle" and 1 or 0, Tween = true })
			end)
			b.Activated:Connect(function()
				close()
				input.Text = ""
				win:Focus(r.Element)
			end)
		end
		entry = ctx:OpenOverlay(panel, function()
			entry = nil
		end)
	end
	input:GetPropertyChangedSignal("Text"):Connect(show)
	input.Focused:Connect(function()
		ctx.Theme:Bind(stroke, "Color", "Accent", { Tween = true })
	end)
	input.FocusLost:Connect(function()
		ctx.Theme:Bind(stroke, "Color", "Border", { Tween = true })
	end)
	return box, input
end

-- config selector + save button (shared with Dashboard)
function W.ConfigSelector(ctx, parent, props)
	local lib = ctx.Library
	local b = ctx:New("TextButton", props)
	b.Parent = parent
	ctx.Theme:Bind(b, "BackgroundColor3", "Element")
	ctx:Corner(b, "SmallCornerRadius")
	ctx:Stroke(b, "Border", 1)
	ctx:Icon(b, "folder", 12, "TextDim", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0) })
	local t = ctx:Text(b, { Position = UDim2.fromOffset(27, 0), Size = UDim2.new(1, -46, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd }, "Text", "FontBody", "SmallTextSize")
	ctx:Icon(b, "chevron", 9, "TextDim", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -9, 0.5, 0) })
	local function refresh()
		t.Text = lib.Config.Current or "default"
	end
	refresh()
	ctx.Maid:Give(lib.Config.Changed:Connect(refresh))
	ctx:Hover(b, function(st)
		ctx.Theme:Bind(b, "BackgroundColor3", st == "Idle" and "Element" or "ElementHover", { Tween = true })
	end)
	b.Activated:Connect(function()
		local items = {}
		for _, name in ipairs(lib.Config:List()) do
			table.insert(items, { Text = name, Selected = name == lib.Config.Current, Callback = function()
				lib.Config:Load(name)
			end })
		end
		if #items == 0 then
			table.insert(items, { Text = "No configs yet" })
		end
		ctx.Skin.ContextMenu(ctx, b, items)
	end)
	return b
end

function W.SaveButton(ctx, parent, props)
	local lib = ctx.Library
	local b = ctx:New("TextButton", props)
	b.Parent = parent
	ctx.Theme:Bind(b, "BackgroundColor3", "Accent")
	ctx:Corner(b, "SmallCornerRadius")
	ctx:Grad(b, "AccentGradient")
	ctx:Icon(b, "save", 14, "TextOnAccent", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BgKey = "Accent" })
	ctx:Hover(b, function(st)
		ctx.Theme:Bind(b, "BackgroundColor3", "Accent", { Alpha = st == "Hover" and 0.15 or (st == "Press" and 0.3 or 0), Tween = true })
	end)
	b.Activated:Connect(function()
		lib.Config:Save(lib.Config.Current or "default")
	end)
	return b
end

function W.Window(ctx, win)
	local lib = ctx.Library
	local root = Kit.Root(ctx, win)
	ctx.Theme:Bind(root, "BackgroundColor3", "Background", { Window = true })
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "Border", 1)
	ctx:Shadow(root, "CornerRadius", 5)
	local sw = ctx:T("SidebarWidth")
	local size = win:GetSize()
	local compact = ctx.IsMobile and size.X * ctx.Scale < 720

	-- sidebar ---------------------------------------------------------------
	local side = ctx:Frame(root, { Name = "Sidebar", Size = UDim2.new(0, sw, 1, 0), ZIndex = 5 }, "BackgroundSecondary", { Window = true })
	ctx:Corner(side, "CornerRadius")
	ctx:Frame(side, { Name = "Square", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 14, 1, 0), ZIndex = 5 }, "BackgroundSecondary", { Window = true })
	ctx:Frame(side, { Name = "Edge", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0), ZIndex = 6 }, "Border")
	local logo = ctx:Logo(side, { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 }, "Text", 24)
	if logo:IsA("TextLabel") then
		logo.TextSize = 26
		local glow = Instance.new("UIStroke")
		glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		glow.Thickness = 1.5
		glow.Parent = logo
		ctx.Theme:Bind(glow, "Color", "Accent", { Alpha = 0.35 })
	end
	local tabScroll = ctx:New("ScrollingFrame", { Parent = side, Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 1, -66 - 64), ZIndex = 7, ScrollBarThickness = 0 })
	ctx:Pad(tabScroll, 0, 10, 8, 10)
	ctx:List(tabScroll, { Pad = 2 })
	-- user card
	local user = ctx:Frame(side, { Name = "User", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 64), ZIndex = 7 })
	ctx:Frame(user, { Size = UDim2.new(1, -20, 0, 1), Position = UDim2.fromOffset(10, 0), ZIndex = 7 }, "Border")
	ctx:AvatarCircle(user, 34, { Position = UDim2.new(0, 14, 0.5, -17), Stroke = "Accent" })
	local uname = ctx:Text(user, { Text = ctx:Username(), Position = UDim2.new(0, 56, 0.5, -15), Size = UDim2.new(1, -64, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 8 }, "Text", "FontTitle", "TextSize")
	local _ = uname
	local info = ctx:Text(user, { Position = UDim2.new(0, 56, 0.5, 2), Size = UDim2.new(1, -64, 0, 14), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 8 }, "TextDim", "FontBody", "SmallTextSize")
	ctx.Theme:Bind(info, "Text", "UserInfo")

	-- content ----------------------------------------------------------------
	local contentX = compact and 0 or sw
	local content = ctx:Frame(root, { Name = "Content", Position = UDim2.fromOffset(contentX, 0), Size = UDim2.new(1, -contentX, 1, 0), ClipsDescendants = true, ZIndex = 2 })
	local top = ctx:Frame(content, { Name = "Topbar", Size = UDim2.new(1, 0, 0, 52), ZIndex = 3 })
	ctx:Frame(top, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), ZIndex = 3 }, "Divider")
	local leftX = 16
	local burger
	if compact then
		burger = ctx:New("TextButton", { Parent = top, Position = UDim2.new(0, 10, 0.5, -16), Size = UDim2.fromOffset(32, 32), BackgroundTransparency = 0, ZIndex = 4 }, { BackgroundColor3 = "Element" })
		ctx:Corner(burger, "SmallCornerRadius")
		ctx:Icon(burger, "menu", 14, "Text", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 5 })
		leftX = 52
	end
	local title = ctx:Text(top, { Position = UDim2.fromOffset(leftX, 0), Size = UDim2.new(0, 120, 1, 0), ZIndex = 4 }, "Text", "FontTitle", "TitleSize")
	local subBar = ctx:Frame(top, { Name = "SubTabs", Position = UDim2.fromOffset(leftX, 0), Size = UDim2.new(1, -leftX - 360, 1, 0), ZIndex = 4 })
	ctx:List(subBar, { Dir = "H", Pad = 4, VA = "Center" })
	local right = ctx:Frame(top, { Name = "Tools", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 0), Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 4 })
	ctx:List(right, { Dir = "H", Pad = 8, VA = "Center", HA = "Right" })
	W.ConfigSelector(ctx, right, { Size = UDim2.fromOffset(compact and 90 or 120, 30), LayoutOrder = 1, ZIndex = 5 })
	W.SaveButton(ctx, right, { Size = UDim2.fromOffset(30, 30), LayoutOrder = 2, ZIndex = 5 })
	W.SearchBox(ctx, win, right, { Size = UDim2.fromOffset(compact and 120 or 180, 30), LayoutOrder = 3, ZIndex = 5 })
	local pages = ctx:Frame(content, { Name = "Pages", Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -52), ZIndex = 2 })

	Kit.Draggable(ctx, win, root, top)
	Kit.Draggable(ctx, win, root, logo)
	Kit.Resizer(ctx, win, root, "TextDisabled", 640, 420)

	-- drawer (mobile)
	local drawerOpen = false
	local function setDrawer(open)
		drawerOpen = open
		Tween.Play(side, { Position = UDim2.fromOffset(open and 0 or -sw - 10, 0) }, 0.25)
	end
	if compact then
		root.ClipsDescendants = true -- the parked drawer must not show outside the window
		side.Position = UDim2.fromOffset(-sw - 10, 0)
		burger.Activated:Connect(function()
			setDrawer(not drawerOpen)
		end)
	end

	-- categories
	local headings = {}
	local function categoryIndex(cat)
		return (table.find(win.Categories, cat) or 0) + 1
	end
	local function heading(cat)
		if headings[cat] then
			return
		end
		local h = ctx:Text(tabScroll, { Text = cat, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = categoryIndex(cat) * 1000, ZIndex = 8 }, "TextDisabled", "FontTitle", "SmallTextSize")
		ctx:Pad(h, 8, 0, 0, 6)
		headings[cat] = h
	end

	local view = Kit.Tabs(ctx, win, {
		TabHolder = tabScroll,
		PageHolder = pages,
		PageAnim = "Slide",
		SubTabHolder = subBar,
		OnSubTabVisibility = function(show)
			title.Visible = not show
		end,
		OnSelect = function(tab)
			title.Text = tab.Name
			if compact and drawerOpen then
				setDrawer(false)
			end
		end,
		TabButton = function(tab, holder)
			local cat = tab.Category or "General"
			if not tab.Category then
				if not table.find(win.Categories, "General") then
					table.insert(win.Categories, 1, "General")
				end
			end
			heading(cat)
			local b = ctx:New("TextButton", { Parent = holder, Name = "Tab_" .. tab.Name, Size = UDim2.new(1, 0, 0, ctx:RowH(1.1)), BackgroundTransparency = 1, ZIndex = 8 })
			ctx:Corner(b, "SmallCornerRadius")
			local icon = ctx:Icon(b, tab.Icon, 14, "TextDim", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), ZIndex = 9, BgKey = "BackgroundSecondary" })
			local t = ctx:Text(b, { Text = tab.Name, Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -40, 1, 0), ZIndex = 9 }, "TextDim", "FontBody", "TextSize")
			local bar = ctx:Frame(b, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(3, 0), ZIndex = 9 }, "Accent")
			ctx:Corner(bar, "full")
			local selected = false
			local function paint(st)
				local hot = st == "Hover" or st == "Press"
				ctx.Theme:Bind(t, "TextColor3", selected and "Accent" or (hot and "Text" or "TextDim"), { Tween = true })
				ctx:IconColor(icon, selected and "Accent" or (hot and "Text" or "TextDim"), true)
				ctx.Theme:Bind(b, "BackgroundColor3", "Accent", { Alpha = selected and 0.88 or (hot and 0.95 or 1), Tween = true })
			end
			ctx:Hover(b, paint)
			local tabIndex = table.find(win.Tabs, tab) or 0
			return {
				Root = b,
				Order = categoryIndex(cat) * 1000 + tabIndex,
				SetSelected = function(sel, instant)
					selected = sel
					paint("Idle")
					Tween.Play(bar, { Size = UDim2.fromOffset(3, sel and 16 or 0) }, instant and 0 or 0.25)
				end,
			}
		end,
		SubTabButton = function(sub, holder)
			local b = ctx:New("TextButton", { Parent = holder, Size = UDim2.new(0, 0, 0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Text = sub.Name, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, { Font = "FontBody", TextSize = "TextSize", TextColor3 = "TextDim" })
			ctx:Pad(b, 0, 12, 0, 12)
			ctx:Corner(b, "SmallCornerRadius")
			local line = ctx:Frame(b, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 11), Size = UDim2.new(0, 0, 0, 2), ZIndex = 6 }, "Accent")
			ctx:Corner(line, "full")
			local sel = false
			local function paint(st)
				ctx.Theme:Bind(b, "TextColor3", sel and "Text" or (st ~= "Idle" and "Text" or "TextDim"), { Tween = true })
				ctx.Theme:Bind(b, "BackgroundColor3", "ElementHover", { Alpha = (st ~= "Idle" and not sel) and 0.4 or 1, Tween = true })
			end
			ctx:Hover(b, paint)
			return {
				Root = b,
				SetSelected = function(s, instant)
					sel = s
					paint("Idle")
					Tween.Play(line, { Size = UDim2.new(s and 1 or 0, s and -16 or 0, 0, 2) }, instant and 0 or 0.25)
				end,
			}
		end,
	})
	view.Root = root
	function view:SetOpen(open, instant)
		Kit.SetOpen(ctx, root, open, instant, "Scale")
	end
	function view:Destroy()
		root:Destroy()
	end
	local _ = Util
	return view
end

-- rounded group box, header + divider, rows separated by subtle dividers
function W.Group(ctx, group, column)
	local root = ctx:Frame(column, { Name = "Group_" .. group.Name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, "Panel")
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "Border", 1)
	ctx:List(root, {})
	local header = ctx:Frame(root, { Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 1 })
	if group.Icon then
		ctx:Icon(header, group.Icon, 13, "Accent", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0) })
	end
	ctx:Text(header, { Text = group.Name, Position = UDim2.fromOffset(group.Icon and 34 or 14, 0), Size = UDim2.new(1, -28, 1, 0) }, "TextDim", "FontTitle", "SmallTextSize")
	ctx:Frame(header, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1) }, "Divider")
	local container = ctx:Frame(root, { Name = "Container", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	ctx:Pad(container, 8, 14, 10, 14)
	ctx:List(container, { Pad = ctx:T("Spacing") })
	return { Root = root, Container = container }
end

return W
end
__MODULES["Skins/Modern"] = function(require)
--[[
	Skin "Modern" – wide blue-black window, sidebar with logo / categories / user card,
	top bar with sub-tabs, config selector, save button and search, rounded groups,
	pill switches, sliders with a value bubble, gear popouts and smooth animations.
]]
local Base = require("Skins/Base")
local W = require("Skins/Modern/Window")

return Base.Extend({
	Name = "Modern",
	Description = "Wide window, sidebar categories, search, pill switches",
	Theme = require("Skins/Modern/Theme"),
	Style = {
		ToggleStyle = "Pill",
		PillW = 32,
		PillH = 17,
		ToggleLabelActive = false,
		LabelAbove = false,
		InlineWidth = 0.5,
		SliderValue = "Bubble",
		SliderTrack = 4,
		SliderKnob = 11,
		TrackCorner = "full",
		ControlCorner = "SmallCornerRadius",
		ControlStroke = "Border",
		ControlStrokeHover = "BorderLight",
		RowDividers = true,
		KeyStyle = "Chip",
		SwatchW = 18,
		SwatchH = 18,
		SwatchCorner = "full",
		SwatchStroke = "BorderLight",
		ButtonStyle = "Filled",
		ButtonStroke = "Border",
		ButtonStrokeHover = "Accent",
		ButtonHeight = 1.05,
		BoxHeight = 0.9,
		ListItemH = 0.95,
		PanelStroke = "Border",
		IconBg = "Panel",
		GearSize = 13,
		PopoutWidth = 250,
		DialogWidth = 360,
	},
	Window = W.Window,
	Group = W.Group,
	Loader = require("Skins/Modern/Loader"),
})
end
__MODULES["Skins/Onetap/Loader"] = function(require)
--[[
	Onetap loader: minimal. Logo area, product selector, status line and an orange progress bar.
]]
local Tween = require("Core/Tween")

return function(ctx, opts, handle)
	local Wd, Ht = 400, 272
	local root = ctx:Frame(ctx.Layers.Loader, { Name = "Loader", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(Wd, Ht) }, "Background")
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "BorderDark", 1)
	ctx:Shadow(root, "CornerRadius", 4)
	local logoArea = ctx:Frame(root, { Size = UDim2.new(1, 0, 0, 110) }, "Topbar")
	ctx:Corner(logoArea, "CornerRadius")
	local logo = ctx:Logo(logoArea, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 44), TextXAlignment = Enum.TextXAlignment.Center }, "Accent", 40)
	if logo:IsA("TextLabel") then
		logo.TextSize = 42
		logo.Text = string.lower(logo.Text)
	end
	ctx:Text(logoArea, { Text = string.lower(opts.Subtitle or ctx:T("LoaderSubtitle")) .. ", " .. string.lower(opts.Username or ctx:Username()), Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center }, "TextDim", "FontBody", "SmallTextSize")
	ctx:Frame(root, { Position = UDim2.fromOffset(0, 110), Size = UDim2.new(1, 0, 0, 2) }, "Accent")

	-- product selector  <  name  >
	local selected = 1
	local nameLbl = ctx:Text(root, { Position = UDim2.fromOffset(40, 124), Size = UDim2.new(1, -80, 0, 24), TextXAlignment = Enum.TextXAlignment.Center }, "Text", "FontTitle", "TitleSize")
	local detail = ctx:Text(root, { Position = UDim2.fromOffset(40, 146), Size = UDim2.new(1, -80, 0, 16), TextXAlignment = Enum.TextXAlignment.Center }, "TextDim", "FontBody", "SmallTextSize")
	local function render()
		local p = opts.Products[selected]
		nameLbl.Text = string.lower(p.Name)
		detail.Text = string.lower((p.Status or "undetected") .. "  ·  expires " .. (p.Expires or "never"))
	end
	local function arrow(icon, x, dir)
		local b = ctx:New("TextButton", { Parent = root, Position = UDim2.fromOffset(x, 126), Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 0 }, { BackgroundColor3 = "Element" })
		ctx:Corner(b, "SmallCornerRadius")
		local i = ctx:Icon(b, icon, 12, "TextDim", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		ctx:Hover(b, function(st)
			ctx:IconColor(i, st == "Idle" and "TextDim" or "Accent", true)
		end)
		b.Activated:Connect(function()
			if handle.Running then
				return
			end
			selected = (selected - 1 + dir) % #opts.Products + 1
			render()
		end)
	end
	arrow("chevron-left", 16, -1)
	arrow("chevron-right", Wd - 40, 1)
	render()

	local bar = ctx:Frame(root, { Position = UDim2.new(0, 16, 1, -58), Size = UDim2.new(1, -32, 0, 4) }, "Element")
	local fill = ctx:Frame(bar, { Size = UDim2.fromScale(0, 1) }, "Accent")
	local status = ctx:Text(root, { Position = UDim2.new(0, 16, 1, -50), Size = UDim2.new(1, -32, 0, 16) }, "TextDim", "FontBody", "SmallTextSize")
	status.Text = string.lower(ctx:T("LoaderStatus"))
	local pct = ctx:Text(root, { Position = UDim2.new(0, 16, 1, -50), Size = UDim2.new(1, -32, 0, 16), TextXAlignment = Enum.TextXAlignment.Right }, "Accent", "FontMono", "SmallTextSize")
	local btn = ctx:New("TextButton", { Parent = root, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 172), Size = UDim2.fromOffset(120, 26), Text = "LOAD", TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0 }, { BackgroundColor3 = "Accent", TextColor3 = "TextOnAccent", Font = "FontTitle", TextSize = "TextSize" })
	ctx:Corner(btn, "SmallCornerRadius")
	ctx:Hover(btn, function(st)
		ctx.Theme:Bind(btn, "BackgroundColor3", "Accent", { Alpha = st == "Hover" and 0.15 or (st == "Press" and 0.3 or 0), Tween = true })
	end)
	btn.Activated:Connect(function()
		ctx:Sound("SoundClick")
		handle.Start(selected)
	end)
	local view = { Root = root }
	function view:OnStart()
		btn.Text = "LOADING"
	end
	function view:SetProgress(p, text)
		Tween.Play(fill, { Size = UDim2.fromScale(p, 1) }, 0.3)
		status.Text = string.lower(text or "")
		pct.Text = math.floor(p * 100 + 0.5) .. "%"
	end
	function view:SetStatus(text)
		status.Text = string.lower(text)
	end
	function view:Close(cb)
		Tween.Play(root, { Position = UDim2.new(0.5, 0, 0.5, 20) }, 0.2)
		task.delay(Tween.Duration(0.2), function()
			root:Destroy()
			if cb then
				cb()
			end
		end)
	end
	return view
end
end
__MODULES["Skins/Onetap/Theme"] = function(require)
--[[ Onetap skin – default theme values + presets (dark anthracite, orange accent, flat) ]]
local C = Color3.fromRGB

return {
	Defaults = {
		Accent = C(245, 166, 35),
		AccentDark = C(214, 128, 16),
		Background = C(30, 30, 33),
		BackgroundSecondary = C(23, 23, 26),
		Topbar = C(23, 23, 26),
		Panel = C(38, 38, 42),
		PanelHeader = C(33, 33, 37),
		Border = C(50, 50, 55),
		BorderDark = C(16, 16, 18),
		BorderLight = C(66, 66, 72),
		Element = C(52, 52, 57),
		ElementHover = C(62, 62, 68),
		ElementActive = C(72, 72, 79),
		Text = C(232, 232, 232),
		TextDim = C(150, 150, 155),
		TextDisabled = C(92, 92, 98),
		TextOnAccent = C(24, 24, 24),
		Divider = C(46, 46, 51),
		Knob = C(240, 240, 240),
		Glow = C(245, 166, 35),
		Info = C(245, 166, 35),
		Tooltip = C(23, 23, 26),
		AccentGradient = { Enabled = false, Colors = { "Accent", "AccentDark" }, Rotation = 90, Animated = false, Speed = 0.5 },
		FontTitle = "SourceSansBold",
		FontBody = "SourceSansSemibold",
		FontMono = "RobotoMono",
		TextSize = 15,
		TitleSize = 16,
		SmallTextSize = 13,
		CornerRadius = 2,
		SmallCornerRadius = 2,
		ShadowEnabled = true,
		ShadowTransparency = 0.5,
		WindowWidth = 720,
		WindowHeight = 530,
		SidebarWidth = 150,
		Spacing = 7,
		Padding = 12,
		ElementHeight = 22,
		GroupSpacing = 12,
		AnimationSpeed = 1.6,
		EasingStyle = "Quad",
		NotifyPosition = "BottomRight",
		NotifyWidth = 260,
		MobileButtonShape = "Rounded",
		QuickToggleShape = "Square",
	},
	Presets = {
		Default = {},
		Lime = { Accent = C(150, 210, 40), AccentDark = C(100, 160, 20), Glow = C(150, 210, 40), Info = C(150, 210, 40) },
		Ice = { Accent = C(90, 180, 255), AccentDark = C(50, 130, 220), Glow = C(90, 180, 255), Info = C(90, 180, 255) },
		Ruby = { Accent = C(230, 60, 70), AccentDark = C(170, 30, 40), Glow = C(230, 60, 70), Info = C(230, 60, 70) },
		Graphite = { Background = C(22, 22, 24), Panel = C(30, 30, 33), Element = C(44, 44, 48), Border = C(40, 40, 44) },
	},
}
end
__MODULES["Skins/Onetap/Window"] = function(require)
--[[
	Onetap window: top header with the logo and a text tab bar, orange accent line,
	flat group boxes with clean lines. Sub-tabs appear as a slim second bar.
]]
local Kit = require("Skins/Base/Window")
local Tween = require("Core/Tween")

local W = {}

function W.Window(ctx, win)
	local root = Kit.Root(ctx, win)
	ctx.Theme:Bind(root, "BackgroundColor3", "Background", { Window = true })
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "BorderDark", 1)
	ctx:Shadow(root, "CornerRadius", 4)
	local headerH = 46
	local header = ctx:Frame(root, { Name = "Header", Size = UDim2.new(1, 0, 0, headerH), ZIndex = 3 }, "Topbar", { Window = true })
	ctx:Corner(header, "CornerRadius")
	ctx:Frame(header, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 6), ZIndex = 3 }, "Topbar", { Window = true })
	local line = ctx:Frame(root, { Name = "AccentLine", Position = UDim2.fromOffset(0, headerH), Size = UDim2.new(1, 0, 0, 2), ZIndex = 4 }, "Accent")
	ctx:Grad(line, "AccentGradient")
	local logo = ctx:Logo(header, { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(0, 120, 1, 0), ZIndex = 4 }, "Accent", 22)
	if logo:IsA("TextLabel") then
		logo.TextSize = 22
		logo.Text = string.lower(logo.Text)
		ctx.Theme:Bind(logo, "Text", "LogoText", function(v)
			return string.lower(v)
		end)
	end
	local tabBar = ctx:New("ScrollingFrame", { Parent = header, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(1, -160, 1, 0), ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollBarThickness = 0, ZIndex = 4 })
	ctx:List(tabBar, { Dir = "H", Pad = 2, HA = "Right", VA = "Center" })
	local body = ctx:Frame(root, { Name = "Body", Position = UDim2.fromOffset(0, headerH + 2), Size = UDim2.new(1, 0, 1, -headerH - 2), ClipsDescendants = true })
	ctx:Texture(body)
	local subBar = ctx:Frame(body, { Name = "SubTabs", Size = UDim2.new(1, 0, 0, 30), Visible = false, ZIndex = 3 }, "BackgroundSecondary")
	ctx:List(subBar, { Dir = "H", Pad = 0 })
	ctx:Pad(subBar, 0, 10, 0, 10)
	local pages = ctx:Frame(body, { Name = "Pages", Size = UDim2.fromScale(1, 1), ZIndex = 2 })

	Kit.Draggable(ctx, win, root, header)
	Kit.Resizer(ctx, win, root, "TextDisabled", 560, 380)

	local view = Kit.Tabs(ctx, win, {
		TabHolder = tabBar,
		PageHolder = pages,
		PageAnim = "None",
		SubTabHolder = subBar,
		OnSubTabVisibility = function(show)
			pages.Position = UDim2.fromOffset(0, show and 30 or 0)
			pages.Size = UDim2.new(1, 0, 1, show and -30 or 0)
		end,
		TabButton = function(tab, holder)
			local b = ctx:New("TextButton", { Parent = holder, Name = "Tab_" .. tab.Name, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Text = string.upper(tab.Name), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, { Font = "FontTitle", TextSize = "TextSize", TextColor3 = "TextDim" })
			ctx:Pad(b, 0, 12, 0, 12)
			local under = ctx:Frame(b, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(0, 0, 0, 2), ZIndex = 6 }, "Accent")
			local sel = false
			local function paint(st)
				ctx.Theme:Bind(b, "TextColor3", sel and "Accent" or (st ~= "Idle" and "Text" or "TextDim"), { Tween = true })
			end
			ctx:Hover(b, paint)
			return {
				Root = b,
				SetSelected = function(s, instant)
					sel = s
					paint("Idle")
					Tween.Play(under, { Size = UDim2.new(s and 1 or 0, s and -16 or 0, 0, 2) }, instant and 0 or 0.18)
				end,
			}
		end,
		SubTabButton = function(sub, holder)
			local b = ctx:New("TextButton", { Parent = holder, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Text = string.lower(sub.Name), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 }, { Font = "FontBody", TextSize = "SmallTextSize", TextColor3 = "TextDim" })
			ctx:Pad(b, 0, 10, 0, 10)
			local sel = false
			local function paint(st)
				ctx.Theme:Bind(b, "TextColor3", sel and "Text" or (st ~= "Idle" and "Text" or "TextDim"), { Tween = true })
				ctx.Theme:Bind(b, "BackgroundColor3", "Panel", { Alpha = sel and 0 or 1, Tween = true })
			end
			ctx:Hover(b, paint)
			return {
				Root = b,
				SetSelected = function(s)
					sel = s
					paint("Idle")
				end,
			}
		end,
	})
	view.Root = root
	function view:SetOpen(open, instant)
		Kit.SetOpen(ctx, root, open, instant, "Scale")
	end
	function view:Destroy()
		root:Destroy()
	end
	return view
end

-- flat group: thin accent line on top, title bar, clean dividers
function W.Group(ctx, group, column)
	local root = ctx:Frame(column, { Name = "Group_" .. group.Name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, "Panel")
	ctx:Corner(root, "SmallCornerRadius")
	ctx:Stroke(root, "BorderDark", 1)
	ctx:List(root, {})
	local top = ctx:Frame(root, { Size = UDim2.new(1, 0, 0, 2), LayoutOrder = 0 }, "Accent")
	local _ = top
	local header = ctx:Frame(root, { Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1 }, "PanelHeader")
	ctx:Text(header, { Text = string.lower(group.Name), Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0) }, "Text", "FontTitle", "TextSize")
	ctx:Frame(header, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1) }, "Border")
	local container = ctx:Frame(root, { Name = "Container", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	ctx:Pad(container, 8, 10, 10, 10)
	ctx:List(container, { Pad = ctx:T("Spacing") })
	return { Root = root, Container = container }
end

return W
end
__MODULES["Skins/Onetap"] = function(require)
--[[
	Skin "Onetap" – dark anthracite, orange accent, text tab bar on top, flat group boxes,
	clean lines, square checkboxes, flat sliders.
]]
local Base = require("Skins/Base")
local W = require("Skins/Onetap/Window")

return Base.Extend({
	Name = "Onetap",
	Description = "Top text tabs, flat groups, orange accent",
	Theme = require("Skins/Onetap/Theme"),
	Style = {
		ToggleStyle = "Checkbox",
		CheckSize = 12,
		CheckCorner = "SmallCornerRadius",
		CheckStroke = "BorderDark",
		CheckMark = true,
		CheckGap = 8,
		ToggleLabelActive = true,
		LabelAbove = true,
		SliderTrack = 5,
		SliderKnob = 0,
		SliderValue = "Right",
		SliderValueColor = "Accent",
		SliderRows = 1.5,
		TrackCorner = "SmallCornerRadius",
		ControlCorner = "SmallCornerRadius",
		ControlStroke = "BorderDark",
		ControlStrokeHover = "Accent",
		KeyStyle = "Chip",
		SwatchW = 20,
		SwatchH = 10,
		SwatchCorner = "SmallCornerRadius",
		SwatchStroke = "BorderDark",
		ButtonStyle = "Filled",
		ButtonStroke = "BorderDark",
		ButtonStrokeHover = "Accent",
		ButtonHeight = 1.25,
		ButtonFont = "FontTitle",
		BoxHeight = 1.1,
		AboveOverlap = 2,
		ListItemH = 1.1,
		PanelStroke = "BorderDark",
		IconBg = "Panel",
		PopoutWidth = 240,
	},
	Window = W.Window,
	Group = W.Group,
	Loader = require("Skins/Onetap/Loader"),
})
end
__MODULES["Tabs/Appearance"] = function(require)
--[[
	Win:AddThemeTab(opts) – ready-made appearance tab (skin selection, presets, every theme key,
	export/import, reset per section). Styled automatically by the active skin.
	These controls are NoSave: the theme itself is stored in configs / theme presets.
]]
local Util = require("Core/Util")

local LABELS = {
	BackgroundSecondary = "Sidebar background", PanelHeader = "Panel header", TextOnAccent = "Text on accent",
	ElementHover = "Element hover", ElementActive = "Element active", TextDim = "Text (dim)", TextDisabled = "Text (disabled)",
	BorderDark = "Border (dark)", BorderLight = "Border (light)", AccentDark = "Accent (dark)",
	WindowTransparency = "Window transparency", BackgroundTexture = "Texture", TextureTransparency = "Texture transparency",
	TextureSpacing = "Texture spacing", BackgroundImage = "Image (asset id)", BackgroundImageTransparency = "Image transparency",
	FontTitle = "Title font", FontBody = "Body font", FontMono = "Mono font", TextSize = "Text size", TitleSize = "Title size",
	SmallTextSize = "Small text size", CornerRadius = "Corner radius", SmallCornerRadius = "Small corner radius",
	BorderThickness = "Border thickness", ShadowEnabled = "Shadow", ShadowTransparency = "Shadow transparency",
	WindowWidth = "Window width", WindowHeight = "Window height", UIScale = "UI scale", SidebarWidth = "Sidebar width",
	ElementHeight = "Element height", GroupSpacing = "Group spacing", AnimationsEnabled = "Animations",
	AnimationSpeed = "Animation speed", EasingStyle = "Easing style", EasingDirection = "Easing direction",
	LogoText = "Logo text", LogoImage = "Logo image (asset id)", UserInfo = "User info line", AvatarImage = "Avatar image",
	LoaderTitle = "Loader title", LoaderSubtitle = "Loader greeting", LoaderStatus = "Loader status",
	NotifyPosition = "Position", NotifyDuration = "Duration", NotifyWidth = "Width", SoundsEnabled = "Sounds",
	SoundVolume = "Volume", SoundClick = "Click sound", SoundToggle = "Toggle sound", SoundNotify = "Notify sound",
	MobileButtonSize = "Open button size", MobileButtonShape = "Open button shape", TouchTarget = "Touch target (px)",
	QuickToggleShape = "Quick toggle shape",
}

return function(win, opts)
	opts = opts or {}
	local lib = win.Library
	local Theme = lib.Theme
	local tab = win:AddTab({ Name = opts.Name or "Appearance", Icon = opts.Icon or "palette", Category = opts.Category or "Settings" })
	local general = tab:AddSubTab({ Name = "General" })
	local colors = tab:AddSubTab({ Name = "Colors" })
	local layout = tab:AddSubTab({ Name = "Layout" })
	local controls = {} -- key -> refresh function

	local function label(key)
		return LABELS[key] or key
	end

	-- builds the right control for a theme key
	local function control(group, key)
		local meta = Theme:MetaFor(key)
		local v = Theme:Get(key)
		local flag = "__theme_" .. key
		local el
		if meta.Type == "Color3" then
			el = group:AddColorPicker({
				Name = label(key),
				Flag = flag,
				NoSave = true,
				Default = { Color = v, Transparency = Theme:Get("Alpha." .. key) or 0 },
				Callback = function(val)
					Theme:Set(key, val.Color)
					Theme:Set("Alpha." .. key, val.Transparency)
				end,
			})
			controls[key] = function()
				el:Set({ Color = Theme:Get(key), Transparency = Theme:Get("Alpha." .. key) or 0, Rainbow = false }, { Silent = true })
			end
		elseif meta.Type == "boolean" then
			el = group:AddToggle({ Name = label(key), Flag = flag, NoSave = true, Default = v, Callback = function(val)
				Theme:Set(key, val)
			end })
		elseif meta.Type == "number" then
			el = group:AddSlider({ Name = label(key), Flag = flag, NoSave = true, Min = meta.Min or 0, Max = meta.Max or 100, Increment = meta.Step or 1, Default = v, Callback = function(val)
				Theme:Set(key, val)
			end })
		elseif meta.Type == "string" and meta.Options then
			el = group:AddDropdown({ Name = label(key), Flag = flag, NoSave = true, Values = meta.Options, Default = v, Searchable = #meta.Options > 10, Callback = function(val)
				Theme:Set(key, val)
			end })
		elseif meta.Type == "string" then
			el = group:AddTextbox({ Name = label(key), Flag = flag, NoSave = true, Default = v, Callback = function(val)
				Theme:Set(key, val)
			end })
		end
		if el and not controls[key] then
			controls[key] = function()
				el:Set(Theme:Get(key), { Silent = true })
			end
		end
		return el
	end

	local function gradientControls(group, key)
		local g = Theme:Get(key)
		group:AddDivider({ Text = label(key) })
		local function set(field, val)
			Theme:Set(key, { [field] = val })
		end
		local en = group:AddToggle({ Name = "Enabled", Flag = "__theme_" .. key .. "_en", NoSave = true, Default = g.Enabled ~= false, Callback = function(v)
			set("Enabled", v)
		end })
		local an = group:AddToggle({ Name = "Animated", Flag = "__theme_" .. key .. "_an", NoSave = true, Default = g.Animated == true, Callback = function(v)
			set("Animated", v)
		end })
		local rot = group:AddSlider({ Name = "Rotation", Flag = "__theme_" .. key .. "_rot", NoSave = true, Min = 0, Max = 360, Default = g.Rotation or 0, Suffix = "°", Callback = function(v)
			set("Rotation", v)
		end })
		local sp = group:AddSlider({ Name = "Speed", Flag = "__theme_" .. key .. "_sp", NoSave = true, Min = 0.05, Max = 2, Increment = 0.05, Default = g.Speed or 0.5, Callback = function(v)
			set("Speed", v)
		end })
		local pickers = {}
		for i, c in ipairs(g.Colors or {}) do
			if typeof(c) == "Color3" then
				pickers[i] = group:AddColorPicker({ Name = "Color " .. i, Flag = "__theme_" .. key .. "_c" .. i, NoSave = true, Default = c, Callback = function(val)
					local cur = Theme:Get(key)
					local list = table.clone(cur.Colors)
					list[i] = val.Color
					Theme:Set(key, { Colors = list })
				end })
			end
		end
		controls[key] = function()
			local cur = Theme:Get(key)
			en:Set(cur.Enabled ~= false, { Silent = true })
			an:Set(cur.Animated == true, { Silent = true })
			rot:Set(cur.Rotation or 0, { Silent = true })
			sp:Set(cur.Speed or 0.5, { Silent = true })
			for i, p in pairs(pickers) do
				if typeof(cur.Colors[i]) == "Color3" then
					p:Set(cur.Colors[i], { Silent = true })
				end
			end
		end
	end

	---------------------------------------------------------------- General
	local skinGroup = general:AddGroup({ Name = "Skin", Side = "Left" })
	local skinDrop = skinGroup:AddDropdown({ Name = "Skin", Flag = "__ui_skin", NoSave = true, Values = lib:GetSkins(), Default = lib.SkinName, Callback = function(v)
		lib:SetSkin(v)
	end })
	local presetDrop = skinGroup:AddDropdown({ Name = "Preset", Flag = "__ui_preset", NoSave = true, Values = Theme:Presets(), Default = "Default" })
	skinGroup:AddButton({ Name = "Apply preset", Callback = function()
		local ok, err = Theme:ApplyPreset(presetDrop.Value or "Default")
		if ok == false then
			lib:Notify({ Title = "Theme", Content = tostring(err), Type = "Error" })
		end
	end })
	local presetName = skinGroup:AddTextbox({ Name = "Preset name", Flag = "__ui_preset_name", NoSave = true, Placeholder = "my preset" })
	skinGroup:AddButton({ Name = "Save as preset", Callback = function()
		local ok = Theme:SavePreset(presetName.Value)
		if ok then
			presetDrop:Refresh(Theme:Presets())
			lib:Notify({ Title = "Theme", Content = "Preset saved", Type = "Success" })
		end
	end })
	skinGroup:AddButton({ Name = "Delete preset", Confirm = true, Callback = function()
		local name = presetDrop.Value
		if name and name:sub(1, 8) == "custom: " then
			Theme:DeletePreset(name)
			presetDrop:Refresh(Theme:Presets())
		else
			lib:Notify({ Title = "Theme", Content = "Built-in presets cannot be deleted", Type = "Warning" })
		end
	end })

	local fonts = general:AddGroup({ Name = "Fonts", Side = "Left" })
	for _, k in ipairs(Theme.Sections.Fonts) do
		control(fonts, k)
	end
	local anim = general:AddGroup({ Name = "Animation", Side = "Left" })
	for _, k in ipairs(Theme.Sections.Animation) do
		control(anim, k)
	end

	local share = general:AddGroup({ Name = "Share & reset", Side = "Right" })
	share:AddButton({ Name = "Export theme (clipboard)", Callback = function()
		local s = Theme:ExportString()
		local copied = s and Util.SetClipboard(s)
		lib:Notify({ Title = "Theme", Content = copied and "Theme string copied to clipboard" or "Clipboard unavailable – string printed to console", Type = copied and "Success" or "Warning" })
		if not copied then
			print(s)
		end
	end })
	local importBox = share:AddTextbox({ Name = "Theme string", Flag = "__ui_theme_import", NoSave = true, Placeholder = "paste here" })
	share:AddButton({ Name = "Import theme", Callback = function()
		local s = importBox.Value
		if s == "" then
			s = Util.GetClipboard() or ""
		end
		local ok, err = Theme:ImportString(s)
		lib:Notify({ Title = "Theme", Content = ok and "Theme imported" or ("Import failed: " .. tostring(err)), Type = ok and "Success" or "Error" })
	end })
	local resetDrop = share:AddDropdown({ Name = "Section", Flag = "__ui_reset_section", NoSave = true, Values = Theme.Base.SectionOrder, Default = "Colors" })
	share:AddButton({ Name = "Reset section", Callback = function()
		Theme:Reset(resetDrop.Value)
	end })
	share:AddButton({ Name = "Reset everything", Confirm = true, Callback = function()
		Theme:Reset(nil)
	end })

	local brand = general:AddGroup({ Name = "Branding", Side = "Right" })
	for _, k in ipairs(Theme.Sections.Branding) do
		control(brand, k)
	end
	local notif = general:AddGroup({ Name = "Notifications & sounds", Side = "Right" })
	for _, k in ipairs(Theme.Sections.Notifications) do
		control(notif, k)
	end
	notif:AddButton({ Name = "Test notification", Callback = function()
		lib:Notify({ Title = "Preview", Content = "This is how notifications look.", Type = "Info" })
	end })
	for _, k in ipairs(Theme.Sections.Sounds) do
		control(notif, k)
	end

	---------------------------------------------------------------- Colors
	local colorKeys = Theme.Sections.Colors
	local half = math.ceil(#colorKeys / 2)
	local cl = colors:AddGroup({ Name = "Colors", Side = "Left" })
	local cr = colors:AddGroup({ Name = "Colors ", Side = "Right" })
	for i, k in ipairs(colorKeys) do
		control(i <= half and cl or cr, k)
	end
	local grads = colors:AddGroup({ Name = "Gradients", Side = "Left" })
	for _, k in ipairs(Theme.Sections.Gradients) do
		gradientControls(grads, k)
	end
	local bg = colors:AddGroup({ Name = "Background", Side = "Right" })
	for _, k in ipairs(Theme.Sections.Background) do
		control(bg, k)
	end

	---------------------------------------------------------------- Layout
	local lay = layout:AddGroup({ Name = "Layout", Side = "Left" })
	for _, k in ipairs(Theme.Sections.Layout) do
		control(lay, k)
	end
	local mob = layout:AddGroup({ Name = "Mobile", Side = "Right" })
	mob:AddDropdown({ Name = "Device mode", Flag = "__ui_mobile_mode", NoSave = true, Values = { "Auto", "Mobile", "Desktop" }, Default = lib.Mobile.Mode, Callback = function(v)
		lib:SetMobileMode(v)
	end })
	for _, k in ipairs(Theme.Sections.Mobile) do
		control(mob, k)
	end
	mob:AddToggle({ Name = "Floating open button", Flag = "__ui_floating_button", Default = lib.Mobile:ShowButton(), Callback = function(v)
		lib.Mobile.ForceButton = v
		lib.Renderer:Rebuild(false)
	end })
	mob:AddButton({ Name = "Edit quick toggles", Callback = function()
		lib.Mobile:SetEditMode(not lib.Mobile.EditMode)
	end })
	local ov = layout:AddGroup({ Name = "Overlays", Side = "Right" })
	ov:AddToggle({ Name = "Watermark", Flag = "__ui_watermark", Default = lib.WatermarkState.Enabled, Callback = function(v)
		lib:SetWatermark(v)
	end })
	ov:AddToggle({ Name = "Keybind list", Flag = "__ui_keybind_list", Default = lib.KeybindListState.Enabled, Callback = function(v)
		lib:SetKeybindList(v)
	end })

	---------------------------------------------------------------- sync with theme changes (presets, import, reset, skin switch)
	lib.Maid:Give(Theme.Changed:Connect(function(key)
		if key == "*" then
			for _, f in pairs(controls) do
				pcall(f)
			end
			skinDrop:Set(lib.SkinName, { Silent = true })
			presetDrop:Refresh(Theme:Presets())
		else
			local base = key:gsub("^Alpha%.", "")
			if controls[base] then
				pcall(controls[base])
			end
		end
	end))
	lib.SkinChanged:Connect(function(name)
		skinDrop:Set(name, { Silent = true })
	end)
	return tab
end
end
__MODULES["Tabs/ConfigTab"] = function(require)
--[[
	Win:AddConfigTab(opts) – ready-made config manager styled by the active skin:
	list, save / save as, load, overwrite (confirm), delete (confirm), rename, duplicate, refresh,
	autoload, export / import string, autosave interval, save on close, menu key, overlays, unload.
]]
local Util = require("Core/Util")

return function(win, opts)
	opts = opts or {}
	local lib = win.Library
	local Config = lib.Config
	local tab = win:AddTab({ Name = opts.Name or "Config", Icon = opts.Icon or "folder", Category = opts.Category or "Settings" })

	local list = tab:AddGroup({ Name = "Configs", Side = "Left" })
	local drop = list:AddDropdown({ Name = "Configs", Flag = "__cfg_list", NoSave = true, Values = Config:List(), AllowNull = true, Searchable = true, Placeholder = "select a config" })
	local nameBox = list:AddTextbox({ Name = "Config name", Flag = "__cfg_name", NoSave = true, Placeholder = "new config name" })
	local autoLabel = list:AddLabel({ Text = "Autoload: none" })

	local function selected()
		return drop.Value
	end
	local function refresh()
		drop:Refresh(Config:List())
		autoLabel:SetText("Autoload: " .. (Config:GetAutoload() or "none"))
	end

	list:AddButton({ Name = "Save as new", Style = "Primary", Callback = function()
		local name = Config.CleanName(nameBox.Value)
		if not name then
			lib:Notify({ Title = "Config", Content = "Enter a config name first", Type = "Warning" })
			return
		end
		if Config:Exists(name) then
			lib:Confirm("Overwrite config?", ("'%s' already exists. Overwrite it?"):format(name), function()
				Config:Save(name)
				refresh()
				drop:Set(name)
			end)
			return
		end
		Config:Save(name)
		refresh()
		drop:Set(name)
	end })
	list:AddButton({ Name = "Load", Callback = function()
		if selected() then
			Config:Load(selected())
		end
	end })
	list:AddButton({ Name = "Overwrite", Callback = function()
		local name = selected()
		if not name then
			return
		end
		lib:Confirm("Overwrite config?", ("Replace '%s' with the current settings?"):format(name), function()
			Config:Save(name)
		end)
	end })
	list:AddButton({ Name = "Delete", Callback = function()
		local name = selected()
		if not name then
			return
		end
		lib:Confirm("Delete config?", ("'%s' will be deleted permanently."):format(name), function()
			Config:Delete(name)
			refresh()
		end)
	end })
	list:AddButton({ Name = "Rename to name above", Callback = function()
		local ok, err = Config:Rename(selected(), nameBox.Value)
		if not ok then
			lib:Notify({ Title = "Config", Content = "Rename failed: " .. tostring(err), Type = "Error" })
		end
		refresh()
	end })
	list:AddButton({ Name = "Duplicate", Callback = function()
		if selected() then
			Config:Duplicate(selected(), Config.CleanName(nameBox.Value))
			refresh()
		end
	end })
	list:AddButton({ Name = "Refresh list", Callback = refresh })
	list:AddButton({ Name = "Set as autoload", Callback = function()
		if selected() then
			Config:SetAutoload(selected())
			refresh()
			lib:Notify({ Title = "Config", Content = ("'%s' will load automatically"):format(selected()), Type = "Success" })
		end
	end })
	list:AddButton({ Name = "Clear autoload", Callback = function()
		Config:SetAutoload(nil)
		refresh()
	end })

	local share = tab:AddGroup({ Name = "Share", Side = "Right" })
	share:AddButton({ Name = "Export to clipboard", Callback = function()
		local s = Config:Export(selected())
		local copied = s ~= nil and (Util.HasFunc("setclipboard") or Util.HasFunc("toclipboard")) ~= nil
		lib:Notify({ Title = "Config", Content = s and (copied and "Config string copied" or "Config string printed to console") or "Export failed", Type = s and "Success" or "Error" })
		if s and not copied then
			print(s)
		end
	end })
	local importBox = share:AddTextbox({ Name = "Config string", Flag = "__cfg_import", NoSave = true, Placeholder = "paste a config string" })
	share:AddButton({ Name = "Import & apply", Callback = function()
		local s = importBox.Value
		if s == "" then
			s = Util.GetClipboard() or ""
		end
		Config:Import(s, { SaveAs = Config.CleanName(nameBox.Value) })
		refresh()
	end })

	local settings = tab:AddGroup({ Name = "Settings", Side = "Right" })
	local st = Config.Settings
	local interval = st.autosave and st.autosave.interval or 60
	local auto = settings:AddToggle({ Name = "Auto save", Flag = "__cfg_autosave", NoSave = true, Default = st.autosave and st.autosave.enabled or false, Tooltip = "Saves the current config periodically", Callback = function(v)
		Config:SetAutoSave(v, interval)
	end })
	settings:AddSlider({ Name = "Auto save interval", Flag = "__cfg_autosave_interval", NoSave = true, Min = 10, Max = 600, Increment = 10, Default = interval, Suffix = "s", Callback = function(v)
		interval = v
		if auto.Value then
			Config:SetAutoSave(true, v)
		end
	end })
	settings:AddToggle({ Name = "Save on close", Flag = "__cfg_save_close", NoSave = true, Default = st.saveOnClose == true, Callback = function(v)
		Config:SetSaveOnClose(v)
	end })
	settings:AddKeybind({ Name = "Menu key", Flag = "__menu_key", Default = win.ToggleKey, Mode = "Toggle", Callback = function(v)
		win:SetToggleKey(v.Key)
	end })
	settings:AddToggle({ Name = "Watermark", Flag = "__ui_watermark_cfg", Default = lib.WatermarkState.Enabled, Callback = function(v)
		lib:SetWatermark(v)
	end })
	settings:AddToggle({ Name = "Keybind list", Flag = "__ui_keybinds_cfg", Default = lib.KeybindListState.Enabled, Callback = function(v)
		lib:SetKeybindList(v)
	end })
	settings:AddLabel({ Text = Config:IsPersistent() and "Storage: file system" or "Storage: session only (no file API)" })
	settings:AddButton({ Name = "Unload " .. lib.Name, Callback = function()
		lib:Confirm("Unload?", "Destroy the interface and disconnect everything?", function()
			lib:Destroy()
		end)
	end })

	lib.Maid:Give(Config.Changed:Connect(function(action)
		if action ~= "load" then
			refresh()
		end
	end))
	refresh()
	if Config.Settings.autosave and Config.Settings.autosave.enabled then
		Config:SetAutoSave(true, interval)
	end
	return tab
end
end
__MODULES["init"] = function(require)
--[[
	Nova UI – entry point (the name comes from Meta.lua).
	Returns the library singleton. Re-executing the script destroys the previous instance.
]]
local Meta = require("Meta")
local Util = require("Core/Util")
local Maid = require("Core/Maid")
local Signal = require("Core/Signal")
local Theme = require("Core/Theme")
local Flags = require("Core/Flags")
local Registry = require("Core/Registry")
local Config = require("Core/Config")
local Input = require("Core/Input")
local Icons = require("Core/Icons")
local Tween = require("Core/Tween")
local FS = require("Core/FS")
local Renderer = require("Core/Renderer")
local Types = require("Components/Types")
local Window = require("Components/Window")
local Mobile = require("Mobile")
local ESP = require("ESPPreview")
local Base = require("Skins/Base")

-- built-in skins
Registry:Register(require("Skins/Classic"))
Registry:Register(require("Skins/Modern"))
Registry:Register(require("Skins/Onetap"))
Registry:Register(require("Skins/Fatal"))
Registry:Register(require("Skins/Dashboard"))

local RunService = Util.Services.RunService
local UIS = Util.Services.UserInputService

local Library = {}
Library.__index = Library

local function new()
	local env = Util.GetEnv()
	local prev = env[Meta.GlobalKey]
	if type(prev) == "table" and type(prev.Destroy) == "function" then
		pcall(prev.Destroy, prev)
	end

	local self = setmetatable({}, Library)
	env[Meta.GlobalKey] = self
	self.Meta = Meta
	self.Name = Meta.Name
	self.Version = Meta.Version
	self.Maid = Maid.new()
	self.Skins = Registry
	self.SkinBase = Base
	self.Icons = Icons
	self.Tween = Tween
	self.FS = FS
	self.Util = Util
	self.Theme = Theme.new(function(name)
		local s = Registry:Get(name)
		return s and s.Theme or {}
	end)
	self.Flags = Flags.new()
	self.Input = Input.new()
	self.Maid:Give(self.Input)
	self.Keybinds = {}
	self.Rainbows = {}
	self.SkinChanged = Signal.new()
	self.HistoryChanged = Signal.new()
	self.History = {}
	self.Unread = 0
	self.Unloaded = Signal.new()
	self.WatermarkState = { Enabled = false, Fields = { Title = true, User = true, FPS = true, Ping = true, Time = true } }
	self.KeybindListState = { Enabled = false }
	self.CurrentScale = 1

	-- GUI ---------------------------------------------------------------
	local gui = Instance.new("ScreenGui")
	gui.Name = Meta.Folder .. "_" .. tostring(math.random(100000, 999999))
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	self.ScreenGui = gui
	self.GuiParent = Util.ParentGui(gui)
	self.Maid:Give(gui)

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui
	self.Root = root
	self.UIScale = Instance.new("UIScale")
	self.UIScale.Parent = root

	self.Layers = {}
	-- quick toggles (Mobile) sit under the window, the floating button lives in Notify (always on top)
	for i, name in ipairs({ "Mobile", "Window", "Overlay", "Notify", "Dialog", "Tooltip", "Loader" }) do
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromScale(1, 1)
		f.ZIndex = i * 10
		f.Parent = root
		self.Layers[name] = f
	end

	self.Config = Config.new(self)
	self.Mobile = Mobile.new(self)
	self.Renderer = Renderer.new(self)

	-- skin + theme ---------------------------------------------------------
	self.SkinName = Meta.DefaultSkin
	self.Skin = Registry:Get(self.SkinName)
	self.Theme:LoadSkin(self.SkinName)
	self:ApplyScale()
	self.Maid:Give(self.Theme.Changed:Connect(function(key)
		self:_onThemeChanged(key)
	end))
	local cam = Util.Services.Workspace and Util.Services.Workspace.CurrentCamera
	if cam then
		self.Maid:Give(cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:ApplyScale()
		end))
	end

	self:_setupInput()
	self.Renderer:Build()
	return self
end

---------------------------------------------------------------- scale / screen
function Library:ApplyScale()
	local s = self.Theme:Get("UIScale") or 1
	if self.Mobile and self.Mobile:IsMobile() then
		s = s * self.Mobile:AutoScale()
	end
	s = math.clamp(s, 0.35, 2)
	self.CurrentScale = s
	self.UIScale.Scale = s
	self.Root.Size = UDim2.fromScale(1 / s, 1 / s)
end

-- screen size in UI-root space (after UIScale)
function Library:ScreenSize()
	local vp = Util.Viewport()
	local s = self.CurrentScale or 1
	return Vector2.new(vp.X / s, vp.Y / s)
end

function Library:_onThemeChanged(key)
	if key == "UIScale" then
		self:ApplyScale()
		return
	end
	if key == "WindowWidth" or key == "WindowHeight" then
		local win = self.Window
		if win and win.View and win.View.Root then
			win.State.Sizes[self.SkinName] = nil
			local size = win:GetSize()
			Tween.Play(win.View.Root, { Size = UDim2.fromOffset(size.X, size.Y) }, 0.2)
		end
		return
	end
	if key == "NotifyPosition" then
		return
	end
	local meta = self.Theme:MetaFor(key)
	if meta.Rebuild then
		-- debounce: rebuild once the value stopped changing
		if self._rebuildThread then
			pcall(task.cancel, self._rebuildThread)
		end
		self._rebuildThread = task.delay(0.6, function()
			self._rebuildThread = nil
			self.Renderer:Rebuild(false)
		end)
	end
end

---------------------------------------------------------------- skins
function Library:RegisterSkin(skin)
	return Registry:Register(skin)
end

function Library:GetSkins()
	return Registry:List()
end

-- UI:SetSkin("Modern") – rebuilds the UI (fade), keeping flags, tab and window position
function Library:SetSkin(name, opts)
	opts = opts or {}
	local skin = Registry:Get(name)
	if not skin then
		self:Notify({ Title = "Skin", Content = "Unknown skin '" .. tostring(name) .. "'", Type = "Error" })
		return false
	end
	if self.SkinName == name and not opts.Force then
		return true
	end
	local function swap()
		self.SkinName = name
		self.Skin = skin
		self.Theme:LoadSkin(name)
		self:ApplyScale()
	end
	if opts.NoRebuild then
		swap()
	else
		self.Renderer:Rebuild(not opts.Instant, swap)
	end
	self.SkinChanged:Fire(name)
	return true
end

---------------------------------------------------------------- window
--[[
	UI:CreateWindow{
		Title, Skin, Size = Vector2|UDim2, ToggleKey = Enum.KeyCode.RightShift,
		Logo, LogoText, Username, UserInfo, Subtitle, Avatar,   -- branding (theme keys)
		FloatingButton = true|false|nil(auto: mobile only), Watermark = bool, KeybindList = bool
	}
]]
function Library:CreateWindow(opts)
	opts = opts or {}
	if self.Window then
		warn("[" .. self.Name .. "] only one window is supported – returning the existing one")
		return self.Window
	end
	local branding = {
		Title = opts.Title,
		Subtitle = opts.Subtitle,
		LogoText = opts.LogoText,
		LogoImage = opts.Logo,
		Username = opts.Username,
		UserInfo = opts.UserInfo,
		AvatarImage = opts.Avatar,
	}
	for k, v in pairs(branding) do
		self.Theme.Defaults[k] = v
		self.Theme.Base.Defaults[k] = v
		self.Theme:Set(k, v, { Instant = true, NoOverride = true })
	end
	if opts.Skin and opts.Skin ~= self.SkinName then
		self:SetSkin(opts.Skin, { NoRebuild = true })
	end
	local win = Window.new(self, opts)
	self.Window = win
	if opts.FloatingButton ~= nil then
		self.Mobile.ForceButton = opts.FloatingButton
	end
	self.Renderer:Teardown()
	self.Renderer:Build()
	if opts.Watermark then
		self:SetWatermark(true)
	end
	if opts.KeybindList then
		self:SetKeybindList(true)
	end
	-- the menu key is a regular keybind flag so it is saved in configs
	return win
end

---------------------------------------------------------------- notifications / dialogs
-- UI:Notify{ Title, Content, Duration, Type = "Info"|"Success"|"Warning"|"Error", Icon }
function Library:Notify(opts, duration)
	if type(opts) == "string" then
		opts = { Content = opts, Duration = duration }
	end
	opts = opts or {}
	opts.Title = opts.Title or self.Theme:Get("Title")
	return self.Renderer:Notify(opts)
end

-- UI:Dialog{ Title, Content, Buttons = { {Text, Primary, Callback}, ... } } -> handle (:Close())
function Library:Dialog(opts)
	opts = opts or {}
	local ctx = self.Renderer.Ctx
	local handle = {}
	local view
	function handle.Close()
		if view then
			pcall(view.Close, view)
			view = nil
		end
	end
	opts.Buttons = opts.Buttons or { { Text = "OK", Primary = true } }
	for _, b in ipairs(opts.Buttons) do
		local cb = b.Callback
		b._click = function()
			handle.Close()
			if cb then
				task.spawn(cb)
			end
		end
	end
	view = ctx.Skin.Dialog(ctx, opts)
	return handle
end

-- confirm helper used by the config tab
function Library:Confirm(title, content, onYes)
	return self:Dialog({
		Title = title,
		Content = content,
		Buttons = {
			{ Text = "Confirm", Primary = true, Callback = onYes },
			{ Text = "Cancel" },
		},
	})
end

---------------------------------------------------------------- loader
--[[
	UI:Loader{
		Skin = "Classic",                    -- defaults to the current skin
		Title, Subtitle, Username,           -- default: branding keys
		Products = { { Name, Status = "Undetected", Expires = "Never", Game = "Universal", Icon } },
		Steps = { "Checking hwid", "Downloading", ... } | { {Text, Duration}, ... },
		AutoLoad = false,                    -- start immediately with product 1
		OnLoad = function(product) end,      -- called after the bar finished
		Yield = true,                        -- block until finished (default)
	} -> handle { Finished: Signal, Start(index), Close() }
]]
function Library:Loader(opts)
	opts = opts or {}
	local skinName = opts.Skin or self.SkinName
	if opts.Skin and opts.Skin ~= self.SkinName and Registry:Get(opts.Skin) then
		self:SetSkin(opts.Skin, { Instant = true })
	end
	local skin = Registry:Get(skinName) or self.Skin
	local ctx = self.Renderer.Ctx
	opts.Products = opts.Products or opts.Scripts or { { Name = self.Theme:Get("Title"), Status = "Undetected", Expires = "Never", Game = "Universal" } }
	opts.Steps = opts.Steps or { "Authenticating", "Checking version", "Downloading modules", "Building interface", "Done" }
	local handle = { Finished = Signal.new(), Running = false, Done = false }
	local view
	function handle.SetStatus(text)
		if view and view.SetStatus then
			view:SetStatus(text)
		end
	end
	function handle.Close()
		if view then
			view:Close()
		end
	end
	function handle.Start(index)
		if handle.Running or handle.Done then
			return
		end
		handle.Running = true
		local product = opts.Products[index or 1] or opts.Products[1]
		handle.Product = product
		if view.OnStart then
			view:OnStart(product, index or 1)
		end
		task.spawn(function()
			local steps = opts.Steps
			for i, step in ipairs(steps) do
				local text = type(step) == "table" and step.Text or tostring(step)
				local dur = type(step) == "table" and step.Duration or (opts.StepDuration or 0.45)
				if type(step) == "table" and type(step.Run) == "function" then
					pcall(step.Run)
				end
				view:SetProgress((i - 1) / #steps, text, i, #steps)
				task.wait(dur)
			end
			view:SetProgress(1, steps[#steps] and (type(steps[#steps]) == "table" and steps[#steps].Text or tostring(steps[#steps])) or "Done", #steps, #steps)
			task.wait(0.35)
			handle.Done = true
			view:Close(function()
				if opts.OnLoad then
					pcall(opts.OnLoad, product)
				end
				handle.Finished:Fire(product)
			end)
		end)
	end
	view = skin.Loader(ctx, opts, handle)
	if opts.AutoLoad then
		handle.Start(1)
	end
	if opts.Yield ~= false then
		handle.Finished:Wait()
	end
	return handle
end

---------------------------------------------------------------- watermark & keybind list
function Library:SetWatermark(enabled, fields)
	self.WatermarkState.Enabled = enabled ~= false
	if type(fields) == "table" then
		self.WatermarkState.Fields = fields
	end
	self.Renderer:RefreshWatermark()
	self:_watermarkLoop()
end

function Library:_watermarkLoop()
	local st = self.WatermarkState
	if self._wmThread then
		pcall(task.cancel, self._wmThread)
		self._wmThread = nil
	end
	if self._fpsConn then
		self._fpsConn:Disconnect()
		self._fpsConn = nil
	end
	if not st.Enabled then
		return
	end
	local frames = 0
	if RunService then
		self._fpsConn = RunService.Heartbeat:Connect(function()
			frames += 1
		end)
	end
	self._wmThread = task.spawn(function()
		while st.Enabled do
			task.wait(1)
			self.FPS = frames
			frames = 0
			self:_updateWatermarkText()
		end
	end)
end

function Library:GetPing()
	local ok, p = pcall(function()
		return math.floor(Util.Services.Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
	end)
	if ok and p then
		return p
	end
	local lp = Util.LocalPlayer()
	local ok2, p2 = pcall(function()
		return math.floor(lp:GetNetworkPing() * 1000)
	end)
	return ok2 and p2 or 0
end

function Library:WatermarkText()
	local f = self.WatermarkState.Fields
	local parts = {}
	local ctx = self.Renderer.Ctx
	if f.Title then
		table.insert(parts, self.Theme:Get("Title"))
	end
	if f.User and ctx then
		table.insert(parts, ctx:Username())
	end
	if f.FPS then
		table.insert(parts, tostring(self.FPS or 60) .. " fps")
	end
	if f.Ping then
		table.insert(parts, tostring(self:GetPing()) .. " ms")
	end
	if f.Time then
		table.insert(parts, os.date("%H:%M:%S"))
	end
	return table.concat(parts, "  |  ")
end

function Library:_updateWatermarkText()
	local v = self.Renderer.WatermarkView
	if v then
		v:SetText(self:WatermarkText())
	end
end

function Library:SetKeybindList(enabled)
	self.KeybindListState.Enabled = enabled ~= false
	self.Renderer:RefreshKeybindList()
end

function Library:ActiveKeybinds()
	local out = {}
	for el in pairs(self.Keybinds) do
		local v = el.Value
		if v and v.Key then
			local owner = el.Parent
			local active
			if owner and owner.Kind == "Toggle" then
				active = owner.Value == true
			else
				active = el.State == true or v.Mode == "Always"
			end
			if active then
				table.insert(out, { Name = el:ShortName(), Key = el:KeyText(), Mode = v.Mode, Element = el })
			end
		end
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

function Library:_updateKeybindList()
	local v = self.Renderer.KeybindListView
	if v then
		v:SetItems(self:ActiveKeybinds())
	end
end

---------------------------------------------------------------- keybinds
function Library:_registerKeybind(el)
	self.Keybinds[el] = true
	local owner = el.Parent
	if owner and owner.Kind == "Toggle" and not owner._kbHooked then
		owner._kbHooked = true
		owner.Changed:Connect(function()
			self:_updateKeybindList()
		end)
	end
	el.Changed:Connect(function(v)
		if v.Mode == "Always" then
			el.State = true
			if owner and owner.Kind == "Toggle" then
				owner:Set(true)
			end
		end
		self:_updateKeybindList()
	end)
end

function Library:_unregisterKeybind(el)
	self.Keybinds[el] = nil
end

function Library:_keybindStateChanged()
	self:_updateKeybindList()
end

-- start capturing the next key for a keybind element; cb(keyName|nil) when done
function Library:CaptureKey(cb)
	self._capture = cb
end

function Library:_setupInput()
	local input = self.Input
	self.Maid:Give(input.Began:Connect(function(io, gp)
		if self._capture then
			local t = io.UserInputType
			local key
			if t == Enum.UserInputType.Keyboard then
				if io.KeyCode == Enum.KeyCode.Escape or io.KeyCode == Enum.KeyCode.Backspace then
					key = false
				else
					key = io.KeyCode.Name
				end
			elseif t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3 then
				key = Types.KeyName(t)
			end
			if key ~= nil then
				local cb = self._capture
				self._capture = nil
				task.defer(cb, key ~= false and key or nil)
			end
			return
		end
		if UIS and UIS:GetFocusedTextBox() then
			return
		end
		local win = self.Window
		if win and Types.MatchKey(io, win.ToggleKey) then
			win:Toggle()
			return
		end
		for el in pairs(self.Keybinds) do
			local v = el.Value
			if v and v.Key and Types.MatchKey(io, v.Key) and not el:IsDisabled() then
				local owner = el.Parent
				local isToggle = owner and owner.Kind == "Toggle"
				if v.Mode == "Toggle" then
					if isToggle then
						owner:Set(not owner.Value)
						el:SetState(owner.Value)
					else
						el:SetState(not el.State)
					end
				elseif v.Mode == "Hold" then
					if isToggle then
						owner:Set(true)
					end
					el:SetState(true)
				elseif v.Mode == "Always" then
					el:SetState(true)
				end
			end
		end
	end))
	self.Maid:Give(input.Ended:Connect(function(io)
		for el in pairs(self.Keybinds) do
			local v = el.Value
			if v and v.Key and v.Mode == "Hold" and Types.MatchKey(io, v.Key) then
				local owner = el.Parent
				if owner and owner.Kind == "Toggle" then
					owner:Set(false)
				end
				el:SetState(false)
			end
		end
	end))
end

---------------------------------------------------------------- rainbow color pickers (one loop for all)
function Library:_rainbow(el, on)
	if on then
		self.Rainbows[el] = true
	else
		self.Rainbows[el] = nil
	end
	if next(self.Rainbows) and not self._rainbowConn and RunService then
		local acc = 0
		self._rainbowConn = RunService.Heartbeat:Connect(function(dt)
			acc += dt
			if acc < 1 / 20 then
				return
			end
			acc = 0
			local hue = (os.clock() * 0.15) % 1
			for e in pairs(self.Rainbows) do
				local v = e.Value
				if v and v.Rainbow then
					e:Set({ Color = Color3.fromHSV(hue, 0.85, 1), Transparency = v.Transparency, Rainbow = true }, { Instant = true })
				else
					self.Rainbows[e] = nil
				end
			end
			if not next(self.Rainbows) and self._rainbowConn then
				self._rainbowConn:Disconnect()
				self._rainbowConn = nil
			end
		end)
	end
end

---------------------------------------------------------------- ESP
-- current ESP preview settings, read from the bound flags
function Library:GetESPSettings(flagMap)
	return ESP.GetSettings(self, flagMap)
end

---------------------------------------------------------------- mobile
-- "Auto" | "Mobile" | "Desktop"
function Library:SetMobileMode(mode)
	self.Mobile:SetMode(mode)
end

function Library:IsMobile()
	return self.Mobile:IsMobile()
end

---------------------------------------------------------------- cleanup
function Library:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	pcall(function()
		self.Config:OnClose()
	end)
	self.Unloaded:Fire()
	pcall(function()
		self.Renderer:Teardown()
	end)
	if self._wmThread then
		pcall(task.cancel, self._wmThread)
	end
	if self._fpsConn then
		self._fpsConn:Disconnect()
	end
	if self._rainbowConn then
		self._rainbowConn:Disconnect()
	end
	self.Config:Destroy()
	self.Theme:Destroy()
	self.Maid:Clean()
	local env = Util.GetEnv()
	if env[Meta.GlobalKey] == self then
		env[Meta.GlobalKey] = nil
	end
end
Library.Unload = Library.Destroy

return new()
end
return __require("init")
