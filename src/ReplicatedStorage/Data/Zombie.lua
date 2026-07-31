--!strict

export type Config = {
	health: number,
	templateName: string,
}

local Zombie: Config = table.freeze({
	health = 100,
	templateName = "Zombie",
})

return Zombie
