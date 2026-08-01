--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))

local ZombieData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Zombie"))

type ScoreEntry = {
	name: string,
	points: number,
	userId: number,
}
type ScoreState = {
	points: number,
}
type TroveType = typeof(Trove.new())
type ScoreServiceType = {
	_serviceTrove: TroveType,
	_playerStates: { [Player]: ScoreState },
	addZombieKill: (self: ScoreServiceType, player: Player) -> (),
	publishFinalScores: (self: ScoreServiceType) -> (),
	resetScores: (self: ScoreServiceType) -> (),
	onStart: (self: ScoreServiceType) -> (),
}

local ScoreService = {
	_serviceTrove = Trove.new(),
	_playerStates = {},
} :: ScoreServiceType

local function setupPlayer(self: ScoreServiceType, player: Player)
	if self._playerStates[player] then
		return
	end

	self._playerStates[player] = {
		points = 0,
	}
end

local function removePlayer(self: ScoreServiceType, player: Player)
	self._playerStates[player] = nil
end

function ScoreService.addZombieKill(self: ScoreServiceType, player: Player): ()
	if not player:IsDescendantOf(Players) then
		return
	end

	local state = self._playerStates[player]
	if not state then
		return
	end

	state.points += ZombieData.pointsPerKill
end

function ScoreService.publishFinalScores(self: ScoreServiceType): ()
	local entries: { ScoreEntry } = {}
	for _, player in Players:GetPlayers() do
		table.insert(entries, {
			name = player.Name,
			points = (self._playerStates[player] and self._playerStates[player].points) or 0,
			userId = player.UserId,
		})
	end

	table.sort(entries, function(left, right)
		if left.points == right.points then
			return left.userId < right.userId
		end
		return left.points > right.points
	end)

	for _, entry in entries do
		print(string.format("%s: %d points", entry.name, entry.points))
	end
end

function ScoreService.resetScores(self: ScoreServiceType): ()
	for _, player in Players:GetPlayers() do
		local state = self._playerStates[player]
		if state then
			state.points = 0
		end
	end
end

function ScoreService.onStart(self: ScoreServiceType): ()
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

return ScoreService
