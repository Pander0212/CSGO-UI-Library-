--[[
	Skin "Modern" – wide blue-black window, sidebar with logo / categories / user card,
	top bar with sub-tabs, config selector, save button and search, rounded groups,
	pill switches, sliders with a value bubble, gear popouts and smooth animations.
]]
local Base = require("Skins/Base")
local W = require("Skins/Modern/Window")

return Base.Extend({
	Name = "Modern",
	Description = "Wide window, sidebar categories, search, pill switches",
	Theme = require("Skins/Modern/Theme"),
	Style = {
		ToggleStyle = "Pill",
		PillW = 32,
		PillH = 17,
		ToggleLabelActive = false,
		LabelAbove = false,
		InlineWidth = 0.5,
		SliderValue = "Bubble",
		SliderTrack = 4,
		SliderKnob = 11,
		TrackCorner = "full",
		ControlCorner = "SmallCornerRadius",
		ControlStroke = "Border",
		ControlStrokeHover = "BorderLight",
		RowDividers = true,
		KeyStyle = "Chip",
		SwatchW = 18,
		SwatchH = 18,
		SwatchCorner = "full",
		SwatchStroke = "BorderLight",
		ButtonStyle = "Filled",
		ButtonStroke = "Border",
		ButtonStrokeHover = "Accent",
		ButtonHeight = 1.05,
		BoxHeight = 0.9,
		ListItemH = 0.95,
		PanelStroke = "Border",
		IconBg = "Panel",
		GearSize = 13,
		PopoutWidth = 250,
		DialogWidth = 360,
	},
	Window = W.Window,
	Group = W.Group,
	Loader = require("Skins/Modern/Loader"),
})
