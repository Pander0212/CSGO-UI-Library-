--[[
	Base skin: the complete reference implementation of the skin interface.
	Custom skins are created with Base.Extend{ ... } and only override what differs:

	local MySkin = UI.SkinBase.Extend({
		Name = "MySkin",
		Theme = { Defaults = { Accent = Color3.fromRGB(255, 0, 0) }, Presets = { Default = {} } },
		Style = { ToggleStyle = "Pill" },
		Window = function(ctx, window) ... end,      -- optional
		Components = { Toggle = function(ctx, el, parent) ... end }, -- optional
		Loader = function(ctx, opts, handle) ... end, -- optional
	})
	UI:RegisterSkin(MySkin)
]]
local Components = require("Skins/Base/Components")
local Overlays = require("Skins/Base/Overlays")
local Kit = require("Skins/Base/Window")

local Base = {
	Name = "Base",
	Description = "Reference skin",
	Theme = { Defaults = {}, Presets = { Default = {} } },
	Style = {},
	Components = Components,
	Window = Kit.Window,
	Group = Overlays.Group,
	DropdownList = Overlays.DropdownList,
	ColorPanel = Overlays.ColorPanel,
	Popout = Overlays.Popout,
	ContextMenu = Overlays.ContextMenu,
	Notification = Overlays.Notification,
	Dialog = Overlays.Dialog,
	Tooltip = Overlays.Tooltip,
	Watermark = Overlays.Watermark,
	KeybindList = Overlays.KeybindList,
	FloatingButton = Overlays.FloatingButton,
	QuickToggle = Overlays.QuickToggle,
	Loader = Overlays.Loader,
	-- helper namespaces for skin authors
	Kit = Kit,
	C = Components._,
	O = Overlays,
}

local SKIP = { Extend = true, Kit = true, C = true, O = true }

function Base.Extend(def)
	local skin = {}
	for k, v in pairs(Base) do
		if not SKIP[k] then
			skin[k] = v
		end
	end
	for k, v in pairs(def) do
		if k ~= "Components" and k ~= "Style" then
			skin[k] = v
		end
	end
	local comps = {}
	for k, v in pairs(Base.Components) do
		comps[k] = v
	end
	for k, v in pairs(def.Components or {}) do
		comps[k] = v
	end
	skin.Components = comps
	local style = {}
	for k, v in pairs(Base.Style) do
		style[k] = v
	end
	for k, v in pairs(def.Style or {}) do
		style[k] = v
	end
	skin.Style = style
	skin.Theme = def.Theme or { Defaults = {}, Presets = { Default = {} } }
	skin.Theme.Presets = skin.Theme.Presets or { Default = {} }
	skin.Theme.Presets.Default = skin.Theme.Presets.Default or {}
	return skin
end

return Base
