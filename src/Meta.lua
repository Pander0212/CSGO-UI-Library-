--[[
	Meta.lua
	THE single place to rename / rebrand the library.
	Everything (folder names, export prefixes, window defaults, global keys) reads from here.
]]
return {
	Name = "Nova UI", -- display name
	Folder = "NovaUI", -- root folder used by the config system
	Version = "1.0.0",
	ConfigVersion = 2, -- bump + add a migration in Core/Config.lua when the format changes
	SettingsVersion = 1,
	GlobalKey = "__NOVA_UI_INSTANCE", -- used to destroy the previous instance on re-execute
	ExportPrefix = "NOVA", -- prefix for exported config / theme strings
	DefaultSkin = "Classic",
}
