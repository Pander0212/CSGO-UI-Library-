--[[
	Config system.
	  NovaUI/<PlaceId>/configs/<name>.json   – configs (flags, theme, skin, window, mobile)
	  NovaUI/themes/<name>.json               – theme presets (see Core/Theme.lua)
	  NovaUI/settings.json                    – autoload per place, autosave, misc settings

	API (UI.Config):
	  :Save(name, {Overwrite=bool})  :Load(name)  :Delete(name)  :Rename(old, new)  :Duplicate(name, new)
	  :List()  :Exists(name)  :SetAutoload(name|nil)  :GetAutoload()  :LoadAutoload()
	  :Export(name?) -> string   :Import(string, {Apply=true, SaveAs=name})
	  :SetAutoSave(enabled, intervalSeconds)  :SetSaveOnClose(bool)
	Everything is pcall'd; corrupt files raise a notification instead of an error.
]]
local Util = require("Core/Util")
local FS = require("Core/FS")
local Meta = require("Meta")
local Signal = require("Core/Signal")

local Config = {}
Config.__index = Config

-- Migrations: Migrations[n] upgrades data from version n to n + 1
Config.Migrations = {
	[1] = function(data)
		-- v1 stored flags under "values" and the theme as a flat table
		data.flags = data.flags or data.values or {}
		data.values = nil
		if data.theme and not data.theme.overrides then
			data.theme = { skin = data.skin, overrides = { [data.skin or Meta.DefaultSkin] = data.theme } }
		end
		data.version = 2
		return data
	end,
}

function Config.new(lib)
	local self = setmetatable({}, Config)
	self.Library = lib
	self.Root = Meta.Folder
	self.Folder = Meta.Folder .. "/" .. Util.PlaceId() .. "/configs"
	self.ThemeFolder = Meta.Folder .. "/themes"
	self.SettingsPath = Meta.Folder .. "/settings.json"
	self.Current = nil -- name of the last loaded / saved config
	self.Changed = Signal.new() -- (action, name)
	self.Settings = {
		version = Meta.SettingsVersion,
		autoload = {},
		autosave = { enabled = false, interval = 60 },
		saveOnClose = false,
		mobileMode = "Auto",
	}
	pcall(function()
		FS.MakeFolder(self.Folder)
		FS.MakeFolder(self.ThemeFolder)
	end)
	self:LoadSettings()
	return self
end

function Config:IsPersistent()
	return FS.Available()
end

---------------------------------------------------------------- settings.json
function Config:LoadSettings()
	local raw = FS.Read(self.SettingsPath)
	if not raw then
		return
	end
	local ok, data = pcall(Util.JSONDecode, raw)
	if ok and type(data) == "table" then
		for k, v in pairs(data) do
			self.Settings[k] = v
		end
	else
		self:_notify("Settings file is corrupt – using defaults", "Warning")
	end
end

function Config:SaveSettings()
	local ok, json = pcall(Util.JSONEncode, self.Settings)
	if ok then
		FS.Write(self.SettingsPath, json)
	end
end

---------------------------------------------------------------- helpers
local function cleanName(name)
	if type(name) ~= "string" then
		return nil
	end
	name = name:gsub("[^%w%-%_%. ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		return nil
	end
	return name
end
Config.CleanName = cleanName

function Config:Path(name)
	return self.Folder .. "/" .. name .. ".json"
end

function Config:_notify(text, kind)
	local lib = self.Library
	if lib and lib.Notify then
		pcall(lib.Notify, lib, { Title = "Config", Content = text, Type = kind or "Info" })
	end
end

function Config:List()
	return FS.List(self.Folder, ".json")
end

function Config:Exists(name)
	name = cleanName(name)
	return name ~= nil and FS.Exists(self:Path(name))
end

---------------------------------------------------------------- collect / apply
function Config:Collect(name)
	local lib = self.Library
	local flags = {}
	for flag, el in pairs(lib.Flags.Elements) do
		if el.Savable and not el.Options.NoSave then
			local ok, v = pcall(el.Serialize, el)
			if ok then
				flags[flag] = v
			end
		end
	end
	return {
		version = Meta.ConfigVersion,
		library = Meta.Name,
		name = name,
		saved = os.time(),
		skin = lib.SkinName,
		theme = lib.Theme:ExportTable(false),
		flags = flags,
		window = lib.Window and lib.Window:GetState() or nil,
		mobile = lib.Mobile and lib.Mobile:GetState() or nil,
		esp = lib.ESPState and Util.Serialize(lib.ESPState) or nil,
	}
end

function Config:Migrate(data)
	local v = tonumber(data.version) or 1
	while v < Meta.ConfigVersion do
		local m = Config.Migrations[v]
		if not m then
			break
		end
		data = m(data)
		v = tonumber(data.version) or (v + 1)
	end
	return data
end

function Config:Apply(data)
	local lib = self.Library
	data = self:Migrate(data)
	if type(data.theme) == "table" then
		lib.Theme:ImportTable(data.theme, { NoReload = true })
	end
	if type(data.skin) == "string" and lib.Skins:Get(data.skin) and data.skin ~= lib.SkinName then
		lib:SetSkin(data.skin, { Instant = true })
	else
		lib.Theme:LoadSkin(lib.SkinName)
	end
	if type(data.flags) == "table" then
		for flag, raw in pairs(data.flags) do
			local el = lib.Flags.Elements[flag]
			if el and el.Savable and not el.Options.NoSave then
				local ok, err = pcall(function()
					local value = el:Deserialize(raw)
					el:Set(value, { Silent = el.Options.IgnoreConfig == true, Force = el.Options.IgnoreConfig ~= true })
				end)
				if not ok then
					warn(("[Config] could not load flag %s: %s"):format(flag, tostring(err)))
				end
			end
		end
	end
	if data.window and lib.Window then
		lib.Window:SetState(data.window)
	end
	if data.mobile and lib.Mobile then
		lib.Mobile:SetState(data.mobile)
	end
	if type(data.esp) == "table" then
		lib.ESPState = Util.Deserialize(data.esp)
	end
end

---------------------------------------------------------------- public API
function Config:Save(name, opts)
	opts = opts or {}
	name = cleanName(name or self.Current)
	if not name then
		self:_notify("Enter a valid config name", "Error")
		return false, "invalid name"
	end
	if opts.Overwrite == false and self:Exists(name) then
		return false, "exists"
	end
	local ok, json = pcall(function()
		return Util.JSONEncode(self:Collect(name))
	end)
	if not ok then
		self:_notify("Saving failed: " .. tostring(json), "Error")
		return false, json
	end
	FS.MakeFolder(self.Folder)
	local _, where = FS.Write(self:Path(name), json)
	self.Current = name
	self.Changed:Fire("save", name)
	if not opts.Silent then
		self:_notify(("Saved '%s'%s"):format(name, where == "memory" and " (session only)" or ""), "Success")
	end
	return true
end

function Config:Load(name, opts)
	opts = opts or {}
	name = cleanName(name)
	if not name then
		return false, "invalid name"
	end
	local raw = FS.Read(self:Path(name))
	if not raw then
		self:_notify(("Config '%s' not found"):format(name), "Error")
		return false, "not found"
	end
	local ok, data = pcall(Util.JSONDecode, raw)
	if not ok or type(data) ~= "table" then
		self:_notify(("Config '%s' is corrupt and was not loaded"):format(name), "Error")
		return false, "corrupt"
	end
	local ok2, err = pcall(self.Apply, self, data)
	if not ok2 then
		self:_notify(("Config '%s' could not be applied: %s"):format(name, tostring(err)), "Error")
		return false, err
	end
	self.Current = name
	self.Changed:Fire("load", name)
	if not opts.Silent then
		self:_notify(("Loaded '%s'"):format(name), "Success")
	end
	return true
end

function Config:Delete(name)
	name = cleanName(name)
	if not name or not self:Exists(name) then
		return false, "not found"
	end
	FS.Delete(self:Path(name))
	if self:GetAutoload() == name then
		self:SetAutoload(nil)
	end
	if self.Current == name then
		self.Current = nil
	end
	self.Changed:Fire("delete", name)
	self:_notify(("Deleted '%s'"):format(name), "Info")
	return true
end

function Config:Rename(old, new)
	old, new = cleanName(old), cleanName(new)
	if not old or not new then
		return false, "invalid name"
	end
	local raw = FS.Read(self:Path(old))
	if not raw then
		return false, "not found"
	end
	if self:Exists(new) then
		return false, "exists"
	end
	FS.Write(self:Path(new), raw)
	FS.Delete(self:Path(old))
	if self:GetAutoload() == old then
		self:SetAutoload(new)
	end
	if self.Current == old then
		self.Current = new
	end
	self.Changed:Fire("rename", new)
	self:_notify(("Renamed '%s' → '%s'"):format(old, new), "Success")
	return true
end

function Config:Duplicate(name, new)
	name = cleanName(name)
	if not name then
		return false, "invalid name"
	end
	local raw = FS.Read(self:Path(name))
	if not raw then
		return false, "not found"
	end
	new = cleanName(new)
	if not new then
		local i = 1
		new = name .. " copy"
		while self:Exists(new) do
			i += 1
			new = name .. " copy " .. i
		end
	end
	FS.Write(self:Path(new), raw)
	self.Changed:Fire("duplicate", new)
	self:_notify(("Duplicated as '%s'"):format(new), "Success")
	return true, new
end

function Config:SetAutoload(name)
	self.Settings.autoload = self.Settings.autoload or {}
	self.Settings.autoload[Util.PlaceId()] = name and cleanName(name) or nil
	self:SaveSettings()
	self.Changed:Fire("autoload", name)
	return true
end

function Config:GetAutoload()
	return self.Settings.autoload and self.Settings.autoload[Util.PlaceId()] or nil
end

function Config:LoadAutoload()
	local name = self:GetAutoload()
	if name and self:Exists(name) then
		return self:Load(name)
	end
	return false
end

function Config:Export(name)
	local data
	if name then
		local raw = FS.Read(self:Path(cleanName(name) or ""))
		if not raw then
			return nil
		end
		data = raw
	else
		local ok, json = pcall(function()
			return Util.JSONEncode(self:Collect("export"))
		end)
		if not ok then
			return nil
		end
		data = json
	end
	local s = Meta.ExportPrefix .. "-CFG:" .. data
	Util.SetClipboard(s)
	return s
end

function Config:Import(s, opts)
	opts = opts or {}
	if type(s) ~= "string" or s == "" then
		return false, "empty"
	end
	local prefix = Meta.ExportPrefix .. "-CFG:"
	if s:sub(1, #prefix) == prefix then
		s = s:sub(#prefix + 1)
	end
	local ok, data = pcall(Util.JSONDecode, s)
	if not ok or type(data) ~= "table" then
		self:_notify("Import failed: invalid config string", "Error")
		return false, "invalid"
	end
	if opts.SaveAs then
		local name = cleanName(opts.SaveAs)
		if name then
			FS.Write(self:Path(name), s)
		end
	end
	if opts.Apply ~= false then
		local ok2, err = pcall(self.Apply, self, data)
		if not ok2 then
			self:_notify("Import failed: " .. tostring(err), "Error")
			return false, err
		end
	end
	self.Changed:Fire("import", opts.SaveAs)
	self:_notify("Config imported", "Success")
	return true
end

function Config:SetAutoSave(enabled, interval)
	self.Settings.autosave = { enabled = enabled == true, interval = math.max(10, tonumber(interval) or 60) }
	self:SaveSettings()
	if self._autoThread then
		pcall(task.cancel, self._autoThread)
		self._autoThread = nil
	end
	if enabled then
		self._autoThread = task.spawn(function()
			while true do
				task.wait(self.Settings.autosave.interval)
				if self.Current then
					self:Save(self.Current, { Silent = true })
				end
			end
		end)
	end
end

function Config:SetSaveOnClose(v)
	self.Settings.saveOnClose = v == true
	self:SaveSettings()
end

function Config:OnClose()
	if self.Settings.saveOnClose and self.Current then
		pcall(self.Save, self, self.Current, { Silent = true })
	end
end

function Config:Destroy()
	if self._autoThread then
		pcall(task.cancel, self._autoThread)
		self._autoThread = nil
	end
	self.Changed:Destroy()
end

return Config
