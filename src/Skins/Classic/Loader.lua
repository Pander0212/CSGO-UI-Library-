--[[
	Classic loader: small window in the layered border style with the rainbow bar,
	username + status line, a list of scripts/games, a "Load" button and a simple progress bar.
]]
local Tween = require("Core/Tween")
local W = require("Skins/Classic/Window")

return function(ctx, opts, handle)
	local layer = ctx.Layers.Loader
	local Wd, Ht = 360, 330
	local root = ctx:New("Frame", { Parent = layer, Name = "Loader", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(Wd, Ht) })
	local inner = W.Layered(ctx, root, 4)
	W.RainbowBar(ctx, inner, 2)
	ctx:Texture(inner)
	local pad = 14
	local title = ctx:Text(inner, { Text = opts.Title or (ctx:T("LoaderTitle") ~= "" and ctx:T("LoaderTitle") or ctx:T("Title")), Position = UDim2.fromOffset(pad, 12), Size = UDim2.new(1, -pad * 2, 0, 16) }, "Text", "FontTitle", "TitleSize")
	ctx:Text(inner, { Text = "v" .. ctx.Library.Version, Position = UDim2.fromOffset(pad, 12), Size = UDim2.new(1, -pad * 2, 0, 16), TextXAlignment = Enum.TextXAlignment.Right }, "TextDisabled", "FontMono", "SmallTextSize")
	local _ = title
	ctx:Text(inner, { Text = (opts.Subtitle or ctx:T("LoaderSubtitle")) .. ", " .. (opts.Username or ctx:Username()), Position = UDim2.fromOffset(pad, 32), Size = UDim2.new(1, -pad * 2, 0, 14) }, "TextDim", "FontBody", "SmallTextSize")
	local status = ctx:Text(inner, { Text = "status: " .. string.lower(ctx:T("LoaderStatus")), Position = UDim2.fromOffset(pad, 48), Size = UDim2.new(1, -pad * 2, 0, 14) }, "Accent", "FontMono", "SmallTextSize")

	-- scripts list (group box look)
	local box = ctx:Frame(inner, { Position = UDim2.fromOffset(pad, 76), Size = UDim2.new(1, -pad * 2, 1, -76 - 84) }, "BorderDark")
	local boxInner = ctx:Frame(box, { Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2) }, "Border")
	local list = ctx:Frame(boxInner, { Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2) }, "Panel")
	ctx:Pad(list, 10, 8, 6, 8)
	ctx:List(list, { Pad = 2 })
	local t = ctx:Text(box, { Text = "scripts", Position = UDim2.fromOffset(10, -7), Size = UDim2.fromOffset(0, 13), AutomaticSize = Enum.AutomaticSize.X, ZIndex = box.ZIndex + 5 }, "Text", "FontTitle", "TextSize")
	t.BackgroundTransparency = 0
	ctx.Theme:Bind(t, "BackgroundColor3", "Background")
	ctx:Pad(t, 0, 3, 0, 3)
	local selected = 1
	local rows = {}
	local function paintRows()
		for i, r in ipairs(rows) do
			ctx.Theme:Bind(r.Name, "TextColor3", i == selected and "Accent" or "Text", { Tween = true })
			ctx.Theme:Bind(r.Root, "BackgroundColor3", "ElementHover", { Alpha = i == selected and 0.7 or 1, Tween = true })
		end
	end
	for i, p in ipairs(opts.Products) do
		local row = ctx:New("TextButton", { Parent = list, Size = UDim2.new(1, 0, 0, ctx:Touch(20)), LayoutOrder = i, BackgroundTransparency = 1 })
		local name = ctx:Text(row, { Text = p.Name, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0.55, 0, 1, 0) }, "Text", "FontBody", "TextSize")
		local okStatus = (p.Status or "Undetected")
		local key = (okStatus:lower():find("undetect") or okStatus:lower():find("online")) and "Success" or (okStatus:lower():find("updat") and "Warning" or "Error")
		ctx:Text(row, { Text = string.lower(okStatus), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Size = UDim2.new(0.45, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right }, key, "FontMono", "SmallTextSize")
		table.insert(rows, { Root = row, Name = name })
		row.Activated:Connect(function()
			if handle.Running then
				return
			end
			selected = i
			paintRows()
		end)
	end
	paintRows()

	-- progress + button
	local barOuter = ctx:Frame(inner, { Position = UDim2.new(0, pad, 1, -74), Size = UDim2.new(1, -pad * 2, 0, 6) }, "BorderDark")
	local bar = ctx:Frame(barOuter, { Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2) }, "Element")
	local fill = ctx:Frame(bar, { Size = UDim2.fromScale(0, 1) }, "Accent")
	ctx:Grad(fill, "AccentGradient")
	local step = ctx:Text(inner, { Text = "", Position = UDim2.new(0, pad, 1, -64), Size = UDim2.new(1, -pad * 2, 0, 14) }, "TextDim", "FontMono", "SmallTextSize")
	local btnOuter = ctx:Frame(inner, { Position = UDim2.new(0, pad, 1, -44), Size = UDim2.new(1, -pad * 2, 0, 30) }, "BorderDark")
	local btn = ctx:New("TextButton", { Parent = btnOuter, Position = UDim2.fromOffset(1, 1), Size = UDim2.new(1, -2, 1, -2), Text = "load", TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0 }, { BackgroundColor3 = "Element", TextColor3 = "Text", Font = "FontTitle", TextSize = "TextSize" })
	ctx:Grad(btn, "ElementGradient", { Force = true })
	ctx:Hover(btn, function(st)
		ctx.Theme:Bind(btn, "BackgroundColor3", st == "Idle" and "Element" or (st == "Press" and "ElementActive" or "ElementHover"), { Tween = true })
		ctx.Theme:Bind(btn, "TextColor3", st == "Idle" and "Text" or "Accent", { Tween = true })
	end)
	btn.Activated:Connect(function()
		ctx:Sound("SoundClick")
		handle.Start(selected)
	end)

	local view = { Root = root }
	function view:OnStart(product)
		btn.Text = "loading " .. string.lower(product.Name) .. "..."
		status.Text = "status: injecting"
	end
	function view:SetProgress(p, text)
		Tween.Play(fill, { Size = UDim2.fromScale(p, 1) }, 0.25)
		step.Text = string.lower(text or "")
	end
	function view:SetStatus(text)
		status.Text = "status: " .. string.lower(text)
	end
	function view:Close(cb)
		status.Text = "status: done"
		task.delay(Tween.Duration(0.1), function()
			root:Destroy()
			if cb then
				cb()
			end
		end)
	end
	return view
end
