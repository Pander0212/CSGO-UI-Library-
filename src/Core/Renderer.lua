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
