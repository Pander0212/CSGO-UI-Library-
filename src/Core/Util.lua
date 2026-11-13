--[[
	Util: services, instance creation, colors, serialization, environment helpers.
]]
local Util = {}

local function svc(name)
	local ok, s = pcall(function()
		return game:GetService(name)
	end)
	return ok and s or nil
end

Util.Services = {
	Players = svc("Players"),
	RunService = svc("RunService"),
	UserInputService = svc("UserInputService"),
	TweenService = svc("TweenService"),
	HttpService = svc("HttpService"),
	GuiService = svc("GuiService"),
	TextService = svc("TextService"),
	CoreGui = svc("CoreGui"),
	Stats = svc("Stats"),
	SoundService = svc("SoundService"),
	Workspace = svc("Workspace") or workspace,
}

---------------------------------------------------------------- tables
function Util.DeepCopy(t)
	if type(t) ~= "table" then
		return t
	end
	local n = {}
	for k, v in pairs(t) do
		n[k] = Util.DeepCopy(v)
	end
	return n
end

-- fill missing keys of `opts` from `defaults` (shallow)
function Util.Defaults(opts, defaults)
	opts = opts or {}
	for k, v in pairs(defaults) do
		if opts[k] == nil then
			opts[k] = v
		end
	end
	return opts
end

function Util.Count(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

function Util.Keys(t)
	local out = {}
	for k in pairs(t) do
		table.insert(out, k)
	end
	table.sort(out, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return out
end

function Util.DeepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in pairs(a) do
		if not Util.DeepEqual(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

---------------------------------------------------------------- math
function Util.Clamp(v, a, b)
	return math.max(a, math.min(b, v))
end

function Util.Round(v, inc)
	inc = inc or 1
	if inc <= 0 then
		return v
	end
	local r = math.floor(v / inc + 0.5) * inc
	-- kill float noise
	local decimals = Util.Decimals(inc)
	local m = 10 ^ decimals
	return math.floor(r * m + 0.5) / m
end

function Util.Decimals(inc)
	local s = tostring(inc)
	local dot = string.find(s, "%.")
	if not dot then
		return 0
	end
	return math.min(#s - dot, 6)
end

function Util.FormatNumber(v, decimals)
	if decimals and decimals > 0 then
		return string.format("%." .. decimals .. "f", v)
	end
	return tostring(math.floor(v + 0.5))
end

function Util.Lerp(a, b, t)
	return a + (b - a) * t
end

---------------------------------------------------------------- colors
function Util.ColorToHex(c)
	return string.format(
		"#%02x%02x%02x",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5)
	)
end

function Util.HexToColor(s)
	if type(s) ~= "string" then
		return nil
	end
	s = s:gsub("#", ""):gsub("%s", "")
	if #s == 3 then
		s = s:sub(1, 1):rep(2) .. s:sub(2, 2):rep(2) .. s:sub(3, 3):rep(2)
	end
	if #s ~= 6 or s:find("[^%x]") then
		return nil
	end
	return Color3.fromRGB(tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16))
end

function Util.Darken(c, f)
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s, math.clamp(v * (1 - f), 0, 1))
end

function Util.Lighten(c, f)
	return c:Lerp(Color3.new(1, 1, 1), f)
end

-- Build a ColorSequence from a list of colors (evenly spaced)
function Util.Sequence(colors)
	if #colors == 0 then
		colors = { Color3.new(1, 1, 1) }
	end
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local kps = {}
	local n = math.min(#colors, 20)
	for i = 1, n do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / (n - 1), colors[i]))
	end
	return ColorSequence.new(kps)
end

-- sample a cyclic palette at t (0..1, wraps)
function Util.SampleCyclic(colors, t)
	local n = #colors
	if n == 0 then
		return Color3.new(1, 1, 1)
	end
	if n == 1 then
		return colors[1]
	end
	t = t % 1
	local f = t * n
	local i = math.floor(f)
	local a = colors[i + 1]
	local b = colors[(i + 1) % n + 1]
	return a:Lerp(b, f - i)
end

function Util.HealthColor(t)
	-- red -> yellow -> green
	t = Util.Clamp(t, 0, 1)
	if t < 0.5 then
		return Color3.fromRGB(230, 60, 60):Lerp(Color3.fromRGB(240, 200, 50), t * 2)
	end
	return Color3.fromRGB(240, 200, 50):Lerp(Color3.fromRGB(80, 220, 100), (t - 0.5) * 2)
end

---------------------------------------------------------------- instances
function Util.Create(class, props, children)
	local inst = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Util.FontEnum(name)
	if typeof(name) == "EnumItem" then
		return name
	end
	local ok, f = pcall(function()
		return Enum.Font[name]
	end)
	return ok and f or Enum.Font.Gotham
end

function Util.TextWidth(text, size, font)
	local ts = Util.Services.TextService
	if ts then
		local ok, v = pcall(function()
			return ts:GetTextSize(text, size, Util.FontEnum(font), Vector2.new(10000, 10000))
		end)
		if ok and v then
			return v.X
		end
	end
	return #text * size * 0.55
end

-- position a rotated frame as a line between two 2D points (in parent offset space)
function Util.SetLine(frame, a, b, thickness)
	local d = b - a
	local len = d.Magnitude
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	frame.Size = UDim2.fromOffset(len, thickness or 1)
	frame.Rotation = math.deg(math.atan2(d.Y, d.X))
end

function Util.IsVisible(gui)
	local g = gui
	while g and g:IsA("GuiObject") do
		if not g.Visible then
			return false
		end
		g = g.Parent
	end
	if g and g:IsA("ScreenGui") and not g.Enabled then
		return false
	end
	return g ~= nil
end

---------------------------------------------------------------- environment (executor)
function Util.GetEnv()
	local ok, env = pcall(function()
		return getgenv and getgenv()
	end)
	if ok and type(env) == "table" then
		return env
	end
	return shared or _G
end

function Util.HasFunc(name)
	local env = Util.GetEnv()
	local f = env[name]
	if f == nil then
		local ok, g = pcall(function()
			return getfenv(0)[name]
		end)
		f = ok and g or nil
	end
	return type(f) == "function" and f or nil
end

function Util.SetClipboard(text)
	local f = Util.HasFunc("setclipboard") or Util.HasFunc("toclipboard") or Util.HasFunc("set_clipboard")
	if f then
		local ok = pcall(f, text)
		return ok
	end
	return false
end

function Util.GetClipboard()
	local f = Util.HasFunc("getclipboard")
	if f then
		local ok, v = pcall(f)
		if ok then
			return v
		end
	end
	return nil
end

-- gethui() -> CoreGui -> PlayerGui
function Util.ParentGui(gui)
	local hui = Util.HasFunc("gethui")
	if hui then
		local ok, container = pcall(hui)
		if ok and container then
			local ok2 = pcall(function()
				gui.Parent = container
			end)
			if ok2 and gui.Parent then
				return "gethui"
			end
		end
	end
	local env = Util.GetEnv()
	if env.syn and type(env.syn.protect_gui) == "function" then
		pcall(env.syn.protect_gui, gui)
	end
	local ok = pcall(function()
		gui.Parent = Util.Services.CoreGui
	end)
	if ok and gui.Parent then
		return "CoreGui"
	end
	local lp = Util.Services.Players and Util.Services.Players.LocalPlayer
	if lp then
		gui.Parent = lp:WaitForChild("PlayerGui")
		return "PlayerGui"
	end
	return nil
end

function Util.LocalPlayer()
	return Util.Services.Players and Util.Services.Players.LocalPlayer
end

function Util.PlaceId()
	local ok, id = pcall(function()
		return game.PlaceId
	end)
	return ok and tostring(id) or "0"
end

---------------------------------------------------------------- JSON + value serialization
function Util.JSONEncode(t)
	return Util.Services.HttpService:JSONEncode(t)
end

function Util.JSONDecode(s)
	return Util.Services.HttpService:JSONDecode(s)
end

-- Convert Roblox datatypes into JSON safe values
function Util.Serialize(v)
	local t = typeof(v)
	if t == "Color3" then
		return { __t = "Color3", v = Util.ColorToHex(v) }
	elseif t == "EnumItem" then
		return { __t = "Enum", e = tostring(v.EnumType), v = v.Name }
	elseif t == "Vector2" then
		return { __t = "Vector2", v = { v.X, v.Y } }
	elseif t == "UDim2" then
		return { __t = "UDim2", v = { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } }
	elseif t == "table" then
		local out = {}
		for k, x in pairs(v) do
			out[k] = Util.Serialize(x)
		end
		return out
	end
	return v
end

function Util.Deserialize(v)
	if type(v) ~= "table" then
		return v
	end
	if v.__t == "Color3" then
		return Util.HexToColor(v.v) or Color3.new(1, 1, 1)
	elseif v.__t == "Enum" then
		local ok, e = pcall(function()
			return Enum[v.e][v.v]
		end)
		return ok and e or nil
	elseif v.__t == "Vector2" then
		return Vector2.new(v.v[1], v.v[2])
	elseif v.__t == "UDim2" then
		return UDim2.new(v.v[1], v.v[2], v.v[3], v.v[4])
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = Util.Deserialize(x)
	end
	return out
end

function Util.Viewport()
	local cam = Util.Services.Workspace and Util.Services.Workspace.CurrentCamera
	if cam then
		return cam.ViewportSize
	end
	return Vector2.new(1280, 720)
end

function Util.GuiInset()
	local gs = Util.Services.GuiService
	if gs then
		local ok, a = pcall(function()
			return gs:GetGuiInset()
		end)
		if ok and a then
			return a
		end
	end
	return Vector2.new(0, 36)
end

return Util
