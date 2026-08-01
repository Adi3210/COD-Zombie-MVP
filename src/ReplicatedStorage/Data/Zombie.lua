--!strict

export type Config = {
	health: number,
	pointsPerKill: number,
	spawnInterval: number,
	templateName: string,
	touchDamage: number,
	touchDamageCooldown: number,
	updateInterval: number,
}

local Zombie: Config = table.freeze({
	health = 100,
	pointsPerKill = 100,
	spawnInterval = 1,
	templateName = "Zombie",
	touchDamage = 20,
	touchDamageCooldown = 1,
	updateInterval = 0.25,
})

return Zombie
