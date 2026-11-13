--[[
	Onetap loader: minimal. Logo area, product selector, status line and an orange progress bar.
]]
local Tween = require("Core/Tween")

return function(ctx, opts, handle)
	local Wd, Ht = 400, 272
	local root = ctx:Frame(ctx.Layers.Loader, { Name = "Loader", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(Wd, Ht) }, "Background")
	ctx:Corner(root, "CornerRadius")
	ctx:Stroke(root, "BorderDark", 1)
	ctx:Shadow(root, "CornerRadius", 4)
	local logoArea = ctx:Frame(root, { Size = UDim2.new(1, 0, 0, 110) }, "Topbar")
	ctx:Corner(logoArea, "CornerRadius")
	local logo = ctx:Logo(logoArea, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 44), TextXAlignment = Enum.TextXAlignment.Center }, "Accent", 40)
	if logo:IsA("TextLabel") then
		logo.TextSize = 42
		logo.Text = string.lower(logo.Text)
	end
	ctx:Text(logoArea, { Text = string.lower(opts.Subtitle or ctx:T("LoaderSubtitle")) .. ", " .. string.lower(opts.Username or ctx:Username()), Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center }, "TextDim", "FontBody", "SmallTextSize")
	ctx:Frame(root, { Position = UDim2.fromOffset(0, 110), Size = UDim2.new(1, 0, 0, 2) }, "Accent")

	-- product selector  <  name  >
	local selected = 1
	local nameLbl = ctx:Text(root, { Position = UDim2.fromOffset(40, 124), Size = UDim2.new(1, -80, 0, 24), TextXAlignment = Enum.TextXAlignment.Center }, "Text", "FontTitle", "TitleSize")
	local detail = ctx:Text(root, { Position = UDim2.fromOffset(40, 146), Size = UDim2.new(1, -80, 0, 16), TextXAlignment = Enum.TextXAlignment.Center }, "TextDim", "FontBody", "SmallTextSize")
	local function render()
		local p = opts.Products[selected]
		nameLbl.Text = string.lower(p.Name)
		detail.Text = string.lower((p.Status or "undetected") .. "  ·  expires " .. (p.Expires or "never"))
	end
	local function arrow(icon, x, dir)
		local b = ctx:New("TextButton", { Parent = root, Position = UDim2.fromOffset(x, 126), Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 0 }, { BackgroundColor3 = "Element" })
		ctx:Corner(b, "SmallCornerRadius")
		local i = ctx:Icon(b, icon, 12, "TextDim", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		ctx:Hover(b, function(st)
			ctx:IconColor(i, st == "Idle" and "TextDim" or "Accent", true)
		end)
		b.Activated:Connect(function()
			if handle.Running then
				return
			end
			selected = (selected - 1 + dir) % #opts.Products + 1
			render()
		end)
	end
	arrow("chevron-left", 16, -1)
	arrow("chevron-right", Wd - 40, 1)
	render()

	local bar = ctx:Frame(root, { Position = UDim2.new(0, 16, 1, -58), Size = UDim2.new(1, -32, 0, 4) }, "Element")
	local fill = ctx:Frame(bar, { Size = UDim2.fromScale(0, 1) }, "Accent")
	local status = ctx:Text(root, { Position = UDim2.new(0, 16, 1, -50), Size = UDim2.new(1, -32, 0, 16) }, "TextDim", "FontBody", "SmallTextSize")
	status.Text = string.lower(ctx:T("LoaderStatus"))
	local pct = ctx:Text(root, { Position = UDim2.new(0, 16, 1, -50), Size = UDim2.new(1, -32, 0, 16), TextXAlignment = Enum.TextXAlignment.Right }, "Accent", "FontMono", "SmallTextSize")
	local btn = ctx:New("TextButton", { Parent = root, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 172), Size = UDim2.fromOffset(120, 26), Text = "LOAD", TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0 }, { BackgroundColor3 = "Accent", TextColor3 = "TextOnAccent", Font = "FontTitle", TextSize = "TextSize" })
	ctx:Corner(btn, "SmallCornerRadius")
	ctx:Hover(btn, function(st)
		ctx.Theme:Bind(btn, "BackgroundColor3", "Accent", { Alpha = st == "Hover" and 0.15 or (st == "Press" and 0.3 or 0), Tween = true })
	end)
	btn.Activated:Connect(function()
		ctx:Sound("SoundClick")
		handle.Start(selected)
	end)
	local view = { Root = root }
	function view:OnStart()
		btn.Text = "LOADING"
	end
	function view:SetProgress(p, text)
		Tween.Play(fill, { Size = UDim2.fromScale(p, 1) }, 0.3)
		status.Text = string.lower(text or "")
		pct.Text = math.floor(p * 100 + 0.5) .. "%"
	end
	function view:SetStatus(text)
		status.Text = string.lower(text)
	end
	function view:Close(cb)
		Tween.Play(root, { Position = UDim2.new(0.5, 0, 0.5, 20) }, 0.2)
		task.delay(Tween.Duration(0.2), function()
			root:Destroy()
			if cb then
				cb()
			end
		end)
	end
	return view
end
