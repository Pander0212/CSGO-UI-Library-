--!nocheck
--[[
	Minimal Roblox API mock used to RUN the bundled library outside Roblox (tests + screenshots).
	Datatypes and Instances are userdata (newproxy) with a __type metatable field, exactly like
	Roblox values, so typeof()/type() behave the same. Implements the Instance tree, services,
	a virtual-time task scheduler, executor file functions and a JSON dumper for the GUI tree.
	Not a Roblox replacement – just enough to execute every code path of the UI.
]]
MOCK = { Clock = 0, Warnings = {}, Viewport = { 1600, 900 } }

local DATA = setmetatable({}, { __mode = "k" })
local TYPES = setmetatable({}, { __mode = "k" })
local function D(u)
	return DATA[u]
end
MOCK.D = D
-- Luau ignores __type on newproxy() userdata, so typeof is routed through a registry
local rawtypeof = typeof
function typeof(v)
	return TYPES[v] or rawtypeof(v)
end

-- creates a constructor for a userdata type: fields per value, methods / operators shared
local function makeType(name, methods, ops, getter, setter)
	return function(data)
		local u = newproxy(true)
		local mt = getmetatable(u)
		mt.__type = name
		mt.__index = function(self, k)
			local v = data[k]
			if v ~= nil then
				return v
			end
			local m = methods[k]
			if m ~= nil then
				return m
			end
			if getter then
				return getter(self, data, k)
			end
			return nil
		end
		mt.__newindex = function(self, k, v)
			if setter then
				setter(self, data, k, v)
			else
				error(name .. "." .. tostring(k) .. " cannot be assigned to")
			end
		end
		for k, f in pairs(ops) do
			mt[k] = f
		end
		DATA[u] = data
		TYPES[u] = name
		return u
	end
end

function warn(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	table.insert(MOCK.Warnings, table.concat(parts, " "))
end

---------------------------------------------------------------- Vector2
local V2m, V2o = {}, {}
local newV2 = makeType("Vector2", V2m, V2o, function(_, d, k)
	if k == "Magnitude" then
		return math.sqrt(d.X * d.X + d.Y * d.Y)
	elseif k == "Unit" then
		local m = math.sqrt(d.X * d.X + d.Y * d.Y)
		return Vector2.new(d.X / m, d.Y / m)
	end
end)
Vector2 = {}
function Vector2.new(x, y)
	return newV2({ X = x or 0, Y = y or 0 })
end
V2o.__add = function(a, b)
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
V2o.__sub = function(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
V2o.__mul = function(a, b)
	if type(a) == "number" then
		return Vector2.new(a * b.X, a * b.Y)
	elseif type(b) == "number" then
		return Vector2.new(a.X * b, a.Y * b)
	end
	return Vector2.new(a.X * b.X, a.Y * b.Y)
end
V2o.__div = function(a, b)
	if type(b) == "number" then
		return Vector2.new(a.X / b, a.Y / b)
	end
	return Vector2.new(a.X / b.X, a.Y / b.Y)
end
V2o.__unm = function(a)
	return Vector2.new(-a.X, -a.Y)
end
V2o.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2o.__tostring = function(a)
	return a.X .. ", " .. a.Y
end
function V2m.Lerp(a, b, t)
	return a + (b - a) * t
end
Vector2.zero = Vector2.new(0, 0)

---------------------------------------------------------------- Vector3
local V3m, V3o = {}, {}
local newV3 = makeType("Vector3", V3m, V3o, function(_, d, k)
	if k == "Magnitude" then
		return math.sqrt(d.X * d.X + d.Y * d.Y + d.Z * d.Z)
	elseif k == "Unit" then
		local m = math.sqrt(d.X * d.X + d.Y * d.Y + d.Z * d.Z)
		return Vector3.new(d.X / m, d.Y / m, d.Z / m)
	end
end)
Vector3 = {}
function Vector3.new(x, y, z)
	return newV3({ X = x or 0, Y = y or 0, Z = z or 0 })
end
function V3m.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3m.Cross(a, b)
	return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3m.Lerp(a, b, t)
	return a + (b - a) * t
end
V3o.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3o.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3o.__mul = function(a, b)
	if type(a) == "number" then
		return Vector3.new(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3o.__div = function(a, b)
	if type(b) == "number" then
		return Vector3.new(a.X / b, a.Y / b, a.Z / b)
	end
	return Vector3.new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3o.__unm = function(a)
	return Vector3.new(-a.X, -a.Y, -a.Z)
end
V3o.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

---------------------------------------------------------------- CFrame (rotation matrix + position)
local CFm, CFo = {}, {}
local newCF = makeType("CFrame", CFm, CFo, function(_, d, k)
	if k == "Position" or k == "p" then
		return d.pos
	elseif k == "X" then
		return d.pos.X
	elseif k == "Y" then
		return d.pos.Y
	elseif k == "Z" then
		return d.pos.Z
	elseif k == "LookVector" then
		return Vector3.new(-d.r[3], -d.r[6], -d.r[9])
	end
end)
CFrame = {}
local function mkcf(px, py, pz, r)
	return newCF({ pos = Vector3.new(px, py, pz), r = r or { 1, 0, 0, 0, 1, 0, 0, 0, 1 } })
end
local function mulR(a, b)
	local r = {}
	for i = 0, 2 do
		for j = 0, 2 do
			local s = 0
			for k = 0, 2 do
				s += a[i * 3 + k + 1] * b[k * 3 + j + 1]
			end
			r[i * 3 + j + 1] = s
		end
	end
	return r
end
local function mulRV(r, v)
	return Vector3.new(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z)
end
function CFrame.lookAt(pos, target)
	local f = (target - pos).Unit
	local right = f:Cross(Vector3.new(0, 1, 0)).Unit
	local u = right:Cross(f)
	return mkcf(pos.X, pos.Y, pos.Z, { right.X, u.X, -f.X, right.Y, u.Y, -f.Y, right.Z, u.Z, -f.Z })
end
function CFrame.new(a, b, c)
	if a == nil then
		return mkcf(0, 0, 0)
	end
	if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
		return CFrame.lookAt(a, b)
	end
	if typeof(a) == "Vector3" then
		return mkcf(a.X, a.Y, a.Z)
	end
	return mkcf(a, b, c)
end
function CFrame.Angles(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local X = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Y = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Z = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return mkcf(0, 0, 0, mulR(mulR(X, Y), Z))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFo.__mul = function(a, b)
	local da = D(a)
	if typeof(b) == "Vector3" then
		return mulRV(da.r, b) + da.pos
	end
	local db = D(b)
	local p = mulRV(da.r, db.pos) + da.pos
	return mkcf(p.X, p.Y, p.Z, mulR(da.r, db.r))
end
CFo.__add = function(a, v)
	local d = D(a)
	return mkcf(d.pos.X + v.X, d.pos.Y + v.Y, d.pos.Z + v.Z, d.r)
end
CFo.__sub = function(a, v)
	local d = D(a)
	return mkcf(d.pos.X - v.X, d.pos.Y - v.Y, d.pos.Z - v.Z, d.r)
end
function CFm.Inverse(a)
	local d = D(a)
	local r = d.r
	local t = { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
	local p = -mulRV(t, d.pos)
	return mkcf(p.X, p.Y, p.Z, t)
end
function CFm.PointToObjectSpace(a, v)
	return CFm.Inverse(a) * v
end
function CFm.PointToWorldSpace(a, v)
	return a * v
end
function CFm.GetComponents(a)
	local d = D(a)
	local r = d.r
	return d.pos.X, d.pos.Y, d.pos.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end

---------------------------------------------------------------- Color3
local C3m, C3o = {}, {}
local newC3 = makeType("Color3", C3m, C3o)
Color3 = {}
function Color3.new(r, g, b)
	return newC3({ R = r or 0, G = g or 0, B = b or 0 })
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	h = h % 1
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then
		return Color3.new(v, t, p)
	elseif i == 1 then
		return Color3.new(q, v, p)
	elseif i == 2 then
		return Color3.new(p, v, t)
	elseif i == 3 then
		return Color3.new(p, q, v)
	elseif i == 4 then
		return Color3.new(t, p, v)
	end
	return Color3.new(v, p, q)
end
function Color3.fromHex(s)
	s = s:gsub("#", "")
	return Color3.fromRGB(tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16))
end
function C3m.ToHSV(c)
	local r, g, b = c.R, c.G, c.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h = h / 6
	end
	return h, mx == 0 and 0 or d / mx, mx
end
Color3.toHSV = C3m.ToHSV
function C3m.Lerp(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3m.ToHex(c)
	return string.format("%02x%02x%02x", c.R * 255, c.G * 255, c.B * 255)
end
C3o.__eq = function(a, b)
	return math.abs(a.R - b.R) < 1e-6 and math.abs(a.G - b.G) < 1e-6 and math.abs(a.B - b.B) < 1e-6
end
C3o.__tostring = function(c)
	return string.format("%g, %g, %g", c.R, c.G, c.B)
end

---------------------------------------------------------------- UDim / UDim2
local UDm, UDo = {}, {}
local newUD = makeType("UDim", UDm, UDo)
UDim = {}
function UDim.new(s, o)
	return newUD({ Scale = s or 0, Offset = o or 0 })
end
UDo.__add = function(a, b)
	return UDim.new(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDo.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
local UD2m, UD2o = {}, {}
local newUD2 = makeType("UDim2", UD2m, UD2o, function(_, d, k)
	if k == "Width" then
		return d.X
	elseif k == "Height" then
		return d.Y
	end
end)
UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	if typeof(xs) == "UDim" then
		return newUD2({ X = xs, Y = xo })
	end
	return newUD2({ X = UDim.new(xs or 0, xo or 0), Y = UDim.new(ys or 0, yo or 0) })
end
function UDim2.fromScale(x, y)
	return UDim2.new(x, 0, y, 0)
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x, 0, y)
end
UD2o.__add = function(a, b)
	return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
UD2o.__sub = function(a, b)
	return UDim2.new(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
UD2o.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
function UD2m.Lerp(a, b, t)
	return UDim2.new(a.X.Scale + (b.X.Scale - a.X.Scale) * t, a.X.Offset + (b.X.Offset - a.X.Offset) * t, a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t)
end

---------------------------------------------------------------- sequences / misc datatypes
local newCSK = makeType("ColorSequenceKeypoint", {}, {})
ColorSequenceKeypoint = { new = function(t, c)
	return newCSK({ Time = t, Value = c })
end }
local newCS = makeType("ColorSequence", {}, {})
ColorSequence = { new = function(a, b)
	if typeof(a) == "Color3" then
		return newCS({ Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) } })
	end
	return newCS({ Keypoints = a })
end }
local newNSK = makeType("NumberSequenceKeypoint", {}, {})
NumberSequenceKeypoint = { new = function(t, v)
	return newNSK({ Time = t, Value = v })
end }
local newNS = makeType("NumberSequence", {}, {})
NumberSequence = { new = function(a, b)
	if type(a) == "number" then
		return newNS({ Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) } })
	end
	return newNS({ Keypoints = a })
end }
local newTI = makeType("TweenInfo", {}, {})
TweenInfo = { new = function(t, s, d)
	return newTI({ Time = t or 1, EasingStyle = s, EasingDirection = d })
end }
local newNR = makeType("NumberRange", {}, {})
NumberRange = { new = function(a, b)
	return newNR({ Min = a, Max = b or a })
end }

---------------------------------------------------------------- Enum
local enums = {}
local newEI = makeType("EnumItem", {}, { __tostring = function(e)
	return "Enum." .. tostring(e.EnumType) .. "." .. e.Name
end })
local function makeEnum(enumName)
	local items = {}
	local u = newproxy(true)
	local mt = getmetatable(u)
	mt.__type = "Enum"
	TYPES[u] = "Enum"
	mt.__tostring = function()
		return enumName
	end
	mt.__index = function(self, itemName)
		if itemName == "GetEnumItems" then
			return function()
				local out = {}
				for _, it in pairs(items) do
					table.insert(out, it)
				end
				return out
			end
		end
		local it = items[itemName]
		if not it then
			it = newEI({ Name = itemName, EnumType = self, Value = 0 })
			items[itemName] = it
		end
		return it
	end
	return u
end
do
	local u = newproxy(true)
	local mt = getmetatable(u)
	mt.__type = "Enums"
	TYPES[u] = "Enums"
	mt.__index = function(_, enumName)
		local e = enums[enumName]
		if not e then
			e = makeEnum(enumName)
			enums[enumName] = e
		end
		return e
	end
	Enum = u
end

---------------------------------------------------------------- signals
local SIGm, CONNm = {}, {}
local newSig = makeType("RBXScriptSignal", SIGm, {})
local newConn = makeType("RBXScriptConnection", CONNm, {}, nil, function(_, d, k, v)
	d[k] = v
end)
local function newSignal()
	return newSig({ handlers = {} })
end
function SIGm.Connect(s, fn)
	local c = newConn({ Connected = true, fn = fn, sig = s })
	table.insert(D(s).handlers, c)
	return c
end
SIGm.connect = SIGm.Connect
function SIGm.Once(s, fn)
	local c
	c = s:Connect(function(...)
		c:Disconnect()
		fn(...)
	end)
	return c
end
function SIGm.Wait(s)
	local th = coroutine.running()
	s:Once(function(...)
		task.spawn(th, ...)
	end)
	return coroutine.yield()
end
function SIGm.Fire(s, ...)
	for _, c in ipairs(table.clone(D(s).handlers)) do
		if D(c).Connected then
			local ok, err = pcall(D(c).fn, ...)
			if not ok then
				warn("[mock] signal handler error: " .. tostring(err))
			end
		end
	end
end
function CONNm.Disconnect(c)
	local d = D(c)
	d.Connected = false
	local list = D(d.sig).handlers
	local i = table.find(list, c)
	if i then
		table.remove(list, i)
	end
end

---------------------------------------------------------------- task scheduler (virtual time)
local queue = {}
local cancelled = setmetatable({}, { __mode = "k" })
local function resume(th, ...)
	if cancelled[th] or coroutine.status(th) == "dead" then
		return
	end
	local ok, err = coroutine.resume(th, ...)
	if not ok then
		warn("[mock] thread error: " .. tostring(err) .. "\n" .. debug.traceback(th))
	end
end
local function schedule(at, th, args)
	table.insert(queue, { at = at, th = th, args = args })
end
task = {}
function task.spawn(f, ...)
	local th = type(f) == "thread" and f or coroutine.create(f)
	resume(th, ...)
	return th
end
function task.defer(f, ...)
	local th = type(f) == "thread" and f or coroutine.create(f)
	schedule(MOCK.Clock, th, table.pack(...))
	return th
end
function task.delay(t, f, ...)
	local th = type(f) == "thread" and f or coroutine.create(f)
	schedule(MOCK.Clock + (t or 0), th, table.pack(...))
	return th
end
function task.wait(t)
	t = t or 0.03
	local th = coroutine.running()
	schedule(MOCK.Clock + t, th, table.pack(t))
	return coroutine.yield()
end
function task.cancel(th)
	cancelled[th] = true
end
wait = task.wait
spawn = task.spawn
delay = task.delay
function tick()
	return MOCK.Clock
end

---------------------------------------------------------------- Instances
local Methods = {}
local EVENTS = {
	MouseEnter = true, MouseLeave = true, InputBegan = true, InputEnded = true, InputChanged = true,
	Activated = true, MouseButton1Down = true, MouseButton1Up = true, MouseButton1Click = true, MouseButton2Click = true,
	TouchTap = true, Focused = true, FocusLost = true, Changed = true, Destroying = true, ChildAdded = true,
	ChildRemoved = true, Completed = true, AncestryChanged = true, MouseWheelForward = true, MouseWheelBackward = true,
	RenderStepped = true, Heartbeat = true, Stepped = true, TouchPinch = true, TouchStarted = true, TouchEnded = true,
	PlayerAdded = true, PlayerRemoving = true, CharacterAdded = true,
}

local DEFAULTS = {
	GuiObject = {
		Size = UDim2.new(0, 100, 0, 100), Position = UDim2.new(), AnchorPoint = Vector2.new(0, 0),
		BackgroundColor3 = Color3.fromRGB(163, 162, 165), BackgroundTransparency = 0, BorderSizePixel = 1,
		BorderColor3 = Color3.fromRGB(27, 42, 53), Visible = true, ZIndex = 1, LayoutOrder = 0, Rotation = 0,
		ClipsDescendants = false, Active = false, Interactable = true, AutomaticSize = Enum.AutomaticSize.None,
	},
	Text = {
		Text = "Label", TextColor3 = Color3.fromRGB(27, 42, 53), TextSize = 14, TextTransparency = 0,
		TextWrapped = false, TextScaled = false, RichText = false, TextStrokeTransparency = 1,
		TextStrokeColor3 = Color3.new(0, 0, 0), PlaceholderText = "", PlaceholderColor3 = Color3.fromRGB(178, 178, 178),
		ClearTextOnFocus = true, TextEditable = true, AutoButtonColor = true, Font = Enum.Font.Legacy,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, TextTruncate = Enum.TextTruncate.None,
	},
	Image = { Image = "", ImageColor3 = Color3.new(1, 1, 1), ImageTransparency = 0, AutoButtonColor = true },
	ScrollingFrame = { CanvasSize = UDim2.new(0, 0, 2, 0), CanvasPosition = Vector2.new(0, 0), ScrollBarThickness = 12, ScrollBarImageTransparency = 0, ScrollBarImageColor3 = Color3.new(0, 0, 0) },
	UIStroke = { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0, Enabled = true, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual },
	UICorner = { CornerRadius = UDim.new(0, 8) },
	UIGradient = { Color = ColorSequence.new(Color3.new(1, 1, 1)), Transparency = NumberSequence.new(0), Rotation = 0, Offset = Vector2.new(0, 0), Enabled = true },
	UIGridLayout = { CellSize = UDim2.new(0, 100, 0, 100), CellPadding = UDim2.new(0, 5, 0, 5), SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = Enum.FillDirection.Horizontal },
	UIListLayout = { Padding = UDim.new(0, 0), FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Left, VerticalAlignment = Enum.VerticalAlignment.Top, SortOrder = Enum.SortOrder.LayoutOrder },
	UIPadding = { PaddingTop = UDim.new(), PaddingBottom = UDim.new(), PaddingLeft = UDim.new(), PaddingRight = UDim.new() },
	UIScale = { Scale = 1 },
	UISizeConstraint = { MinSize = Vector2.new(0, 0), MaxSize = Vector2.new(math.huge, math.huge) },
	ScreenGui = { Enabled = true, IgnoreGuiInset = false, DisplayOrder = 0, ResetOnSpawn = true },
	Part = { Size = Vector3.new(4, 1, 2), CFrame = CFrame.new(), Color = Color3.fromRGB(163, 162, 165), Transparency = 0, Anchored = false, CanCollide = true, Material = Enum.Material.Plastic },
	Camera = { CFrame = CFrame.new(), FieldOfView = 70 },
	NumberValue = { Value = 0 },
	Sound = { SoundId = "", Volume = 0.5 },
}
local GUI = {
	Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true, ImageButton = true,
	ScrollingFrame = true, ViewportFrame = true, CanvasGroup = true,
}
local TEXT = { TextLabel = true, TextButton = true, TextBox = true }
local IMAGE = { ImageLabel = true, ImageButton = true }
local ISA = {
	GuiObject = GUI, GuiButton = { TextButton = true, ImageButton = true }, GuiBase2d = GUI,
	UIBase = { UIStroke = true, UICorner = true, UIGradient = true, UIPadding = true, UIScale = true, UISizeConstraint = true, UIListLayout = true, UIGridLayout = true, UIAspectRatioConstraint = true },
	UIListLayout = { UIListLayout = true }, BasePart = { Part = true, MeshPart = true }, Sound = { Sound = true },
	ScreenGui = { ScreenGui = true }, LayerCollector = { ScreenGui = true },
	Script = {}, LocalScript = {}, ModuleScript = {}, ForceField = {},
}

local function instGet(self, d, k)
	if EVENTS[k] then
		local s = d.sig[k]
		if not s then
			s = newSignal()
			d.sig[k] = s
		end
		return s
	end
	if k == "AbsoluteSize" or k == "AbsolutePosition" then
		local pos, size = MOCK.Abs(self)
		return k == "AbsoluteSize" and size or pos
	end
	if k == "Position" and d.p.CFrame then
		return d.p.CFrame.Position
	end
	for _, c in ipairs(d.c) do
		if c.Name == k then
			return c
		end
	end
	return nil
end

local function instSet(self, d, k, v)
	local p = d.p
	if k == "Parent" then
		local old = p.Parent
		if old == v then
			return
		end
		if d.destroyed then
			error("The Parent property of " .. tostring(p.Name) .. " is locked")
		end
		if old then
			local list = D(old).c
			local i = table.find(list, self)
			if i then
				table.remove(list, i)
			end
		end
		p.Parent = v
		if v then
			table.insert(D(v).c, self)
		end
		return
	end
	if k == "Position" and p.CFrame and typeof(v) == "Vector3" then
		p.CFrame = CFrame.new(v)
		return
	end
	p[k] = v
	if d.psig[k] then
		d.psig[k]:Fire()
	end
	local ch = d.sig.Changed
	if ch then
		ch:Fire(p.ClassName == "NumberValue" and v or k)
	end
end

-- instance field reads go: props -> Methods -> events/children (getter)
local function newInstanceRaw(d)
	local u = newproxy(true)
	local mt = getmetatable(u)
	mt.__type = "Instance"
	mt.__index = function(self, k)
		local v = d.p[k]
		if v ~= nil then
			return v
		end
		local m = Methods[k]
		if m ~= nil then
			return m
		end
		return instGet(self, d, k)
	end
	mt.__newindex = function(self, k, v)
		instSet(self, d, k, v)
	end
	mt.__tostring = function()
		return tostring(d.p.Name)
	end
	DATA[u] = d
	TYPES[u] = "Instance"
	return u
end

local idCounter = 0
local function newInstance(className)
	idCounter += 1
	local props = { Name = className, ClassName = className }
	local function fill(t)
		for k, v in pairs(t) do
			props[k] = v
		end
	end
	if GUI[className] then
		fill(DEFAULTS.GuiObject)
	end
	if TEXT[className] then
		fill(DEFAULTS.Text)
		props.Text = className == "TextLabel" and "Label" or (className == "TextButton" and "Button" or "")
	end
	if IMAGE[className] then
		fill(DEFAULTS.Image)
	end
	if DEFAULTS[className] then
		fill(DEFAULTS[className])
	end
	return newInstanceRaw({ p = props, c = {}, sig = {}, psig = {}, attr = {}, id = idCounter })
end

function Methods.IsA(self, c)
	local cn = self.ClassName
	if cn == c or c == "Instance" then
		return true
	end
	local set = ISA[c]
	return set ~= nil and set[cn] == true
end
function Methods.GetChildren(self)
	return table.clone(D(self).c)
end
function Methods.GetDescendants(self)
	local out = {}
	local function walk(o)
		for _, c in ipairs(D(o).c) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function Methods.FindFirstChild(self, name, recursive)
	for _, c in ipairs(D(self).c) do
		if c.Name == name then
			return c
		end
		if recursive then
			local r = c:FindFirstChild(name, true)
			if r then
				return r
			end
		end
	end
	return nil
end
Methods.WaitForChild = function(self, name)
	return self:FindFirstChild(name)
end
function Methods.FindFirstChildOfClass(self, cn)
	for _, c in ipairs(D(self).c) do
		if c.ClassName == cn then
			return c
		end
	end
	return nil
end
function Methods.FindFirstChildWhichIsA(self, cn)
	for _, c in ipairs(D(self).c) do
		if c:IsA(cn) then
			return c
		end
	end
	return nil
end
function Methods.Destroy(self)
	local d = D(self)
	if d.destroyed then
		return
	end
	local ev = d.sig.Destroying
	if ev then
		ev:Fire()
	end
	for _, c in ipairs(table.clone(d.c)) do
		c:Destroy()
	end
	self.Parent = nil
	d.destroyed = true
	for _, s in pairs(d.sig) do
		D(s).handlers = {}
	end
end
function Methods.ClearAllChildren(self)
	for _, c in ipairs(table.clone(D(self).c)) do
		c:Destroy()
	end
end
function Methods.GetPropertyChangedSignal(self, prop)
	local d = D(self)
	if not d.psig[prop] then
		d.psig[prop] = newSignal()
	end
	return d.psig[prop]
end
function Methods.SetAttribute(self, k, v)
	D(self).attr[k] = v
end
function Methods.GetAttribute(self, k)
	return D(self).attr[k]
end
function Methods.Clone(self)
	local n = newInstance(self.ClassName)
	for k, v in pairs(D(self).p) do
		if k ~= "Parent" then
			D(n).p[k] = v
		end
	end
	for _, c in ipairs(D(self).c) do
		c:Clone().Parent = n
	end
	return n
end
function Methods.GetFullName(self)
	local parts = {}
	local o = self
	while o do
		table.insert(parts, 1, o.Name)
		o = o.Parent
	end
	return table.concat(parts, ".")
end
function Methods.ReleaseFocus() end
function Methods.CaptureFocus() end
function Methods.GetBoundingBox(self)
	local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in ipairs(self:GetDescendants()) do
		if d:IsA("BasePart") then
			local p, s = d.CFrame.Position, d.Size / 2
			mn = Vector3.new(math.min(mn.X, p.X - s.X), math.min(mn.Y, p.Y - s.Y), math.min(mn.Z, p.Z - s.Z))
			mx = Vector3.new(math.max(mx.X, p.X + s.X), math.max(mx.Y, p.Y + s.Y), math.max(mx.Z, p.Z + s.Z))
		end
	end
	return CFrame.new((mn + mx) / 2), mx - mn
end
function Methods.Play(self)
	local p = D(self).p
	if p.__target then
		for k, v in pairs(p.__props) do
			p.__target[k] = v
		end
	end
	local s = self.Completed
	task.defer(function()
		s:Fire(Enum.PlaybackState.Completed)
	end)
end
function Methods.Cancel() end
function Methods.Pause() end

Instance = {}
function Instance.new(className, parent)
	local i = newInstance(className)
	if parent then
		i.Parent = parent
	end
	return i
end

---------------------------------------------------------------- absolute layout for AbsoluteSize / AbsolutePosition reads
-- approximates Roblox layout: UDim2, AnchorPoint, UIPadding, UIListLayout, AutomaticSize, UIScale, CanvasPosition
local inset = Vector2.new(0, 36)
local function padOf(g, w, h)
	local p = g:FindFirstChildOfClass("UIPadding")
	if not p then
		return 0, 0, 0, 0
	end
	return p.PaddingTop.Scale * h + p.PaddingTop.Offset, p.PaddingRight.Scale * w + p.PaddingRight.Offset,
		p.PaddingBottom.Scale * h + p.PaddingBottom.Offset, p.PaddingLeft.Scale * w + p.PaddingLeft.Offset
end
local function guiKids(g)
	local out = {}
	for i, c in ipairs(D(g).c) do
		if c:IsA("GuiObject") and c.Visible then
			table.insert(out, { c, i })
		end
	end
	table.sort(out, function(a, b)
		if a[1].LayoutOrder ~= b[1].LayoutOrder then
			return a[1].LayoutOrder < b[1].LayoutOrder
		end
		return a[2] < b[2]
	end)
	local list = {}
	for _, e in ipairs(out) do
		table.insert(list, e[1])
	end
	return list
end
local measure
function measure(g, pw, ph, memo)
	local m = memo[g]
	if m then
		return m[1], m[2]
	end
	local s = g.Size
	local w = pw * s.X.Scale + s.X.Offset
	local h = ph * s.Y.Scale + s.Y.Offset
	local auto = g.AutomaticSize and g.AutomaticSize.Name or "None"
	if auto ~= "None" then
		local pt, pr, pb, pl = padOf(g, w, h)
		local cw, ch = 0, 0
		if g:IsA("TextLabel") or g:IsA("TextButton") or g:IsA("TextBox") then
			local text = g.Text ~= "" and g.Text or (g.PlaceholderText or "")
			local tw = #text * g.TextSize * 0.55
			cw, ch = tw, g.TextSize
			if g.TextWrapped and w - pl - pr > 0 then
				ch = math.ceil(tw / (w - pl - pr)) * g.TextSize * 1.15
			end
		end
		local list = g:FindFirstChildOfClass("UIListLayout")
		local horiz = list and list.FillDirection.Name == "Horizontal"
		local gap = list and list.Padding.Offset or 0
		local n = 0
		for _, k in ipairs(guiKids(g)) do
			local kw, kh = measure(k, w - pl - pr, h - pt - pb, memo)
			if list then
				n += 1
				if horiz then
					cw += kw + (n > 1 and gap or 0)
					ch = math.max(ch, kh)
				else
					ch += kh + (n > 1 and gap or 0)
					cw = math.max(cw, kw)
				end
			else
				cw = math.max(cw, k.Position.X.Offset + kw)
				ch = math.max(ch, k.Position.Y.Offset + kh)
			end
		end
		if auto == "X" or auto == "XY" then
			w = math.max(w, cw + pl + pr)
		end
		if auto == "Y" or auto == "XY" then
			h = math.max(h, ch + pt + pb)
		end
	end
	memo[g] = { w, h }
	return w, h
end
function MOCK.Abs(inst)
	local chain = {}
	local o = inst
	while o and not o:IsA("ScreenGui") and o.Parent do
		table.insert(chain, 1, o)
		o = o.Parent
	end
	local memo = {}
	local pos = Vector2.new(0, 0)
	local size = Vector2.new(MOCK.Viewport[1], MOCK.Viewport[2])
	local scale = 1
	local parent = nil
	for _, g in ipairs(chain) do
		if g:IsA("GuiObject") then
			local pt, pr, pb, pl = 0, 0, 0, 0
			if parent then
				pt, pr, pb, pl = padOf(parent, size.X, size.Y)
			end
			local cw, chh = size.X - pl - pr, size.Y - pt - pb
			local w, h = measure(g, cw, chh, memo)
			local list = parent and parent:FindFirstChildOfClass("UIListLayout")
			local x, y
			if list then
				local horiz = list.FillDirection.Name == "Horizontal"
				local gap = list.Padding.Offset
				local cur, total = 0, 0
				local kids = guiKids(parent)
				for i, k in ipairs(kids) do
					local kw, kh = measure(k, cw, chh, memo)
					total += (horiz and kw or kh) + (i > 1 and gap or 0)
				end
				local before = 0
				for i, k in ipairs(kids) do
					if k == g then
						break
					end
					local kw, kh = measure(k, cw, chh, memo)
					before += (horiz and kw or kh) + gap
				end
				local _ = cur
				if horiz then
					local ha = list.HorizontalAlignment.Name
					local start = ha == "Center" and (cw - total) / 2 or (ha == "Right" and cw - total or 0)
					x = pl + start + before
					local va = list.VerticalAlignment.Name
					y = pt + (va == "Center" and (chh - h) / 2 or (va == "Bottom" and chh - h or 0))
				else
					local va = list.VerticalAlignment.Name
					local start = va == "Center" and (chh - total) / 2 or (va == "Bottom" and chh - total or 0)
					y = pt + start + before
					local ha = list.HorizontalAlignment.Name
					x = pl + (ha == "Center" and (cw - w) / 2 or (ha == "Right" and cw - w or 0))
				end
			else
				local p, a = g.Position, g.AnchorPoint
				x = pl + cw * p.X.Scale + p.X.Offset - a.X * w
				y = pt + chh * p.Y.Scale + p.Y.Offset - a.Y * h
			end
			if parent and parent:IsA("ScrollingFrame") then
				x -= parent.CanvasPosition.X
				y -= parent.CanvasPosition.Y
			end
			pos = Vector2.new(pos.X + x * scale, pos.Y + y * scale)
			local sc = g:FindFirstChildOfClass("UIScale")
			size = Vector2.new(w, h)
			if sc then
				scale *= sc.Scale
			end
			parent = g
		end
	end
	return pos, size * scale
end

local newInput = makeType("InputObject", {}, {}, nil, function(_, d, k, v)
	d[k] = v
end)

---------------------------------------------------------------- services
local function service(name, extra)
	local s = newInstance(name)
	for k, v in pairs(extra or {}) do
		D(s).p[k] = v
	end
	return s
end

local Players = service("Players")
local LocalPlayer = service("Player", { Name = "nova_user", DisplayName = "NovaUser", UserId = 1, Character = nil })
D(Players).p.LocalPlayer = LocalPlayer
Methods.GetNetworkPing = function()
	return 0.042
end
Methods.GetUserThumbnailAsync = function()
	return ""
end
local PlayerGui = Instance.new("PlayerGui")
PlayerGui.Name = "PlayerGui"
PlayerGui.Parent = LocalPlayer

local RunService = service("RunService")
local UIS = service("UserInputService", { TouchEnabled = MOCK.TouchEnabled, KeyboardEnabled = MOCK.KeyboardEnabled, MouseEnabled = true })
Methods.GetFocusedTextBox = function()
	return nil
end
Methods.GetMouseLocation = function()
	return Vector2.new(0, 0)
end
local TweenService = service("TweenService")
Methods.Create = function(self, target, info, props)
	if self.ClassName ~= "TweenService" then
		error("Create called on non TweenService")
	end
	local tw = newInstance("Tween")
	D(tw).p.__target = target
	D(tw).p.__props = props
	return tw
end
local HttpService = service("HttpService")
local GuiService = service("GuiService")
Methods.GetGuiInset = function()
	return inset, Vector2.new(0, 0)
end
local TextService = service("TextService")
Methods.GetTextSize = function(_, text, size)
	return Vector2.new(#tostring(text) * size * 0.55, size)
end
local CoreGui = service("CoreGui")
local Stats = service("Stats")
local SoundService = service("SoundService")
Methods.PlayLocalSound = function() end
local Workspace = service("Workspace")
local Camera = Instance.new("Camera")
D(Workspace).p.CurrentCamera = Camera
D(Camera).p.ViewportSize = Vector2.new(MOCK.Viewport[1], MOCK.Viewport[2])

local services = {
	Players = Players, RunService = RunService, UserInputService = UIS, TweenService = TweenService,
	HttpService = HttpService, GuiService = GuiService, TextService = TextService, CoreGui = CoreGui,
	Stats = Stats, SoundService = SoundService, Workspace = Workspace,
}
game = service("DataModel", { PlaceId = 123456, GameId = 1 })
Methods.GetService = function(_, name)
	local s = services[name]
	if not s then
		error("unknown service " .. tostring(name))
	end
	return s
end
workspace = Workspace

function MOCK.SetViewport(w, h, touch)
	MOCK.Viewport = { w, h }
	D(Camera).p.ViewportSize = Vector2.new(w, h)
	D(UIS).p.TouchEnabled = touch == true
	D(UIS).p.KeyboardEnabled = not touch
end

---------------------------------------------------------------- JSON
local function encode(v, out)
	local t = type(v)
	if t == "nil" then
		table.insert(out, "null")
	elseif t == "boolean" then
		table.insert(out, tostring(v))
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			table.insert(out, "null")
		elseif v == math.floor(v) and math.abs(v) < 1e15 then
			table.insert(out, string.format("%d", v))
		else
			table.insert(out, string.format("%.6g", v))
		end
	elseif t == "string" then
		table.insert(out, '"' .. v:gsub('[%c"\\]', function(c)
			local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
			return map[c] or string.format("\\u%04x", string.byte(c))
		end) .. '"')
	elseif t == "table" then
		local n = #v
		local isArray = n > 0 or next(v) == nil
		if isArray then
			for k in pairs(v) do
				if type(k) ~= "number" then
					isArray = false
					break
				end
			end
		end
		if isArray then
			table.insert(out, "[")
			for i = 1, n do
				if i > 1 then
					table.insert(out, ",")
				end
				encode(v[i], out)
			end
			table.insert(out, "]")
		else
			table.insert(out, "{")
			local first = true
			local keys = {}
			for k in pairs(v) do
				table.insert(keys, tostring(k))
			end
			table.sort(keys)
			for _, k in ipairs(keys) do
				local val = v[k]
				if val == nil then
					val = v[tonumber(k)]
				end
				if not first then
					table.insert(out, ",")
				end
				first = false
				encode(k, out)
				table.insert(out, ":")
				encode(val, out)
			end
			table.insert(out, "}")
		end
	else
		error("cannot JSON encode " .. typeof(v))
	end
end
function MOCK.JSONEncode(v)
	local out = {}
	encode(v, out)
	return table.concat(out)
end
function MOCK.JSONDecode(s)
	local i = 1
	local function ws()
		i = s:find("[^%s]", i) or #s + 1
	end
	local parse
	local function str()
		i += 1
		local buf = {}
		while true do
			local c = s:sub(i, i)
			if c == "" then
				error("unterminated string")
			end
			if c == '"' then
				i += 1
				break
			end
			if c == "\\" then
				local n = s:sub(i + 1, i + 1)
				local map = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f" }
				if n == "u" then
					table.insert(buf, utf8.char(tonumber(s:sub(i + 2, i + 5), 16)))
					i += 6
				else
					table.insert(buf, map[n] or n)
					i += 2
				end
			else
				table.insert(buf, c)
				i += 1
			end
		end
		return table.concat(buf)
	end
	function parse()
		ws()
		local c = s:sub(i, i)
		if c == "{" then
			i += 1
			local t = {}
			ws()
			if s:sub(i, i) == "}" then
				i += 1
				return t
			end
			while true do
				ws()
				local k = str()
				ws()
				assert(s:sub(i, i) == ":", "expected :")
				i += 1
				t[k] = parse()
				ws()
				local d = s:sub(i, i)
				i += 1
				if d == "}" then
					return t
				end
				assert(d == ",", "expected , in object")
			end
		elseif c == "[" then
			i += 1
			local t = {}
			ws()
			if s:sub(i, i) == "]" then
				i += 1
				return t
			end
			while true do
				table.insert(t, parse())
				ws()
				local d = s:sub(i, i)
				i += 1
				if d == "]" then
					return t
				end
				assert(d == ",", "expected , in array")
			end
		elseif c == '"' then
			return str()
		elseif s:sub(i, i + 3) == "true" then
			i += 4
			return true
		elseif s:sub(i, i + 4) == "false" then
			i += 5
			return false
		elseif s:sub(i, i + 3) == "null" then
			i += 4
			return nil
		else
			local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
			if not num or num == "" then
				error("unexpected character '" .. c .. "' at " .. i)
			end
			i += #num
			return tonumber(num)
		end
	end
	local r = parse()
	return r
end
Methods.JSONEncode = function(_, v)
	return MOCK.JSONEncode(v)
end
Methods.JSONDecode = function(_, s)
	return MOCK.JSONDecode(s)
end

---------------------------------------------------------------- executor environment
MOCK.Files = {}
MOCK.Folders = {}
MOCK.Clipboard = nil
local genv = {}
function getgenv()
	return genv
end
function gethui()
	return CoreGui
end
function writefile(p, c)
	MOCK.Files[p] = c
end
function readfile(p)
	local c = MOCK.Files[p]
	if c == nil then
		error("file not found " .. p)
	end
	return c
end
function isfile(p)
	return MOCK.Files[p] ~= nil
end
function isfolder(p)
	return MOCK.Folders[p] == true
end
function makefolder(p)
	MOCK.Folders[p] = true
end
function delfile(p)
	MOCK.Files[p] = nil
end
function listfiles(folder)
	local out = {}
	for p in pairs(MOCK.Files) do
		if p:sub(1, #folder + 1) == folder .. "/" and not p:sub(#folder + 2):find("/") then
			table.insert(out, p)
		end
	end
	return out
end
function setclipboard(s)
	MOCK.Clipboard = s
end
for _, n in ipairs({ "writefile", "readfile", "isfile", "isfolder", "makefolder", "delfile", "listfiles", "setclipboard", "gethui" }) do
	genv[n] = _G and _G[n] or getfenv()[n]
end
shared = {}

---------------------------------------------------------------- simulation helpers
function MOCK.Step(dt)
	dt = dt or 1 / 30
	MOCK.Clock += dt
	-- run due tasks (sorted)
	local guard = 0
	while true do
		guard += 1
		if guard > 10000 then
			warn("[mock] scheduler guard hit")
			break
		end
		local bestIdx, best
		for idx, item in ipairs(queue) do
			if item.at <= MOCK.Clock and (not best or item.at < best.at) then
				best, bestIdx = item, idx
			end
		end
		if not best then
			break
		end
		table.remove(queue, bestIdx)
		resume(best.th, table.unpack(best.args, 1, best.args.n))
	end
	RunService.RenderStepped:Fire(dt)
	RunService.Heartbeat:Fire(dt)
end

function MOCK.Advance(seconds, dt)
	dt = dt or 1 / 30
	local n = math.ceil(seconds / dt)
	for _ = 1, n do
		MOCK.Step(dt)
	end
end

local function inputObject(kind, extra)
	local d = { UserInputType = Enum.UserInputType[kind], KeyCode = Enum.KeyCode.Unknown, Position = Vector3.new(0, 0, 0), Delta = Vector3.new(0, 0, 0), UserInputState = Enum.UserInputState.Begin }
	for k, v in pairs(extra or {}) do
		d[k] = v
	end
	return newInput(d)
end
MOCK.Input = inputObject

-- simulate a click on a GuiButton (fires the events the library listens to)
function MOCK.Click(gui, x)
	local pos
	if x then
		pos = Vector3.new(x, 0, 0)
	else
		local p, s = MOCK.Abs(gui)
		pos = Vector3.new(p.X + s.X / 2, p.Y + s.Y / 2 - 36, 0)
	end
	local io = inputObject("MouseButton1", { Position = pos })
	gui.MouseEnter:Fire()
	gui.InputBegan:Fire(io)
	UIS.InputBegan:Fire(io, false)
	gui.MouseButton1Down:Fire()
	UIS.InputEnded:Fire(io, false)
	gui.InputEnded:Fire(io)
	gui.Activated:Fire(io)
	gui.MouseButton1Click:Fire()
	gui.MouseLeave:Fire()
end

function MOCK.Hover(gui)
	gui.MouseEnter:Fire()
end

function MOCK.Key(name)
	local io = inputObject("Keyboard", { KeyCode = Enum.KeyCode[name] })
	UIS.InputBegan:Fire(io, false)
	UIS.InputEnded:Fire(io, false)
end

function MOCK.Find(root, pred)
	for _, d in ipairs(root:GetDescendants()) do
		if pred(d) then
			return d
		end
	end
	return nil
end

function MOCK.FindText(root, text, class)
	return MOCK.Find(root, function(d)
		return (class == nil or d.ClassName == class) and (d.ClassName == "TextButton" or d.ClassName == "TextLabel" or d.ClassName == "TextBox") and d.Text == text
	end)
end

---------------------------------------------------------------- dump
local DUMP_PROPS = {
	"Name", "Size", "Position", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "Visible", "ZIndex",
	"LayoutOrder", "Rotation", "ClipsDescendants", "AutomaticSize", "Text", "TextColor3", "TextSize", "Font",
	"TextXAlignment", "TextYAlignment", "TextTransparency", "TextWrapped", "TextScaled", "TextTruncate",
	"TextStrokeTransparency", "TextStrokeColor3", "PlaceholderText", "PlaceholderColor3", "Image", "ImageColor3", "ImageTransparency",
	"CanvasPosition", "AutomaticCanvasSize", "ScrollBarThickness", "ScrollBarImageColor3",
	"CornerRadius", "Color", "Thickness", "Transparency", "Enabled", "ApplyStrokeMode", "Rotation", "Offset",
	"Padding", "FillDirection", "HorizontalAlignment", "VerticalAlignment", "SortOrder",
	"PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight", "Scale", "MinSize", "MaxSize",
	"CellSize", "CellPadding", "CFrame", "FieldOfView", "Ambient", "LightColor", "LightDirection", "IgnoreGuiInset",
}
local function ser(v)
	local t = typeof(v)
	if t == "UDim2" then
		return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset }
	elseif t == "UDim" then
		return { v.Scale, v.Offset }
	elseif t == "Vector2" then
		return { v.X, v.Y }
	elseif t == "Vector3" then
		return { v.X, v.Y, v.Z }
	elseif t == "Color3" then
		return { math.floor(v.R * 255 + 0.5), math.floor(v.G * 255 + 0.5), math.floor(v.B * 255 + 0.5) }
	elseif t == "EnumItem" then
		return v.Name
	elseif t == "ColorSequence" then
		local out = {}
		for _, k in ipairs(v.Keypoints) do
			table.insert(out, { k.Time, math.floor(k.Value.R * 255 + 0.5), math.floor(k.Value.G * 255 + 0.5), math.floor(k.Value.B * 255 + 0.5) })
		end
		return { __cs = out }
	elseif t == "NumberSequence" then
		local out = {}
		for _, k in ipairs(v.Keypoints) do
			table.insert(out, { k.Time, k.Value })
		end
		return { __ns = out }
	elseif t == "CFrame" then
		return { v:GetComponents() }
	elseif t == "number" or t == "string" or t == "boolean" then
		return v
	end
	return nil
end
local SKIP = { Sound = true, Camera = false, NumberValue = true, Tween = true, Model = false }
local function dumpInst(inst)
	if SKIP[inst.ClassName] then
		return nil
	end
	local p = D(inst).p
	local props = {}
	for _, k in ipairs(DUMP_PROPS) do
		local v = p[k]
		if v ~= nil then
			props[k] = ser(v)
		end
	end
	if inst.ClassName == "Part" then
		props.Size = ser(p.Size)
		props.Color = ser(p.Color)
		props.Transparency = p.Transparency
	end
	if inst.ClassName == "ViewportFrame" and p.CurrentCamera then
		local cam = p.CurrentCamera
		props.Camera = { CFrame = ser(cam.CFrame), FieldOfView = cam.FieldOfView }
	end
	local kids = {}
	for _, c in ipairs(D(inst).c) do
		local d = dumpInst(c)
		if d then
			table.insert(kids, d)
		end
	end
	return { c = inst.ClassName, p = props, k = kids }
end
function MOCK.Dump(name, root)
	print("@@DUMP " .. name .. " " .. MOCK.Viewport[1] .. "x" .. MOCK.Viewport[2] .. "@@" .. MOCK.JSONEncode(dumpInst(root)))
end
function MOCK.FlushWarnings()
	for _, w in ipairs(MOCK.Warnings) do
		print("@@WARN@@" .. w)
	end
	MOCK.Warnings = {}
end
MOCK.CoreGui = CoreGui
MOCK.UIS = UIS
MOCK.RunService = RunService
