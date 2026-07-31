--!strict

export type Config = {
	capacity: number,
	damage: number,
	cooldown: number,
}

local Weapon: Config = table.freeze({
	capacity = 12,
	damage = 25,
	cooldown = 0.25,
})

return Weapon
