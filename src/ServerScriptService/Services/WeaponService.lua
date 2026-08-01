--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Comm = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Comm"))
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))

local Format = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("Format"))
local NetData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Net"))
local WeaponData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Weapon"))
local WeaponUtil = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("Weapon"))

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
	isReloading: boolean,
	reloadTask: thread?,
	reloadToken: number,
}

type TroveType = typeof(Trove.new())
type WeaponServiceType = {
	_serviceTrove: TroveType,
	_playerRuntimes: { [Player]: WeaponRuntime? },
	_playerTroves: { [Player]: TroveType },
	_weaponComm: any,
	_attackRequestSignal: any,
	_weaponStateProperty: any,
	_shotEffectSignal: any,
	_damageEffectSignal: any,
	onStart: (self: WeaponServiceType) -> (),
}

local WeaponService = {
	_serviceTrove = Trove.new(),
	_playerRuntimes = {},
	_playerTroves = {},
	_weaponComm = nil :: any,
	_attackRequestSignal = nil :: any,
	_weaponStateProperty = nil :: any,
	_shotEffectSignal = nil :: any,
	_damageEffectSignal = nil :: any,
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

local publishWeaponState: (self: WeaponServiceType, player: Player) -> ()

local function cancelReload(runtime: WeaponRuntime)
	runtime.isReloading = false
	runtime.reloadToken += 1
	if runtime.reloadTask then
		task.cancel(runtime.reloadTask)
		runtime.reloadTask = nil
	end
end

local function grantWeapon(self: WeaponServiceType, player: Player, playerTrove: TroveType, character: Model)
	if not isCurrentPlayerLife(self, player, playerTrove, character) or not RoundService:isWeaponEnabled() then
		return
	end

	local previousRuntime = self._playerRuntimes[player]
	if previousRuntime and previousRuntime.character == character and previousRuntime.tool.Parent then
		return
	end
	if previousRuntime then
		cancelReload(previousRuntime)
		if previousRuntime.tool.Parent then
			previousRuntime.tool:Destroy()
		end
	end
	self._playerRuntimes[player] = nil

	local backpack = getBackpack(player)
	if not backpack then
		warn("Could not find a Backpack for " .. player.Name)
		return
	end

	if not isCurrentPlayerLife(self, player, playerTrove, character) or not RoundService:isWeaponEnabled() then
		return
	end

	local tool = weapons:FindFirstChild(WeaponData.weaponName)
	if not tool or not tool:IsA("Tool") then
		warn("Could not find a Tool named " .. WeaponData.weaponName)
		return
	end

	local toolClone = tool:Clone()
	if not isCurrentPlayerLife(self, player, playerTrove, character) or not RoundService:isWeaponEnabled() then
		toolClone:Destroy()
		return
	end

	toolClone.Parent = backpack
	self._playerRuntimes[player] = {
		ammo = WeaponData.capacity,
		character = character,
		isReloading = false,
		nextShotAt = 0,
		tool = toolClone,
		nextRequestAt = 0,
		reloadTask = nil,
		reloadToken = 0,
	}
	local function deferToolStateReconciliation()
		task.defer(function()
			local runtime = self._playerRuntimes[player]
			if not runtime or runtime.tool ~= toolClone then
				return
			end
			if toolClone.Parent ~= runtime.character then
				cancelReload(runtime)
			end
			publishWeaponState(self, player)
		end)
	end
	playerTrove:Connect(toolClone:GetPropertyChangedSignal("Parent"), function()
		deferToolStateReconciliation()
	end)
	playerTrove:Connect(toolClone.Destroying, function()
		local runtime = self._playerRuntimes[player]
		if not runtime or runtime.tool ~= toolClone then
			return
		end
		cancelReload(runtime)
		self._playerRuntimes[player] = nil
		self._weaponStateProperty:SetFor(player, {
			ammo = 0,
			capacity = WeaponData.capacity,
			equipped = false,
			isReloading = false,
		})
	end)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		playerTrove:Connect(humanoid.Died, function()
			local runtime = self._playerRuntimes[player]
			if not runtime or runtime.character ~= character then
				return
			end
			cancelReload(runtime)
			self._playerRuntimes[player] = nil
			toolClone:Destroy()
			self._weaponStateProperty:SetFor(player, {
				ammo = 0,
				capacity = WeaponData.capacity,
				equipped = false,
				isReloading = false,
			})
		end)
	end
	publishWeaponState(self, player)
end

function publishWeaponState(self: WeaponServiceType, player: Player)
	local runtime = self._playerRuntimes[player]
	if self._weaponStateProperty and runtime then
		self._weaponStateProperty:SetFor(player, {
			ammo = runtime.ammo,
			capacity = WeaponData.capacity,
			equipped = runtime.tool.Parent == runtime.character,
			isReloading = runtime.isReloading,
		})
	end
end

local function revokeWeapon(self: WeaponServiceType, player: Player)
	local runtime = self._playerRuntimes[player]
	if runtime then
		cancelReload(runtime)
		self._playerRuntimes[player] = nil
		if runtime.tool.Parent then
			runtime.tool:Destroy()
		end
	end
	if self._weaponStateProperty then
		self._weaponStateProperty:SetFor(player, {
			ammo = 0,
			capacity = WeaponData.capacity,
			equipped = false,
			isReloading = false,
		})
	end
end

local function reconcileWeaponAvailability(self: WeaponServiceType, enabled: boolean)
	for _, player in Players:GetPlayers() do
		if not enabled then
			revokeWeapon(self, player)
			continue
		end

		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local playerTrove = self._playerTroves[player]
		if character and humanoid and humanoid.Health > 0 and playerTrove then
			grantWeapon(self, player, playerTrove, character)
		end
	end
end

local function beginReload(self: WeaponServiceType, player: Player, requestedTool: Tool)
	local runtime = self._playerRuntimes[player]
	if not runtime then
		return
	end
	if
		player.Character ~= runtime.character
		or requestedTool ~= runtime.tool
		or runtime.tool.Parent ~= runtime.character
		or runtime.ammo >= WeaponData.capacity
		or runtime.isReloading
		or not RoundService:isWeaponEnabled()
	then
		return
	end

	local humanoid = runtime.character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	runtime.isReloading = true
	runtime.reloadToken += 1
	local reloadToken = runtime.reloadToken
	publishWeaponState(self, player)
	runtime.reloadTask = task.delay(WeaponData.reloadDuration, function()
		local currentRuntime = self._playerRuntimes[player]
		if not currentRuntime or currentRuntime ~= runtime or currentRuntime.reloadToken ~= reloadToken then
			return
		end

		currentRuntime.reloadTask = nil
		currentRuntime.isReloading = false
		local currentHumanoid = currentRuntime.character:FindFirstChildOfClass("Humanoid")
		if
			player.Character == currentRuntime.character
			and currentRuntime.tool.Parent == currentRuntime.character
			and currentHumanoid
			and currentHumanoid.Health > 0
			and RoundService:isWeaponEnabled()
		then
			currentRuntime.ammo = WeaponData.capacity
		end
		publishWeaponState(self, player)
	end)
end

local function getRootPart(character: Model): BasePart?
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function getRayOrigin(character: Model): Vector3?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head.Position
	end

	local rootPart = getRootPart(character)
	return rootPart and rootPart.Position or nil
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
	if not RoundService:isWeaponEnabled() or runtime.ammo <= 0 or runtime.isReloading or now < runtime.nextShotAt then
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
	if not Format.isFiniteNumber(originDistance) or originDistance > CAMERA_ORIGIN_TOLERANCE then
		return false
	end
	return true
end

local function performAttack(self: WeaponServiceType, player: Player, attackRequest: any)
	if not canPerformAttack(self, player, attackRequest) then
		return
	end

	local runtime = self._playerRuntimes[player]
	if not runtime then
		return
	end

	local safeOrigin = getRayOrigin(runtime.character)
	if not safeOrigin then
		return
	end

	local muzzlePosition = WeaponUtil.getMuzzlePosition(runtime.tool, safeOrigin)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { runtime.character, runtime.tool }
	local muzzleOffset = muzzlePosition - safeOrigin
	if muzzleOffset.Magnitude > 0 and workspace:Raycast(safeOrigin, muzzleOffset, raycastParams) then
		return
	end

	local cameraTarget = attackRequest.cameraOrigin + attackRequest.aimDirection.Unit * TRACE_DISTANCE
	local muzzleDirection = cameraTarget - muzzlePosition
	if muzzleDirection.Magnitude == 0 then
		return
	end
	local direction = muzzleDirection.Unit * TRACE_DISTANCE
	local result = workspace:Raycast(muzzlePosition, direction, raycastParams)
	local hitPosition = if result then result.Position else muzzlePosition + direction

	runtime.ammo -= 1
	runtime.nextShotAt = os.clock() + WeaponData.cooldown
	publishWeaponState(self, player)
	self._shotEffectSignal:FireAll({
		origin = muzzlePosition,
		destination = hitPosition,
		shooterUserId = player.UserId,
		tool = runtime.tool,
	})
	if runtime.ammo == 0 then
		beginReload(self, player, runtime.tool)
	end
	if result then
		local damagedZombie = ZombieService:damageZombie(player, result.Instance, WeaponData.damage)
		if damagedZombie then
			self._damageEffectSignal:Fire(player, {
				damage = WeaponData.damage,
				position = result.Position,
				tool = runtime.tool,
			})
		end
	end
end

local function setupPlayer(self: WeaponServiceType, player: Player)
	if self._playerTroves[player] then
		return
	end

	local playerTrove = self._serviceTrove:Extend()
	self._playerTroves[player] = playerTrove
	playerTrove:Connect(player.CharacterAdded, function(character)
		if RoundService:isWeaponEnabled() then
			grantWeapon(self, player, playerTrove, character)
		else
			revokeWeapon(self, player)
		end
	end)

	if player.Character and RoundService:isWeaponEnabled() then
		grantWeapon(self, player, playerTrove, player.Character)
	end
	publishWeaponState(self, player)
end

local function removePlayer(self: WeaponServiceType, player: Player)
	local runtime = self._playerRuntimes[player]
	if runtime then
		cancelReload(runtime)
	end
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
	self._shotEffectSignal = self._weaponComm:CreateSignal(NetData.weapon.shotEffect, true)
	self._damageEffectSignal = self._weaponComm:CreateSignal(NetData.weapon.damageEffect, true)
	self._weaponStateProperty = self._weaponComm:CreateProperty(NetData.weapon.weaponState, {
		ammo = 0,
		capacity = WeaponData.capacity,
		equipped = false,
		isReloading = false,
	})
	self._serviceTrove:Add(self._attackRequestSignal:Connect(function(player: Player, attackRequest: any)
		performAttack(self, player, attackRequest)
	end))
	self._serviceTrove:Connect(RoundService.weaponAvailabilityChanged, function(enabled: boolean)
		reconcileWeaponAvailability(self, enabled)
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
	reconcileWeaponAvailability(self, RoundService:isWeaponEnabled())
end

return WeaponService
