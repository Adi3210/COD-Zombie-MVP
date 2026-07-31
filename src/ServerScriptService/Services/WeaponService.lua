--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Comm"))
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))

local Format = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("Format"))
local Net = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Net"))
local Weapon = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Weapon"))

local assets = ReplicatedStorage:WaitForChild("Assets")
local weapons = assets:WaitForChild("Weapons")

local CAMERA_ORIGIN_TOLERANCE = 16
local MAXIMUM_AIM_DIRECTION_MAGNITUDE = 1000
local MINIMUM_REQUEST_INTERVAL = 1 / 30

type WeaponRuntime = {
	character: Model,
	tool: Tool,
	nextRequestAt: number,
}

type TroveType = typeof(Trove.new())
type WeaponServiceType = {
	ServiceTrove: TroveType,
	PlayerRuntimes: { [Player]: WeaponRuntime? },
	PlayerTroves: { [Player]: TroveType },
	WeaponComm: any,
	AttackRequestSignal: any,
	onStart: (self: WeaponServiceType) -> (),
}

local WeaponService = {
	ServiceTrove = Trove.new(),
	PlayerRuntimes = {},
	PlayerTroves = {},
	WeaponComm = nil :: any,
	AttackRequestSignal = nil :: any,
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
	return self.PlayerTroves[player] == playerTrove and player.Character == character
end

local function grantWeapon(self: WeaponServiceType, player: Player, playerTrove: TroveType, character: Model)
	if not isCurrentPlayerLife(self, player, playerTrove, character) then
		return
	end

	self.PlayerRuntimes[player] = nil

	local backpack = getBackpack(player)
	if not backpack then
		warn("Could not find a Backpack for " .. player.Name)
		return
	end

	if not isCurrentPlayerLife(self, player, playerTrove, character) then
		return
	end

	local tool = weapons:FindFirstChild(Weapon.weaponName)
	if not tool or not tool:IsA("Tool") then
		warn("Could not find a Tool named " .. Weapon.weaponName)
		return
	end

	local toolClone = tool:Clone()
	if not isCurrentPlayerLife(self, player, playerTrove, character) then
		toolClone:Destroy()
		return
	end

	toolClone.Parent = backpack
	self.PlayerRuntimes[player] = {
		character = character,
		tool = toolClone,
		nextRequestAt = 0,
	}
end

local function getRootPart(character: Model): BasePart?
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function canPerformAttack(self: WeaponServiceType, player: Player, attackRequest: any): boolean
	local runtime = self.PlayerRuntimes[player]
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

	print("Can perform attack")
	-- TODO:Ammo, cooldown, raycast
end

local function setupPlayer(self: WeaponServiceType, player: Player)
	if self.PlayerTroves[player] then
		return
	end

	local playerTrove = self.ServiceTrove:Extend()
	self.PlayerTroves[player] = playerTrove
	playerTrove:Connect(player.CharacterAdded, function(character)
		grantWeapon(self, player, playerTrove, character)
	end)

	if player.Character then
		grantWeapon(self, player, playerTrove, player.Character)
	end
end

local function removePlayer(self: WeaponServiceType, player: Player)
	self.PlayerRuntimes[player] = nil

	local playerTrove = self.PlayerTroves[player]
	if not playerTrove then
		return
	end

	self.PlayerTroves[player] = nil
	self.ServiceTrove:Remove(playerTrove :: any)
end

function WeaponService.onStart(self: WeaponServiceType): ()
	self.WeaponComm = Comm.ServerComm.new(ReplicatedStorage, Net.weapon.namespace)
	self.AttackRequestSignal = self.WeaponComm:CreateSignal(Net.weapon.attackRequest)
	self.ServiceTrove:Add(self.AttackRequestSignal:Connect(function(player: Player, attackRequest: any)
		performAttack(self, player, attackRequest)
	end))

	self.ServiceTrove:Connect(Players.PlayerAdded, function(player)
		setupPlayer(self, player)
	end)
	self.ServiceTrove:Connect(Players.PlayerRemoving, function(player)
		removePlayer(self, player)
	end)

	for _, player in Players:GetPlayers() do
		setupPlayer(self, player)
	end
end

return WeaponService
