--[[
	ESP preview component: ViewportFrame with an R15 dummy (local character clone or default rig),
	drag to rotate, scroll / pinch to zoom, idle rotation. Overlays (box 2D/corner/filled, name,
	distance, health bar with selectable side + animated demo value, tracer, skeleton, chams) are bound
	live to flags and styled with the active skin's theme.

	UI:GetESPSettings() returns the current values so your own ESP code can use them.
	RenderStepped runs only while the preview is actually visible on screen.
]]
local Util = require("Core/Util")
local Input = require("Core/Input")
local Rig = require("ESPPreview/Rig")

local RunService = Util.Services.RunService
local UIS = Util.Services.UserInputService

local ESP = {}

ESP.DefaultFlags = {
	Enabled = "esp_enabled",
	Box = "esp_box",
	BoxType = "esp_box_type",
	BoxColor = "esp_box_color",
	Name = "esp_name",
	NameColor = "esp_name_color",
	Distance = "esp_distance",
	HealthBar = "esp_health",
	HealthSide = "esp_health_side",
	Tracer = "esp_tracer",
	TracerColor = "esp_tracer_color",
	Skeleton = "esp_skeleton",
	SkeletonColor = "esp_skeleton_color",
	Chams = "esp_chams",
	ChamsColor = "esp_chams_color",
}

function ESP.ResolveFlags(map)
	local out = {}
	for k, v in pairs(ESP.DefaultFlags) do
		out[k] = (map and map[k]) or v
	end
	return out
end

local function col(v, default)
	if type(v) == "table" and typeof(v.Color) == "Color3" then
		return v.Color, v.Transparency or 0
	end
	if typeof(v) == "Color3" then
		return v, 0
	end
	return default, 0
end

function ESP.GetSettings(lib, map)
	local F = ESP.ResolveFlags(map)
	local V = lib.Flags.Values
	local function bool(k, d)
		local v = V[F[k]]
		if v == nil then
			return d
		end
		return v == true
	end
	local white = Color3.new(1, 1, 1)
	local s = {
		Enabled = bool("Enabled", true),
		Box = bool("Box", true),
		BoxType = V[F.BoxType] or "2D",
		Name = bool("Name", true),
		Distance = bool("Distance", true),
		HealthBar = bool("HealthBar", true),
		HealthSide = V[F.HealthSide] or "Left",
		Tracer = bool("Tracer", false),
		Skeleton = bool("Skeleton", false),
		Chams = bool("Chams", false),
	}
	s.BoxColor, s.BoxTransparency = col(V[F.BoxColor], white)
	s.NameColor = col(V[F.NameColor], white)
	s.TracerColor, s.TracerTransparency = col(V[F.TracerColor], white)
	s.SkeletonColor, s.SkeletonTransparency = col(V[F.SkeletonColor], white)
	s.ChamsColor, s.ChamsTransparency = col(V[F.ChamsColor], Color3.fromRGB(160, 90, 255))
	return s
end

local function line(ctx, parent, z)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.ZIndex = z
	f.Parent = parent
	return f
end

function ESP.Render(ctx, el, parent)
	local lib = ctx.Library
	local o = el.Options
	local h = o.Height or 280
	local root = ctx:Frame(parent, { Name = "ESPPreview", Size = UDim2.new(1, 0, 0, h) })
	local view = { Root = root }
	local box = ctx:Frame(root, { Size = UDim2.fromScale(1, 1), ClipsDescendants = true }, "BackgroundSecondary")
	ctx:Corner(box, "SmallCornerRadius")
	ctx:Stroke(box, ctx.Style.ControlStroke or "Border", 1)
	ctx:Grad(box, "BackgroundGradient")
	-- floor grid for depth
	for i = 1, 5 do
		ctx:Frame(box, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.62 + i * 0.075, 0), Size = UDim2.new(0.25 + i * 0.15, 0, 0, 1) }, "Border", { Alpha = 0.3 + i * 0.08 })
	end

	local vf = Instance.new("ViewportFrame")
	vf.Name = "Viewport"
	vf.BackgroundTransparency = 1
	vf.Size = UDim2.fromScale(1, 1)
	vf.Ambient = Color3.fromRGB(170, 170, 180)
	vf.LightColor = Color3.fromRGB(255, 255, 255)
	vf.LightDirection = Vector3.new(-1, -1, -1)
	vf.Parent = box
	local world = Instance.new("WorldModel")
	world.Parent = vf
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vf
	vf.CurrentCamera = cam
	local model, parts, allParts, base = Rig.Build()
	model.Parent = world
	local original = {}
	for _, p in ipairs(allParts) do
		original[p] = { Color = p.Color, Transparency = p.Transparency, Material = p.Material }
	end

	local overlay = ctx:Frame(box, { Name = "Overlay", Size = UDim2.fromScale(1, 1), ZIndex = box.ZIndex + 5 })
	local Z = overlay.ZIndex + 1
	-- box variants
	local boxOutline = Instance.new("Frame")
	boxOutline.BackgroundTransparency = 1
	boxOutline.ZIndex = Z
	boxOutline.Parent = overlay
	local outlineStroke = Instance.new("UIStroke")
	outlineStroke.Thickness = 3
	outlineStroke.Color = Color3.new(0, 0, 0)
	outlineStroke.Transparency = 0.4
	outlineStroke.Parent = boxOutline
	local boxFrame = Instance.new("Frame")
	boxFrame.BackgroundTransparency = 1
	boxFrame.BorderSizePixel = 0
	boxFrame.ZIndex = Z + 1
	boxFrame.Parent = overlay
	local boxStroke = Instance.new("UIStroke")
	boxStroke.Thickness = 1
	boxStroke.Parent = boxFrame
	local corners = {}
	for i = 1, 8 do
		local c = line(ctx, overlay, Z + 1)
		c.AnchorPoint = Vector2.new(0, 0)
		table.insert(corners, c)
	end
	-- texts
	local nameLabel = ctx:Text(overlay, { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(160, 14), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, ZIndex = Z + 2, Text = o.PlayerName or ctx:Username() }, "Text", "FontMono", "SmallTextSize")
	local distLabel = ctx:Text(overlay, { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(100, 14), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, ZIndex = Z + 2 }, "TextDim", "FontMono", "SmallTextSize")
	-- health bar
	local hpBg = Instance.new("Frame")
	hpBg.BorderSizePixel = 0
	hpBg.BackgroundColor3 = Color3.new(0, 0, 0)
	hpBg.BackgroundTransparency = 0.3
	hpBg.ZIndex = Z + 1
	hpBg.Parent = overlay
	local hpFill = Instance.new("Frame")
	hpFill.BorderSizePixel = 0
	hpFill.ZIndex = Z + 2
	hpFill.Parent = hpBg
	local hpText = ctx:Text(overlay, { Size = UDim2.fromOffset(30, 12), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3, ZIndex = Z + 3, TextSize = 10 }, "Text", "FontMono", 10)
	-- tracer + skeleton
	local tracer = line(ctx, overlay, Z)
	local bones = {}
	for i = 1, #Rig.Bones do
		bones[i] = line(ctx, overlay, Z + 1)
	end
	-- hint + hit area
	local hint = ctx:Text(box, { Text = ctx.IsMobile and "drag to rotate · pinch to zoom" or "drag to rotate · scroll to zoom", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.new(1, -12, 0, 12), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = Z + 4 }, "TextDisabled", "FontBody", "SmallTextSize")
	local _ = hint
	local hit = ctx:Hitbox(box, { ZIndex = Z + 5 })

	local state = lib.ESPState or { Yaw = 0.5, Distance = 15 }
	lib.ESPState = state
	local dragging = false
	local startYaw = state.Yaw
	ctx.Maid:Give(ctx.Input:Drag(hit, {
		OnStart = function()
			dragging = true
			startYaw = state.Yaw
		end,
		OnMove = function(delta)
			state.Yaw = startYaw + delta.X * 0.012
		end,
		OnEnd = function()
			dragging = false
		end,
	}))
	hit.InputChanged:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseWheel then
			state.Distance = Util.Clamp(state.Distance - io.Position.Z * 1.2, 8, 26)
		end
	end)
	if UIS then
		ctx.Maid:Give(UIS.TouchPinch:Connect(function(positions, scale, _, st)
			if not Util.IsVisible(box) or not positions[1] then
				return
			end
			local p = Input.ToAbs(positions[1])
			local a, s = box.AbsolutePosition, box.AbsoluteSize
			if p.X < a.X or p.Y < a.Y or p.X > a.X + s.X or p.Y > a.Y + s.Y then
				return
			end
			if st == Enum.UserInputState.Begin then
				view._pinchStart = state.Distance
			end
			state.Distance = Util.Clamp((view._pinchStart or state.Distance) / math.max(scale, 0.2), 8, 26)
		end))
	end

	local chamsOn = nil
	local function applyChams(on, c, t)
		if on then
			for _, p in ipairs(allParts) do
				if p.Name ~= "HumanoidRootPart" then
					p.Color = c
					p.Transparency = t
					p.Material = Enum.Material.SmoothPlastic
				end
			end
		elseif chamsOn ~= false then
			for p, d in pairs(original) do
				p.Color = d.Color
				p.Transparency = d.Transparency
				p.Material = d.Material
			end
		end
		chamsOn = on
	end

	local function project(camCF, fov, w, hh, pos)
		local rel = camCF:PointToObjectSpace(pos)
		local depth = -rel.Z
		if depth <= 0.01 then
			depth = 0.01
		end
		local f = (hh / 2) / math.tan(math.rad(fov / 2))
		return Vector2.new(w / 2 + rel.X * f / depth, hh / 2 - rel.Y * f / depth)
	end

	local t0 = os.clock()
	function view:Step(dt)
		local s = ESP.GetSettings(lib, o.Flags)
		if not dragging and o.IdleRotation ~= false then
			state.Yaw += (dt or 0) * (o.IdleSpeed or 0.5)
		end
		local rot = CFrame.Angles(0, state.Yaw, 0)
		for _, p in ipairs(allParts) do
			p.CFrame = rot * base[p]
		end
		local camPos = Vector3.new(0, 2.8, state.Distance)
		local camCF = CFrame.new(camPos, Vector3.new(0, 2.8, 0))
		cam.CFrame = camCF
		local sc = lib.CurrentScale or 1
		local w, hh = box.AbsoluteSize.X / sc, box.AbsoluteSize.Y / sc
		if w <= 1 then
			w, hh = 300, h
		end
		applyChams(s.Enabled and s.Chams, s.ChamsColor, s.ChamsTransparency)
		-- bounding box from the R15 parts
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
		for _, p in pairs(parts) do
			local cf, size = p.CFrame, p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local v = project(camCF, cam.FieldOfView, w, hh, cf * Vector3.new(size.X * sx, size.Y * sy, size.Z * sz))
						minX, minY = math.min(minX, v.X), math.min(minY, v.Y)
						maxX, maxY = math.max(maxX, v.X), math.max(maxY, v.Y)
					end
				end
			end
		end
		local bw, bh = maxX - minX, maxY - minY
		local on = s.Enabled
		local showBox = on and s.Box
		local filled = s.BoxType == "Filled"
		local corner = s.BoxType == "Corner"
		boxFrame.Visible = showBox and not corner
		boxOutline.Visible = showBox and not corner
		boxFrame.Position = UDim2.fromOffset(minX, minY)
		boxFrame.Size = UDim2.fromOffset(bw, bh)
		boxOutline.Position = boxFrame.Position
		boxOutline.Size = boxFrame.Size
		boxStroke.Color = s.BoxColor
		boxStroke.Transparency = s.BoxTransparency
		boxFrame.BackgroundTransparency = filled and 0.8 or 1
		boxFrame.BackgroundColor3 = s.BoxColor
		local cl = math.min(bw, bh) * 0.25
		local cdef = {
			{ minX, minY, cl, 1 }, { minX, minY, 1, cl },
			{ maxX - cl, minY, cl, 1 }, { maxX - 1, minY, 1, cl },
			{ minX, maxY - 1, cl, 1 }, { minX, maxY - cl, 1, cl },
			{ maxX - cl, maxY - 1, cl, 1 }, { maxX - 1, maxY - cl, 1, cl },
		}
		for i, c in ipairs(corners) do
			c.Visible = showBox and corner
			c.Position = UDim2.fromOffset(cdef[i][1], cdef[i][2])
			c.Size = UDim2.fromOffset(cdef[i][3], cdef[i][4])
			c.BackgroundColor3 = s.BoxColor
			c.BackgroundTransparency = s.BoxTransparency
		end
		nameLabel.Visible = on and s.Name
		nameLabel.Position = UDim2.fromOffset((minX + maxX) / 2, minY - 3)
		nameLabel.TextColor3 = s.NameColor
		distLabel.Visible = on and s.Distance
		distLabel.Position = UDim2.fromOffset((minX + maxX) / 2, maxY + 3)
		distLabel.Text = string.format("%dm", math.floor(state.Distance * 1.4))
		-- health (animated demo value)
		local hp = 0.55 + 0.45 * math.sin((os.clock() - t0) * 1.3)
		local side = s.HealthSide
		hpBg.Visible = on and s.HealthBar
		hpText.Visible = hpBg.Visible
		local th = 3
		if side == "Left" or side == "Right" then
			local x = side == "Left" and (minX - 6) or (maxX + 3)
			hpBg.Position = UDim2.fromOffset(x, minY)
			hpBg.Size = UDim2.fromOffset(th, bh)
			hpFill.AnchorPoint = Vector2.new(0, 1)
			hpFill.Position = UDim2.fromScale(0, 1)
			hpFill.Size = UDim2.fromScale(1, hp)
			hpText.Position = UDim2.fromOffset(x - 14 + th / 2, minY + bh * (1 - hp) - 6)
		else
			local y = side == "Top" and (minY - 6 - (s.Name and 14 or 0)) or (maxY + 3 + (s.Distance and 14 or 0))
			hpBg.Position = UDim2.fromOffset(minX, y)
			hpBg.Size = UDim2.fromOffset(bw, th)
			hpFill.AnchorPoint = Vector2.new(0, 0)
			hpFill.Position = UDim2.fromScale(0, 0)
			hpFill.Size = UDim2.fromScale(hp, 1)
			hpText.Position = UDim2.fromOffset(minX + bw * hp - 15, y - 12)
		end
		hpFill.BackgroundColor3 = Util.HealthColor(hp)
		hpText.Text = tostring(math.floor(hp * 100))
		-- tracer
		tracer.Visible = on and s.Tracer
		Util.SetLine(tracer, Vector2.new(w / 2, hh), Vector2.new((minX + maxX) / 2, maxY), 1)
		tracer.BackgroundColor3 = s.TracerColor
		tracer.BackgroundTransparency = s.TracerTransparency
		-- skeleton
		for i, b in ipairs(Rig.Bones) do
			local a, c = parts[b[1]], parts[b[2]]
			local fr = bones[i]
			fr.Visible = on and s.Skeleton
			if fr.Visible and a and c then
				local pa = a.Position
				local pc = c.Position
				if b[1] == "Head" then
					pc = (c.CFrame * Vector3.new(0, c.Size.Y / 2, 0))
				end
				Util.SetLine(fr, project(camCF, cam.FieldOfView, w, hh, pa), project(camCF, cam.FieldOfView, w, hh, pc), 1)
				fr.BackgroundColor3 = s.SkeletonColor
				fr.BackgroundTransparency = s.SkeletonTransparency
			end
		end
	end

	view:Step(0)
	if RunService then
		local conn = RunService.RenderStepped:Connect(function(dt)
			if not root.Parent or not Util.IsVisible(root) then
				return
			end
			view:Step(dt)
		end)
		ctx.Maid:Give(conn)
		root.Destroying:Connect(function()
			conn:Disconnect()
		end)
	end
	-- flags changed while hidden: refresh once
	ctx.Maid:Give(lib.Flags.Changed:Connect(function()
		if root.Parent then
			view:Step(0)
		end
	end))
	function view:SetDisabled() end
	return view
end

return ESP
