--!strict

export type Config = {
	weaponName: string,
	capacity: number,
	damage: number,
	cooldown: number,
}

local Weapon: Config = table.freeze({
	weaponName = "Starter Pistol",
	capacity = 12,
	damage = 25,
	cooldown = 0.25,
})

return Weapon
