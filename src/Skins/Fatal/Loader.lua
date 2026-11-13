--[[
	Fatal loader: glowing logo intro with a pulse, product list and a gradient progress bar.
]]
local Tween = require("Core/Tween")
local Comp = require("Skins/Fatal/Components")

return function(ctx, opts, handle)
	local Wd, Ht = 470, 320
	local root = ctx:Frame(ctx.Layers.Loader, { Name = "Loader", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(Wd, Ht) }, "Background")
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "Border", 1)
	ctx:Grad(root, "BackgroundGradient")
	ctx:Glow(root, "Glow", "CornerRadius", 6, 0.3)

	-- logo intro: scale in + pulsing glow
	local logo = ctx:Logo(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 30), Size = UDim2.new(1, -40, 0, 48), TextXAlignment = Enum.TextXAlignment.Center }, "Highlight", 40)
	local stop
	if logo:IsA("TextLabel") then
		logo.TextSize = 40
		logo.Text = string.upper(logo.Text)
		ctx:Grad(logo, "HeaderGradient", { Force = true })
		local glow = Instance.new("UIStroke")
		glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		glow.Thickness = 3
		glow.Parent = logo
		ctx.Theme:Bind(glow, "Color", "Glow", { Alpha = 0.5 })
		stop = Comp.Pulse(glow, 0.25, 0.8, 1.6)
		local sc = Instance.new("UIScale")
		sc.Scale = 0.6
		sc.Parent = logo
		Tween.Play(sc, { Scale = 1 }, 0.6, Enum.EasingStyle.Back)
	end
	ctx:Text(root, { Text = string.upper((opts.Subtitle or ctx:T("LoaderSubtitle")) .. ", " .. (opts.Username or ctx:Username())), Position = UDim2.fromOffset(0, 82), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center }, "TextDim", "FontTitle", "SmallTextSize")

	-- products
	local list = ctx:Frame(root, { Position = UDim2.fromOffset(24, 112), Size = UDim2.new(1, -48, 0, 116) })
	ctx:List(list, { Pad = 6 })
	local selected = 1
	local rows = {}
	local function paint()
		for i, r in ipairs(rows) do
			ctx.Theme:Bind(r.Stroke, "Color", i == selected and "Accent" or "Border", { Tween = true })
			ctx.Theme:Bind(r.Name, "TextColor3", i == selected and "Text" or "TextDim", { Tween = true })
		end
	end
	for i, p in ipairs(opts.Products) do
		if i > 3 then
			break
		end
		local row = ctx:New("TextButton", { Parent = list, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = i, BackgroundTransparency = 0 }, { BackgroundColor3 = "Panel" })
		ctx:Corner(row, "SmallCornerRadius")
		local stroke = ctx:Stroke(row, "Border", 1)
		local name = ctx:Text(row, { Text = string.upper(p.Name), Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.5, 0, 1, 0) }, "TextDim", "FontTitle", "SmallTextSize")
		local s = string.lower(p.Status or "")
		local key = (s:find("undetect") or s:find("online")) and "Success" or (s:find("updat") and "Warning" or "Error")
		ctx:Text(row, { Text = string.upper(p.Status or "Undetected") .. "  ·  " .. (p.Expires or "Never"), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0.5, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right }, key, "FontBody", "SmallTextSize")
		table.insert(rows, { Stroke = stroke, Name = name })
		row.Activated:Connect(function()
			if not handle.Running then
				selected = i
				paint()
			end
		end)
	end
	paint()

	-- gradient progress bar + button
	local bar = ctx:Frame(root, { Position = UDim2.new(0, 24, 1, -72), Size = UDim2.new(1, -48, 0, 6) }, "Element")
	ctx:Corner(bar, "full")
	local fill = ctx:Frame(bar, { Size = UDim2.fromScale(0, 1) }, "Highlight")
	ctx:Corner(fill, "full")
	ctx:Grad(fill, "AccentGradient", { Force = true })
	ctx:Glow(fill, "Glow", nil, 2, 0.35)
	local status = ctx:Text(root, { Position = UDim2.new(0, 24, 1, -62), Size = UDim2.new(1, -48, 0, 16) }, "TextDim", "FontBody", "SmallTextSize")
	status.Text = string.upper(ctx:T("LoaderStatus"))
	local pct = ctx:Text(root, { Position = UDim2.new(0, 24, 1, -62), Size = UDim2.new(1, -48, 0, 16), TextXAlignment = Enum.TextXAlignment.Right }, "Accent", "FontMono", "SmallTextSize")
	local btn = ctx:New("TextButton", { Parent = root, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(160, 30), Text = "INJECT", TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0 }, { BackgroundColor3 = "Highlight", TextColor3 = "TextOnAccent", Font = "FontTitle", TextSize = "SmallTextSize" })
	ctx:Corner(btn, "full")
	ctx:Grad(btn, "AccentGradient", { Force = true })
	ctx:Glow(btn, "Glow", nil, 3, 0.35)
	ctx:Hover(btn, function(st)
		ctx.Theme:Bind(btn, "BackgroundColor3", "Highlight", { Alpha = st == "Hover" and 0.12 or (st == "Press" and 0.25 or 0), Tween = true })
	end)
	btn.Activated:Connect(function()
		ctx:Sound("SoundClick")
		handle.Start(selected)
	end)
	local view = { Root = root }
	function view:OnStart()
		btn.Text = "INJECTING..."
	end
	function view:SetProgress(p, text)
		Tween.Play(fill, { Size = UDim2.fromScale(math.max(p, 0.02), 1) }, 0.3)
		status.Text = string.upper(text or "")
		pct.Text = math.floor(p * 100 + 0.5) .. "%"
	end
	function view:SetStatus(text)
		status.Text = string.upper(text)
	end
	function view:Close(cb)
		if stop then
			stop()
		end
		Tween.Play(root, { Position = UDim2.new(0.5, 0, 0.5, -20) }, 0.25)
		task.delay(Tween.Duration(0.25), function()
			root:Destroy()
			if cb then
				cb()
			end
		end)
	end
	return view
end
