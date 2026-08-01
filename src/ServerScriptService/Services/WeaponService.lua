--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Comm"))
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))

local Format = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("Format"))
local NetData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Net"))
local WeaponData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Weapon"))

local RoundService = require(script.Parent:WaitForChild("RoundService"))
local ZombieService = require(script.Parent:WaitForChild("ZombieService"))

local assets = ReplicatedStorage:WaitForChild("Assets")
local weapons = assets:WaitForChild("Weapons")

local CAMERA_ORIGIN_TOLERANCE = 16
local MAXIMUM_AIM_DIRECTION_MAGNITUDE = 1000
local MINIMUM_REQUEST_INTERVAL = 1 / 30
local TRACE_DISTANCE = 1000

type WeaponRuntime = {
	character: Model,
	tool: Tool,
	ammo: number,
	nextShotAt: number,
	nextRequestAt: number,
}

type TroveType = typeof(Trove.new())
type WeaponServiceType = {
	_serviceTrove: TroveType,
	_playerRuntimes: { [Player]: WeaponRuntime? },
	_playerTroves: { [Player]: TroveType },
	_weaponComm: any,
	_attackRequestSignal: any,
	_weaponStateProperty: any,
	onStart: (self: WeaponServiceType) -> (),
}

local WeaponService = {
	_serviceTrove = Trove.new(),
	_playerRuntimes = {},
	_playerTroves = {},
	_weaponComm = nil :: any,
	_attackRequestSignal = nil :: any,
	_weaponStateProperty = nil :: any,
} :: WeaponServiceType

local function getBackpack(player: Player): Backpack?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		return backpack
	end

	local waitingBackpack = player:WaitForChild("Backpack", 10)
	if waitingBackpack and waitingBackpack:IsA("Backpack") then
		return waitingBackpack
	end

	return nil
end

local function isCurrentPlayerLife(
	self: WeaponServiceType,
	player: Player,
	playerTrove: TroveType,
	character: Model
): boolean
	return self._playerTroves[player] == playerTrove and player.Character == character
end

local function grantWeapon(self: WeaponServiceType, player: Player, playerTrove: TroveType, character: Model)
	if not isCurrentPlayerLife(self, player, playerTrove, character) then
		return
	end

	self._playerRuntimes[player] = nil

	local backpack = getBackpack(player)
	if not backpack then
		warn("Could not find a Backpack for " .. player.Name)
		return
	end

	if not isCurrentPlayerLife(self, player, playerTrove, character) then
		return
	end

	local tool = weapons:FindFirstChild(WeaponData.weaponName)
	if not tool or not tool:IsA("Tool") then
		warn("Could not find a Tool named " .. WeaponData.weaponName)
		return
	end

	local toolClone = tool:Clone()
	if not isCurrentPlayerLife(self, player, playerTrove, character) then
		toolClone:Destroy()
		return
	end

	toolClone.Parent = backpack
	self._playerRuntimes[player] = {
		ammo = WeaponData.capacity,
		character = character,
		nextShotAt = 0,
		tool = toolClone,
		nextRequestAt = 0,
	}
end

local function publishWeaponState(self: WeaponServiceType, player: Player)
	local runtime = self._playerRuntimes[player]
	if self._weaponStateProperty and runtime then
		self._weaponStateProperty:SetFor(player, {
			ammo = runtime.ammo,
			capacity = WeaponData.capacity,
		})
	end
end

local function getRootPart(character: Model): BasePart?
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function canPerformAttack(self: WeaponServiceType, player: Player, attackRequest: any): boolean
	local runtime = self._playerRuntimes[player]
	if not runtime or type(attackRequest) ~= "table" then
		return false
	end

	local now = os.clock()
	if now < runtime.nextRequestAt then
		return false
	end
	runtime.nextRequestAt = now + MINIMUM_REQUEST_INTERVAL

	local tool = attackRequest.tool
	local cameraOrigin = attackRequest.cameraOrigin
	local aimDirection = attackRequest.aimDirection

	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") then
		return false
	end

	if typeof(cameraOrigin) ~= "Vector3" or typeof(aimDirection) ~= "Vector3" then
		return false
	end

	if not Format.isFiniteVector(cameraOrigin) or not Format.isFiniteVector(aimDirection) then
		return false
	end

	local aimMagnitude = aimDirection.Magnitude
	if
		not Format.isFiniteNumber(aimMagnitude)
		or aimMagnitude == 0
		or aimMagnitude > MAXIMUM_AIM_DIRECTION_MAGNITUDE
	then
		return false
	end

	if player.Character ~= runtime.character or tool ~= runtime.tool or tool.Parent ~= runtime.character then
		return false
	end
	if not RoundService:isRoundActive() or runtime.ammo <= 0 or now < runtime.nextShotAt then
		return false
	end

	local humanoid = runtime.character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local rootPart = getRootPart(runtime.character)
	if not rootPart then
		return false
	end

	local originDistance = (cameraOrigin - rootPart.Position).Magnitude
	return Format.isFiniteNumber(originDistance) and originDistance <= CAMERA_ORIGIN_TOLERANCE
end

local function performAttack(self: WeaponServiceType, player: Player, attackRequest: any)
	if not canPerformAttack(self, player, attackRequest) then
		return
	end

	local runtime = self._playerRuntimes[player]
	if not runtime then
		return
	end

	local direction = attackRequest.aimDirection.Unit * TRACE_DISTANCE
	local raycastParams = RaycastParams.new()
	raycastParams.ExcludeInstances = { runtime.character, runtime.tool }
	local result = workspace:Raycast(attackRequest.cameraOrigin, direction, raycastParams)

	runtime.ammo -= 1
	runtime.nextShotAt = os.clock() + WeaponData.cooldown
	publishWeaponState(self, player)
	if result then
		--TODO: Damage Zombie with weapon by the player
	end
end

local function setupPlayer(self: WeaponServiceType, player: Player)
	if self._playerTroves[player] then
		return
	end

	local playerTrove = self._serviceTrove:Extend()
	self._playerTroves[player] = playerTrove
	playerTrove:Connect(player.CharacterAdded, function(character)
		grantWeapon(self, player, playerTrove, character)
	end)

	if player.Character then
		grantWeapon(self, player, playerTrove, player.Character)
	end
	publishWeaponState(self, player)
end

local function removePlayer(self: WeaponServiceType, player: Player)
	self._playerRuntimes[player] = nil
	if self._weaponStateProperty then
		self._weaponStateProperty:ClearFor(player)
	end

	local playerTrove = self._playerTroves[player]
	if not playerTrove then
		return
	end

	self._playerTroves[player] = nil
	self._serviceTrove:Remove(playerTrove :: any)
end

function WeaponService.onStart(self: WeaponServiceType): ()
	self._weaponComm = Comm.ServerComm.new(ReplicatedStorage, NetData.weapon.namespace)
	self._attackRequestSignal = self._weaponComm:CreateSignal(NetData.weapon.attackRequest)
	self._weaponStateProperty = self._weaponComm:CreateProperty("WeaponState", {
		ammo = 0,
		capacity = WeaponData.capacity,
	})
	self._serviceTrove:Add(self._attackRequestSignal:Connect(function(player: Player, attackRequest: any)
		performAttack(self, player, attackRequest)
	end))

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

return WeaponService
