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
