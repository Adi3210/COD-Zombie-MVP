--!strict

local Format = {}

function Format.isFiniteNumber(value: number): boolean
	return math.isfinite(value)
end

function Format.isFiniteVector(value: Vector3): boolean
	return Format.isFiniteNumber(value.X) and Format.isFiniteNumber(value.Y) and Format.isFiniteNumber(value.Z)
end

function Format.formatSeconds(seconds: number): string
	seconds = math.clamp(seconds, 0, math.huge)

	local minutes = math.floor(seconds / 60)
	seconds -= minutes * 60

	return string.format("%02d:%02d", minutes, seconds)
end

return Format
