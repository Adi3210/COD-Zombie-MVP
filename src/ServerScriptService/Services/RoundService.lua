--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Promise"))
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))

local RoundData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Round"))
local RoundUtil = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("Round"))

local ZombieService = require(script.Parent:WaitForChild("ZombieService"))

type RoundState = "WaitingForPlayers" | "RoundStartCountdown" | "RoundActive" | "RoundClearDelay"
type TransitionPromise = {
	cancel: (self: TransitionPromise) -> (),
}
type TroveType = typeof(Trove.new())
type RoundServiceType = {
	_serviceTrove: TroveType,
	_playerTroves: { [Player]: TroveType },
	_currentRound: number,
	_state: RoundState,
	_transitionPromise: TransitionPromise?,
	_nextRoundId: number,
	_activeRoundId: number?,
	onStart: (self: RoundServiceType) -> (),
}

local RoundService = {
	_serviceTrove = Trove.new(),
	_playerTroves = {},
	_currentRound = 0,
	_state = "WaitingForPlayers",
	_transitionPromise = nil,
	_nextRoundId = 0,
	_activeRoundId = nil,
} :: RoundServiceType

local function cancelTransition(self: RoundServiceType)
	local transitionPromise = self._transitionPromise
	if not transitionPromise then
		return
	end

	self._transitionPromise = nil
	transitionPromise:cancel()
end

local function startRound(self: RoundServiceType): ()
	if #Players:GetPlayers() == 0 then
		self._currentRound = 0
		self._state = "WaitingForPlayers"
		return
	end

	self._currentRound += 1
	self._nextRoundId += 1
	local roundId = self._nextRoundId
	self._activeRoundId = roundId
	self._state = "RoundActive"

	ZombieService:startRound(roundId, self._currentRound, RoundUtil.getZombieCount(self._currentRound))
end

local function startRoundCountdown(self: RoundServiceType): ()
	if self._state ~= "WaitingForPlayers" or #Players:GetPlayers() == 0 then
		return
	end

	cancelTransition(self)
	self._state = "RoundStartCountdown"
	local transitionPromise: TransitionPromise
	transitionPromise = Promise.delay(RoundData.startCountdown):andThen(function()
		local state = self._state :: RoundState
		if self._transitionPromise ~= transitionPromise or state ~= "RoundStartCountdown" then
			return
		end

		self._transitionPromise = nil
		if #Players:GetPlayers() == 0 then
			self._state = "WaitingForPlayers"
			return
		end

		startRound(self)
	end)
	self._transitionPromise = transitionPromise
end

local function resetRun(self: RoundServiceType): ()
	cancelTransition(self)
	self._activeRoundId = nil
	self._currentRound = 0
	self._state = "WaitingForPlayers"
	ZombieService:clearZombies()
end

local function handleZombiesCleared(self: RoundServiceType, roundId: number)
	if self._state ~= "RoundActive" or self._activeRoundId ~= roundId then
		return
	end

	self._activeRoundId = nil
	cancelTransition(self)
	self._state = "RoundClearDelay"
	local transitionPromise: TransitionPromise
	transitionPromise = Promise.delay(RoundData.clearDelay):andThen(function()
		local state = self._state :: RoundState
		if self._transitionPromise ~= transitionPromise or state ~= "RoundClearDelay" then
			return
		end

		self._transitionPromise = nil
		startRound(self)
	end)
	self._transitionPromise = transitionPromise
end

local function setupCharacter(self: RoundServiceType, playerTrove: TroveType, character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("No Humanoid found")
		return
	end

	playerTrove:Connect(humanoid.Died, function()
		resetRun(self)
	end)

	if humanoid.Health > 0 then
		startRoundCountdown(self)
	end
end

local function setupPlayer(self: RoundServiceType, player: Player)
	if self._playerTroves[player] then
		return
	end

	local playerTrove = self._serviceTrove:Extend()
	self._playerTroves[player] = playerTrove
	playerTrove:Connect(player.CharacterAdded, function(character: Model)
		setupCharacter(self, playerTrove, character :: Model)
	end)

	if player.Character then
		setupCharacter(self, playerTrove, player.Character :: Model)
	end
end

local function removePlayer(self: RoundServiceType, player: Player)
	local playerTrove = self._playerTroves[player]
	if not playerTrove then
		return
	end

	self._playerTroves[player] = nil
	self._serviceTrove:Remove(playerTrove :: any)

	task.defer(function()
		if #Players:GetPlayers() == 0 then
			resetRun(self)
		end
	end)
end

function RoundService.onStart(self: RoundServiceType): ()
	self._serviceTrove:Connect(ZombieService.zombiesCleared, function(roundId: number)
		handleZombiesCleared(self, roundId)
	end)
	self._serviceTrove:Connect(Players.PlayerAdded, function(player)
		setupPlayer(self, player)
	end)
	self._serviceTrove:Connect(Players.PlayerRemoving, function(player)
		removePlayer(self, player)
	end)

	for _, player in Players:GetPlayers() do
		setupPlayer(self, player)
	end
end

return RoundService
