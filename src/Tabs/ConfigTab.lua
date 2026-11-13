--[[
	Win:AddConfigTab(opts) – ready-made config manager styled by the active skin:
	list, save / save as, load, overwrite (confirm), delete (confirm), rename, duplicate, refresh,
	autoload, export / import string, autosave interval, save on close, menu key, overlays, unload.
]]
local Util = require("Core/Util")

return function(win, opts)
	opts = opts or {}
	local lib = win.Library
	local Config = lib.Config
	local tab = win:AddTab({ Name = opts.Name or "Config", Icon = opts.Icon or "folder", Category = opts.Category or "Settings" })

	local list = tab:AddGroup({ Name = "Configs", Side = "Left" })
	local drop = list:AddDropdown({ Name = "Configs", Flag = "__cfg_list", NoSave = true, Values = Config:List(), AllowNull = true, Searchable = true, Placeholder = "select a config" })
	local nameBox = list:AddTextbox({ Name = "Config name", Flag = "__cfg_name", NoSave = true, Placeholder = "new config name" })
	local autoLabel = list:AddLabel({ Text = "Autoload: none" })

	local function selected()
		return drop.Value
	end
	local function refresh()
		drop:Refresh(Config:List())
		autoLabel:SetText("Autoload: " .. (Config:GetAutoload() or "none"))
	end

	list:AddButton({ Name = "Save as new", Style = "Primary", Callback = function()
		local name = Config.CleanName(nameBox.Value)
		if not name then
			lib:Notify({ Title = "Config", Content = "Enter a config name first", Type = "Warning" })
			return
		end
		if Config:Exists(name) then
			lib:Confirm("Overwrite config?", ("'%s' already exists. Overwrite it?"):format(name), function()
				Config:Save(name)
				refresh()
				drop:Set(name)
			end)
			return
		end
		Config:Save(name)
		refresh()
		drop:Set(name)
	end })
	list:AddButton({ Name = "Load", Callback = function()
		if selected() then
			Config:Load(selected())
		end
	end })
	list:AddButton({ Name = "Overwrite", Callback = function()
		local name = selected()
		if not name then
			return
		end
		lib:Confirm("Overwrite config?", ("Replace '%s' with the current settings?"):format(name), function()
			Config:Save(name)
		end)
	end })
	list:AddButton({ Name = "Delete", Callback = function()
		local name = selected()
		if not name then
			return
		end
		lib:Confirm("Delete config?", ("'%s' will be deleted permanently."):format(name), function()
			Config:Delete(name)
			refresh()
		end)
	end })
	list:AddButton({ Name = "Rename to name above", Callback = function()
		local ok, err = Config:Rename(selected(), nameBox.Value)
		if not ok then
			lib:Notify({ Title = "Config", Content = "Rename failed: " .. tostring(err), Type = "Error" })
		end
		refresh()
	end })
	list:AddButton({ Name = "Duplicate", Callback = function()
		if selected() then
			Config:Duplicate(selected(), Config.CleanName(nameBox.Value))
			refresh()
		end
	end })
	list:AddButton({ Name = "Refresh list", Callback = refresh })
	list:AddButton({ Name = "Set as autoload", Callback = function()
		if selected() then
			Config:SetAutoload(selected())
			refresh()
			lib:Notify({ Title = "Config", Content = ("'%s' will load automatically"):format(selected()), Type = "Success" })
		end
	end })
	list:AddButton({ Name = "Clear autoload", Callback = function()
		Config:SetAutoload(nil)
		refresh()
	end })

	local share = tab:AddGroup({ Name = "Share", Side = "Right" })
	share:AddButton({ Name = "Export to clipboard", Callback = function()
		local s = Config:Export(selected())
		local copied = s ~= nil and (Util.HasFunc("setclipboard") or Util.HasFunc("toclipboard")) ~= nil
		lib:Notify({ Title = "Config", Content = s and (copied and "Config string copied" or "Config string printed to console") or "Export failed", Type = s and "Success" or "Error" })
		if s and not copied then
			print(s)
		end
	end })
	local importBox = share:AddTextbox({ Name = "Config string", Flag = "__cfg_import", NoSave = true, Placeholder = "paste a config string" })
	share:AddButton({ Name = "Import & apply", Callback = function()
		local s = importBox.Value
		if s == "" then
			s = Util.GetClipboard() or ""
		end
		Config:Import(s, { SaveAs = Config.CleanName(nameBox.Value) })
		refresh()
	end })

	local settings = tab:AddGroup({ Name = "Settings", Side = "Right" })
	local st = Config.Settings
	local interval = st.autosave and st.autosave.interval or 60
	local auto = settings:AddToggle({ Name = "Auto save", Flag = "__cfg_autosave", NoSave = true, Default = st.autosave and st.autosave.enabled or false, Tooltip = "Saves the current config periodically", Callback = function(v)
		Config:SetAutoSave(v, interval)
	end })
	settings:AddSlider({ Name = "Auto save interval", Flag = "__cfg_autosave_interval", NoSave = true, Min = 10, Max = 600, Increment = 10, Default = interval, Suffix = "s", Callback = function(v)
		interval = v
		if auto.Value then
			Config:SetAutoSave(true, v)
		end
	end })
	settings:AddToggle({ Name = "Save on close", Flag = "__cfg_save_close", NoSave = true, Default = st.saveOnClose == true, Callback = function(v)
		Config:SetSaveOnClose(v)
	end })
	settings:AddKeybind({ Name = "Menu key", Flag = "__menu_key", Default = win.ToggleKey, Mode = "Toggle", Callback = function(v)
		win:SetToggleKey(v.Key)
	end })
	settings:AddToggle({ Name = "Watermark", Flag = "__ui_watermark_cfg", Default = lib.WatermarkState.Enabled, Callback = function(v)
		lib:SetWatermark(v)
	end })
	settings:AddToggle({ Name = "Keybind list", Flag = "__ui_keybinds_cfg", Default = lib.KeybindListState.Enabled, Callback = function(v)
		lib:SetKeybindList(v)
	end })
	settings:AddLabel({ Text = Config:IsPersistent() and "Storage: file system" or "Storage: session only (no file API)" })
	settings:AddButton({ Name = "Unload " .. lib.Name, Callback = function()
		lib:Confirm("Unload?", "Destroy the interface and disconnect everything?", function()
			lib:Destroy()
		end)
	end })

	lib.Maid:Give(Config.Changed:Connect(function(action)
		if action ~= "load" then
			refresh()
		end
	end))
	refresh()
	if Config.Settings.autosave and Config.Settings.autosave.enabled then
		Config:SetAutoSave(true, interval)
	end
	return tab
end
