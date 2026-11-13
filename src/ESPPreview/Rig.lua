--[[
	Rig: returns a model for the ESP preview. Tries to clone the local character
	(Archivable = true, scripts stripped, anchored); otherwise builds a blocky R15-proportioned rig.
	Returns model, parts (name -> BasePart), base CFrames (part -> CFrame relative to origin)
]]
local Util = require("Core/Util")

local Rig = {}

-- name, size, position (feet on y = 0)
local R15 = {
	{ "Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 5.2, 0) },
	{ "UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 3.8, 0) },
	{ "LowerTorso", Vector3.new(2, 0.4, 1), Vector3.new(0, 2.8, 0) },
	{ "LeftUpperArm", Vector3.new(1, 1.1, 1), Vector3.new(-1.5, 4.05, 0) },
	{ "LeftLowerArm", Vector3.new(1, 0.9, 1), Vector3.new(-1.5, 3.05, 0) },
	{ "LeftHand", Vector3.new(1, 0.4, 1), Vector3.new(-1.5, 2.4, 0) },
	{ "RightUpperArm", Vector3.new(1, 1.1, 1), Vector3.new(1.5, 4.05, 0) },
	{ "RightLowerArm", Vector3.new(1, 0.9, 1), Vector3.new(1.5, 3.05, 0) },
	{ "RightHand", Vector3.new(1, 0.4, 1), Vector3.new(1.5, 2.4, 0) },
	{ "LeftUpperLeg", Vector3.new(1, 1.2, 1), Vector3.new(-0.5, 2.0, 0) },
	{ "LeftLowerLeg", Vector3.new(1, 1.1, 1), Vector3.new(-0.5, 0.85, 0) },
	{ "LeftFoot", Vector3.new(1, 0.3, 1), Vector3.new(-0.5, 0.15, 0) },
	{ "RightUpperLeg", Vector3.new(1, 1.2, 1), Vector3.new(0.5, 2.0, 0) },
	{ "RightLowerLeg", Vector3.new(1, 1.1, 1), Vector3.new(0.5, 0.85, 0) },
	{ "RightFoot", Vector3.new(1, 0.3, 1), Vector3.new(0.5, 0.15, 0) },
}

Rig.Bones = {
	{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}

local function default()
	local model = Instance.new("Model")
	model.Name = "PreviewRig"
	local parts = {}
	for _, d in ipairs(R15) do
		local p = Instance.new("Part")
		p.Name = d[1]
		p.Size = d[2]
		p.CFrame = CFrame.new(d[3])
		p.Anchored = true
		p.CanCollide = false
		p.Color = d[1] == "Head" and Color3.fromRGB(245, 205, 160) or (d[1]:find("Torso") and Color3.fromRGB(40, 110, 210) or (d[1]:find("Leg") or d[1]:find("Foot")) and Color3.fromRGB(45, 45, 60) or Color3.fromRGB(245, 205, 160))
		p.Parent = model
		parts[d[1]] = p
	end
	return model, parts
end

local function cloneCharacter()
	local lp = Util.LocalPlayer()
	local char = lp and lp.Character
	if not char then
		return nil
	end
	local ok, clone = pcall(function()
		local old = char.Archivable
		char.Archivable = true
		local c = char:Clone()
		char.Archivable = old
		return c
	end)
	if not ok or not clone then
		return nil
	end
	local parts = {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript") or d:IsA("Sound") or d:IsA("ForceField") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			if d.Name == "HumanoidRootPart" then
				d.Transparency = 1
			end
		end
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
	for _, d in ipairs(R15) do
		local p = clone:FindFirstChild(d[1])
		if not p then
			clone:Destroy()
			return nil -- not R15, use the default rig
		end
		parts[d[1]] = p
	end
	-- move feet to y = 0, centered
	local cf, size = clone:GetBoundingBox()
	local offset = CFrame.new(-cf.Position.X, -(cf.Position.Y - size.Y / 2), -cf.Position.Z)
	local rot = CFrame.new(cf.Position) * (cf - cf.Position):Inverse() * CFrame.new(-cf.Position)
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CFrame = offset * rot * d.CFrame
		end
	end
	return clone, parts
end

function Rig.Build()
	local model, parts = cloneCharacter()
	if not model then
		model, parts = default()
	end
	local all, base = {}, {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(all, d)
			base[d] = d.CFrame
		end
	end
	return model, parts, all, base
end

return Rig
