--[[
	Input: one set of UserInputService connections for the whole library,
	unified mouse + touch dragging (with threshold, tap, long-press) and helpers.
]]
local Util = require("Core/Util")
local Signal = require("Core/Signal")
local Maid = require("Core/Maid")

local UIS = Util.Services.UserInputService

local Input = {}
Input.__index = Input

local MB1 = Enum.UserInputType.MouseButton1
local TOUCH = Enum.UserInputType.Touch
local MOVE = Enum.UserInputType.MouseMovement

function Input.new()
	local self = setmetatable({}, Input)
	self.Maid = Maid.new()
	self.Began = Signal.new() -- (input, gameProcessed)
	self.Ended = Signal.new()
	self.Changed = Signal.new()
	if UIS then
		self.Maid:Give(UIS.InputBegan:Connect(function(i, gp)
			self.Began:Fire(i, gp)
		end))
		self.Maid:Give(UIS.InputEnded:Connect(function(i, gp)
			self.Ended:Fire(i, gp)
		end))
		self.Maid:Give(UIS.InputChanged:Connect(function(i, gp)
			self.Changed:Fire(i, gp)
		end))
	end
	return self
end

function Input.IsPress(input)
	return input.UserInputType == MB1 or input.UserInputType == TOUCH
end

function Input.Pos(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

-- InputObject positions exclude the top bar inset, AbsolutePosition (IgnoreGuiInset) does not
function Input.ToAbs(pos)
	return pos + Util.GuiInset()
end

function Input.MousePos()
	if UIS then
		local ok, p = pcall(function()
			return UIS:GetMouseLocation()
		end)
		if ok and p then
			return p
		end
	end
	return Vector2.new(0, 0)
end

--[[
	Input:Drag(handle, opts) -> Maid
	opts.Target       GuiObject to move (Position offset), optional
	opts.GetScale()   current UIScale (deltas are divided by it)
	opts.Threshold    pixels before a press becomes a drag (default 0)
	opts.Clamp(pos)   -> UDim2 clamp hook
	opts.Enabled()    -> bool
	opts.OnStart(), opts.OnMove(delta, pos), opts.OnEnd(moved), opts.OnTap()
	opts.LongPress()  fired after opts.LongPressTime (0.5s) without moving; cancels tap
]]
function Input:Drag(handle, opts)
	opts = opts or {}
	local maid = Maid.new()
	local active, startPos, startTarget, moved, lp
	local function finish(cancelled)
		local wasMoved = moved
		active = nil
		if lp then
			pcall(task.cancel, lp)
			lp = nil
		end
		if opts.OnEnd then
			opts.OnEnd(wasMoved, cancelled)
		end
		if not wasMoved and not cancelled and opts.OnTap then
			opts.OnTap()
		end
	end
	maid:Give(handle.InputBegan:Connect(function(input)
		if not Input.IsPress(input) then
			return
		end
		if opts.Enabled and not opts.Enabled() then
			return
		end
		active = input
		startPos = Input.Pos(input)
		moved = false
		if opts.OnStart then
			opts.OnStart(startPos)
		end
		startTarget = opts.Target and opts.Target.Position
		if opts.LongPress then
			lp = task.delay(opts.LongPressTime or 0.5, function()
				lp = nil
				if active == input and not moved then
					active = nil
					if opts.OnEnd then
						opts.OnEnd(false, true)
					end
					opts.LongPress()
				end
			end)
		end
	end))
	maid:Give(self.Changed:Connect(function(input)
		if not active then
			return
		end
		local t = input.UserInputType
		if not (t == MOVE or t == TOUCH) then
			return
		end
		if active.UserInputType == TOUCH and t ~= TOUCH then
			return
		end
		if active.UserInputType == MB1 and t ~= MOVE then
			return
		end
		local p = Input.Pos(input)
		local delta = p - startPos
		if not moved then
			if delta.Magnitude < (opts.Threshold or 0) then
				return
			end
			moved = true
			if lp then
				pcall(task.cancel, lp)
				lp = nil
			end
		end
		if opts.Target and startTarget then
			local s = opts.GetScale and opts.GetScale() or 1
			local pos = UDim2.new(
				startTarget.X.Scale,
				startTarget.X.Offset + delta.X / s,
				startTarget.Y.Scale,
				startTarget.Y.Offset + delta.Y / s
			)
			if opts.Clamp then
				pos = opts.Clamp(pos) or pos
			end
			opts.Target.Position = pos
		end
		if opts.OnMove then
			opts.OnMove(delta, p)
		end
	end))
	maid:Give(self.Ended:Connect(function(input)
		if not active then
			return
		end
		local t = input.UserInputType
		if t == active.UserInputType or input == active then
			finish(false)
		end
	end))
	maid:Give(function()
		active = nil
	end)
	return maid
end

function Input:Destroy()
	self.Maid:Clean()
end

return Input
