--[[
	Flags: global value store for every element that has a Flag.
	Library.Flags.Values[flag] always holds the current value.
]]
local Signal = require("Core/Signal")

local Flags = {}
Flags.__index = Flags

function Flags.new()
	local self = setmetatable({}, Flags)
	self.Values = {}
	self.Elements = {}
	self.Changed = Signal.new() -- (flag, value)
	return self
end

function Flags:Register(element)
	local flag = element.Flag
	if not flag then
		return
	end
	if self.Elements[flag] and self.Elements[flag] ~= element then
		warn(("[Flags] duplicate flag '%s' – the newer element replaces the older one"):format(flag))
	end
	self.Elements[flag] = element
	self.Values[flag] = element.Value
end

function Flags:Unregister(element)
	if element.Flag and self.Elements[element.Flag] == element then
		self.Elements[element.Flag] = nil
	end
end

function Flags:Get(flag)
	return self.Values[flag]
end

function Flags:Set(flag, value, opts)
	local el = self.Elements[flag]
	if el then
		el:Set(value, opts)
	else
		self.Values[flag] = value
		self.Changed:Fire(flag, value)
	end
end

function Flags:Element(flag)
	return self.Elements[flag]
end

return Flags
