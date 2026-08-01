--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Signal"))

local ZombieData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Zombie"))

local ScoreService = require(script.Parent:WaitForChild("ScoreService"))

local assets = ReplicatedStorage:WaitForChild("Assets")
local zombies = assets:WaitForChild("Zombies")
local zombieSpawns = Workspace:WaitForChild("Spawns", 10)

local ZOMBIE_FOLDER_NAME = "TempZombies"

type ZombieState = {
	humanoid: Humanoid,
	lastDamagingPlayer: Player?,
	roundId: number,
}
type ZombieServiceType = {
	_zombies: { [Model]: ZombieState },
	_activeRoundId: number?,
	_nextSpawnIndex: number,
	_zombieFolder: Folder?,
	clearZombies: (self: ZombieServiceType) -> (),
	damageZombie: (self: ZombieServiceType, player: Player, instance: Instance, damage: number) -> boolean,
	onStart: (self: ZombieServiceType) -> (),
	startRound: (self: ZombieServiceType, roundId: number, roundNumber: number, zombieCount: number) -> (),
	zombiesCleared: any,
}

local ZombieService = {
	_zombies = {},
	_activeRoundId = nil,
	_nextSpawnIndex = 1,
	_zombieFolder = nil,
	zombiesCleared = Signal.new(),
} :: ZombieServiceType

local function initializeZombieFolder(self: ZombieServiceType)
	local createdFolder = Instance.new("Folder")
	createdFolder.Name = ZOMBIE_FOLDER_NAME
	createdFolder.Parent = Workspace
	self._zombieFolder = createdFolder
end

local function createZombie(roundNumber: number, spawnPart: BasePart): (Model, Humanoid)
	local zombieTemplate = zombies:FindFirstChild(ZombieData.templateName)
	if not zombieTemplate or not zombieTemplate:IsA("Model") then
		warn("Could not find zombie")
	end

	local zombie = zombieTemplate:Clone()
	zombie:SetAttribute("Round", roundNumber)

	local humanoid = zombie:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("No Humanoid found in zombie")
	end

	humanoid.MaxHealth = ZombieData.health
	humanoid.Health = ZombieData.health
	zombie:PivotTo(spawnPart.CFrame)
	return zombie, humanoid
end

local function removeZombie(self: ZombieServiceType, zombie: Model, roundId: number)
	local runtime = self._zombies[zombie]
	if not runtime or runtime.roundId ~= roundId then
		return
	end

	self._zombies[zombie] = nil
	if zombie.Parent then
		zombie:Destroy()
	end

	if self._activeRoundId == roundId and not next(self._zombies) then
		self._activeRoundId = nil
		self.zombiesCleared:Fire(roundId)
	end
end

local function findTrackedZombie(self: ZombieServiceType, instance: Instance): ZombieState?
	local zombie = instance:FindFirstAncestorOfClass("Model")
	if not zombie then
		return nil
	end

	return self._zombies[zombie]
end

function ZombieService.damageZombie(
	self: ZombieServiceType,
	player: Player,
	instance: Instance,
	damage: number
): boolean
	if damage <= 0 then
		return false
	end

	local runtime = findTrackedZombie(self, instance)
	if not runtime or runtime.humanoid.Health <= 0 then
		return false
	end

	runtime.lastDamagingPlayer = player
	runtime.humanoid:TakeDamage(damage)
	return true
end

function ZombieService.clearZombies(self: ZombieServiceType): ()
	self._activeRoundId = nil

	local zombiesToClear: { Model } = {}
	for zombie in self._zombies do
		table.insert(zombiesToClear, zombie)
	end

	for _, zombie in zombiesToClear do
		self._zombies[zombie] = nil
		if zombie.Parent then
			zombie:Destroy()
		end
	end
end

function ZombieService.startRound(
	self: ZombieServiceType,
	roundId: number,
	roundNumber: number,
	zombieCount: number
): ()
	if zombieCount < 1 then
		warn("No zombies to spawn")
		return
	end

	local zombieFolder = self._zombieFolder
	if not zombieFolder then
		return
	end

	self:clearZombies()
	self._activeRoundId = roundId
	zombieFolder:SetAttribute("Round", roundNumber)

	local spawnParts: { BasePart } = {}
	for _, child in zombieSpawns:GetChildren() do
		if child:IsA("BasePart") then
			table.insert(spawnParts, child)
		end
	end

	table.sort(spawnParts, function(left, right)
		return left.Name < right.Name
	end)
	if #spawnParts == 0 then
		warn("No zombie spawn parts found")
		self._activeRoundId = nil
		return
	end

	for _ = 1, zombieCount do
		if self._activeRoundId ~= roundId then
			break
		end

		local spawnIndex = (self._nextSpawnIndex - 1) % #spawnParts + 1
		local spawnPart = spawnParts[spawnIndex]
		self._nextSpawnIndex = spawnIndex % #spawnParts + 1
		local zombie, humanoid = createZombie(roundNumber, spawnPart)
		zombie.Parent = zombieFolder

		self._zombies[zombie] = {
			humanoid = humanoid,
			lastDamagingPlayer = nil,
			roundId = roundId,
		}
		humanoid.Died:Connect(function()
			local runtime = self._zombies[zombie]
			if runtime and runtime.lastDamagingPlayer then
				ScoreService:addZombieKill(runtime.lastDamagingPlayer)
			end
			removeZombie(self, zombie, roundId)
		end)
	end
end

function ZombieService.onStart(self: ZombieServiceType): ()
	initializeZombieFolder(self)
end

return ZombieService
