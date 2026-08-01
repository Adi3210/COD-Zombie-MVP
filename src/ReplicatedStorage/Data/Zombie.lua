--!strict

export type Config = {
	health: number,
	pointsPerKill: number,
	templateName: string,
}

local Zombie: Config = table.freeze({
	health = 100,
	pointsPerKill = 100,
	templateName = "Zombie",
})

return Zombie
