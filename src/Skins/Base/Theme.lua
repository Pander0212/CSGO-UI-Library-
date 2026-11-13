--[[
	Base theme: the complete list of theme keys with metadata + neutral default values.
	Every skin only overrides values (Skins/<Name>/Theme.lua). Renderer code never hardcodes
	colors/fonts/sizes – it always reads/binds these keys.

	Entry format: { Key, DefaultValue, Section, Extra }
	Extra: Min/Max/Step for numbers, Options for strings (dropdowns), Rebuild = true when a change
	requires the window to be rebuilt (structural layout keys), Global = true when the value is shared
	across skins (branding etc.).
]]
local C = Color3.fromRGB
local Meta = require("Meta")

local FONTS = {
	"Code", "RobotoMono", "Gotham", "GothamMedium", "GothamBold", "GothamBlack", "SourceSans",
	"SourceSansSemibold", "SourceSansBold", "Ubuntu", "Roboto", "RobotoCondensed", "Arial", "ArialBold",
	"Nunito", "Montserrat", "BuilderSans", "BuilderSansMedium", "BuilderSansBold", "Jura", "Michroma",
	"Oswald", "Arimo", "ArimoBold", "Highway", "SciFi", "Zekton", "Sarpanch", "TitilliumWeb",
}

local EASING = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back", "Bounce", "Elastic" }

local function grad(colors, rotation, enabled, animated, speed)
	return { Enabled = enabled ~= false, Colors = colors, Rotation = rotation or 0, Animated = animated == true, Speed = speed or 0.5 }
end

local Entries = {
	-- Colors ---------------------------------------------------------------------------
	{ "Accent", C(0, 170, 255), "Colors" },
	{ "AccentDark", C(0, 110, 190), "Colors" },
	{ "Background", C(16, 16, 20), "Colors" },
	{ "BackgroundSecondary", C(12, 12, 16), "Colors" },
	{ "Topbar", C(20, 20, 26), "Colors" },
	{ "Panel", C(22, 22, 28), "Colors" },
	{ "PanelHeader", C(26, 26, 33), "Colors" },
	{ "Border", C(40, 40, 50), "Colors" },
	{ "BorderDark", C(0, 0, 0), "Colors" },
	{ "BorderLight", C(60, 60, 72), "Colors" },
	{ "Element", C(30, 30, 38), "Colors" },
	{ "ElementHover", C(38, 38, 48), "Colors" },
	{ "ElementActive", C(46, 46, 58), "Colors" },
	{ "Text", C(235, 235, 240), "Colors" },
	{ "TextDim", C(150, 150, 165), "Colors" },
	{ "TextDisabled", C(85, 85, 95), "Colors" },
	{ "TextOnAccent", C(255, 255, 255), "Colors" },
	{ "Divider", C(34, 34, 42), "Colors" },
	{ "Knob", C(255, 255, 255), "Colors" },
	{ "Shadow", C(0, 0, 0), "Colors" },
	{ "Glow", C(0, 170, 255), "Colors" },
	{ "Success", C(60, 200, 120), "Colors" },
	{ "Warning", C(240, 180, 40), "Colors" },
	{ "Error", C(230, 70, 80), "Colors" },
	{ "Info", C(0, 170, 255), "Colors" },
	{ "Tooltip", C(14, 14, 18), "Colors" },
	{ "Overlay", C(0, 0, 0), "Colors" },
	{ "Highlight", C(255, 255, 255), "Colors" },

	-- Gradients (Colors may be Color3 values or names of color keys) --------------------
	{ "AccentGradient", grad({ "Accent", "AccentDark" }, 90), "Gradients" },
	{ "RainbowBar", grad({ C(59, 175, 222), C(202, 70, 205), C(201, 227, 58) }, 0, true, false, 0.35), "Gradients" },
	{ "BackgroundGradient", grad({ "Background", "BackgroundSecondary" }, 90, false), "Gradients" },
	{ "ElementGradient", grad({ "ElementHover", "Element" }, 90, false), "Gradients" },
	{ "HeaderGradient", grad({ "Accent", "AccentDark" }, 0, false), "Gradients" },

	-- Background ------------------------------------------------------------------------
	{ "BackgroundImage", "", "Background" },
	{ "BackgroundImageTransparency", 0.85, "Background", { Min = 0, Max = 1, Step = 0.01 } },
	{ "BackgroundTexture", "None", "Background", { Options = { "None", "Grid", "Scanlines", "Diagonal" }, Rebuild = true } },
	{ "TextureTransparency", 0.93, "Background", { Min = 0.5, Max = 1, Step = 0.01 } },
	{ "TextureSpacing", 6, "Background", { Min = 2, Max = 32, Step = 1, Rebuild = true } },
	{ "WindowTransparency", 0, "Background", { Min = 0, Max = 0.9, Step = 0.01 } },

	-- Fonts -----------------------------------------------------------------------------
	{ "FontTitle", "GothamBold", "Fonts", { Options = FONTS } },
	{ "FontBody", "Gotham", "Fonts", { Options = FONTS } },
	{ "FontMono", "Code", "Fonts", { Options = FONTS } },
	{ "TextSize", 13, "Fonts", { Min = 8, Max = 22, Step = 1 } },
	{ "TitleSize", 14, "Fonts", { Min = 8, Max = 28, Step = 1 } },
	{ "SmallTextSize", 11, "Fonts", { Min = 7, Max = 18, Step = 1 } },

	-- Layout ----------------------------------------------------------------------------
	{ "CornerRadius", 6, "Layout", { Min = 0, Max = 20, Step = 1 } },
	{ "SmallCornerRadius", 4, "Layout", { Min = 0, Max = 14, Step = 1 } },
	{ "BorderThickness", 1, "Layout", { Min = 0, Max = 4, Step = 1 } },
	{ "ShadowEnabled", true, "Layout" },
	{ "ShadowTransparency", 0.55, "Layout", { Min = 0, Max = 1, Step = 0.01 } },
	{ "WindowWidth", 760, "Layout", { Min = 420, Max = 1400, Step = 10 } },
	{ "WindowHeight", 540, "Layout", { Min = 320, Max = 1000, Step = 10 } },
	{ "UIScale", 1, "Layout", { Min = 0.5, Max = 1.6, Step = 0.05 } },
	{ "SidebarWidth", 180, "Layout", { Min = 56, Max = 320, Step = 2, Rebuild = true } },
	{ "Spacing", 8, "Layout", { Min = 0, Max = 24, Step = 1, Rebuild = true } },
	{ "Padding", 12, "Layout", { Min = 0, Max = 32, Step = 1, Rebuild = true } },
	{ "ElementHeight", 30, "Layout", { Min = 14, Max = 56, Step = 1, Rebuild = true } },
	{ "GroupSpacing", 10, "Layout", { Min = 0, Max = 30, Step = 1, Rebuild = true } },

	-- Animation -------------------------------------------------------------------------
	{ "AnimationsEnabled", true, "Animation" },
	{ "AnimationSpeed", 1, "Animation", { Min = 0.25, Max = 4, Step = 0.05 } },
	{ "EasingStyle", "Quint", "Animation", { Options = EASING } },
	{ "EasingDirection", "Out", "Animation", { Options = { "In", "Out", "InOut" } } },

	-- Branding (shared by every skin) ----------------------------------------------------
	{ "Title", Meta.Name, "Branding", { Global = true } },
	{ "Subtitle", "", "Branding", { Global = true } },
	{ "LogoText", "NOVA", "Branding", { Global = true } },
	{ "LogoImage", "", "Branding", { Global = true } },
	{ "Username", "", "Branding", { Global = true } }, -- empty = LocalPlayer.DisplayName
	{ "UserInfo", "Expires: never", "Branding", { Global = true } },
	{ "AvatarImage", "", "Branding", { Global = true } }, -- empty = LocalPlayer thumbnail
	{ "LoaderTitle", "", "Branding", { Global = true } }, -- empty = Title
	{ "LoaderSubtitle", "Welcome back", "Branding", { Global = true } },
	{ "LoaderStatus", "Ready", "Branding", { Global = true } },

	-- Notifications ---------------------------------------------------------------------
	{ "NotifyPosition", "BottomRight", "Notifications", { Global = true, Options = { "TopLeft", "TopRight", "TopCenter", "BottomLeft", "BottomRight", "BottomCenter" } } },
	{ "NotifyDuration", 4, "Notifications", { Global = true, Min = 1, Max = 15, Step = 0.5 } },
	{ "NotifyWidth", 260, "Notifications", { Min = 180, Max = 420, Step = 10 } },

	-- Sounds ----------------------------------------------------------------------------
	{ "SoundsEnabled", false, "Sounds", { Global = true } },
	{ "SoundVolume", 0.5, "Sounds", { Global = true, Min = 0, Max = 1, Step = 0.05 } },
	{ "SoundClick", "rbxasset://sounds/electronicpingshort.wav", "Sounds", { Global = true } },
	{ "SoundToggle", "rbxasset://sounds/electronicpingshort.wav", "Sounds", { Global = true } },
	{ "SoundNotify", "rbxasset://sounds/electronicpingshort.wav", "Sounds", { Global = true } },

	-- Mobile ----------------------------------------------------------------------------
	{ "MobileButtonSize", 52, "Mobile", { Min = 36, Max = 90, Step = 1 } },
	{ "MobileButtonShape", "Circle", "Mobile", { Options = { "Circle", "Rounded", "Square" } } },
	{ "TouchTarget", 44, "Mobile", { Min = 32, Max = 64, Step = 1, Rebuild = true } },
	{ "QuickToggleShape", "Rounded", "Mobile", { Options = { "Circle", "Rounded", "Square" } } },
}

local Defaults, Meta_, Order, Sections = {}, {}, {}, {}
for _, e in ipairs(Entries) do
	local key, value, section, extra = e[1], e[2], e[3], e[4] or {}
	Defaults[key] = value
	extra.Section = section
	extra.Type = typeof(value) == "table" and "Gradient" or typeof(value)
	Meta_[key] = extra
	table.insert(Order, key)
	Sections[section] = Sections[section] or {}
	table.insert(Sections[section], key)
end

return {
	Defaults = Defaults,
	Meta = Meta_,
	Order = Order,
	Sections = Sections,
	SectionOrder = { "Colors", "Gradients", "Background", "Fonts", "Layout", "Animation", "Branding", "Notifications", "Sounds", "Mobile" },
	Fonts = FONTS,
}
