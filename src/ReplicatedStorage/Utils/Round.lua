--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Round = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Round"))

type RoundUtilType = {
	getZombieCount: (roundNumber: number) -> number,
}

local RoundUtil = {} :: RoundUtilType

function RoundUtil.getZombieCount(roundNumber: number): number
	return Round.baseZombieCount + (roundNumber - 1) * Round.zombieGrowthPerRound
end

return RoundUtil
