--[[
	Central tween helper. Every animation in the library goes through Tween.Play so that
	the theme keys AnimationsEnabled / AnimationSpeed / EasingStyle / EasingDirection apply globally.
]]
local Util = require("Core/Util")
local TweenService = Util.Services.TweenService

local Tween = {
	Enabled = true,
	Speed = 1, -- multiplier: 2 = twice as fast
	Style = Enum.EasingStyle.Quint,
	Direction = Enum.EasingDirection.Out,
}

function Tween.Configure(enabled, speed, style, direction)
	Tween.Enabled = enabled ~= false
	Tween.Speed = math.max(tonumber(speed) or 1, 0.05)
	local ok, s = pcall(function()
		return Enum.EasingStyle[style]
	end)
	if ok and s then
		Tween.Style = s
	end
	local ok2, d = pcall(function()
		return Enum.EasingDirection[direction]
	end)
	if ok2 and d then
		Tween.Direction = d
	end
end

function Tween.Duration(d)
	return (d or 0.2) / Tween.Speed
end

-- Tween.Play(inst, {Prop = value}, duration?, style?, direction?)
function Tween.Play(inst, props, duration, style, direction)
	if not inst then
		return nil
	end
	if not Tween.Enabled or duration == 0 then
		for k, v in pairs(props) do
			inst[k] = v
		end
		return nil
	end
	local info = TweenInfo.new(
		Tween.Duration(duration),
		style or Tween.Style,
		direction or Tween.Direction
	)
	local ok, tw = pcall(TweenService.Create, TweenService, inst, info, props)
	if ok and tw then
		tw:Play()
		return tw
	end
	for k, v in pairs(props) do
		inst[k] = v
	end
	return nil
end

-- Tween a number value via callback (for counters, custom properties)
function Tween.Value(from, to, duration, onStep, onDone)
	if not Tween.Enabled then
		onStep(to)
		if onDone then
			onDone()
		end
		return
	end
	local nv = Instance.new("NumberValue")
	nv.Value = from
	local conn = nv.Changed:Connect(function(v)
		onStep(v)
	end)
	local tw = Tween.Play(nv, { Value = to }, duration)
	if tw then
		tw.Completed:Connect(function()
			conn:Disconnect()
			nv:Destroy()
			onStep(to)
			if onDone then
				onDone()
			end
		end)
	else
		conn:Disconnect()
		onStep(to)
		if onDone then
			onDone()
		end
	end
end

return Tween
