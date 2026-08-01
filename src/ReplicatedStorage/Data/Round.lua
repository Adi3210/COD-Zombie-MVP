--!strict

export type Config = {
	baseZombieCount: number,
	zombieGrowthPerRound: number,
	baseRoundSeconds: number,
	secondsPerZombie: number,
	startCountdown: number,
	clearDelay: number,
}

local Round: Config = table.freeze({
	baseZombieCount = 1,
	zombieGrowthPerRound = 1,
	baseRoundSeconds = 25,
	secondsPerZombie = 5,
	startCountdown = 5,
	clearDelay = 5,
})

return Round
