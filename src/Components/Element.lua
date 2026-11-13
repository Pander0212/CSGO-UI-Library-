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
