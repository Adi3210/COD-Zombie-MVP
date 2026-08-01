--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Round"))

type RoundUtilType = {
	getZombieCount: (roundNumber: number) -> number,
	getDuration: (zombieCount: number) -> number,
}

local RoundUtil = {} :: RoundUtilType

function RoundUtil.getZombieCount(roundNumber: number): number
	return RoundData.baseZombieCount + (roundNumber - 1) * RoundData.zombieGrowthPerRound
end

function RoundUtil.getDuration(zombieCount: number): number
	return RoundData.baseRoundSeconds + zombieCount * RoundData.secondsPerZombie
end

return RoundUtil
