--[[
	Maid: collects connections / instances / functions / objects and cleans them up together.
]]
local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid.CleanTask(job)
	local t = typeof(job)
	if t == "RBXScriptConnection" then
		job:Disconnect()
	elseif t == "Instance" then
		job:Destroy()
	elseif t == "function" then
		job()
	elseif t == "thread" then
		pcall(task.cancel, job)
	elseif t == "table" then
		if type(job.Destroy) == "function" then
			job:Destroy()
		elseif type(job.Disconnect) == "function" then
			job:Disconnect()
		elseif type(job.Clean) == "function" then
			job:Clean()
		end
	end
end

-- Add a task, returns it
function Maid:Give(job)
	if job ~= nil then
		table.insert(self._tasks, job)
	end
	return job
end

-- Named slot: cleans the previous task in that slot
function Maid:Set(name, job)
	local old = self._tasks[name]
	if old ~= nil and old ~= job then
		pcall(Maid.CleanTask, old)
	end
	self._tasks[name] = job
	return job
end

function Maid:Clean()
	local tasks = self._tasks
	self._tasks = {}
	for _, job in pairs(tasks) do
		local ok, err = pcall(Maid.CleanTask, job)
		if not ok then
			warn("[Maid] cleanup error: " .. tostring(err))
		end
	end
end

Maid.Destroy = Maid.Clean
Maid.DoCleaning = Maid.Clean

return Maid
