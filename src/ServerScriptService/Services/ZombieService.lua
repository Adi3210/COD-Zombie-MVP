--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Signal"))
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))

local ZombieData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Zombie"))

local ScoreService = require(script.Parent:WaitForChild("ScoreService"))

local assets = ReplicatedStorage:WaitForChild("Assets")
local zombies = assets:WaitForChild("Zombies")

local ZOMBIE_FOLDER_NAME = "TempZombies"

type ZombieState = {
	humanoid: Humanoid,
	lastDamagingPlayer: Player?,
	roundId: number,
	nextTouchDamageAt: { [Humanoid]: number },
	trove: TroveType,
}
type TroveType = typeof(Trove.new())
type ZombieServiceType = {
	_zombies: { [Model]: ZombieState },
	_activeRoundId: number?,
	_nextSpawnIndex: number,
	_pendingSpawnCount: number,
	_zombieFolder: Folder?,
	_updateTaskRoundId: number?,
	_roundTrove: TroveType,
	clearZombies: (self: ZombieServiceType) -> (),
	damageZombie: (self: ZombieServiceType, player: Player, hit: Instance, damage: number) -> boolean,
	onStart: (self: ZombieServiceType) -> (),
	startRound: (self: ZombieServiceType, roundId: number, round: number, count: number) -> (),
	zombiesCleared: any,
}
type Service = ZombieServiceType

local ZombieService = {
	_zombies = {},
	_activeRoundId = nil,
	_nextSpawnIndex = 1,
	_pendingSpawnCount = 0,
	_zombieFolder = nil,
	_updateTaskRoundId = nil,
	_roundTrove = Trove.new(),
	zombiesCleared = Signal.new(),
} :: ZombieServiceType

local function initializeZombieFolder(self: ZombieServiceType): Folder
	if self._zombieFolder then
		return self._zombieFolder
	end

	local createdFolder = Instance.new("Folder")
	createdFolder.Name = ZOMBIE_FOLDER_NAME
	createdFolder.Parent = Workspace
	self._zombieFolder = createdFolder
	return createdFolder
end

local function getNearestTargetRoot(zombie: Model): BasePart?
	local zombiePivot = zombie:GetPivot().Position
	local nearestRoot: BasePart? = nil
	local nearestDistance = math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and rootPart and rootPart:IsA("BasePart") then
			local distance = (rootPart.Position - zombiePivot).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearestRoot = rootPart
			end
		end
	end
	return nearestRoot
end

local function checkForRoundClear(self: ZombieServiceType, roundId: number)
	if self._activeRoundId == roundId and self._pendingSpawnCount == 0 and not next(self._zombies) then
		self._activeRoundId = nil
		self.zombiesCleared:Fire(roundId)
	end
end

local function removeZombie(self: ZombieServiceType, zombie: Model, roundId: number)
	local runtime = self._zombies[zombie]
	if not runtime or runtime.roundId ~= roundId then
		return
	end

	self._zombies[zombie] = nil
	self._roundTrove:Remove(runtime.trove :: any)
	checkForRoundClear(self, roundId)
end

local function findTrackedZombie(self: ZombieServiceType, instance: Instance): ZombieState?
	local zombie = instance:FindFirstAncestorOfClass("Model")
	if not zombie then
		return nil
	end
	return self._zombies[zombie]
end

local function damageCharacter(runtime: ZombieState, touchedPart: BasePart)
	local character = touchedPart:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not player or not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	if now < (runtime.nextTouchDamageAt[humanoid] or 0) then
		return
	end
	runtime.nextTouchDamageAt[humanoid] = now + ZombieData.touchDamageCooldown
	humanoid:TakeDamage(ZombieData.touchDamage)
end

local function createZombie(self: Service, roundId: number, round: number, spawn: BasePart): Model?
	local zombieTemplate = zombies:FindFirstChild(ZombieData.templateName)
	if not zombieTemplate or not zombieTemplate:IsA("Model") then
		warn("Could not find zombie template " .. ZombieData.templateName)
		return nil
	end

	local zombie = zombieTemplate:Clone()
	local humanoid = zombie:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("No Humanoid found in zombie template " .. ZombieData.templateName)
		zombie:Destroy()
		return nil
	end
	local touchHitbox = zombie:FindFirstChild("HumanoidRootPart")
	if not touchHitbox or not touchHitbox:IsA("BasePart") then
		warn("Zombie template has no HumanoidRootPart touch hitbox")
		zombie:Destroy()
		return nil
	end

	zombie:SetAttribute("Round", round)
	humanoid.MaxHealth = ZombieData.health
	humanoid.Health = ZombieData.health
	zombie:PivotTo(spawn.CFrame)
	zombie.Parent = initializeZombieFolder(self)

	local zombieTrove = self._roundTrove:Extend()
	zombieTrove:Add(zombie)
	local runtime: ZombieState = {
		humanoid = humanoid,
		lastDamagingPlayer = nil,
		roundId = roundId,
		nextTouchDamageAt = {},
		trove = zombieTrove,
	}
	self._zombies[zombie] = runtime
	zombieTrove:Connect(humanoid.Died, function()
		local currentRuntime = self._zombies[zombie]
		if currentRuntime and currentRuntime.lastDamagingPlayer then
			ScoreService:addZombieKill(currentRuntime.lastDamagingPlayer)
		end
		removeZombie(self, zombie, roundId)
	end)
	for _, descendant in zombie:GetDescendants() do
		if descendant:IsA("BasePart") then
			if not descendant.Anchored and descendant:CanSetNetworkOwnership() then
				descendant:SetNetworkOwner(nil)
			end
			if descendant ~= touchHitbox then
				descendant.CanTouch = false
			end
		end
	end
	touchHitbox.CanTouch = true
	zombieTrove:Connect(touchHitbox.Touched, function(touchedPart)
		damageCharacter(runtime, touchedPart)
	end)
	return zombie
end

local function startChase(self: ZombieServiceType, roundId: number)
	self._updateTaskRoundId = roundId
	self._roundTrove:Add(task.spawn(function()
		while self._activeRoundId == roundId and self._updateTaskRoundId == roundId do
			for zombie, runtime in self._zombies do
				if runtime.roundId == roundId and runtime.humanoid.Health > 0 then
					local targetRoot = getNearestTargetRoot(zombie)
					if targetRoot then
						runtime.humanoid:MoveTo(targetRoot.Position)
					end
				end
			end
			task.wait(ZombieData.updateInterval)
		end
	end))
end

function ZombieService.damageZombie(
	self: ZombieServiceType,
	player: Player,
	instance: Instance,
	damage: number
): boolean
	if damage <= 0 or not player:IsDescendantOf(Players) then
		return false
	end

	local runtime = findTrackedZombie(self, instance)
	if not runtime or runtime.humanoid.Health <= 0 or self._activeRoundId ~= runtime.roundId then
		return false
	end

	runtime.lastDamagingPlayer = player
	runtime.humanoid:TakeDamage(damage)
	return true
end

function ZombieService.clearZombies(self: ZombieServiceType): ()
	self._activeRoundId = nil
	self._pendingSpawnCount = 0
	self._updateTaskRoundId = nil

	self._zombies = {}
	self._roundTrove:Clean()
	self._roundTrove = Trove.new()
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

	local zombieSpawns = Workspace:WaitForChild("Spawns", 10)
	if not zombieSpawns then
		warn("No zombie spawn folder found")
		return
	end

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
		return
	end

	local zombieTemplate = zombies:FindFirstChild(ZombieData.templateName)
	if
		not zombieTemplate
		or not zombieTemplate:IsA("Model")
		or not zombieTemplate:FindFirstChildOfClass("Humanoid")
	then
		warn("No zombie template " .. ZombieData.templateName)
		return
	end

	self:clearZombies()
	self._activeRoundId = roundId
	self._pendingSpawnCount = zombieCount
	initializeZombieFolder(self):SetAttribute("Round", roundNumber)
	startChase(self, roundId)
	self._roundTrove:Add(task.spawn(function()
		for spawnNumber = 1, zombieCount do
			if self._activeRoundId ~= roundId then
				return
			end
			local spawnIndex = (self._nextSpawnIndex - 1) % #spawnParts + 1
			self._nextSpawnIndex = spawnIndex % #spawnParts + 1
			local zombie = createZombie(self, roundId, roundNumber, spawnParts[spawnIndex])
			if not zombie then
				return
			end
			self._pendingSpawnCount -= 1
			checkForRoundClear(self, roundId)
			if spawnNumber < zombieCount then
				task.wait(ZombieData.spawnInterval)
			end
		end
	end))
end

function ZombieService.onStart(self: ZombieServiceType): ()
	initializeZombieFolder(self)
end

return ZombieService
