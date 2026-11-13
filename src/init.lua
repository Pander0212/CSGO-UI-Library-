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
