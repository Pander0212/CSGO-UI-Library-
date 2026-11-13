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
