--[[
	Base component renderers. Every skin inherits these and overrides what looks different.
	Each renderer: function(ctx, element, parent) -> view
	  view.Root               GuiObject (row)
	  view.Update(self, value, instant)
	  view.SetDisabled(self, disabled)
	  view.Addons             frame for inline color pickers / keybinds (optional)
	  view.SetHasSub(self, b) shows the gear (sub-options) button (optional)

	ctx.Style switches read here (all optional):
	  ToggleStyle "Checkbox"|"Pill"   CheckSize   CheckCorner (theme key / number)  CheckGradient (bool)
	  PillW, PillH                    ToggleLabelActive (label brightens when on)
	  LabelAbove (slider/dropdown/textbox label on its own line)   InlineWidth (0..1 control width when inline)
	  SliderTrack (px)  SliderKnob (px, 0 = none)  SliderValue "Right"|"Center"|"Bubble"  SliderGradient (bool)
	  KeyStyle "Brackets"|"Chip"      SwatchW, SwatchH, SwatchCorner
	  ControlCorner (key)             ControlStroke (key|nil)  ControlGradient (bool)
	  RowDividers (bool)              ButtonStyle "Outline"|"Filled"|"Primary"   ButtonHeight (mult)
	  LabelCase "upper"|nil
]]
local Util = require("Core/Util")
local Tween = require("Core/Tween")
local Types = require("Components/Types")
local Input = require("Core/Input")

local C = {}

local function S(ctx, key, default)
	local v = ctx.Style[key]
	if v == nil then
		return default
	end
	return v
end

local function caseText(ctx, text)
	if S(ctx, "LabelCase") == "upper" then
		return string.upper(text)
	end
	return text
end
C.CaseText = caseText

---------------------------------------------------------------- shared bits
function C.Row(ctx, parent, el, height)
	local root = ctx:Frame(parent, { Name = el.Kind .. "_" .. tostring(el.Name), Size = UDim2.new(1, 0, 0, height) })
	if S(ctx, "RowDividers") then
		local d = ctx:Frame(root, { Name = "Divider", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, math.floor(ctx:T("Spacing") / 2)), Size = UDim2.new(1, 0, 0, 1) }, "Divider")
		d.ZIndex = root.ZIndex
	end
	return root
end

function C.Label(ctx, parent, el, props)
	props = props or {}
	props.Text = caseText(ctx, tostring(el.Name))
	props.Size = props.Size or UDim2.fromScale(1, 1)
	props.TextTruncate = Enum.TextTruncate.AtEnd
	return ctx:Text(parent, props, props.ColorKey or S(ctx, "LabelColor", "Text"))
end

-- right aligned horizontal holder for addons / gear / pin
function C.AddonHolder(ctx, parent, rightInset)
	local h = ctx:Frame(parent, {
		Name = "Addons",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(rightInset or 0), 0.5, 0),
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		ZIndex = parent.ZIndex + 10,
	})
	ctx:List(h, { Dir = "H", Pad = 4, HA = "Right", VA = "Center" })
	return h
end

-- small icon button (gear, pin)
function C.IconButton(ctx, parent, icon, order, size)
	size = size or 14
	local t = ctx:Touch(size + 4)
	local b = ctx:New("TextButton", { Parent = parent, Name = icon .. "Btn", Size = UDim2.fromOffset(t, t), BackgroundTransparency = 1, LayoutOrder = order, ZIndex = parent.ZIndex + 1 })
	local i = ctx:Icon(b, icon, size, "TextDim", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = b.ZIndex + 1, BgKey = S(ctx, "IconBg", "Panel") })
	ctx:Hover(b, function(st)
		ctx:IconColor(i, (st == "Hover" or st == "Press") and "Text" or (b:GetAttribute("Active") and "Accent" or "TextDim"), true)
	end)
	return b, i
end

-- gear + pin support shared by every element view
function C.Extras(ctx, el, view, holder)
	function view:SetHasSub(has)
		if has and not view.Gear then
			local g = C.IconButton(ctx, holder, "gear", 900, S(ctx, "GearSize", 13))
			view.Gear = g
			g.Activated:Connect(function()
				if el:IsDisabled() then
					return
				end
				ctx.Renderer:OpenPopout(el, g)
			end)
		end
		if view.Gear then
			view.Gear.Visible = has
		end
	end
	if el.Kind == "Toggle" and el.Options.Pinnable then
		local p, icon = C.IconButton(ctx, holder, "pin", 950, 12)
		view.PinButton = p
		local function refresh()
			local pinned = ctx.Library.Mobile:IsPinned(el)
			p:SetAttribute("Active", pinned)
			ctx:IconColor(icon, pinned and "Accent" or "TextDim", true)
			p.Visible = pinned or ctx.IsMobile or view._hover == true
		end
		view.RefreshPin = refresh
		p.Activated:Connect(function()
			el:Pin(not ctx.Library.Mobile:IsPinned(el))
			refresh()
		end)
		refresh()
	end
end

-- Control box (dropdown / textbox / keybind chip)
function C.Box(ctx, parent, props)
	props = props or {}
	local class = props.Class or "TextButton"
	props.Class = nil
	props.Parent = parent
	local b = ctx:New(class, props)
	ctx.Theme:Bind(b, "BackgroundColor3", "Element")
	ctx:Corner(b, S(ctx, "ControlCorner", "SmallCornerRadius"))
	local stroke
	if S(ctx, "ControlStroke") then
		stroke = ctx:Stroke(b, S(ctx, "ControlStroke"), 1)
	end
	if S(ctx, "ControlGradient") then
		ctx:Grad(b, "ElementGradient", { Force = true })
	end
	return b, stroke
end

function C.BoxState(ctx, box, stroke, st)
	local key = (st == "Hover" and "ElementHover") or (st == "Press" and "ElementActive") or "Element"
	ctx.Theme:Bind(box, "BackgroundColor3", key, { Tween = true, Duration = 0.12 })
	if stroke then
		ctx.Theme:Bind(stroke, "Color", (st == "Hover" or st == "Press") and S(ctx, "ControlStrokeHover", "BorderLight") or S(ctx, "ControlStroke"), { Tween = true })
	end
end

---------------------------------------------------------------- Toggle
function C.Toggle(ctx, el, parent)
	local h = ctx:RowH(S(ctx, "ToggleHeight", 1))
	local root = C.Row(ctx, parent, el, h)
	local view = { Root = root }
	local pill = S(ctx, "ToggleStyle", "Checkbox") == "Pill"
	local hit = ctx:Hitbox(root, { ZIndex = root.ZIndex + 1 })
	view.Hit = hit
	local addons = C.AddonHolder(ctx, root)
	view.Addons = addons
	local box, knob, label, check
	if pill then
		local pw, ph = S(ctx, "PillW", 30), S(ctx, "PillH", 16)
		box = ctx:Frame(addons, { Name = "Switch", Size = UDim2.fromOffset(pw, ph), LayoutOrder = 1000 }, "Element")
		ctx:Corner(box, "full")
		if S(ctx, "PillStroke") then
			ctx:Stroke(box, S(ctx, "PillStroke"), 1)
		end
		local k = ph - 6
		knob = ctx:Frame(box, { Size = UDim2.fromOffset(k, k), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0) }, "TextDim")
		ctx:Corner(knob, "full")
		label = C.Label(ctx, root, el, { Size = UDim2.new(1, -pw - 8, 1, 0) })
	else
		-- the whole row is the touch target, so the box keeps its visual size on mobile
		local cs = S(ctx, "CheckSize", 12)
		box = ctx:Frame(root, { Name = "Check", Size = UDim2.fromOffset(cs, cs), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) }, "Element")
		ctx:Corner(box, S(ctx, "CheckCorner", "SmallCornerRadius"))
		if S(ctx, "CheckStroke") then
			ctx:Stroke(box, S(ctx, "CheckStroke"), 1)
		end
		view.Gradient = ctx:Grad(box, S(ctx, "CheckGradientKey", "AccentGradient"), { Force = S(ctx, "CheckGradient", false) })
		if S(ctx, "CheckMark", true) then
			check = ctx:Icon(box, "check", math.floor(cs * 0.8), "TextOnAccent", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
			check.Visible = false
		end
		label = C.Label(ctx, root, el, { Position = UDim2.fromOffset(cs + S(ctx, "CheckGap", 8), 0), Size = UDim2.new(1, -cs - 8, 1, 0) })
	end
	view.Label = label
	view.Box = box
	local hovered = false
	local function paint(instant)
		local on = el.Value
		local dis = el:IsDisabled()
		local tw = not instant
		if pill then
			local pw, ph = S(ctx, "PillW", 30), S(ctx, "PillH", 16)
			local k = ph - 6
			ctx.Theme:Bind(box, "BackgroundColor3", on and "Accent" or (hovered and "ElementHover" or "Element"), { Tween = tw, Alpha = dis and 0.5 or 0 })
			ctx.Theme:Bind(knob, "BackgroundColor3", on and "Knob" or "TextDim", { Tween = tw })
			local pos = on and UDim2.new(0, pw - k - 3, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
			if instant then
				knob.Position = pos
			else
				Tween.Play(knob, { Position = pos }, 0.2)
			end
		else
			if view.Gradient then
				view.Gradient.Enabled = S(ctx, "CheckGradient", false) or (on and ctx:T("AccentGradient").Enabled)
				if not on and S(ctx, "CheckGradient", false) then
					ctx.Theme:BindGradient(view.Gradient, "ElementGradient", { Force = true })
				elseif S(ctx, "CheckGradient", false) then
					ctx.Theme:BindGradient(view.Gradient, S(ctx, "CheckGradientKey", "AccentGradient"), { Force = true })
				end
			end
			ctx.Theme:Bind(box, "BackgroundColor3", on and "Accent" or (hovered and "ElementHover" or "Element"), { Tween = tw, Alpha = dis and 0.5 or 0 })
			if check then
				check.Visible = on
			end
		end
		local labelKey = dis and "TextDisabled" or ((on or hovered or not S(ctx, "ToggleLabelActive", false)) and "Text" or "TextDim")
		ctx.Theme:Bind(label, "TextColor3", labelKey, { Tween = tw })
	end
	ctx:Hover(hit, function(st)
		hovered = st == "Hover" or st == "Press"
		view._hover = hovered
		if view.RefreshPin then
			view.RefreshPin()
		end
		paint(false)
	end, el)
	ctx.Maid:Give(ctx.Input:Drag(hit, {
		Threshold = 8,
		OnTap = function()
			if el:IsDisabled() then
				return
			end
			ctx:Sound("SoundToggle")
			el:Set(not el.Value)
		end,
		LongPress = el.Options.Pinnable and function()
			el:Pin(not ctx.Library.Mobile:IsPinned(el))
			if view.RefreshPin then
				view.RefreshPin()
			end
		end or nil,
	}))
	C.Extras(ctx, el, view, addons)
	function view:Update(_, instant)
		paint(instant)
	end
	function view:SetDisabled()
		paint(true)
	end
	function view:SetText(t)
		label.Text = caseText(ctx, t)
	end
	return view
end

---------------------------------------------------------------- Slider
function C.Slider(ctx, el, parent)
	local o = el.Options
	local above = S(ctx, "LabelAbove", true)
	local trackH = S(ctx, "SliderTrack", 6)
	local valueMode = S(ctx, "SliderValue", "Right")
	local rowH = ctx:RowH()
	local h = above and math.floor(rowH * S(ctx, "SliderRows", 1.55)) or rowH
	local root = C.Row(ctx, parent, el, h)
	local view = { Root = root }
	local labelH = above and (h - trackH - S(ctx, "SliderBottom", 4)) or h
	local label = C.Label(ctx, root, el, { Size = above and UDim2.new(1, -60, 0, labelH) or UDim2.new(1 - S(ctx, "InlineWidth", 0.5), -8, 1, 0) })
	local valueText = ctx:Text(root, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 70, 0, above and labelH or h),
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = valueMode == "Right",
	}, S(ctx, "SliderValueColor", "TextDim"), "FontMono", "SmallTextSize")
	local track = ctx:Frame(root, {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 1),
		Position = above and UDim2.new(0, 0, 1, -S(ctx, "SliderBottom", 4)) or UDim2.new(1 - S(ctx, "InlineWidth", 0.5), 0, 0.5, trackH / 2),
		Size = above and UDim2.new(1, 0, 0, trackH) or UDim2.new(S(ctx, "InlineWidth", 0.5), (valueMode == "Right" or valueMode == "Bubble") and -48 or 0, 0, trackH),
	}, "Element")
	if not above and (valueMode == "Right" or valueMode == "Bubble") then
		valueText.Size = UDim2.new(0, 42, 1, 0)
	end
	ctx:Corner(track, S(ctx, "TrackCorner", "full"))
	if S(ctx, "TrackStroke") then
		ctx:Stroke(track, S(ctx, "TrackStroke"), 1)
	end
	if S(ctx, "ControlGradient") then
		ctx:Grad(track, "ElementGradient", { Force = true })
	end
	local fill = ctx:Frame(track, { Name = "Fill", Size = UDim2.fromScale(0, 1) }, "Accent")
	ctx:Corner(fill, S(ctx, "TrackCorner", "full"))
	ctx:Grad(fill, "AccentGradient", { Force = S(ctx, "SliderGradient", false) })
	local knob
	local ks = S(ctx, "SliderKnob", 0)
	if ks > 0 then
		knob = ctx:Frame(track, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(ks, ks), Position = UDim2.fromScale(0, 0.5), ZIndex = track.ZIndex + 2 }, "Knob")
		ctx:Corner(knob, "full")
		if S(ctx, "KnobStroke") then
			ctx:Stroke(knob, S(ctx, "KnobStroke"), 2)
		end
	end
	local center
	if valueMode == "Center" then
		center = ctx:Text(track, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 60, 0, 12),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = track.ZIndex + 3,
			TextStrokeTransparency = 0.3,
		}, "Text", "FontMono", "SmallTextSize")
	end
	local bubble, bubbleText
	if valueMode == "Bubble" then
		bubble = ctx:Frame(track, { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(38, 18), Position = UDim2.new(0, 0, 0, -6), ZIndex = track.ZIndex + 5, Visible = false }, "Accent")
		ctx:Corner(bubble, "SmallCornerRadius")
		bubbleText = ctx:Text(bubble, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = bubble.ZIndex + 1 }, "TextOnAccent", "FontMono", "SmallTextSize")
		valueText.Visible = true
	end
	local hit = ctx:Hitbox(root, { Size = UDim2.new(track.Size.X.Scale, track.Size.X.Offset, 0, math.max(trackH + 14, ctx:Touch(trackH + 10))), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(track.Position.X.Scale, track.Position.X.Offset, track.Position.Y.Scale, track.Position.Y.Offset - trackH / 2) })
	view.Hit = hit
	local dragging, hovered = false, false
	local function setFromX(x)
		local abs = track.AbsolutePosition.X
		local w = math.max(track.AbsoluteSize.X, 1)
		local t = Util.Clamp((x - abs) / w, 0, 1)
		el:Set(o.Min + (o.Max - o.Min) * t)
	end
	ctx.Maid:Give(ctx.Input:Drag(hit, {
		Enabled = function()
			return not el:IsDisabled()
		end,
		OnStart = function(p)
			dragging = true
			setFromX(Input.ToAbs(p).X)
			view:Paint()
		end,
		OnMove = function(_, p)
			setFromX(Input.ToAbs(p).X)
		end,
		OnEnd = function()
			dragging = false
			view:Paint()
		end,
	}))
	ctx:Hover(hit, function(st)
		hovered = st ~= "Idle" and st ~= "Disabled"
		view:Paint()
	end, el)
	function view:Paint()
		local dis = el:IsDisabled()
		ctx.Theme:Bind(fill, "BackgroundColor3", dis and "TextDisabled" or "Accent", { Tween = true })
		ctx.Theme:Bind(label, "TextColor3", dis and "TextDisabled" or "Text", { Tween = true })
		ctx.Theme:Bind(track, "BackgroundColor3", (hovered or dragging) and "ElementHover" or "Element", { Tween = true })
		if bubble then
			bubble.Visible = (hovered or dragging) and not dis
		end
		if knob then
			Tween.Play(knob, { Size = UDim2.fromOffset(ks + ((hovered or dragging) and 2 or 0), ks + ((hovered or dragging) and 2 or 0)) }, 0.12)
		end
	end
	function view:Update(v, instant)
		local t = (v - o.Min) / math.max(o.Max - o.Min, 1e-9)
		local text = Types.Slider.Format(el, v)
		valueText.Text = text
		if center then
			center.Text = text
			center.Position = UDim2.new(Util.Clamp(t, 0.06, 0.94), 0, 0.5, 0)
		end
		if bubbleText then
			bubbleText.Text = text
			bubble.Size = UDim2.fromOffset(math.max(30, Util.TextWidth(text, ctx:T("SmallTextSize"), ctx:T("FontMono")) + 12), 18)
			bubble.Position = UDim2.new(t, 0, 0, -6)
		end
		local d = (instant or dragging) and 0 or 0.12
		Tween.Play(fill, { Size = UDim2.fromScale(t, 1) }, d)
		if knob then
			Tween.Play(knob, { Position = UDim2.fromScale(t, 0.5) }, d)
		end
	end
	function view:SetDisabled()
		view:Paint()
	end
	function view:SetText(t)
		label.Text = caseText(ctx, t)
	end
	view:Paint()
	return view
end

---------------------------------------------------------------- Dropdown
function C.Dropdown(ctx, el, parent)
	local above = S(ctx, "LabelAbove", true)
	local rowH = ctx:RowH()
	local boxH = math.floor(rowH * S(ctx, "BoxHeight", 0.9))
	local h = above and (rowH + boxH - S(ctx, "AboveOverlap", 4)) or rowH
	local root = C.Row(ctx, parent, el, h)
	local view = { Root = root }
	local iw = S(ctx, "InlineWidth", 0.5)
	local label = C.Label(ctx, root, el, { Size = above and UDim2.new(1, 0, 0, h - boxH) or UDim2.new(1 - iw, -8, 1, 0) })
	local addons = C.AddonHolder(ctx, root)
	if above then
		addons.AnchorPoint = Vector2.new(1, 0)
		addons.Position = UDim2.new(1, 0, 0, 0)
		addons.Size = UDim2.new(0, 0, 0, h - boxH)
	end
	view.Addons = addons
	local box, stroke = C.Box(ctx, root, {
		AnchorPoint = Vector2.new(1, 1),
		Position = above and UDim2.new(1, 0, 1, 0) or UDim2.new(1, 0, 0.5, boxH / 2),
		Size = above and UDim2.new(1, 0, 0, boxH) or UDim2.new(iw, 0, 0, boxH),
	})
	if not above then
		addons.Position = UDim2.new(1 - iw, -6, 0.5, 0)
	end
	view.Hit = box
	local text = ctx:Text(box, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -26, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd }, "TextDim", "FontBody", "SmallTextSize")
	local arrow = ctx:Icon(box, "chevron", S(ctx, "ArrowSize", 10), "TextDim", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0) })
	ctx:Hover(box, function(st)
		C.BoxState(ctx, box, stroke, st)
	end, el)
	local entry
	box.Activated:Connect(function()
		if el:IsDisabled() then
			return
		end
		ctx:Sound("SoundClick")
		if entry then
			ctx:CloseOverlay(entry)
			return
		end
		local list = ctx.Skin.DropdownList(ctx, el, box)
		Tween.Play(arrow, { Rotation = 180 }, 0.15)
		entry = ctx:OpenOverlay(list.Root, function()
			entry = nil
			view.List = nil
			Tween.Play(arrow, { Rotation = 0 }, 0.15)
		end)
		view.List = list
	end)
	C.Extras(ctx, el, view, addons)
	function view:Update(v)
		text.Text = Types.Dropdown.Display(el, v)
		if view.List and view.List.Refresh then
			view.List:Refresh()
		end
	end
	function view:Refresh()
		view:Update(el.Value)
	end
	function view:SetDisabled(d)
		ctx.Theme:Bind(label, "TextColor3", d and "TextDisabled" or "Text")
		ctx.Theme:Bind(text, "TextColor3", d and "TextDisabled" or "TextDim")
	end
	function view:SetText(t)
		label.Text = caseText(ctx, t)
	end
	return view
end

---------------------------------------------------------------- Textbox
function C.Textbox(ctx, el, parent)
	local above = S(ctx, "LabelAbove", true)
	local rowH = ctx:RowH()
	local boxH = math.floor(rowH * S(ctx, "BoxHeight", 0.9))
	local h = above and (rowH + boxH - S(ctx, "AboveOverlap", 4)) or rowH
	local root = C.Row(ctx, parent, el, h)
	local view = { Root = root }
	local iw = S(ctx, "InlineWidth", 0.5)
	local label = C.Label(ctx, root, el, { Size = above and UDim2.new(1, 0, 0, h - boxH) or UDim2.new(1 - iw, -8, 1, 0) })
	local frame, stroke = C.Box(ctx, root, {
		Class = "Frame",
		AnchorPoint = Vector2.new(1, 1),
		Position = above and UDim2.new(1, 0, 1, 0) or UDim2.new(1, 0, 0.5, boxH / 2),
		Size = above and UDim2.new(1, 0, 0, boxH) or UDim2.new(iw, 0, 0, boxH),
	})
	local box = ctx:Text(frame, {
		Position = UDim2.fromOffset(8, 0),
		Size = UDim2.new(1, -16, 1, 0),
		PlaceholderText = el.Options.Placeholder or "...",
		ClearTextOnFocus = el.Options.ClearTextOnFocus == true,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, "Text", "FontBody", "SmallTextSize", "TextBox")
	ctx.Theme:Bind(box, "PlaceholderColor3", "TextDisabled")
	view.Hit = box
	local focused = false
	box.Focused:Connect(function()
		if el:IsDisabled() then
			box:ReleaseFocus()
			return
		end
		focused = true
		if stroke then
			ctx.Theme:Bind(stroke, "Color", "Accent", { Tween = true })
		end
		ctx.Theme:Bind(frame, "BackgroundColor3", "ElementActive", { Tween = true })
	end)
	box.FocusLost:Connect(function(enter)
		focused = false
		C.BoxState(ctx, frame, stroke, "Idle")
		if el.Options.Finished and not enter then
			box.Text = el.Value
			return
		end
		el:Set(box.Text)
		box.Text = el.Value
	end)
	if el.Options.Numeric then
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local clean = box.Text:gsub("[^%d%.%-]", "")
			if clean ~= box.Text then
				box.Text = clean
			end
		end)
	end
	ctx:Hover(frame, function(st)
		if not focused then
			C.BoxState(ctx, frame, stroke, st)
		end
	end, el)
	function view:Update(v)
		if not focused then
			box.Text = v
		end
	end
	function view:SetDisabled(d)
		ctx.Theme:Bind(label, "TextColor3", d and "TextDisabled" or "Text")
		box.TextEditable = not d
	end
	function view:SetText(t)
		label.Text = caseText(ctx, t)
	end
	return view
end

---------------------------------------------------------------- keybind
-- key display (shared by row keybind and inline keybind)
function C.KeyDisplay(ctx, el, parent, props)
	local style = S(ctx, "KeyStyle", "Chip")
	props = props or {}
	local b
	if style == "Brackets" then
		b = ctx:Text(parent, {
			Size = UDim2.fromOffset(40, 14),
			AutomaticSize = Enum.AutomaticSize.X,
			TextXAlignment = Enum.TextXAlignment.Right,
			LayoutOrder = props.LayoutOrder,
			AnchorPoint = props.AnchorPoint,
			Position = props.Position,
			ZIndex = parent.ZIndex + 1,
		}, "TextDisabled", "FontMono", "SmallTextSize", "TextButton")
	else
		b = ctx:New("TextButton", {
			Parent = parent,
			Size = UDim2.fromOffset(28, math.floor(ctx:RowH() * 0.7)),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = props.LayoutOrder,
			AnchorPoint = props.AnchorPoint,
			Position = props.Position,
			ZIndex = parent.ZIndex + 1,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, { BackgroundColor3 = "Element", TextColor3 = "TextDim", Font = "FontMono", TextSize = "SmallTextSize" })
		b.BackgroundTransparency = 0
		ctx:Corner(b, "SmallCornerRadius")
		ctx:Pad(b, 0, 6, 0, 6)
		if S(ctx, "ControlStroke") then
			ctx:Stroke(b, S(ctx, "ControlStroke"), 1)
		end
	end
	local listening = false
	local function render()
		if listening then
			b.Text = style == "Brackets" and "[...]" or "..."
		else
			local k = el:KeyText()
			b.Text = style == "Brackets" and ("[" .. k .. "]") or k
		end
	end
	ctx:Hover(b, function(st)
		ctx.Theme:Bind(b, "TextColor3", listening and "Accent" or (st == "Hover" and "Text" or (style == "Brackets" and "TextDisabled" or "TextDim")), { Tween = true })
		if style ~= "Brackets" then
			ctx.Theme:Bind(b, "BackgroundColor3", st == "Hover" and "ElementHover" or "Element", { Tween = true })
		end
	end, el)
	b.Activated:Connect(function()
		if el:IsDisabled() or listening then
			return
		end
		listening = true
		render()
		ctx.Theme:Bind(b, "TextColor3", "Accent")
		ctx.Library:CaptureKey(function(key)
			listening = false
			el:Set({ Key = key, Mode = el.Value.Mode })
			render()
			ctx.Theme:Bind(b, "TextColor3", style == "Brackets" and "TextDisabled" or "TextDim")
		end)
	end)
	-- right click / long press: mode menu
	local function modeMenu()
		if el:IsDisabled() then
			return
		end
		local items = {}
		for _, m in ipairs(Types.Modes) do
			table.insert(items, { Text = m, Selected = el.Value.Mode == m, Callback = function()
				el:Set({ Key = el.Value.Key, Mode = m })
			end })
		end
		ctx.Skin.ContextMenu(ctx, b, items)
	end
	b.MouseButton2Click:Connect(modeMenu)
	ctx.Maid:Give(ctx.Input:Drag(b, { Threshold = 10, LongPress = modeMenu, LongPressTime = 0.55 }))
	return b, render
end

function C.Keybind(ctx, el, parent)
	local root = C.Row(ctx, parent, el, ctx:RowH())
	local view = { Root = root }
	local label = C.Label(ctx, root, el, { Size = UDim2.new(1, -80, 1, 0) })
	local addons = C.AddonHolder(ctx, root)
	view.Addons = addons
	local key, render = C.KeyDisplay(ctx, el, addons, { LayoutOrder = 1000 })
	view.Hit = key
	C.Extras(ctx, el, view, addons)
	function view:Update()
		render()
	end
	function view:SetDisabled(d)
		ctx.Theme:Bind(label, "TextColor3", d and "TextDisabled" or "Text")
	end
	function view:SetText(t)
		label.Text = caseText(ctx, t)
	end
	return view
end

function C.InlineKeybind(ctx, el, holder)
	local key, render = C.KeyDisplay(ctx, el, holder, {})
	local view = { Root = key }
	function view:Update()
		render()
	end
	return view
end

---------------------------------------------------------------- color picker
function C.Swatch(ctx, el, parent, props)
	props = props or {}
	local w, h = S(ctx, "SwatchW", 18), S(ctx, "SwatchH", 10)
	-- transparent button sized for touch, the visible swatch sits centered inside it
	local hw, hh = ctx:Touch(w), ctx.IsMobile and ctx:Touch(h) or h
	local b = ctx:New("TextButton", {
		Parent = parent,
		Name = "Swatch",
		Size = UDim2.fromOffset(hw, hh),
		LayoutOrder = props.LayoutOrder,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		ZIndex = parent.ZIndex + 1,
		BackgroundTransparency = 1,
	})
	local sw = ctx:New("Frame", { Parent = b, Name = "Color", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, h), ZIndex = b.ZIndex + 1 })
	ctx:Corner(sw, S(ctx, "SwatchCorner", "SmallCornerRadius"))
	local stroke = ctx:Stroke(sw, S(ctx, "SwatchStroke", "BorderDark"), 1)
	if S(ctx, "SwatchShade", false) then
		local shade = ctx:Shade(sw, 90, 0, 0)
		shade.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	end
	ctx:Hover(b, function(st)
		ctx.Theme:Bind(stroke, "Color", st == "Idle" and S(ctx, "SwatchStroke", "BorderDark") or "Accent", { Tween = true })
	end, el)
	local entry
	b.Activated:Connect(function()
		if el:IsDisabled() then
			return
		end
		ctx:Sound("SoundClick")
		if entry then
			ctx:CloseOverlay(entry)
			return
		end
		local panel = ctx.Skin.ColorPanel(ctx, el, b)
		entry = ctx:OpenOverlay(panel.Root, function()
			entry = nil
		end)
	end)
	local function update(v)
		sw.BackgroundColor3 = v.Color
		sw.BackgroundTransparency = v.Transparency * 0.8
	end
	return b, update
end

function C.ColorPicker(ctx, el, parent)
	local root = C.Row(ctx, parent, el, ctx:RowH())
	local view = { Root = root }
	local label = C.Label(ctx, root, el, { Size = UDim2.new(1, -60, 1, 0) })
	local addons = C.AddonHolder(ctx, root)
	view.Addons = addons
	local sw, update = C.Swatch(ctx, el, addons, { LayoutOrder = 1000 })
	view.Hit = sw
	C.Extras(ctx, el, view, addons)
	function view:Update(v)
		update(v)
	end
	function view:SetDisabled(d)
		ctx.Theme:Bind(label, "TextColor3", d and "TextDisabled" or "Text")
	end
	function view:SetText(t)
		label.Text = caseText(ctx, t)
	end
	return view
end

function C.InlineColorPicker(ctx, el, holder)
	local sw, update = C.Swatch(ctx, el, holder, {})
	local view = { Root = sw }
	function view:Update(v)
		update(v)
	end
	return view
end

---------------------------------------------------------------- button
function C.Button(ctx, el, parent)
	local h = ctx:RowH(S(ctx, "ButtonHeight", 1))
	local root = C.Row(ctx, parent, el, h)
	local view = { Root = root }
	local style = el.Options.Style or S(ctx, "ButtonStyle", "Filled")
	local inset = S(ctx, "ButtonInset", 2)
	local b = ctx:New("TextButton", {
		Parent = root,
		Size = UDim2.new(1, 0, 1, -inset * 2),
		Position = UDim2.fromOffset(0, inset),
		Text = caseText(ctx, el.Name),
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0,
		ClipsDescendants = true,
	}, { Font = S(ctx, "ButtonFont", "FontBody"), TextSize = "TextSize" })
	ctx:Corner(b, S(ctx, "ButtonCorner", S(ctx, "ControlCorner", "SmallCornerRadius")))
	local stroke
	if style == "Outline" or S(ctx, "ButtonStroke") then
		stroke = ctx:Stroke(b, S(ctx, "ButtonStroke", "Border"), 1)
	end
	local grad
	if S(ctx, "ControlGradient") and style ~= "Primary" then
		grad = ctx:Grad(b, "ElementGradient", { Force = true })
	elseif style == "Primary" then
		grad = ctx:Grad(b, "AccentGradient")
	end
	view.Hit = b
	local confirming = false
	local function paint(st)
		local dis = el:IsDisabled()
		if style == "Primary" then
			ctx.Theme:Bind(b, "BackgroundColor3", "Accent", { Tween = true, Alpha = dis and 0.6 or (st == "Hover" and 0.12 or (st == "Press" and 0.25 or 0)) })
			ctx.Theme:Bind(b, "TextColor3", dis and "TextDisabled" or "TextOnAccent", { Tween = true })
		elseif style == "Outline" then
			ctx.Theme:Bind(b, "BackgroundColor3", st == "Press" and "ElementActive" or "ElementHover", { Tween = true, Alpha = st == "Idle" and 1 or 0 })
			ctx.Theme:Bind(b, "TextColor3", dis and "TextDisabled" or (st == "Idle" and "TextDim" or "Text"), { Tween = true })
		else
			ctx.Theme:Bind(b, "BackgroundColor3", (st == "Hover" and "ElementHover") or (st == "Press" and "ElementActive") or "Element", { Tween = true, Duration = 0.1 })
			ctx.Theme:Bind(b, "TextColor3", dis and "TextDisabled" or (confirming and "Warning" or (st == "Idle" and S(ctx, "ButtonText", "Text") or "Text")), { Tween = true })
		end
		if stroke then
			ctx.Theme:Bind(stroke, "Color", (st == "Hover" or st == "Press") and (S(ctx, "ButtonStrokeHover", "Accent")) or S(ctx, "ButtonStroke", "Border"), { Tween = true })
		end
		if S(ctx, "ButtonPressScale", true) then
			Tween.Play(b, { Size = UDim2.new(1, st == "Press" and -4 or 0, 1, -inset * 2 - (st == "Press" and 2 or 0)), Position = UDim2.fromOffset(st == "Press" and 2 or 0, inset + (st == "Press" and 1 or 0)) }, 0.08)
		end
	end
	local refresh = ctx:Hover(b, paint, el)
	b.Activated:Connect(function()
		if el:IsDisabled() then
			return
		end
		ctx:Sound("SoundClick")
		if el.Options.Confirm and not confirming then
			confirming = true
			b.Text = caseText(ctx, el.Options.ConfirmText or "Are you sure?")
			refresh()
			task.delay(2.5, function()
				if confirming then
					confirming = false
					b.Text = caseText(ctx, el.Name)
					refresh()
				end
			end)
			return
		end
		if confirming then
			confirming = false
			b.Text = caseText(ctx, el.Name)
			refresh()
		end
		el:FireCallback(nil)
	end)
	function view:SetDisabled()
		refresh()
	end
	function view:SetText(t)
		b.Text = caseText(ctx, t)
	end
	paint("Idle")
	return view
end

---------------------------------------------------------------- label / paragraph / divider
function C.LabelElement(ctx, el, parent)
	local root = C.Row(ctx, parent, el, ctx:RowH(S(ctx, "LabelHeight", 0.85)))
	local view = { Root = root }
	local label = ctx:Text(root, {
		Size = UDim2.new(1, -40, 1, 0),
		Text = el.Options.Text or el.Name,
		TextWrapped = el.Options.Wrap == true,
		RichText = el.Options.RichText == true,
	}, el.Options.Color or "TextDim")
	local addons = C.AddonHolder(ctx, root)
	view.Addons = addons
	C.Extras(ctx, el, view, addons)
	function view:SetText(t)
		label.Text = t
	end
	function view:SetDisabled(d)
		ctx.Theme:Bind(label, "TextColor3", d and "TextDisabled" or (el.Options.Color or "TextDim"))
	end
	return view
end

function C.Paragraph(ctx, el, parent)
	local root = ctx:Frame(parent, { Name = "Paragraph", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	ctx:List(root, { Pad = 3 })
	ctx:Pad(root, 2, 0, 4, 0)
	local view = { Root = root }
	local title = ctx:Text(root, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Text = caseText(ctx, el.Options.Title or el.Name), TextWrapped = true, LayoutOrder = 1 }, "Text", "FontTitle", "TextSize")
	local body = ctx:Text(root, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = el.Options.Content or "",
		TextWrapped = true,
		RichText = el.Options.RichText == true,
		LayoutOrder = 2,
	}, "TextDim", "FontBody", "SmallTextSize")
	function view:SetText(t)
		title.Text = caseText(ctx, t)
	end
	function view:SetContent(t)
		body.Text = t
	end
	return view
end

function C.Divider(ctx, el, parent)
	local text = el.Options.Text
	local root = C.Row(ctx, parent, el, text and ctx:RowH(0.8) or math.max(6, ctx:T("Spacing")))
	local view = { Root = root }
	if text then
		local t = ctx:Text(root, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = caseText(ctx, text),
			TextXAlignment = Enum.TextXAlignment.Center,
		}, "TextDim", "FontBody", "SmallTextSize")
		local w = Util.TextWidth(t.Text, ctx:T("SmallTextSize"), ctx:T("FontBody")) / 2 + 8
		ctx:Frame(root, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(0.5, -w, 0, 1) }, "Divider")
		ctx:Frame(root, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.new(0.5, -w, 0, 1) }, "Divider")
	else
		ctx:Frame(root, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 1) }, "Divider")
	end
	return view
end

function C.ESPPreview(ctx, el, parent)
	return require("ESPPreview").Render(ctx, el, parent)
end

-- map element kinds to renderers
return {
	Toggle = C.Toggle,
	Slider = C.Slider,
	Dropdown = C.Dropdown,
	Textbox = C.Textbox,
	Keybind = C.Keybind,
	ColorPicker = C.ColorPicker,
	Button = C.Button,
	Label = C.LabelElement,
	Paragraph = C.Paragraph,
	Divider = C.Divider,
	ESPPreview = C.ESPPreview,
	InlineColorPicker = C.InlineColorPicker,
	InlineKeybind = C.InlineKeybind,
	_ = C, -- helpers for skins
}
