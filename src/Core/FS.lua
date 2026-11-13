--[[
	File system wrapper around the executor file API. Every call is pcall'd.
	If the API is missing (or a call fails) a session-only in-memory store is used instead.
]]
local Util = require("Core/Util")

local FS = { Memory = {}, MemoryFolders = {} }

local function fn(name)
	return Util.HasFunc(name)
end

function FS.Available()
	return fn("writefile") ~= nil and fn("readfile") ~= nil and fn("isfile") ~= nil and fn("makefolder") ~= nil
		and fn("isfolder") ~= nil and fn("listfiles") ~= nil
end

local function call(name, ...)
	local f = fn(name)
	if not f then
		return false, "missing " .. name
	end
	return pcall(f, ...)
end

function FS.MakeFolder(path)
	-- create each segment
	local acc = ""
	for seg in string.gmatch(path, "[^/]+") do
		acc = acc == "" and seg or (acc .. "/" .. seg)
		FS.MemoryFolders[acc] = true
		if FS.Available() then
			local ok, exists = call("isfolder", acc)
			if not (ok and exists) then
				call("makefolder", acc)
			end
		end
	end
end

function FS.Write(path, content)
	if FS.Available() then
		local ok = call("writefile", path, content)
		if ok then
			FS.Memory[path] = nil
			return true, "disk"
		end
	end
	FS.Memory[path] = content
	return true, "memory"
end

function FS.Read(path)
	if FS.Memory[path] ~= nil then
		return FS.Memory[path]
	end
	if FS.Available() then
		local ok, exists = call("isfile", path)
		if ok and exists then
			local ok2, data = call("readfile", path)
			if ok2 then
				return data
			end
		end
	end
	return nil
end

function FS.Exists(path)
	if FS.Memory[path] ~= nil then
		return true
	end
	if FS.Available() then
		local ok, exists = call("isfile", path)
		return ok and exists == true
	end
	return false
end

function FS.Delete(path)
	FS.Memory[path] = nil
	if FS.Available() then
		local ok = call("delfile", path)
		return ok
	end
	return true
end

local function basename(p)
	p = p:gsub("\\", "/")
	return p:match("([^/]+)$") or p
end

-- list file names (without extension) inside folder with extension ext (e.g. ".json")
function FS.List(folder, ext)
	ext = ext or ".json"
	local seen, out = {}, {}
	local function add(name)
		if name:sub(-#ext) == ext then
			local n = name:sub(1, -#ext - 1)
			if not seen[n] then
				seen[n] = true
				table.insert(out, n)
			end
		end
	end
	if FS.Available() then
		local ok, files = call("listfiles", folder)
		if ok and type(files) == "table" then
			for _, f in ipairs(files) do
				add(basename(f))
			end
		end
	end
	local prefix = folder .. "/"
	for path in pairs(FS.Memory) do
		if path:sub(1, #prefix) == prefix and not path:sub(#prefix + 1):find("/") then
			add(path:sub(#prefix + 1))
		end
	end
	table.sort(out)
	return out
end

return FS
