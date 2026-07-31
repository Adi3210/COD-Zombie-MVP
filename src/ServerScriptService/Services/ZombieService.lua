--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Signal"))

local ZombieData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Zombie"))

local assets = ReplicatedStorage:WaitForChild("Assets")
local zombies = assets:WaitForChild("Zombies")
local zombieSpawns = Workspace:WaitForChild("Spawns", 10)

local ZOMBIE_FOLDER_NAME = "TempZombies"

type ZombieServiceType = {
	_zombies: { [Model]: number },
	_activeRoundId: number?,
	_nextSpawnIndex: number,
	_zombieFolder: Folder?,
	clearZombies: (self: ZombieServiceType) -> (),
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
	local existingFolder = Workspace:WaitForChild(ZOMBIE_FOLDER_NAME, 10)
	if existingFolder and existingFolder:IsA("Folder") then
		self._zombieFolder = existingFolder
		return
	end

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
	if self._zombies[zombie] ~= roundId then
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

	for _ = 1, zombieCount do
		if self._activeRoundId ~= roundId then
			break
		end

		local spawnIndex = (self._nextSpawnIndex - 1) % #spawnParts + 1
		local spawnPart = spawnParts[spawnIndex]
		self._nextSpawnIndex = spawnIndex % #spawnParts + 1
		local zombie, humanoid = createZombie(roundNumber, spawnPart)
		zombie.Parent = zombieFolder

		self._zombies[zombie] = roundId
		humanoid.Died:Connect(function()
			removeZombie(self, zombie, roundId)
		end)
	end
end

function ZombieService.onStart(self: ZombieServiceType): ()
	initializeZombieFolder(self)
end

return ZombieService
