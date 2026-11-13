--[[ Fatal component overrides: glowing checkboxes, glowing notifications ]]
local Base = require("Skins/Base")
local Tween = require("Core/Tween")
local C = Base.C

local M = {}

function M.Toggle(ctx, el, parent)
	local view = C.Toggle(ctx, el, parent)
	local glow = Instance.new("UIStroke")
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	glow.Thickness = 2
	glow.Parent = view.Box
	local update = view.Update
	function view:Update(v, instant)
		update(view, v, instant)
		ctx.Theme:Bind(glow, "Color", el.Value and "Glow" or "BorderDark", { Alpha = el.Value and 0.45 or 0, Tween = not instant })
	end
	return view
end

function M.Notification(ctx, opts, holder)
	local view = Base.O.Notification(ctx, opts, holder)
	local card = view.Root:FindFirstChildOfClass("Frame")
	if card then
		local key = Base.O.TypeKey[opts.Type] or "Accent"
		local s = card:FindFirstChildOfClass("UIStroke")
		if s then
			ctx.Theme:Bind(s, "Color", key, { Alpha = 0.35 })
			s.Thickness = 1.5
		end
		local stripe = card:FindFirstChild("Stripe")
		if stripe then
			ctx:Grad(stripe, "AccentGradient", { Force = true, Rotation = 90 })
		end
	end
	return view
end

-- pulsing glow helper used by the loader
function M.Pulse(stroke, minA, maxA, period)
	local running = true
	task.spawn(function()
		local up = true
		while running and stroke.Parent do
			Tween.Play(stroke, { Transparency = up and minA or maxA }, period / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			up = not up
			task.wait(Tween.Duration(period / 2))
		end
	end)
	return function()
		running = false
	end
end

return M
