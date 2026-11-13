--[[
	Types: the shared VALUE logic of every component kind (independent of any skin).
	  Init(el, opts)            normalise options
	  Normalize(el, value)      -> canonical value
	  Serialize(el, value)      -> JSON-safe value
	  Deserialize(el, raw)      -> value
	  Savable                   whether the value goes into configs
]]
local Util = require("Core/Util")

local Types = {}

local function identity(_, v)
	return v
end

---------------------------------------------------------------- Toggle
Types.Toggle = {
	Savable = true,
	Default = false,
	Normalize = function(_, v)
		return v == true
	end,
}

---------------------------------------------------------------- Slider
Types.Slider = {
	Savable = true,
	Init = function(el, o)
		o.Min = tonumber(o.Min) or 0
		o.Max = tonumber(o.Max) or 100
		if o.Max < o.Min then
			o.Min, o.Max = o.Max, o.Min
		end
		if o.Rounding and not o.Increment then
			o.Increment = 10 ^ -o.Rounding
		end
		o.Increment = tonumber(o.Increment) or 1
		el.Decimals = Util.Decimals(o.Increment)
		if o.Default == nil then
			o.Default = o.Min
		end
		o.Suffix = o.Suffix or ""
	end,
	Normalize = function(el, v)
		local o = el.Options
		v = tonumber(v) or o.Min
		return Util.Clamp(Util.Round(v, o.Increment), o.Min, o.Max)
	end,
	Format = function(el, v)
		local o = el.Options
		if o.Format then
			local ok, s = pcall(o.Format, v)
			if ok then
				return tostring(s)
			end
		end
		return Util.FormatNumber(v, el.Decimals) .. (o.Suffix or "")
	end,
}

---------------------------------------------------------------- Dropdown
Types.Dropdown = {
	Savable = true,
	Init = function(el, o)
		o.Values = o.Values or o.Options or o.Items or {}
		o.Multi = o.Multi == true
		if o.Default == nil then
			if o.Multi then
				o.Default = {}
			elseif o.AllowNull ~= true then
				o.Default = o.Values[1]
			end
		end
	end,
	Normalize = function(el, v)
		local o = el.Options
		local function valid(x)
			return o.AllowCustom or table.find(o.Values, x) ~= nil
		end
		if o.Multi then
			local set = {}
			if type(v) == "table" then
				for k, x in pairs(v) do
					if type(k) == "number" then
						set[x] = true
					elseif x == true then
						set[k] = true
					end
				end
			elseif v ~= nil then
				set[v] = true
			end
			local out = {}
			for _, x in ipairs(o.Values) do
				if set[x] then
					table.insert(out, x)
				end
			end
			return out
		end
		if type(v) == "table" then
			v = v[1]
		end
		if v ~= nil and valid(v) then
			return v
		end
		if o.AllowNull then
			return nil
		end
		return o.Values[1]
	end,
	Display = function(el, v)
		if el.Options.Multi then
			if type(v) ~= "table" or #v == 0 then
				return el.Options.Placeholder or "None"
			end
			return table.concat(v, ", ")
		end
		if v == nil then
			return el.Options.Placeholder or "None"
		end
		return tostring(v)
	end,
}

---------------------------------------------------------------- Textbox
Types.Textbox = {
	Savable = true,
	Init = function(_, o)
		if o.Default == nil then
			o.Default = ""
		end
	end,
	Normalize = function(el, v)
		v = v == nil and "" or tostring(v)
		if el.Options.Numeric then
			v = v:gsub("[^%d%.%-]", "")
		end
		if el.Options.MaxLength then
			v = v:sub(1, el.Options.MaxLength)
		end
		return v
	end,
}

---------------------------------------------------------------- Keybind
local SHORT = {
	LeftShift = "LSHIFT", RightShift = "RSHIFT", LeftControl = "LCTRL", RightControl = "RCTRL",
	LeftAlt = "LALT", RightAlt = "RALT", MB1 = "MB1", MB2 = "MB2", MB3 = "MB3", Return = "ENTER",
	Backspace = "BACK", CapsLock = "CAPS", Insert = "INS", Delete = "DEL", PageUp = "PGUP", PageDown = "PGDN",
	Space = "SPACE", Tab = "TAB", Escape = "ESC", Backquote = "`", LeftBracket = "[", RightBracket = "]",
	Semicolon = ";", Quote = "'", Comma = ",", Period = ".", Slash = "/", BackSlash = "\\", Minus = "-", Equals = "=",
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
}

local function keyName(k)
	if k == nil then
		return nil
	end
	if typeof(k) == "EnumItem" then
		if k.EnumType == Enum.UserInputType then
			if k == Enum.UserInputType.MouseButton1 then
				return "MB1"
			elseif k == Enum.UserInputType.MouseButton2 then
				return "MB2"
			elseif k == Enum.UserInputType.MouseButton3 then
				return "MB3"
			end
			return nil
		end
		return k.Name
	end
	if type(k) == "string" then
		if k == "" or k == "None" or k == "Unknown" then
			return nil
		end
		if k == "MouseButton1" then
			return "MB1"
		elseif k == "MouseButton2" then
			return "MB2"
		elseif k == "MouseButton3" then
			return "MB3"
		end
		return k
	end
	return nil
end

Types.KeyName = keyName
Types.Modes = { "Toggle", "Hold", "Always" }

function Types.KeyDisplay(key)
	if not key then
		return "-"
	end
	return SHORT[key] or string.upper(key)
end

Types.Keybind = {
	Savable = true,
	Init = function(el, o)
		o.Mode = o.Mode or "Toggle"
		if o.Default == nil then
			o.Default = { Key = nil, Mode = o.Mode }
		end
		el.State = false
	end,
	Normalize = function(el, v)
		local mode = el.Value and el.Value.Mode or el.Options.Mode or "Toggle"
		if type(v) == "table" and (v.Key ~= nil or v.Mode ~= nil) then
			return { Key = keyName(v.Key), Mode = table.find(Types.Modes, v.Mode) and v.Mode or mode }
		elseif type(v) == "table" then
			return { Key = nil, Mode = mode }
		end
		return { Key = keyName(v), Mode = mode }
	end,
	Serialize = function(_, v)
		return { Key = v.Key or "None", Mode = v.Mode }
	end,
	Deserialize = function(_, raw)
		return raw
	end,
}

-- does an InputObject match a key name?
function Types.MatchKey(input, key)
	if not key then
		return false
	end
	local t = input.UserInputType
	if key == "MB1" then
		return t == Enum.UserInputType.MouseButton1
	elseif key == "MB2" then
		return t == Enum.UserInputType.MouseButton2
	elseif key == "MB3" then
		return t == Enum.UserInputType.MouseButton3
	end
	return t == Enum.UserInputType.Keyboard and input.KeyCode.Name == key
end

---------------------------------------------------------------- ColorPicker
Types.ColorPicker = {
	Savable = true,
	Init = function(_, o)
		if o.Default == nil then
			o.Default = Color3.new(1, 1, 1)
		end
	end,
	Normalize = function(el, v)
		local cur = el.Value or {}
		if typeof(v) == "Color3" then
			return { Color = v, Transparency = cur.Transparency or el.Options.Transparency or 0, Rainbow = false }
		elseif type(v) == "string" then
			return { Color = Util.HexToColor(v) or Color3.new(1, 1, 1), Transparency = cur.Transparency or 0, Rainbow = false }
		elseif type(v) == "table" then
			local c = v.Color
			if type(c) == "string" then
				c = Util.HexToColor(c)
			end
			return {
				Color = typeof(c) == "Color3" and c or (cur.Color or Color3.new(1, 1, 1)),
				Transparency = Util.Clamp(tonumber(v.Transparency) or cur.Transparency or 0, 0, 1),
				Rainbow = v.Rainbow == true,
			}
		end
		return { Color = Color3.new(1, 1, 1), Transparency = 0, Rainbow = false }
	end,
	Serialize = function(_, v)
		return { Color = Util.ColorToHex(v.Color), Transparency = v.Transparency, Rainbow = v.Rainbow }
	end,
	Deserialize = function(_, raw)
		return raw
	end,
}

---------------------------------------------------------------- non-value components
Types.Button = { Savable = false }
Types.Label = { Savable = false }
Types.Paragraph = { Savable = false }
Types.Divider = { Savable = false }
Types.ESPPreview = { Savable = false }

for _, t in pairs(Types) do
	if type(t) == "table" then
		t.Serialize = t.Serialize or identity
		t.Deserialize = t.Deserialize or identity
	end
end

return Types
