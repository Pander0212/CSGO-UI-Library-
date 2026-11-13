--[[
	Classic component overrides: checkbox sits in the group's left gutter (like the reference menu),
	everything else uses the Base renderers driven by the Classic Style table.
]]
local Base = require("Skins/Base")
local Tween = require("Core/Tween")
local C = Base.C

local M = {}

function M.Toggle(ctx, el, parent)
	local view = C.Toggle(ctx, el, parent)
	view.Box.Position = UDim2.new(0, -20, 0.5, 0)
	view.Label.Position = UDim2.fromOffset(0, 0)
	view.Label.Size = UDim2.new(1, -60, 1, 0)
	-- the checkbox is outside the row: give it its own hit target
	local hit = ctx:Hitbox(view.Box, { Size = UDim2.new(1, 8, 1, 8), Position = UDim2.fromOffset(-4, -4) })
	hit.Activated:Connect(function()
		if not el:IsDisabled() then
			el:Set(not el.Value)
		end
	end)
	return view
end

-- skeet style notification: square box, rainbow line, mono text
function M.Notification(ctx, opts, holder)
	local W = ctx:T("NotifyWidth")
	local key = Base.O.TypeKey[opts.Type] or "Accent"
	local root = ctx:Frame(holder, { Name = "Notification", Size = UDim2.fromOffset(W, 0), AutomaticSize = Enum.AutomaticSize.Y })
	local card = ctx:Frame(root, { Size = UDim2.fromOffset(W, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(-W - 30, 0) }, "Panel")
	ctx:Stroke(card, "BorderDark", 1)
	local bar = ctx:Frame(card, { Size = UDim2.new(1, 0, 0, 2) }, "Highlight")
	ctx:Grad(bar, "RainbowBar", { Force = true, Static = true })
	local body = ctx:Frame(card, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	ctx:Pad(body, 8, 10, 8, 10)
	ctx:List(body, { Pad = 2 })
	local t = ctx:Text(body, { Text = "[" .. string.lower(opts.Title or "") .. "] ", Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 1 }, key, "FontMono", "TextSize")
	t.RichText = false
	ctx:Text(body, { Text = opts.Content or "", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 2 }, "Text", "FontMono", "SmallTextSize")
	Tween.Play(card, { Position = UDim2.fromOffset(0, 0) }, 0.2)
	local view = { Root = root }
	function view:Close(instant)
		if instant then
			root:Destroy()
			return
		end
		Tween.Play(card, { Position = UDim2.fromOffset(-W - 30, 0) }, 0.15)
		task.delay(Tween.Duration(0.15), function()
			root:Destroy()
		end)
	end
	return view
end

return M
