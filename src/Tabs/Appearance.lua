--[[
	Win:AddThemeTab(opts) – ready-made appearance tab (skin selection, presets, every theme key,
	export/import, reset per section). Styled automatically by the active skin.
	These controls are NoSave: the theme itself is stored in configs / theme presets.
]]
local Util = require("Core/Util")

local LABELS = {
	BackgroundSecondary = "Sidebar background", PanelHeader = "Panel header", TextOnAccent = "Text on accent",
	ElementHover = "Element hover", ElementActive = "Element active", TextDim = "Text (dim)", TextDisabled = "Text (disabled)",
	BorderDark = "Border (dark)", BorderLight = "Border (light)", AccentDark = "Accent (dark)",
	WindowTransparency = "Window transparency", BackgroundTexture = "Texture", TextureTransparency = "Texture transparency",
	TextureSpacing = "Texture spacing", BackgroundImage = "Image (asset id)", BackgroundImageTransparency = "Image transparency",
	FontTitle = "Title font", FontBody = "Body font", FontMono = "Mono font", TextSize = "Text size", TitleSize = "Title size",
	SmallTextSize = "Small text size", CornerRadius = "Corner radius", SmallCornerRadius = "Small corner radius",
	BorderThickness = "Border thickness", ShadowEnabled = "Shadow", ShadowTransparency = "Shadow transparency",
	WindowWidth = "Window width", WindowHeight = "Window height", UIScale = "UI scale", SidebarWidth = "Sidebar width",
	ElementHeight = "Element height", GroupSpacing = "Group spacing", AnimationsEnabled = "Animations",
	AnimationSpeed = "Animation speed", EasingStyle = "Easing style", EasingDirection = "Easing direction",
	LogoText = "Logo text", LogoImage = "Logo image (asset id)", UserInfo = "User info line", AvatarImage = "Avatar image",
	LoaderTitle = "Loader title", LoaderSubtitle = "Loader greeting", LoaderStatus = "Loader status",
	NotifyPosition = "Position", NotifyDuration = "Duration", NotifyWidth = "Width", SoundsEnabled = "Sounds",
	SoundVolume = "Volume", SoundClick = "Click sound", SoundToggle = "Toggle sound", SoundNotify = "Notify sound",
	MobileButtonSize = "Open button size", MobileButtonShape = "Open button shape", TouchTarget = "Touch target (px)",
	QuickToggleShape = "Quick toggle shape",
}

return function(win, opts)
	opts = opts or {}
	local lib = win.Library
	local Theme = lib.Theme
	local tab = win:AddTab({ Name = opts.Name or "Appearance", Icon = opts.Icon or "palette", Category = opts.Category or "Settings" })
	local general = tab:AddSubTab({ Name = "General" })
	local colors = tab:AddSubTab({ Name = "Colors" })
	local layout = tab:AddSubTab({ Name = "Layout" })
	local controls = {} -- key -> refresh function

	local function label(key)
		return LABELS[key] or key
	end

	-- builds the right control for a theme key
	local function control(group, key)
		local meta = Theme:MetaFor(key)
		local v = Theme:Get(key)
		local flag = "__theme_" .. key
		local el
		if meta.Type == "Color3" then
			el = group:AddColorPicker({
				Name = label(key),
				Flag = flag,
				NoSave = true,
				Default = { Color = v, Transparency = Theme:Get("Alpha." .. key) or 0 },
				Callback = function(val)
					Theme:Set(key, val.Color)
					Theme:Set("Alpha." .. key, val.Transparency)
				end,
			})
			controls[key] = function()
				el:Set({ Color = Theme:Get(key), Transparency = Theme:Get("Alpha." .. key) or 0, Rainbow = false }, { Silent = true })
			end
		elseif meta.Type == "boolean" then
			el = group:AddToggle({ Name = label(key), Flag = flag, NoSave = true, Default = v, Callback = function(val)
				Theme:Set(key, val)
			end })
		elseif meta.Type == "number" then
			el = group:AddSlider({ Name = label(key), Flag = flag, NoSave = true, Min = meta.Min or 0, Max = meta.Max or 100, Increment = meta.Step or 1, Default = v, Callback = function(val)
				Theme:Set(key, val)
			end })
		elseif meta.Type == "string" and meta.Options then
			el = group:AddDropdown({ Name = label(key), Flag = flag, NoSave = true, Values = meta.Options, Default = v, Searchable = #meta.Options > 10, Callback = function(val)
				Theme:Set(key, val)
			end })
		elseif meta.Type == "string" then
			el = group:AddTextbox({ Name = label(key), Flag = flag, NoSave = true, Default = v, Callback = function(val)
				Theme:Set(key, val)
			end })
		end
		if el and not controls[key] then
			controls[key] = function()
				el:Set(Theme:Get(key), { Silent = true })
			end
		end
		return el
	end

	local function gradientControls(group, key)
		local g = Theme:Get(key)
		group:AddDivider({ Text = label(key) })
		local function set(field, val)
			Theme:Set(key, { [field] = val })
		end
		local en = group:AddToggle({ Name = "Enabled", Flag = "__theme_" .. key .. "_en", NoSave = true, Default = g.Enabled ~= false, Callback = function(v)
			set("Enabled", v)
		end })
		local an = group:AddToggle({ Name = "Animated", Flag = "__theme_" .. key .. "_an", NoSave = true, Default = g.Animated == true, Callback = function(v)
			set("Animated", v)
		end })
		local rot = group:AddSlider({ Name = "Rotation", Flag = "__theme_" .. key .. "_rot", NoSave = true, Min = 0, Max = 360, Default = g.Rotation or 0, Suffix = "°", Callback = function(v)
			set("Rotation", v)
		end })
		local sp = group:AddSlider({ Name = "Speed", Flag = "__theme_" .. key .. "_sp", NoSave = true, Min = 0.05, Max = 2, Increment = 0.05, Default = g.Speed or 0.5, Callback = function(v)
			set("Speed", v)
		end })
		local pickers = {}
		for i, c in ipairs(g.Colors or {}) do
			if typeof(c) == "Color3" then
				pickers[i] = group:AddColorPicker({ Name = "Color " .. i, Flag = "__theme_" .. key .. "_c" .. i, NoSave = true, Default = c, Callback = function(val)
					local cur = Theme:Get(key)
					local list = table.clone(cur.Colors)
					list[i] = val.Color
					Theme:Set(key, { Colors = list })
				end })
			end
		end
		controls[key] = function()
			local cur = Theme:Get(key)
			en:Set(cur.Enabled ~= false, { Silent = true })
			an:Set(cur.Animated == true, { Silent = true })
			rot:Set(cur.Rotation or 0, { Silent = true })
			sp:Set(cur.Speed or 0.5, { Silent = true })
			for i, p in pairs(pickers) do
				if typeof(cur.Colors[i]) == "Color3" then
					p:Set(cur.Colors[i], { Silent = true })
				end
			end
		end
	end

	---------------------------------------------------------------- General
	local skinGroup = general:AddGroup({ Name = "Skin", Side = "Left" })
	local skinDrop = skinGroup:AddDropdown({ Name = "Skin", Flag = "__ui_skin", NoSave = true, Values = lib:GetSkins(), Default = lib.SkinName, Callback = function(v)
		lib:SetSkin(v)
	end })
	local presetDrop = skinGroup:AddDropdown({ Name = "Preset", Flag = "__ui_preset", NoSave = true, Values = Theme:Presets(), Default = "Default" })
	skinGroup:AddButton({ Name = "Apply preset", Callback = function()
		local ok, err = Theme:ApplyPreset(presetDrop.Value or "Default")
		if ok == false then
			lib:Notify({ Title = "Theme", Content = tostring(err), Type = "Error" })
		end
	end })
	local presetName = skinGroup:AddTextbox({ Name = "Preset name", Flag = "__ui_preset_name", NoSave = true, Placeholder = "my preset" })
	skinGroup:AddButton({ Name = "Save as preset", Callback = function()
		local ok = Theme:SavePreset(presetName.Value)
		if ok then
			presetDrop:Refresh(Theme:Presets())
			lib:Notify({ Title = "Theme", Content = "Preset saved", Type = "Success" })
		end
	end })
	skinGroup:AddButton({ Name = "Delete preset", Confirm = true, Callback = function()
		local name = presetDrop.Value
		if name and name:sub(1, 8) == "custom: " then
			Theme:DeletePreset(name)
			presetDrop:Refresh(Theme:Presets())
		else
			lib:Notify({ Title = "Theme", Content = "Built-in presets cannot be deleted", Type = "Warning" })
		end
	end })

	local fonts = general:AddGroup({ Name = "Fonts", Side = "Left" })
	for _, k in ipairs(Theme.Sections.Fonts) do
		control(fonts, k)
	end
	local anim = general:AddGroup({ Name = "Animation", Side = "Left" })
	for _, k in ipairs(Theme.Sections.Animation) do
		control(anim, k)
	end

	local share = general:AddGroup({ Name = "Share & reset", Side = "Right" })
	share:AddButton({ Name = "Export theme (clipboard)", Callback = function()
		local s = Theme:ExportString()
		local copied = s and Util.SetClipboard(s)
		lib:Notify({ Title = "Theme", Content = copied and "Theme string copied to clipboard" or "Clipboard unavailable – string printed to console", Type = copied and "Success" or "Warning" })
		if not copied then
			print(s)
		end
	end })
	local importBox = share:AddTextbox({ Name = "Theme string", Flag = "__ui_theme_import", NoSave = true, Placeholder = "paste here" })
	share:AddButton({ Name = "Import theme", Callback = function()
		local s = importBox.Value
		if s == "" then
			s = Util.GetClipboard() or ""
		end
		local ok, err = Theme:ImportString(s)
		lib:Notify({ Title = "Theme", Content = ok and "Theme imported" or ("Import failed: " .. tostring(err)), Type = ok and "Success" or "Error" })
	end })
	local resetDrop = share:AddDropdown({ Name = "Section", Flag = "__ui_reset_section", NoSave = true, Values = Theme.Base.SectionOrder, Default = "Colors" })
	share:AddButton({ Name = "Reset section", Callback = function()
		Theme:Reset(resetDrop.Value)
	end })
	share:AddButton({ Name = "Reset everything", Confirm = true, Callback = function()
		Theme:Reset(nil)
	end })

	local brand = general:AddGroup({ Name = "Branding", Side = "Right" })
	for _, k in ipairs(Theme.Sections.Branding) do
		control(brand, k)
	end
	local notif = general:AddGroup({ Name = "Notifications & sounds", Side = "Right" })
	for _, k in ipairs(Theme.Sections.Notifications) do
		control(notif, k)
	end
	notif:AddButton({ Name = "Test notification", Callback = function()
		lib:Notify({ Title = "Preview", Content = "This is how notifications look.", Type = "Info" })
	end })
	for _, k in ipairs(Theme.Sections.Sounds) do
		control(notif, k)
	end

	---------------------------------------------------------------- Colors
	local colorKeys = Theme.Sections.Colors
	local half = math.ceil(#colorKeys / 2)
	local cl = colors:AddGroup({ Name = "Colors", Side = "Left" })
	local cr = colors:AddGroup({ Name = "Colors ", Side = "Right" })
	for i, k in ipairs(colorKeys) do
		control(i <= half and cl or cr, k)
	end
	local grads = colors:AddGroup({ Name = "Gradients", Side = "Left" })
	for _, k in ipairs(Theme.Sections.Gradients) do
		gradientControls(grads, k)
	end
	local bg = colors:AddGroup({ Name = "Background", Side = "Right" })
	for _, k in ipairs(Theme.Sections.Background) do
		control(bg, k)
	end

	---------------------------------------------------------------- Layout
	local lay = layout:AddGroup({ Name = "Layout", Side = "Left" })
	for _, k in ipairs(Theme.Sections.Layout) do
		control(lay, k)
	end
	local mob = layout:AddGroup({ Name = "Mobile", Side = "Right" })
	mob:AddDropdown({ Name = "Device mode", Flag = "__ui_mobile_mode", NoSave = true, Values = { "Auto", "Mobile", "Desktop" }, Default = lib.Mobile.Mode, Callback = function(v)
		lib:SetMobileMode(v)
	end })
	for _, k in ipairs(Theme.Sections.Mobile) do
		control(mob, k)
	end
	mob:AddToggle({ Name = "Floating open button", Flag = "__ui_floating_button", Default = lib.Mobile:ShowButton(), Callback = function(v)
		lib.Mobile.ForceButton = v
		lib.Renderer:Rebuild(false)
	end })
	mob:AddButton({ Name = "Edit quick toggles", Callback = function()
		lib.Mobile:SetEditMode(not lib.Mobile.EditMode)
	end })
	local ov = layout:AddGroup({ Name = "Overlays", Side = "Right" })
	ov:AddToggle({ Name = "Watermark", Flag = "__ui_watermark", Default = lib.WatermarkState.Enabled, Callback = function(v)
		lib:SetWatermark(v)
	end })
	ov:AddToggle({ Name = "Keybind list", Flag = "__ui_keybind_list", Default = lib.KeybindListState.Enabled, Callback = function(v)
		lib:SetKeybindList(v)
	end })

	---------------------------------------------------------------- sync with theme changes (presets, import, reset, skin switch)
	lib.Maid:Give(Theme.Changed:Connect(function(key)
		if key == "*" then
			for _, f in pairs(controls) do
				pcall(f)
			end
			skinDrop:Set(lib.SkinName, { Silent = true })
			presetDrop:Refresh(Theme:Presets())
		else
			local base = key:gsub("^Alpha%.", "")
			if controls[base] then
				pcall(controls[base])
			end
		end
	end))
	lib.SkinChanged:Connect(function(name)
		skinDrop:Set(name, { Silent = true })
	end)
	return tab
end
