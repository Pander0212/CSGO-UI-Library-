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
