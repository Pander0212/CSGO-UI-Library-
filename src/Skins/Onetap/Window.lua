--[[
	Onetap window: top header with the logo and a text tab bar, orange accent line,
	flat group boxes with clean lines. Sub-tabs appear as a slim second bar.
]]
local Kit = require("Skins/Base/Window")
local Tween = require("Core/Tween")

local W = {}

function W.Window(ctx, win)
	local root = Kit.Root(ctx, win)
	ctx.Theme:Bind(root, "BackgroundColor3", "Background", { Window = true })
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "BorderDark", 1)
	ctx:Shadow(root, "CornerRadius", 4)
	local headerH = 46
	local header = ctx:Frame(root, { Name = "Header", Size = UDim2.new(1, 0, 0, headerH), ZIndex = 3 }, "Topbar", { Window = true })
	ctx:Corner(header, "CornerRadius")
	ctx:Frame(header, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 6), ZIndex = 3 }, "Topbar", { Window = true })
	local line = ctx:Frame(root, { Name = "AccentLine", Position = UDim2.fromOffset(0, headerH), Size = UDim2.new(1, 0, 0, 2), ZIndex = 4 }, "Accent")
	ctx:Grad(line, "AccentGradient")
	local logo = ctx:Logo(header, { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(0, 120, 1, 0), ZIndex = 4 }, "Accent", 22)
	if logo:IsA("TextLabel") then
		logo.TextSize = 22
		logo.Text = string.lower(logo.Text)
		ctx.Theme:Bind(logo, "Text", "LogoText", function(v)
			return string.lower(v)
		end)
	end
	local tabBar = ctx:New("ScrollingFrame", { Parent = header, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(1, -160, 1, 0), ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollBarThickness = 0, ZIndex = 4 })
	ctx:List(tabBar, { Dir = "H", Pad = 2, HA = "Right", VA = "Center" })
	local body = ctx:Frame(root, { Name = "Body", Position = UDim2.fromOffset(0, headerH + 2), Size = UDim2.new(1, 0, 1, -headerH - 2), ClipsDescendants = true })
	ctx:Texture(body)
	local subBar = ctx:Frame(body, { Name = "SubTabs", Size = UDim2.new(1, 0, 0, 30), Visible = false, ZIndex = 3 }, "BackgroundSecondary")
	ctx:List(subBar, { Dir = "H", Pad = 0 })
	ctx:Pad(subBar, 0, 10, 0, 10)
	local pages = ctx:Frame(body, { Name = "Pages", Size = UDim2.fromScale(1, 1), ZIndex = 2 })

	Kit.Draggable(ctx, win, root, header)
	Kit.Resizer(ctx, win, root, "TextDisabled", 560, 380)

	local view = Kit.Tabs(ctx, win, {
		TabHolder = tabBar,
		PageHolder = pages,
		PageAnim = "None",
		SubTabHolder = subBar,
		OnSubTabVisibility = function(show)
			pages.Position = UDim2.fromOffset(0, show and 30 or 0)
			pages.Size = UDim2.new(1, 0, 1, show and -30 or 0)
		end,
		TabButton = function(tab, holder)
			local b = ctx:New("TextButton", { Parent = holder, Name = "Tab_" .. tab.Name, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Text = string.upper(tab.Name), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, { Font = "FontTitle", TextSize = "TextSize", TextColor3 = "TextDim" })
			ctx:Pad(b, 0, 12, 0, 12)
			local under = ctx:Frame(b, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(0, 0, 0, 2), ZIndex = 6 }, "Accent")
			local sel = false
			local function paint(st)
				ctx.Theme:Bind(b, "TextColor3", sel and "Accent" or (st ~= "Idle" and "Text" or "TextDim"), { Tween = true })
			end
			ctx:Hover(b, paint)
			return {
				Root = b,
				SetSelected = function(s, instant)
					sel = s
					paint("Idle")
					Tween.Play(under, { Size = UDim2.new(s and 1 or 0, s and -16 or 0, 0, 2) }, instant and 0 or 0.18)
				end,
			}
		end,
		SubTabButton = function(sub, holder)
			local b = ctx:New("TextButton", { Parent = holder, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, Text = string.lower(sub.Name), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 }, { Font = "FontBody", TextSize = "SmallTextSize", TextColor3 = "TextDim" })
			ctx:Pad(b, 0, 10, 0, 10)
			local sel = false
			local function paint(st)
				ctx.Theme:Bind(b, "TextColor3", sel and "Text" or (st ~= "Idle" and "Text" or "TextDim"), { Tween = true })
				ctx.Theme:Bind(b, "BackgroundColor3", "Panel", { Alpha = sel and 0 or 1, Tween = true })
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

-- flat group: thin accent line on top, title bar, clean dividers
function W.Group(ctx, group, column)
	local root = ctx:Frame(column, { Name = "Group_" .. group.Name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, "Panel")
	ctx:Corner(root, "SmallCornerRadius")
	ctx:Stroke(root, "BorderDark", 1)
	ctx:List(root, {})
	local top = ctx:Frame(root, { Size = UDim2.new(1, 0, 0, 2), LayoutOrder = 0 }, "Accent")
	local _ = top
	local header = ctx:Frame(root, { Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1 }, "PanelHeader")
	ctx:Text(header, { Text = string.lower(group.Name), Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0) }, "Text", "FontTitle", "TextSize")
	ctx:Frame(header, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1) }, "Border")
	local container = ctx:Frame(root, { Name = "Container", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
	ctx:Pad(container, 8, 10, 10, 10)
	ctx:List(container, { Pad = ctx:T("Spacing") })
	return { Root = root, Container = container }
end

return W
