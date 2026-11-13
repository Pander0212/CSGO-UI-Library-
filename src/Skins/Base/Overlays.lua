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
