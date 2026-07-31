--!strict

export type Config = {
	baseZombieCount: number,
	zombieGrowthPerRound: number,
	startCountdown: number,
	clearDelay: number,
}

local Round: Config = table.freeze({
	baseZombieCount = 1,
	zombieGrowthPerRound = 1,
	startCountdown = 5,
	clearDelay = 5,
})

return Round
