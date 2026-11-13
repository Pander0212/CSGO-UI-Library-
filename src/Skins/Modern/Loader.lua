--[[
	Modern loader: rounded screen with avatar + greeting, product cards (name, status badge,
	expiry date, "Load" button) and an animated loading spinner with a progress bar.
]]
local Tween = require("Core/Tween")

local function greeting()
	local h = tonumber(os.date("%H")) or 12
	if h < 5 then
		return "Good night"
	elseif h < 12 then
		return "Good morning"
	elseif h < 18 then
		return "Good afternoon"
	end
	return "Good evening"
end

local function statusKey(s)
	s = string.lower(s or "")
	if s:find("undetect") or s:find("online") or s:find("working") then
		return "Success"
	elseif s:find("updat") or s:find("risk") then
		return "Warning"
	end
	return "Error"
end

-- rotating arc spinner (two half rings + gradient), animated with a light loop
local function spinner(ctx, parent, size)
	local holder = ctx:Frame(parent, { Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
	local ring = ctx:Frame(holder, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	ctx:Corner(ring, "full")
	local st = ctx:Stroke(ring, "Accent", 3)
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.9), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = st
	local track = ctx:Frame(holder, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = holder.ZIndex - 1 })
	ctx:Corner(track, "full")
	ctx:Stroke(track, "Element", 3)
	local running = true
	task.spawn(function()
		while running and holder.Parent do
			g.Rotation = (g.Rotation + 12) % 360
			task.wait(1 / 30)
		end
	end)
	holder.Destroying:Connect(function()
		running = false
	end)
	return holder
end

return function(ctx, opts, handle)
	local Wd, Ht = 600, 380
	local root = ctx:Frame(ctx.Layers.Loader, { Name = "Loader", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(Wd, Ht) }, "Background")
	ctx:Corner(root, 14)
	ctx:Stroke(root, "Border", 1)
	ctx:Shadow(root, nil, 5)
	local sc = Instance.new("UIScale")
	sc.Scale = 0.94
	sc.Parent = root
	Tween.Play(sc, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)

	-- left: profile
	local left = ctx:Frame(root, { Size = UDim2.new(0, 210, 1, 0) }, "BackgroundSecondary")
	ctx:Corner(left, 14)
	ctx:Frame(left, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 16, 1, 0) }, "BackgroundSecondary")
	ctx:Frame(left, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0) }, "Border")
	ctx:Logo(left, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center }, "Text", 24).TextSize = 24
	ctx:AvatarCircle(left, 64, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Stroke = "Accent" })
	ctx:Text(left, { Text = greeting() .. ",", Position = UDim2.fromOffset(0, 168), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center }, "TextDim", "FontBody", "SmallTextSize")
	ctx:Text(left, { Text = opts.Username or ctx:Username(), Position = UDim2.fromOffset(0, 186), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center }, "Text", "FontTitle", "TitleSize")
	local info = ctx:Text(left, { Position = UDim2.fromOffset(0, 210), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center }, "Accent", "FontBody", "SmallTextSize")
	ctx.Theme:Bind(info, "Text", "UserInfo")
	ctx:Text(left, { Text = "v" .. ctx.Library.Version, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -14), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center }, "TextDisabled", "FontMono", "SmallTextSize")

	-- right: products
	local right = ctx:Frame(root, { Position = UDim2.fromOffset(210, 0), Size = UDim2.new(1, -210, 1, 0) })
	ctx:Text(right, { Text = opts.Title or "Products", Position = UDim2.fromOffset(22, 18), Size = UDim2.new(1, -44, 0, 22) }, "Text", "FontTitle", "TitleSize").TextSize = 18
	ctx:Text(right, { Text = (opts.Subtitle or "Select a product to load"), Position = UDim2.fromOffset(22, 42), Size = UDim2.new(1, -44, 0, 16) }, "TextDim", "FontBody", "SmallTextSize")
	local list = ctx:New("ScrollingFrame", { Parent = right, Position = UDim2.fromOffset(16, 70), Size = UDim2.new(1, -32, 1, -86) }, { ScrollBarImageColor3 = "Accent" })
	ctx:List(list, { Pad = 8 })
	ctx:Pad(list, 2, 6, 2, 6)
	for i, p in ipairs(opts.Products) do
		local card = ctx:Frame(list, { Size = UDim2.new(1, 0, 0, 70), LayoutOrder = i }, "Panel")
		ctx:Corner(card, "CornerRadius")
		local stroke = ctx:Stroke(card, "Border", 1)
		local iconBox = ctx:Frame(card, { Position = UDim2.new(0, 12, 0.5, -20), Size = UDim2.fromOffset(40, 40) }, "Accent", { Alpha = 0.85 })
		ctx:Corner(iconBox, "SmallCornerRadius")
		ctx:Icon(iconBox, p.Icon or "zap", 18, "Accent", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		ctx:Text(card, { Text = p.Name, Position = UDim2.fromOffset(64, 13), Size = UDim2.new(1, -170, 0, 18) }, "Text", "FontTitle", "TextSize")
		local key = statusKey(p.Status)
		local meta = ctx:Frame(card, { Position = UDim2.fromOffset(64, 36), Size = UDim2.new(1, -170, 0, 18), ClipsDescendants = true })
		ctx:List(meta, { Dir = "H", Pad = 8, VA = "Center" })
		local badge = ctx:Frame(meta, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1 }, key, { Alpha = 0.85 })
		ctx:Corner(badge, "full")
		ctx:Pad(badge, 0, 8, 0, 8)
		ctx:Text(badge, { Text = p.Status or "Undetected", Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X }, key, "FontTitle", 11)
		ctx:Text(meta, { Text = "until " .. (p.Expires or "never"), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2 }, "TextDim", "FontBody", "SmallTextSize")
		local btn = ctx:New("TextButton", { Parent = card, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(84, 32), Text = "Load", TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0 }, { BackgroundColor3 = "Accent", TextColor3 = "TextOnAccent", Font = "FontTitle", TextSize = "SmallTextSize" })
		ctx:Corner(btn, "SmallCornerRadius")
		ctx:Grad(btn, "AccentGradient")
		ctx:Hover(btn, function(st)
			ctx.Theme:Bind(btn, "BackgroundColor3", "Accent", { Alpha = st == "Hover" and 0.15 or (st == "Press" and 0.3 or 0), Tween = true })
			ctx.Theme:Bind(stroke, "Color", st == "Idle" and "Border" or "Accent", { Tween = true })
		end)
		btn.Activated:Connect(function()
			ctx:Sound("SoundClick")
			handle.Start(i)
		end)
	end

	-- loading overlay
	local loading = ctx:Frame(right, { Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 20 }, "Background")
	ctx:Corner(loading, 14)
	local spinHolder = ctx:Frame(loading, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -30), Size = UDim2.fromOffset(56, 56), ZIndex = 21 })
	local title = ctx:Text(loading, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 14), Size = UDim2.new(1, -60, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21 }, "Text", "FontTitle", "TitleSize")
	local step = ctx:Text(loading, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 38), Size = UDim2.new(1, -60, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21 }, "TextDim", "FontBody", "SmallTextSize")
	local bar = ctx:Frame(loading, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 66), Size = UDim2.new(0.6, 0, 0, 4), ZIndex = 21 }, "Element")
	ctx:Corner(bar, "full")
	local fill = ctx:Frame(bar, { Size = UDim2.fromScale(0, 1), ZIndex = 22 }, "Accent")
	ctx:Corner(fill, "full")
	ctx:Grad(fill, "HeaderGradient", { Force = true })

	local view = { Root = root }
	function view:OnStart(product)
		loading.Visible = true
		title.Text = "Loading " .. product.Name
		spinner(ctx, spinHolder, 56)
	end
	function view:SetProgress(p, text)
		Tween.Play(fill, { Size = UDim2.fromScale(p, 1) }, 0.3)
		step.Text = text or ""
	end
	function view:SetStatus(text)
		step.Text = text
	end
	function view:Close(cb)
		Tween.Play(sc, { Scale = 0.94 }, 0.2)
		task.delay(Tween.Duration(0.2), function()
			root:Destroy()
			if cb then
				cb()
			end
		end)
	end
	return view
end
