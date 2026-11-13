--[[
	Icons: a small vector icon set drawn with Frames (no external assets needed),
	so icons work in every executor and scale crisply. Any string that looks like an asset
	("rbxassetid://123", "rbxasset://...", "http...", or a plain number) is rendered as ImageLabel.

	Icons.Register(name, assetIdOrDefinition) lets you add / replace icons (branding).
	Definition primitives (coordinates in 0..1 of the icon box):
	  {"rect", x, y, w, h, radius?, rotation?}   {"ring", cx, cy, d, thickness}
	  {"dot", cx, cy, d}                         {"line", x1, y1, x2, y2, thickness}
]]
local Icons = { Defs = {} }

local D = Icons.Defs
D.crosshair = { { "ring", 0.5, 0.5, 0.62, 0.09 }, { "rect", 0.455, 0.02, 0.09, 0.3 }, { "rect", 0.455, 0.68, 0.09, 0.3 }, { "rect", 0.02, 0.455, 0.3, 0.09 }, { "rect", 0.68, 0.455, 0.3, 0.09 }, { "dot", 0.5, 0.5, 0.13 } }
D.target = { { "ring", 0.5, 0.5, 0.9, 0.08 }, { "ring", 0.5, 0.5, 0.5, 0.08 }, { "dot", 0.5, 0.5, 0.16 } }
D.eye = { { "ring", 0.5, 0.5, 0.86, 0.08, 0.55 }, { "dot", 0.5, 0.5, 0.3 } }
D.user = { { "dot", 0.5, 0.3, 0.36 }, { "rect", 0.18, 0.58, 0.64, 0.36, 0.5 } }
D.users = { { "dot", 0.36, 0.32, 0.3 }, { "rect", 0.1, 0.58, 0.52, 0.32, 0.5 }, { "dot", 0.7, 0.36, 0.24 }, { "rect", 0.56, 0.6, 0.38, 0.28, 0.5 } }
D.gear = { { "ring", 0.5, 0.5, 0.5, 0.14 }, { "rect", 0.42, 0.04, 0.16, 0.92, 0.2 }, { "rect", 0.42, 0.04, 0.16, 0.92, 0.2, 60 }, { "rect", 0.42, 0.04, 0.16, 0.92, 0.2, 120 }, { "dot", 0.5, 0.5, 0.5, "bg" }, { "ring", 0.5, 0.5, 0.52, 0.13 } }
D.settings = D.gear
D.palette = { { "ring", 0.5, 0.5, 0.88, 0.09 }, { "dot", 0.32, 0.36, 0.16 }, { "dot", 0.52, 0.26, 0.16 }, { "dot", 0.7, 0.4, 0.16 }, { "dot", 0.62, 0.66, 0.2 } }
D.folder = { { "rect", 0.08, 0.2, 0.36, 0.2, 0.3 }, { "rect", 0.08, 0.3, 0.84, 0.54, 0.15 } }
D.globe = { { "ring", 0.5, 0.5, 0.86, 0.08 }, { "ring", 0.5, 0.5, 0.4, 0.08, 2.1 }, { "rect", 0.08, 0.46, 0.84, 0.08 } }
D.shield = { { "rect", 0.2, 0.08, 0.6, 0.5, 0.15 }, { "rect", 0.29, 0.42, 0.42, 0.42, 0.15, 45 } }
D.sword = { { "rect", 0.46, 0.04, 0.1, 0.66, 0.4, 45 }, { "rect", 0.2, 0.6, 0.36, 0.09, 0.4, 45 }, { "rect", 0.12, 0.72, 0.14, 0.14, 0.4, 45 } }
D.home = { { "rect", 0.22, 0.46, 0.56, 0.44, 0.1 }, { "rect", 0.26, 0.2, 0.48, 0.48, 0.1, 45 } }
D.bell = { { "rect", 0.24, 0.2, 0.52, 0.56, 0.6 }, { "rect", 0.14, 0.66, 0.72, 0.1, 0.4 }, { "dot", 0.5, 0.85, 0.16 } }
D.search = { { "ring", 0.42, 0.42, 0.6, 0.11 }, { "line", 0.62, 0.62, 0.92, 0.92, 0.12 } }
D.list = { { "rect", 0.1, 0.18, 0.8, 0.11 }, { "rect", 0.1, 0.45, 0.8, 0.11 }, { "rect", 0.1, 0.72, 0.8, 0.11 } }
D.menu = D.list
D.star = { { "rect", 0.27, 0.27, 0.46, 0.46, 0.05, 0 }, { "rect", 0.27, 0.27, 0.46, 0.46, 0.05, 45 } }
D.zap = { { "rect", 0.44, 0.02, 0.14, 0.56, 0.2, 25 }, { "rect", 0.42, 0.42, 0.14, 0.56, 0.2, 25 }, { "rect", 0.3, 0.44, 0.4, 0.12, 0.2 } }
D.code = { { "line", 0.38, 0.22, 0.12, 0.5, 0.1 }, { "line", 0.12, 0.5, 0.38, 0.78, 0.1 }, { "line", 0.62, 0.22, 0.88, 0.5, 0.1 }, { "line", 0.88, 0.5, 0.62, 0.78, 0.1 } }
D.save = { { "ring", 0.5, 0.5, 0.84, 0.09, 0.12 }, { "rect", 0.3, 0.12, 0.4, 0.26, 0.1 }, { "rect", 0.28, 0.58, 0.44, 0.3, 0.1 } }
D.pin = { { "dot", 0.5, 0.34, 0.5 }, { "dot", 0.5, 0.34, 0.2, "bg" }, { "rect", 0.32, 0.5, 0.36, 0.3, 0.1, 45 } }
D.chevron = { { "line", 0.22, 0.38, 0.5, 0.66, 0.11 }, { "line", 0.5, 0.66, 0.78, 0.38, 0.11 } }
D["chevron-down"] = D.chevron
D["chevron-up"] = { { "line", 0.22, 0.62, 0.5, 0.34, 0.11 }, { "line", 0.5, 0.34, 0.78, 0.62, 0.11 } }
D["chevron-right"] = { { "line", 0.38, 0.22, 0.66, 0.5, 0.11 }, { "line", 0.66, 0.5, 0.38, 0.78, 0.11 } }
D["chevron-left"] = { { "line", 0.62, 0.22, 0.34, 0.5, 0.11 }, { "line", 0.34, 0.5, 0.62, 0.78, 0.11 } }
D.close = { { "line", 0.2, 0.2, 0.8, 0.8, 0.11 }, { "line", 0.8, 0.2, 0.2, 0.8, 0.11 } }
D.x = D.close
D.plus = { { "rect", 0.44, 0.12, 0.12, 0.76, 0.3 }, { "rect", 0.12, 0.44, 0.76, 0.12, 0.3 } }
D.minus = { { "rect", 0.12, 0.44, 0.76, 0.12, 0.3 } }
D.check = { { "line", 0.14, 0.52, 0.4, 0.76, 0.13 }, { "line", 0.4, 0.76, 0.86, 0.26, 0.13 } }
D.info = { { "ring", 0.5, 0.5, 0.88, 0.09 }, { "rect", 0.45, 0.42, 0.1, 0.32, 0.4 }, { "dot", 0.5, 0.28, 0.12 } }
D.warning = { { "rect", 0.45, 0.16, 0.1, 0.46, 0.4 }, { "dot", 0.5, 0.78, 0.13 } }
D.alert = D.warning
D.trash = { { "rect", 0.22, 0.3, 0.56, 0.6, 0.12 }, { "rect", 0.12, 0.16, 0.76, 0.1, 0.3 }, { "rect", 0.38, 0.06, 0.24, 0.12, 0.3 } }
D.copy = { { "ring", 0.42, 0.42, 0.56, 0.09, 0.15 }, { "ring", 0.6, 0.6, 0.56, 0.09, 0.15 } }
D.edit = { { "rect", 0.42, 0.08, 0.16, 0.78, 0.2, 45 }, { "dot", 0.18, 0.82, 0.14 } }
D.refresh = { { "ring", 0.5, 0.5, 0.7, 0.1 }, { "rect", 0.6, 0.08, 0.26, 0.26, 0.1, 45, "bg" }, { "line", 0.66, 0.12, 0.86, 0.26, 0.1 }, { "line", 0.86, 0.26, 0.66, 0.4, 0.1 } }
D.download = { { "rect", 0.45, 0.08, 0.1, 0.56, 0.3 }, { "line", 0.24, 0.42, 0.5, 0.68, 0.1 }, { "line", 0.5, 0.68, 0.76, 0.42, 0.1 }, { "rect", 0.12, 0.84, 0.76, 0.1, 0.3 } }
D.upload = { { "rect", 0.45, 0.3, 0.1, 0.5, 0.3 }, { "line", 0.24, 0.48, 0.5, 0.22, 0.1 }, { "line", 0.5, 0.22, 0.76, 0.48, 0.1 }, { "rect", 0.12, 0.86, 0.76, 0.1, 0.3 } }
D.lock = { { "rect", 0.2, 0.44, 0.6, 0.48, 0.15 }, { "ring", 0.5, 0.36, 0.42, 0.09, 0.9 } }
D.grid = { { "rect", 0.1, 0.1, 0.34, 0.34, 0.15 }, { "rect", 0.56, 0.1, 0.34, 0.34, 0.15 }, { "rect", 0.1, 0.56, 0.34, 0.34, 0.15 }, { "rect", 0.56, 0.56, 0.34, 0.34, 0.15 } }
D.sliders = { { "rect", 0.1, 0.24, 0.8, 0.08, 0.3 }, { "rect", 0.1, 0.68, 0.8, 0.08, 0.3 }, { "dot", 0.32, 0.28, 0.22 }, { "dot", 0.66, 0.72, 0.22 } }
D.play = { { "rect", 0.2, 0.25, 0.5, 0.5, 0.1, 45 }, { "rect", 0.0, 0.1, 0.45, 0.8, 0, 0, "bg" } }
D.power = { { "ring", 0.5, 0.54, 0.76, 0.1 }, { "rect", 0.4, 0.04, 0.2, 0.4, 0, 0, "bg" }, { "rect", 0.45, 0.06, 0.1, 0.44, 0.4 } }
D.clock = { { "ring", 0.5, 0.5, 0.86, 0.09 }, { "rect", 0.45, 0.2, 0.1, 0.34, 0.4 }, { "line", 0.5, 0.52, 0.7, 0.62, 0.1 } }
D.box = { { "ring", 0.5, 0.5, 0.8, 0.1, 0.1 } }
D.cube = { { "ring", 0.5, 0.5, 0.62, 0.09, 0.1, 45 }, { "dot", 0.5, 0.5, 0.14 } }
D.car = { { "rect", 0.06, 0.42, 0.88, 0.3, 0.3 }, { "rect", 0.22, 0.24, 0.56, 0.3, 0.3 }, { "dot", 0.28, 0.74, 0.2 }, { "dot", 0.72, 0.74, 0.2 } }
D.skull = { { "dot", 0.5, 0.42, 0.72 }, { "rect", 0.32, 0.62, 0.36, 0.28, 0.2 }, { "dot", 0.36, 0.44, 0.18, "bg" }, { "dot", 0.64, 0.44, 0.18, "bg" } }
D.map = { { "rect", 0.1, 0.16, 0.24, 0.68, 0.1, 6 }, { "rect", 0.38, 0.16, 0.24, 0.68, 0.1, -6 }, { "rect", 0.66, 0.16, 0.24, 0.68, 0.1, 6 } }
D.heart = { { "dot", 0.34, 0.38, 0.42 }, { "dot", 0.66, 0.38, 0.42 }, { "rect", 0.27, 0.3, 0.46, 0.46, 0.08, 45 } }
D.layers = { { "rect", 0.2, 0.12, 0.6, 0.6, 0.12, 45 }, { "rect", 0.24, 0.5, 0.52, 0.12, 0.3 } }
D.move = { { "rect", 0.45, 0.08, 0.1, 0.84, 0.3 }, { "rect", 0.08, 0.45, 0.84, 0.1, 0.3 }, { "dot", 0.5, 0.5, 0.24 } }
D.dot = { { "dot", 0.5, 0.5, 0.5 } }
D.logo = { { "rect", 0.2, 0.2, 0.6, 0.6, 0.15, 45 }, { "rect", 0.34, 0.34, 0.32, 0.32, 0.15, 45, "bg" }, { "dot", 0.5, 0.5, 0.16 } }

local function isAsset(s)
	if type(s) == "number" then
		return true
	end
	return type(s) == "string" and (s:find("^rbxasset") or s:find("^http") or s:match("^%d+$")) ~= nil
end

function Icons.IsAsset(s)
	return isAsset(s)
end

function Icons.Register(name, def)
	Icons.Defs[name] = def
end

function Icons.Has(name)
	return Icons.Defs[name] ~= nil or isAsset(name)
end

--[[
	Icons.Create(theme, name, size, colorKey, props?)
	Returns a Frame (or ImageLabel) whose drawing follows the theme color key.
	`bgKey` (props.BgKey) is used for "cut-out" primitives.
]]
function Icons.Create(theme, name, size, colorKey, props)
	props = props or {}
	colorKey = colorKey or "Text"
	local def = Icons.Defs[name]
	if def and type(def) ~= "table" then
		name = def
		def = nil
	end
	if not def and isAsset(name) then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(size, size)
		img.Image = type(name) == "number" and ("rbxassetid://" .. name) or (name:match("^%d+$") and "rbxassetid://" .. name or name)
		img.ScaleType = Enum.ScaleType.Fit
		theme:Bind(img, "ImageColor3", colorKey)
		for k, v in pairs(props) do
			if k ~= "BgKey" then
				img[k] = v
			end
		end
		return img
	end
	def = def or Icons.Defs.dot
	local box = Instance.new("Frame")
	box.Name = "Icon"
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	box.Size = UDim2.fromOffset(size, size)
	for k, v in pairs(props) do
		if k ~= "BgKey" then
			box[k] = v
		end
	end
	local bgKey = props.BgKey or "Background"
	for i, p in ipairs(def) do
		local kind = p[1]
		local f = Instance.new("Frame")
		f.Name = kind .. i
		f.BorderSizePixel = 0
		f.ZIndex = (props.ZIndex or 1) + (p[#p] == "bg" and 1 or 0)
		local key = p[#p] == "bg" and bgKey or colorKey
		if p[#p] ~= "bg" then
			f:SetAttribute("IconFg", true)
		end
		if kind == "rect" then
			f.Position = UDim2.fromScale(p[2], p[3])
			f.Size = UDim2.fromScale(p[4], p[5])
			f.Rotation = type(p[7]) == "number" and p[7] or 0
			local r = type(p[6]) == "number" and p[6] or 0
			if r > 0 then
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(r, 0)
				c.Parent = f
			end
			theme:Bind(f, "BackgroundColor3", key)
		elseif kind == "dot" then
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale(p[2], p[3])
			f.Size = UDim2.fromScale(p[4], p[4])
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = f
			theme:Bind(f, "BackgroundColor3", key)
		elseif kind == "ring" then
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale(p[2], p[3])
			local d = p[4]
			local squash = type(p[6]) == "number" and p[6] or nil
			if squash and squash > 1 then
				f.Size = UDim2.fromScale(d / squash, d)
			elseif squash and squash < 1 and squash > 0.3 then
				f.Size = UDim2.fromScale(d, d * squash)
			else
				f.Size = UDim2.fromScale(d, d)
			end
			f.Rotation = type(p[7]) == "number" and p[7] or 0
			f.BackgroundTransparency = 1
			local c = Instance.new("UICorner")
			c.CornerRadius = (squash and squash <= 0.3) and UDim.new(squash, 0) or UDim.new(1, 0)
			c.Parent = f
			local s = Instance.new("UIStroke")
			s.Thickness = math.max(1, math.floor(size * p[5] + 0.5))
			s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			s.Parent = f
			theme:Bind(s, "Color", key)
		elseif kind == "line" then
			local x1, y1, x2, y2 = p[2] * size, p[3] * size, p[4] * size, p[5] * size
			local dx, dy = x2 - x1, y2 - y1
			local len = math.sqrt(dx * dx + dy * dy)
			local th = math.max(1, math.floor(size * (p[6] or 0.1) + 0.5))
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
			f.Size = UDim2.fromOffset(len + th * 0.5, th)
			f.Rotation = math.deg(math.atan2(dy, dx))
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(1, 0)
			c.Parent = f
			theme:Bind(f, "BackgroundColor3", key)
		end
		f.Parent = box
	end
	return box
end

-- Recolor an icon created by Icons.Create (rebinds every foreground primitive)
function Icons.SetColor(theme, icon, colorKey, tween)
	if not icon then
		return
	end
	if icon:IsA("ImageLabel") then
		theme:Bind(icon, "ImageColor3", colorKey, { Tween = tween })
		return
	end
	for _, f in ipairs(icon:GetChildren()) do
		if f:GetAttribute("IconFg") then
			local s = f:FindFirstChildOfClass("UIStroke")
			if s then
				theme:Bind(s, "Color", colorKey, { Tween = tween })
			else
				theme:Bind(f, "BackgroundColor3", colorKey, { Tween = tween })
			end
		end
	end
end

return Icons
