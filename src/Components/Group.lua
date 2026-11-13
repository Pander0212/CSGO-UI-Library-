--[[
	Group (group box / section). Holds elements; every Add* returns the element logic object.
	Also used for sub-option popouts (Element:AddSubOptions()).
]]
local Element = require("Components/Element")

local Group = {}
Group.__index = Group

local counter = 0

function Group.new(lib, page, opts)
	opts = opts or {}
	counter += 1
	return setmetatable({
		Library = lib,
		Page = page, -- SubTab (nil for popouts)
		Name = opts.Name or opts.Title or "Group",
		Side = (opts.Side == "Right" or opts.Side == 2) and "Right" or "Left",
		Icon = opts.Icon,
		Options = opts,
		Elements = {},
		Order = counter,
		Visible = opts.Visible ~= false,
	}, Group)
end

function Group:_add(kind, opts)
	opts = opts or {}
	local el = Element.new(self.Library, kind, self, opts)
	el.Group = self
	table.insert(self.Elements, el)
	if self.View and self.Library.Renderer then
		self.Library.Renderer:RenderElement(el, self)
	end
	return el
end

function Group:AddToggle(opts)
	return self:_add("Toggle", opts)
end
Group.AddCheckbox = Group.AddToggle

function Group:AddSlider(opts)
	return self:_add("Slider", opts)
end

function Group:AddDropdown(opts)
	return self:_add("Dropdown", opts)
end

function Group:AddTextbox(opts)
	return self:_add("Textbox", opts)
end
Group.AddInput = Group.AddTextbox

function Group:AddKeybind(opts)
	return self:_add("Keybind", opts)
end

function Group:AddColorPicker(opts)
	return self:_add("ColorPicker", opts)
end

function Group:AddButton(opts, cb)
	if type(opts) == "string" then
		opts = { Name = opts, Callback = cb }
	end
	return self:_add("Button", opts)
end

function Group:AddLabel(opts)
	if type(opts) == "string" then
		opts = { Text = opts }
	end
	return self:_add("Label", opts)
end

function Group:AddParagraph(opts)
	return self:_add("Paragraph", opts)
end

function Group:AddDivider(opts)
	if type(opts) == "string" then
		opts = { Text = opts }
	end
	return self:_add("Divider", opts or {})
end

function Group:AddESPPreview(opts)
	return self:_add("ESPPreview", opts or {})
end

--[[
	Convenience: creates the standard ESP flags that the preview binds to
	(see ESPPreview.DefaultFlags). Returns a table of the created elements.
]]
function Group:AddESPSettings(opts)
	opts = opts or {}
	local ESP = require("ESPPreview")
	local F = ESP.ResolveFlags(opts.Flags)
	local C = Color3.fromRGB
	local out = {}
	out.Enabled = self:AddToggle({ Name = "Enabled", Flag = F.Enabled, Default = true, Pinnable = true })
	out.Box = self:AddToggle({ Name = "Bounding box", Flag = F.Box, Default = true }):AddColorPicker({ Flag = F.BoxColor, Default = C(255, 255, 255) })
	out.BoxType = self:AddDropdown({ Name = "Box type", Flag = F.BoxType, Values = { "2D", "Corner", "Filled" }, Default = "2D" })
	out.Name = self:AddToggle({ Name = "Name", Flag = F.Name, Default = true }):AddColorPicker({ Flag = F.NameColor, Default = C(255, 255, 255) })
	out.Distance = self:AddToggle({ Name = "Distance", Flag = F.Distance, Default = true })
	out.Health = self:AddToggle({ Name = "Health bar", Flag = F.HealthBar, Default = true })
	out.HealthSide = self:AddDropdown({ Name = "Health bar side", Flag = F.HealthSide, Values = { "Left", "Right", "Top", "Bottom" }, Default = "Left" })
	out.Tracer = self:AddToggle({ Name = "Tracer", Flag = F.Tracer, Default = false }):AddColorPicker({ Flag = F.TracerColor, Default = C(255, 255, 255) })
	out.Skeleton = self:AddToggle({ Name = "Skeleton", Flag = F.Skeleton, Default = false }):AddColorPicker({ Flag = F.SkeletonColor, Default = C(255, 255, 255) })
	out.Chams = self:AddToggle({ Name = "Chams", Flag = F.Chams, Default = false }):AddColorPicker({ Flag = F.ChamsColor, Default = C(160, 90, 255), Transparency = 0.3 })
	return out
end

function Group:SetVisible(v)
	self.Visible = v ~= false
	if self.View and self.View.Root then
		self.View.Root.Visible = self.Visible
	end
end

return Group
