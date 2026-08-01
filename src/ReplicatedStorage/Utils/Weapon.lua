--!strict

local WeaponUtil = {}

function WeaponUtil.getMuzzlePosition(tool: Tool, fallback: Vector3): Vector3
	local flare = tool:FindFirstChild("Flare", true)
	if flare and flare:IsA("BasePart") then
		return flare.Position
	end

	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle.Position
	end

	return fallback
end

return WeaponUtil
