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
