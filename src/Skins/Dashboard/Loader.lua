--[[
	Dashboard loader: logo animation (Back easing), typewriter title, product cards,
	gradient progress bar with a moving shimmer, percentage counter and step labels with checkmarks.
]]
local Tween = require("Core/Tween")

return function(ctx, opts, handle)
	local Wd, Ht = 520, 420
	local root = ctx:Frame(ctx.Layers.Loader, { Name = "Loader", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(Wd, Ht) }, "Panel")
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "Border", 1)
	ctx:Shadow(root, "CornerRadius", 5)

	-- logo: scale in with Back easing
	local mark = ctx:Frame(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 28), Size = UDim2.fromOffset(56, 56) }, "Highlight")
	ctx:Corner(mark, 16)
	ctx:Grad(mark, "HeaderGradient", { Force = true, Rotation = 45 })
	ctx:Icon(mark, "logo", 30, "TextOnAccent", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BgKey = "Accent" })
	local msc = Instance.new("UIScale")
	msc.Scale = 0
	msc.Parent = mark
	Tween.Play(msc, { Scale = 1 }, 0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	-- typewriter title
	local fullTitle = opts.Title or (ctx:T("LoaderTitle") ~= "" and ctx:T("LoaderTitle") or ctx:T("Title"))
	local title = ctx:Text(root, { Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Center }, "Text", "FontTitle", "TitleSize")
	title.TextSize = 22
	task.spawn(function()
		for i = 1, #fullTitle do
			if not title.Parent then
				return
			end
			title.Text = string.sub(fullTitle, 1, i) .. (i < #fullTitle and "▍" or "")
			task.wait(Tween.Enabled and 0.05 or 0)
		end
		title.Text = fullTitle
	end)
	ctx:Text(root, { Text = (opts.Subtitle or ctx:T("LoaderSubtitle")) .. ", " .. (opts.Username or ctx:Username()), Position = UDim2.fromOffset(0, 126), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center }, "TextDim", "FontBody", "SmallTextSize")

	-- product cards (horizontal)
	local selected = 1
	local cards = ctx:Frame(root, { Position = UDim2.fromOffset(24, 158), Size = UDim2.new(1, -48, 0, 92) })
	ctx:List(cards, { Dir = "H", Pad = 10 })
	local n = math.min(#opts.Products, 3)
	local strokes = {}
	local function paint()
		for i, s in ipairs(strokes) do
			ctx.Theme:Bind(s, "Color", i == selected and "Accent" or "Border", { Tween = true })
			s.Thickness = i == selected and 2 or 1
		end
	end
	for i = 1, n do
		local p = opts.Products[i]
		local c = ctx:New("TextButton", { Parent = cards, Size = UDim2.new(1 / n, -(10 * (n - 1)) / n, 1, 0), LayoutOrder = i, BackgroundTransparency = 0 }, { BackgroundColor3 = "Element" })
		ctx:Corner(c, "SmallCornerRadius")
		table.insert(strokes, ctx:Stroke(c, "Border", 1))
		ctx:Icon(c, p.Icon or "zap", 16, "Accent", { Position = UDim2.fromOffset(12, 12) })
		ctx:Text(c, { Text = p.Name, Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -24, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd }, "Text", "FontTitle", "TextSize")
		local s = string.lower(p.Status or "")
		local key = (s:find("undetect") or s:find("online")) and "Success" or (s:find("updat") and "Warning" or "Error")
		local dot = ctx:Frame(c, { Position = UDim2.fromOffset(12, 64), Size = UDim2.fromOffset(7, 7) }, key)
		ctx:Corner(dot, "full")
		ctx:Text(c, { Text = (p.Status or "Undetected") .. " · " .. (p.Expires or "Never"), Position = UDim2.fromOffset(24, 58), Size = UDim2.new(1, -30, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd }, "TextDim", "FontBody", "SmallTextSize")
		c.Activated:Connect(function()
			if not handle.Running then
				selected = i
				paint()
			end
		end)
	end
	paint()

	-- progress with shimmer + percentage
	local bar = ctx:Frame(root, { Position = UDim2.new(0, 24, 0, 272), Size = UDim2.new(1, -48, 0, 8), ClipsDescendants = true }, "Element")
	ctx:Corner(bar, "full")
	local fill = ctx:Frame(bar, { Size = UDim2.fromScale(0, 1), ClipsDescendants = true }, "Highlight")
	ctx:Corner(fill, "full")
	ctx:Grad(fill, "HeaderGradient", { Force = true })
	local shimmer = ctx:New("Frame", { Parent = fill, Size = UDim2.new(0, 60, 1, 0), Position = UDim2.new(0, -60, 0, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.2 })
	local sg = Instance.new("UIGradient")
	sg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1) })
	sg.Parent = shimmer
	local pct = ctx:Text(root, { Position = UDim2.new(0, 24, 0, 286), Size = UDim2.new(1, -48, 0, 18), TextXAlignment = Enum.TextXAlignment.Right }, "Text", "FontTitle", "TextSize")
	pct.Text = "0%"
	local stepText = ctx:Text(root, { Position = UDim2.new(0, 24, 0, 286), Size = UDim2.new(1, -100, 0, 18) }, "TextDim", "FontBody", "SmallTextSize")
	stepText.Text = ctx:T("LoaderStatus")

	-- step labels
	local steps = ctx:Frame(root, { Position = UDim2.fromOffset(24, 312), Size = UDim2.new(1, -48, 0, 50) })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.333, -6, 0, 20)
	grid.CellPadding = UDim2.fromOffset(8, 4)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = steps
	local stepRows = {}
	for i, s in ipairs(opts.Steps) do
		local text = type(s) == "table" and s.Text or tostring(s)
		local row = ctx:Frame(steps, { Size = UDim2.new(0.333, -6, 0, 20), LayoutOrder = i })
		local ring = ctx:Frame(row, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(12, 12) }, "Element")
		ctx:Corner(ring, "full")
		local chk = ctx:Icon(ring, "check", 8, "TextOnAccent", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		chk.Visible = false
		local t = ctx:Text(row, { Text = text, Position = UDim2.fromOffset(18, 0), Size = UDim2.new(1, -18, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd }, "TextDisabled", "FontBody", "SmallTextSize")
		stepRows[i] = { Ring = ring, Check = chk, Text = t }
	end

	local btn = ctx:New("TextButton", { Parent = root, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(1, -48, 0, 40), Text = "Launch", TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0 }, { BackgroundColor3 = "Highlight", TextColor3 = "TextOnAccent", Font = "FontTitle", TextSize = "TextSize" })
	ctx:Corner(btn, "SmallCornerRadius")
	ctx:Grad(btn, "HeaderGradient", { Force = true })
	ctx:Hover(btn, function(st)
		ctx.Theme:Bind(btn, "BackgroundColor3", "Highlight", { Alpha = st == "Hover" and 0.1 or (st == "Press" and 0.2 or 0), Tween = true })
	end)
	btn.Activated:Connect(function()
		ctx:Sound("SoundClick")
		handle.Start(selected)
	end)

	local shimmerOn = false
	local current = 0
	local view = { Root = root }
	function view:OnStart()
		btn.Visible = false
		shimmerOn = true
		task.spawn(function()
			while shimmerOn and shimmer.Parent do
				shimmer.Position = UDim2.new(0, -60, 0, 0)
				Tween.Play(shimmer, { Position = UDim2.new(1, 0, 0, 0) }, 0.9, Enum.EasingStyle.Sine)
				task.wait(Tween.Duration(1.1))
			end
		end)
	end
	function view:SetProgress(p, text, index)
		Tween.Play(fill, { Size = UDim2.fromScale(p, 1) }, 0.35)
		local from = current
		current = p
		Tween.Value(from * 100, p * 100, 0.35, function(v)
			pct.Text = math.floor(v + 0.5) .. "%"
		end)
		stepText.Text = text or ""
		for i, r in ipairs(stepRows) do
			local done = index and (i < index or p >= 1)
			local active = index and i == index and p < 1
			ctx.Theme:Bind(r.Ring, "BackgroundColor3", done and "Success" or (active and "Accent" or "Element"), { Tween = true })
			r.Check.Visible = done == true
			ctx.Theme:Bind(r.Text, "TextColor3", done and "Text" or (active and "Accent" or "TextDisabled"), { Tween = true })
		end
	end
	function view:SetStatus(text)
		stepText.Text = text
	end
	function view:Close(cb)
		shimmerOn = false
		local sc = Instance.new("UIScale")
		sc.Parent = root
		Tween.Play(sc, { Scale = 0.9 }, 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		task.delay(Tween.Duration(0.25), function()
			root:Destroy()
			if cb then
				cb()
			end
		end)
	end
	return view
end
