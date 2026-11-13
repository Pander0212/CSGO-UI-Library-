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
