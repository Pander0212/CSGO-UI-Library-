--[[
	Lightweight pure-Lua signal (no BindableEvent, so values are passed by reference).
]]
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(fn)
	local list = self._handlers
	local entry = { Fn = fn, Connected = true }
	function entry.Disconnect()
		if not entry.Connected then
			return
		end
		entry.Connected = false
		local i = table.find(list, entry)
		if i then
			table.remove(list, i)
		end
	end
	table.insert(list, entry)
	return entry
end

function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c.Disconnect()
		fn(...)
	end)
	return c
end

function Signal:Fire(...)
	for _, e in ipairs(table.clone(self._handlers)) do
		if e.Connected then
			local ok, err = pcall(e.Fn, ...)
			if not ok then
				warn("[Signal] handler error: " .. tostring(err))
			end
		end
	end
end

function Signal:Wait()
	local thread = coroutine.running()
	self:Once(function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function Signal:Destroy()
	for _, e in ipairs(self._handlers) do
		e.Connected = false
	end
	self._handlers = {}
end

return Signal
