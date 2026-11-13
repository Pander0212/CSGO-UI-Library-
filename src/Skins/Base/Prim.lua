--[[
	Prim: drawing primitives available on every render context (ctx:New, ctx:Text, ctx:Corner ...).
	All colors / fonts / sizes are bound to theme keys – renderers pass KEYS, never raw values.
]]
local Util = require("Core/Util")
local Icons = require("Core/Icons")

local Prim = {}
Prim.__index = Prim

function Prim.Attach(ctx)
	return setmetatable(ctx, Prim)
end

local TEXT = { TextLabel = true, TextButton = true, TextBox = true }

function Prim:T(key)
	return self.Theme.Values[key]
end

local function fontT(v)
	return Util.FontEnum(v)
end
Prim.FontT = fontT

local function udimT(v)
	return UDim.new(0, v)
end
Prim.UDimT = udimT

-- ctx:New(class, props, binds) binds = { Prop = "Key" | {"Key", opts} }
function Prim:New(class, props, binds)
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	if TEXT[class] then
		inst.BackgroundTransparency = 1
		inst.Text = ""
		inst.TextXAlignment = Enum.TextXAlignment.Left
	end
	if class == "TextButton" or class == "ImageButton" then
		inst.AutoButtonColor = false
	end
	if class == "ImageLabel" or class == "ImageButton" then
		inst.BackgroundTransparency = 1
	end
	if class == "ScrollingFrame" then
		inst.BackgroundTransparency = 1
		inst.ScrollBarThickness = 2
		inst.CanvasSize = UDim2.new()
		inst.AutomaticCanvasSize = Enum.AutomaticSize.Y
		inst.ScrollingDirection = Enum.ScrollingDirection.Y
		inst.ScrollBarImageColor3 = Color3.new(1, 1, 1)
		inst.ScrollBarImageTransparency = 0.6
		inst.ElasticBehavior = Enum.ElasticBehavior.Never
	end
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	if binds then
		for prop, spec in pairs(binds) do
			if type(spec) == "table" then
				self.Theme:Bind(inst, prop, spec[1], spec[2])
			else
				if prop == "Font" then
					self.Theme:Bind(inst, prop, spec, fontT)
				else
					self.Theme:Bind(inst, prop, spec)
				end
			end
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- plain frame with a theme background color
function Prim:Frame(parent, props, colorKey, bopts)
	props = props or {}
	props.Parent = parent
	local f = self:New("Frame", props)
	if colorKey then
		self.Theme:Bind(f, "BackgroundColor3", colorKey, bopts)
	else
		f.BackgroundTransparency = 1
	end
	return f
end

-- text label bound to color / font / size keys
function Prim:Text(parent, props, colorKey, fontKey, sizeKey, class)
	props = props or {}
	props.Parent = parent
	local t = self:New(class or "TextLabel", props)
	self.Theme:Bind(t, "TextColor3", colorKey or "Text")
	self.Theme:Bind(t, "Font", fontKey or "FontBody", fontT)
	if type(sizeKey) == "number" then
		t.TextSize = sizeKey
	else
		self.Theme:Bind(t, "TextSize", sizeKey or "TextSize")
	end
	return t
end

-- invisible full-size click catcher
function Prim:Hitbox(parent, props)
	props = props or {}
	props.Parent = parent
	props.Size = props.Size or UDim2.fromScale(1, 1)
	props.BackgroundTransparency = 1
	props.ZIndex = props.ZIndex or (parent and parent:IsA("GuiObject") and parent.ZIndex + 5 or 5)
	local b = self:New("TextButton", props)
	return b
end

-- key: theme key (string), fixed offset (number) or "full" (pill/circle)
function Prim:Corner(inst, key)
	local c = Instance.new("UICorner")
	if key == "full" then
		c.CornerRadius = UDim.new(1, 0)
	elseif type(key) == "number" then
		c.CornerRadius = UDim.new(0, key)
	else
		self.Theme:Bind(c, "CornerRadius", key or "CornerRadius", udimT)
	end
	c.Parent = inst
	return c
end

-- thickness: number or theme key
function Prim:Stroke(inst, colorKey, thickness, opts)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Miter
	if type(thickness) == "string" then
		self.Theme:Bind(s, "Thickness", thickness)
	else
		s.Thickness = thickness or 1
	end
	self.Theme:Bind(s, "Color", colorKey or "Border", opts)
	s.Parent = inst
	return s
end

function Prim:Pad(inst, t, r, b, l)
	local p = Instance.new("UIPadding")
	t = t or 0
	p.PaddingTop = UDim.new(0, t)
	p.PaddingRight = UDim.new(0, r or t)
	p.PaddingBottom = UDim.new(0, b or t)
	p.PaddingLeft = UDim.new(0, l or r or t)
	p.Parent = inst
	return p
end

-- opts: Dir "V"|"H", Pad number, HA "Left"|"Center"|"Right", VA "Top"|"Center"|"Bottom"
function Prim:List(inst, opts)
	opts = opts or {}
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = opts.Dir == "H" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, opts.Pad or 0)
	if opts.HA then
		l.HorizontalAlignment = Enum.HorizontalAlignment[opts.HA]
	end
	if opts.VA then
		l.VerticalAlignment = Enum.VerticalAlignment[opts.VA]
	end
	l.Parent = inst
	return l
end

-- gradient bound to a theme gradient key. While enabled, the carrier's background renders white so the
-- gradient shows its real colors (Roblox multiplies them). opts.NoMask keeps the tinted (multiplied) look.
function Prim:Grad(inst, key, opts)
	local g = Instance.new("UIGradient")
	g.Parent = inst
	if not (opts and opts.NoMask) and inst:IsA("GuiObject") then
		self.Theme._gradMask[inst] = g
		g:GetPropertyChangedSignal("Enabled"):Connect(function()
			self.Theme:ReapplyProp(inst, "BackgroundColor3")
		end)
	end
	self.Theme:BindGradient(g, key, opts)
	return g
end

-- static gradient from explicit theme color keys (top -> bottom by default)
function Prim:Shade(inst, rotation, transparencyFrom, transparencyTo)
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 90
	g.Transparency = NumberSequence.new(transparencyFrom or 0, transparencyTo or 0)
	g.Parent = inst
	return g
end

function Prim:Icon(parent, name, size, colorKey, props)
	props = props or {}
	local icon = Icons.Create(self.Theme, name, size, colorKey, props)
	icon.Parent = parent
	return icon
end

function Prim:IconColor(icon, colorKey, tween)
	Icons.SetColor(self.Theme, icon, colorKey, tween)
end

-- hover/press state machine. cb(state) with state = "Idle" | "Hover" | "Press" | "Disabled"
function Prim:Hover(gui, cb, el)
	local hovered, pressed = false, false
	local function update()
		if el and el:IsDisabled() then
			cb("Disabled")
		elseif pressed then
			cb("Press")
		elseif hovered then
			cb("Hover")
		else
			cb("Idle")
		end
	end
	gui.MouseEnter:Connect(function()
		hovered = true
		update()
	end)
	gui.MouseLeave:Connect(function()
		hovered = false
		pressed = false
		update()
	end)
	gui.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			pressed = true
			update()
		end
	end)
	gui.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			pressed = false
			if i.UserInputType == Enum.UserInputType.Touch then
				hovered = false
			end
			update()
		end
	end)
	return update
end

-- click (mouse or tap), ignored while el is disabled
function Prim:OnClick(gui, fn, el)
	gui.Activated:Connect(function()
		if el and el:IsDisabled() then
			return
		end
		self:Sound("SoundClick")
		fn()
	end)
end

function Prim:Sound(key)
	if not self:T("SoundsEnabled") then
		return
	end
	local id = self:T(key)
	if not id or id == "" then
		return
	end
	pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Volume = self:T("SoundVolume")
		local ss = Util.Services.SoundService
		if ss and ss.PlayLocalSound then
			s.Parent = ss
			ss:PlayLocalSound(s)
			task.delay(3, function()
				s:Destroy()
			end)
		end
	end)
end

-- row height respecting the mobile touch target
function Prim:RowH(mult)
	local h = self:T("ElementHeight") * (mult or 1)
	if self.IsMobile then
		h = math.max(h, self:T("TouchTarget") / math.max(self.Scale, 0.1))
	end
	return math.floor(h + 0.5)
end

-- size for small hit targets (checkbox, swatch …) – grows on mobile
function Prim:Touch(px)
	if self.IsMobile then
		return math.max(px, math.floor(self:T("TouchTarget") * 0.6 / math.max(self.Scale, 0.1)))
	end
	return px
end

-- soft drop shadow made from stacked strokes (no assets)
function Prim:Shadow(inst, cornerKey, layers)
	if not self:T("ShadowEnabled") then
		return nil
	end
	local holder = Instance.new("Frame")
	holder.Name = "Shadow"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = math.max(inst.ZIndex - 1, 0)
	layers = layers or 4
	for i = 1, layers do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0.5, 0, 0.5, 2 + i)
		f.Size = UDim2.new(1, i * 4, 1, i * 4)
		f.ZIndex = holder.ZIndex
		local base = self:T("ShadowTransparency")
		self.Theme:Bind(f, "BackgroundColor3", "Shadow", { Alpha = 1 - (1 - base) * (0.5 / i) })
		local c = Instance.new("UICorner")
		if cornerKey then
			self.Theme:Bind(c, "CornerRadius", cornerKey, function(v)
				return UDim.new(0, v + i * 2)
			end)
		else
			c.CornerRadius = UDim.new(0, i * 2)
		end
		c.Parent = f
		f.Parent = holder
	end
	holder.Parent = inst.Parent
	-- follow the target
	local function sync()
		holder.Position = inst.Position
		holder.Size = inst.Size
		holder.AnchorPoint = inst.AnchorPoint
		holder.Visible = inst.Visible
	end
	sync()
	inst:GetPropertyChangedSignal("Position"):Connect(sync)
	inst:GetPropertyChangedSignal("Size"):Connect(sync)
	inst:GetPropertyChangedSignal("Visible"):Connect(sync)
	inst.Destroying:Connect(function()
		holder:Destroy()
	end)
	return holder
end

-- colored glow around a frame (stacked rounded frames behind it). Returns the holder.
function Prim:Glow(inst, colorKey, cornerKey, layers, strength)
	local holder = Instance.new("Frame")
	holder.Name = "Glow"
	holder.BackgroundTransparency = 1
	holder.ZIndex = math.max(inst.ZIndex - 1, 0)
	layers = layers or 4
	strength = strength or 0.35
	for i = 1, layers do
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.new(1, i * 4, 1, i * 4)
		f.ZIndex = holder.ZIndex
		self.Theme:Bind(f, "BackgroundColor3", colorKey or "Glow", { Alpha = 1 - strength / (i * 1.6) })
		local c = Instance.new("UICorner")
		if cornerKey then
			self.Theme:Bind(c, "CornerRadius", cornerKey, function(v)
				return UDim.new(0, v + i * 2)
			end)
		else
			c.CornerRadius = UDim.new(0, i * 2)
		end
		c.Parent = f
		f.Parent = holder
	end
	holder.Parent = inst.Parent
	local function sync()
		holder.Position = inst.Position
		holder.Size = inst.Size
		holder.AnchorPoint = inst.AnchorPoint
		holder.Visible = inst.Visible
	end
	sync()
	inst:GetPropertyChangedSignal("Position"):Connect(sync)
	inst:GetPropertyChangedSignal("Size"):Connect(sync)
	inst:GetPropertyChangedSignal("Visible"):Connect(sync)
	inst.Destroying:Connect(function()
		holder:Destroy()
	end)
	return holder
end

-- background texture (theme: BackgroundTexture / TextureTransparency / BackgroundImage)
function Prim:Texture(inst, colorKey)
	local kind = self:T("BackgroundTexture")
	local holder = Instance.new("Frame")
	holder.Name = "Texture"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ClipsDescendants = true
	holder.ZIndex = inst.ZIndex
	holder.Parent = inst
	local img = self:New("ImageLabel", {
		Parent = holder,
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = inst.ZIndex,
	})
	self.Theme:Bind(img, "Image", "BackgroundImage")
	self.Theme:Bind(img, "ImageTransparency", "BackgroundImageTransparency")
	if kind == "None" then
		return holder
	end
	local spacing = math.max(2, self:T("TextureSpacing"))
	-- textures are generated once for a generous area (window can be resized up to ~1.4x)
	local w = math.floor(self:T("WindowWidth") * 1.4)
	local h = math.floor(self:T("WindowHeight") * 1.4)
	local function line(x, y, sw, sh, rot)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(sw, sh)
		f.Rotation = rot or 0
		f.ZIndex = inst.ZIndex
		self.Theme:Bind(f, "BackgroundColor3", colorKey or "Highlight", function(v)
			return v
		end)
		self.Theme:Bind(f, "BackgroundTransparency", "TextureTransparency")
		f.Parent = holder
	end
	if kind == "Grid" then
		local step = spacing * 2
		for x = 0, w, step do
			line(x, 0, 1, h)
		end
		for y = 0, h, step do
			line(0, y, w, 1)
		end
	elseif kind == "Scanlines" then
		for y = 0, h, spacing do
			line(0, y, w, 1)
		end
	elseif kind == "Diagonal" then
		local step = spacing * 3
		for x = -h, w, step do
			line(x + h / 2, h / 2, h * 1.5, 1, -45)
		end
	end
	return holder
end

-- tooltip on hover (desktop) / long-press on non-pinnable elements (touch)
function Prim:Tooltip(gui, el)
	local r = self.Renderer
	local thread
	gui.MouseEnter:Connect(function()
		if not el.Tooltip or el.Tooltip == "" then
			return
		end
		thread = task.delay(0.45, function()
			thread = nil
			if r.TooltipView and gui.Parent then
				r.TooltipView:Show(el.Tooltip, gui)
			end
		end)
	end)
	gui.MouseLeave:Connect(function()
		if thread then
			pcall(task.cancel, thread)
			thread = nil
		end
		if r.TooltipView then
			r.TooltipView:Hide()
		end
	end)
end

-- convert an absolute screen position into UI-root space (accounts for UIScale)
function Prim:ToRoot(v)
	local s = self.Library.CurrentScale or 1
	local rootPos = self.Library.Root.AbsolutePosition
	return Vector2.new((v.X - rootPos.X) / s, (v.Y - rootPos.Y) / s)
end

-- absolute rect of a gui in root space
function Prim:RectOf(gui)
	local s = self.Library.CurrentScale or 1
	local p = self:ToRoot(gui.AbsolutePosition)
	return p, gui.AbsoluteSize / s
end

-- place a floating frame under (or above) an anchor, clamped to the screen
function Prim:PlaceNear(frame, anchor, width, height, gap)
	local p, s = self:RectOf(anchor)
	local screen = self.Library:ScreenSize()
	gap = gap or 4
	local x = p.X
	local y = p.Y + s.Y + gap
	if y + height > screen.Y - 8 then
		y = p.Y - height - gap
	end
	x = Util.Clamp(x, 8, math.max(8, screen.X - width - 8))
	y = Util.Clamp(y, 8, math.max(8, screen.Y - height - 8))
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(width, height)
end

function Prim:OpenOverlay(frame, onClose)
	return self.Renderer:PushOverlay(frame, onClose)
end

function Prim:CloseOverlay(entry)
	if entry then
		self.Renderer:PopOverlay(entry)
	else
		self.Renderer:CloseOverlays()
	end
end

-- user name / avatar helpers (branding keys fall back to the LocalPlayer)
function Prim:Username()
	local u = self:T("Username")
	if u and u ~= "" then
		return u
	end
	local lp = Util.LocalPlayer()
	return lp and lp.DisplayName or "user"
end

function Prim:Avatar()
	local a = self:T("AvatarImage")
	if a and a ~= "" then
		return a
	end
	local lp = Util.LocalPlayer()
	local players = Util.Services.Players
	if lp and players then
		local ok, url = pcall(function()
			return players:GetUserThumbnailAsync(lp.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok then
			return url
		end
	end
	return ""
end

-- avatar circle (image + initial fallback)
function Prim:AvatarCircle(parent, size, props)
	props = props or {}
	local holder = self:Frame(parent, {
		Size = UDim2.fromOffset(size, size),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Name = "Avatar",
	}, "ElementActive")
	self:Corner(holder, "full")
	local initial = self:Text(holder, {
		Size = UDim2.fromScale(1, 1),
		Text = string.upper(string.sub(self:Username(), 1, 1)),
		TextXAlignment = Enum.TextXAlignment.Center,
	}, "Accent", "FontTitle", "TitleSize")
	local img = self:New("ImageLabel", { Parent = holder, Size = UDim2.fromScale(1, 1), Image = self:Avatar() })
	self:Corner(img, "full")
	initial.Visible = img.Image == ""
	if props.Stroke then
		self:Stroke(holder, props.Stroke, 1.5)
	end
	return holder
end

-- logo: image if LogoImage is set, else LogoText
function Prim:Logo(parent, props, colorKey, sizeKey)
	props = props or {}
	local img = self:T("LogoImage")
	if img and img ~= "" then
		props.Parent = parent
		props.Image = Util.HexToColor and (img:match("^%d+$") and "rbxassetid://" .. img or img)
		props.ScaleType = Enum.ScaleType.Fit
		local i = self:New("ImageLabel", props)
		return i
	end
	props.Text = self:T("LogoText")
	local t = self:Text(parent, props, colorKey or "Accent", "FontTitle", sizeKey or "TitleSize")
	self.Theme:Bind(t, "Text", "LogoText")
	return t
end

return Prim
