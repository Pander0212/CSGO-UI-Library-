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
