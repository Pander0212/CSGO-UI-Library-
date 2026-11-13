--[[
	Skin "Dashboard" – original design: top bar with page tabs, search, notification bell and avatar,
	sidebar with collapsible categories, page header with status cards, card groups, large primary buttons.
]]
local Base = require("Skins/Base")
local W = require("Skins/Dashboard/Window")

return Base.Extend({
	Name = "Dashboard",
	Description = "Modern dashboard: cards, status cards, collapsible sidebar",
	Theme = require("Skins/Dashboard/Theme"),
	Style = {
		ToggleStyle = "Pill",
		PillW = 38,
		PillH = 21,
		ToggleLabelActive = false,
		LabelAbove = false,
		InlineWidth = 0.5,
		SliderValue = "Bubble",
		SliderTrack = 6,
		SliderKnob = 14,
		KnobStroke = "Accent",
		SliderGradient = true,
		TrackCorner = "full",
		ControlCorner = "SmallCornerRadius",
		ControlStroke = "Border",
		ControlStrokeHover = "Accent",
		KeyStyle = "Chip",
		SwatchW = 22,
		SwatchH = 22,
		SwatchCorner = "SmallCornerRadius",
		SwatchStroke = "BorderLight",
		ButtonStyle = "Primary",
		ButtonHeight = 1.25,
		ButtonFont = "FontTitle",
		ButtonCorner = "SmallCornerRadius",
		BoxHeight = 1,
		ListItemH = 1,
		PanelStroke = "Border",
		IconBg = "Panel",
		GearSize = 14,
		PopoutWidth = 270,
		DialogWidth = 380,
	},
	Window = W.Window,
	Group = W.Group,
	Loader = require("Skins/Dashboard/Loader"),
})
