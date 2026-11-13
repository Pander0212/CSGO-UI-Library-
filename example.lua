--[[
	Nova UI – full example
	loader -> window with every component, ESP preview, quick toggles, appearance tab (skin switching),
	config tab. Replace the URL with wherever you host dist/NovaUI.lua.
]]
local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Pander0212/CSGO-UI-Library-/main/dist/NovaUI.lua"))()

---------------------------------------------------------------- loader
UI:Loader({
	Skin = "Classic", -- every skin ships its own loader
	Title = "Nova UI",
	Products = {
		{ Name = "Universal", Status = "Undetected", Expires = "Never", Game = "All games" },
		{ Name = "Arsenal", Status = "Undetected", Expires = "31.12.2026", Game = "Arsenal" },
		{ Name = "Phantom Forces", Status = "Updating", Expires = "31.12.2026", Game = "Phantom Forces" },
	},
	Steps = { "Authenticating", "Checking version", "Downloading modules", "Building interface", "Done" },
	-- Yield = true (default): the script continues after "Load" finished
})

---------------------------------------------------------------- window
local Win = UI:CreateWindow({
	Title = "Nova UI",
	LogoText = "NOVA",
	Subtitle = "premium",
	UserInfo = "Till: 31.12.2026",
	Skin = "Classic",
	ToggleKey = Enum.KeyCode.RightShift,
})

---------------------------------------------------------------- Aimbot tab
local Aim = Win:AddTab({ Name = "Aimbot", Icon = "crosshair", Category = "Combat" })
local General = Aim:AddGroup({ Name = "General", Side = "Left" })

local aimToggle = General:AddToggle({
	Name = "Enabled",
	Flag = "aim_enabled",
	Default = true,
	Pinnable = true, -- pin icon / long-press -> on-screen quick toggle (mobile)
	PinLabel = "Aimbot", -- label used on the quick toggle and in the keybind list
	Tooltip = "Master switch for the aimbot",
	Callback = function(v)
		print("aimbot", v)
	end,
})
aimToggle:AddKeybind({ Flag = "aim_key", Default = "MB2", Mode = "Hold" })

local silent = General:AddToggle({ Name = "Silent aim", Flag = "aim_silent", Default = false, Pinnable = true })
silent:AddColorPicker({ Flag = "aim_fov_color", Default = Color3.fromRGB(154, 205, 50) })

local fovToggle = General:AddToggle({ Name = "Draw FOV", Flag = "aim_draw_fov", Default = true })
fovToggle:AddColorPicker({ Flag = "aim_fov_circle", Default = Color3.fromRGB(255, 255, 255), Transparency = 0.4 })
local fovSettings = fovToggle:AddSubOptions({ Name = "FOV circle" })
fovSettings:AddSlider({ Name = "Thickness", Flag = "aim_fov_thick", Min = 1, Max = 5, Default = 1 })
fovSettings:AddToggle({ Name = "Filled", Flag = "aim_fov_filled", Default = false })
fovSettings:AddDropdown({ Name = "Sides", Flag = "aim_fov_sides", Values = { "Circle", "Hexagon", "Square" }, Default = "Circle" })

General:AddSlider({ Name = "Field of view", Flag = "aim_fov", Min = 0, Max = 180, Default = 90, Suffix = "°" })
General:AddSlider({ Name = "Smoothing", Flag = "aim_smooth", Min = 0, Max = 1, Increment = 0.01, Default = 0.35 })
General:AddDropdown({ Name = "Hitbox", Flag = "aim_hitbox", Values = { "Head", "Neck", "Chest", "Stomach", "Pelvis" }, Default = "Head" })
General:AddDropdown({ Name = "Priority", Flag = "aim_priority", Values = { "Head", "Chest", "Arms", "Legs", "Feet" }, Multi = true, Default = { "Head", "Chest" } })

local Trigger = Aim:AddGroup({ Name = "Triggerbot", Side = "Right" })
Trigger:AddToggle({ Name = "Enabled", Flag = "trig_enabled", Default = false, Pinnable = true, PinLabel = "Trigger" }):AddKeybind({ Flag = "trig_key", Default = "E", Mode = "Toggle" })
Trigger:AddSlider({ Name = "Delay", Flag = "trig_delay", Min = 0, Max = 500, Default = 60, Suffix = "ms" })
Trigger:AddToggle({ Name = "Only when scoped", Flag = "trig_scoped", Default = true, Disabled = true, Tooltip = "Disabled example" })
Trigger:AddTextbox({ Name = "Whitelist", Flag = "trig_whitelist", Placeholder = "player names, comma separated" })
Trigger:AddKeybind({ Name = "Panic key", Flag = "panic_key", Default = "End", OnPress = function()
	UI:Notify({ Title = "Panic", Content = "Panic key pressed", Type = "Warning" })
end })
Trigger:AddButton({ Name = "Reset aimbot", Confirm = true, Callback = function()
	UI:Notify({ Title = "Aimbot", Content = "Settings reset", Type = "Success" })
end })

local Other = Aim:AddGroup({ Name = "Other", Side = "Right" })
Other:AddLabel({ Text = "Label with a color" }):AddColorPicker({ Flag = "label_color", Default = Color3.fromRGB(255, 120, 80) })
Other:AddParagraph({ Title = "Paragraph", Content = "Paragraphs wrap long text automatically and are useful for descriptions or changelogs." })
Other:AddDivider({ Text = "divider" })
Other:AddColorPicker({ Name = "Standalone color", Flag = "other_color", Default = Color3.fromRGB(80, 160, 255) })

---------------------------------------------------------------- Visuals tab (ESP preview)
local Vis = Win:AddTab({ Name = "Visuals", Icon = "eye", Category = "Visuals" })
local espGroup = Vis:AddGroup({ Name = "Player ESP", Side = "Left" })
espGroup:AddESPSettings() -- creates the standard esp_* flags used by the preview
local previewGroup = Vis:AddGroup({ Name = "Preview", Side = "Right" })
previewGroup:AddESPPreview({ Height = 300 })
previewGroup:AddButton({ Name = "Print ESP settings", Callback = function()
	for k, v in pairs(UI:GetESPSettings()) do
		print(k, v)
	end
end })

---------------------------------------------------------------- Misc tab with sub tabs
local Misc = Win:AddTab({ Name = "Misc", Icon = "zap", Category = "Misc" })
local movement = Misc:AddSubTab("Movement")
local world = Misc:AddSubTab("World")
local mv = movement:AddGroup({ Name = "Movement", Side = "Left" })
mv:AddToggle({ Name = "Speed", Flag = "mv_speed", Default = false, Pinnable = true }):AddKeybind({ Flag = "mv_speed_key", Default = "X", Mode = "Toggle" })
mv:AddSlider({ Name = "Walk speed", Flag = "mv_walkspeed", Min = 16, Max = 120, Default = 32 })
mv:AddToggle({ Name = "Fly", Flag = "mv_fly", Default = false, Pinnable = true })
mv:AddToggle({ Name = "Infinite jump", Flag = "mv_infjump", Default = true })
local wr = world:AddGroup({ Name = "World", Side = "Left" })
wr:AddToggle({ Name = "Fullbright", Flag = "w_fullbright", Default = false })
wr:AddSlider({ Name = "Time of day", Flag = "w_time", Min = 0, Max = 24, Increment = 0.5, Default = 14, Suffix = "h" })
wr:AddDropdown({ Name = "Sky", Flag = "w_sky", Values = { "Default", "Night", "Space", "Sunset" }, Default = "Default" })

---------------------------------------------------------------- settings tabs
Win:AddThemeTab() -- skin selection, presets, every theme key, export / import
Win:AddConfigTab() -- configs, autoload, autosave, export / import

UI:SetWatermark(true)
UI:SetKeybindList(true)
UI.Config:LoadAutoload() -- loads the autoload config (after the loader, after all flags exist)
UI:Notify({ Title = "Welcome", Content = "Press RightShift to toggle the menu.", Type = "Success" })
