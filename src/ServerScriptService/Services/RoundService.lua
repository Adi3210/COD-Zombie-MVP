--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Promise = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Promise"))
local Comm = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Comm"))
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))

local RoundData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Round"))
local RoundUtil = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("Round"))
local NetData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Net"))

local ScoreService = require(script.Parent:WaitForChild("ScoreService"))
local ZombieService = require(script.Parent:WaitForChild("ZombieService"))

type RoundState = "WaitingForPlayers" | "RoundStartCountdown" | "RoundActive" | "RoundClearDelay"
type TransitionPromise = {
	cancel: (self: TransitionPromise) -> (),
}
type TroveType = typeof(Trove.new())
type RoundServiceType = {
	_serviceTrove: TroveType,
	_playerTroves: { [Player]: TroveType },
	_characterTroves: { [Player]: TroveType },
	_currentRound: number,
	_state: RoundState,
	_isResetting: boolean,
	_transitionPromise: TransitionPromise?,
	_nextRoundId: number,
	_activeRoundId: number?,
	_roundProperty: any,
	_secondsLeft: number,
	_timerId: number,
	_roundComm: any,
	isRoundActive: (self: RoundServiceType) -> boolean,
	onStart: (self: RoundServiceType) -> (),
}

local RoundService = {
	_serviceTrove = Trove.new(),
	_playerTroves = {},
	_characterTroves = {},
	_currentRound = 0,
	_state = "WaitingForPlayers",
	_isResetting = false,
	_transitionPromise = nil,
	_nextRoundId = 0,
	_activeRoundId = nil,
	_roundProperty = nil :: any,
	_secondsLeft = 0,
	_timerId = 0,
	_roundComm = nil :: any,
} :: RoundServiceType

local function publishState(self: RoundServiceType)
	if self._roundProperty then
		self._roundProperty:Set({
			round = self._currentRound,
			secondsLeft = self._secondsLeft,
			state = self._state,
		})
	end
end

local function setTimer(self: RoundServiceType, seconds: number, onExpired: (() -> ())?)
	self._timerId += 1
	local timerId = self._timerId
	local deadline = os.clock() + seconds
	self._secondsLeft = math.ceil(seconds)
	publishState(self)

	task.spawn(function()
		while self._timerId == timerId do
			local secondsLeft = math.max(0, math.ceil(deadline - os.clock()))
			if secondsLeft ~= self._secondsLeft then
				self._secondsLeft = secondsLeft
				publishState(self)
			end
			if secondsLeft == 0 then
				if self._timerId == timerId and onExpired then
					onExpired()
				end
				return
			end
			task.wait(0.1)
		end
	end)
end

local function cancelTransition(self: RoundServiceType)
	self._timerId += 1
	local transitionPromise = self._transitionPromise
	if not transitionPromise then
		return
	end

	self._transitionPromise = nil
	transitionPromise:cancel()
end

local function resetRun(self: RoundServiceType): ()
	if self._isResetting or self._state == "WaitingForPlayers" then
		return
	end

	self._isResetting = true
	cancelTransition(self)
	self._activeRoundId = nil
	self._currentRound = 0
	self._state = "WaitingForPlayers"
	self._secondsLeft = 0
	publishState(self)
	ZombieService:clearZombies()
	ScoreService:publishFinalScores()
	ScoreService:resetScores()
	task.defer(function()
		self._isResetting = false
	end)
end

local function killLivingPlayers(): boolean
	local killedAny = false
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
			killedAny = true
		end
	end
	return killedAny
end

local function startRound(self: RoundServiceType): ()
	if #Players:GetPlayers() == 0 then
		self._currentRound = 0
		self._state = "WaitingForPlayers"
		self._secondsLeft = 0
		publishState(self)
		return
	end

	self._currentRound += 1
	self._nextRoundId += 1
	local roundId = self._nextRoundId
	self._activeRoundId = roundId
	self._state = "RoundActive"
	local zombieCount = RoundUtil.getZombieCount(self._currentRound)
	setTimer(self, RoundUtil.getDuration(zombieCount), function()
		if self._state == "RoundActive" and self._activeRoundId == roundId then
			if not killLivingPlayers() then
				resetRun(self)
			end
		end
	end)
	ZombieService:startRound(roundId, self._currentRound, zombieCount)
end

local function startRoundCountdown(self: RoundServiceType): ()
	if self._state ~= "WaitingForPlayers" or #Players:GetPlayers() == 0 then
		return
	end

	cancelTransition(self)
	self._state = "RoundStartCountdown"
	setTimer(self, RoundData.startCountdown)
	local transitionPromise: TransitionPromise
	transitionPromise = Promise.delay(RoundData.startCountdown):andThen(function()
		local state = self._state :: RoundState
		if self._transitionPromise ~= transitionPromise or state ~= "RoundStartCountdown" then
			return
		end

		self._transitionPromise = nil
		if #Players:GetPlayers() == 0 then
			self._state = "WaitingForPlayers"
			self._secondsLeft = 0
			publishState(self)
			return
		end

		startRound(self)
	end)
	self._transitionPromise = transitionPromise
end

local function handleZombiesCleared(self: RoundServiceType, roundId: number)
	if self._state ~= "RoundActive" or self._activeRoundId ~= roundId then
		return
	end

	self._activeRoundId = nil
	cancelTransition(self)
	self._state = "RoundClearDelay"
	setTimer(self, RoundData.clearDelay)
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

local function setupCharacter(self: RoundServiceType, player: Player, playerTrove: TroveType, character: Model)
	local previousCharacterTrove = self._characterTroves[player]
	if previousCharacterTrove then
		playerTrove:Remove(previousCharacterTrove :: any)
	end
	local characterTrove = playerTrove:Extend()
	self._characterTroves[player] = characterTrove

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	characterTrove:Connect(humanoid.Died, function()
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
		setupCharacter(self, player, playerTrove, character :: Model)
	end)

	if player.Character then
		setupCharacter(self, player, playerTrove, player.Character :: Model)
	end
end

local function removePlayer(self: RoundServiceType, player: Player)
	local playerTrove = self._playerTroves[player]
	if not playerTrove then
		return
	end

	self._playerTroves[player] = nil
	self._characterTroves[player] = nil
	self._serviceTrove:Remove(playerTrove :: any)

	task.defer(function()
		if #Players:GetPlayers() == 0 then
			resetRun(self)
		end
	end)
end

function RoundService.onStart(self: RoundServiceType): ()
	self._roundComm = Comm.ServerComm.new(ReplicatedStorage, NetData.round.namespace)
	self._roundProperty = self._roundComm:CreateProperty(NetData.round.state, {
		round = 0,
		secondsLeft = 0,
		state = "WaitingForPlayers",
	})
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

function RoundService.isRoundActive(self: RoundServiceType): boolean
	return self._state == "RoundActive"
end

return RoundService
