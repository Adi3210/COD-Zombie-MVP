--!strict

local Format = {}

function Format.isFiniteNumber(value: number): boolean
	return math.isfinite(value)
end

function Format.isFiniteVector(value: Vector3): boolean
	return Format.isFiniteNumber(value.X) and Format.isFiniteNumber(value.Y) and Format.isFiniteNumber(value.Z)
end

return Format
