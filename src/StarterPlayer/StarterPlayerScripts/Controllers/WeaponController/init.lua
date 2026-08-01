--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Comm"))
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))

local Format = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("Format"))
local NetData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Net"))
local WeaponData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Weapon"))
local WeaponUtil = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("Weapon"))
local SoundController = require(script.Parent:WaitForChild("SoundController"))
local DamageIndicatorEffect = require(script:WaitForChild("DamageIndicatorEffect"))
local HitmarkerEffect = require(script:WaitForChild("HitmarkerEffect"))
local MuzzleEffect = require(script:WaitForChild("MuzzleEffect"))
local TracerEffect = require(script:WaitForChild("TracerEffect"))

local assets = ReplicatedStorage:WaitForChild("Assets")
local billboards = assets:WaitForChild("Billboards")
local effects = assets:WaitForChild("Effects")

local PREDICTED_TRACE_DISTANCE = 1000

type TroveType = typeof(Trove.new())
type WeaponState = {
	ammo: number,
	capacity: number,
	equipped: boolean,
	isReloading: boolean,
}
type WeaponControllerType = {
	_serviceTrove: TroveType,
	_backpackTrove: TroveType,
	_characterTrove: TroveType,
	_toolTroves: { [Tool]: TroveType },
	_weaponComm: any,
	_attackRequestSignal: any,
	_weaponStateProperty: any,
	_shotEffectSignal: any,
	_damageEffectSignal: any,
	_ammoFrame: Frame?,
	_crosshair: Frame?,
	_playerGui: PlayerGui?,
	_clipAmmoLabel: TextLabel?,
	_totalAmmoLabel: TextLabel?,
	_hitmarkerImage: ImageLabel?,
	_reloadingLabel: TextLabel?,
	_tracerTemplate: BasePart?,
	_damageAnchorTemplate: BasePart?,
	_damageIndicatorTemplate: BillboardGui?,
	_equippedTool: Tool?,
	_previousCameraMode: Enum.CameraMode?,
	_previousCameraDistance: number?,
	_previousCameraMinZoom: number?,
	_pendingCameraMinZoom: number?,
	_weaponsEnabled: boolean,
	_latestState: WeaponState?,
	_weaponHud: ScreenGui?,
	_nextPredictedShotAt: number,
	onStart: (self: WeaponControllerType) -> (),
}

local player = Players.LocalPlayer

local WeaponController = {
	_serviceTrove = Trove.new(),
	_backpackTrove = nil :: any,
	_characterTrove = nil :: any,
	_toolTroves = {},
	_weaponComm = nil :: any,
	_attackRequestSignal = nil :: any,
	_weaponStateProperty = nil :: any,
	_shotEffectSignal = nil :: any,
	_damageEffectSignal = nil :: any,
	_ammoFrame = nil,
	_crosshair = nil,
	_playerGui = nil,
	_clipAmmoLabel = nil,
	_totalAmmoLabel = nil,
	_hitmarkerImage = nil,
	_reloadingLabel = nil,
	_tracerTemplate = nil,
	_damageAnchorTemplate = nil,
	_damageIndicatorTemplate = nil,
	_equippedTool = nil,
	_previousCameraMode = nil,
	_previousCameraDistance = nil,
	_previousCameraMinZoom = nil,
	_pendingCameraMinZoom = nil,
	_weaponsEnabled = false,
	_latestState = nil,
	_weaponHud = nil,
	_nextPredictedShotAt = 0,
} :: WeaponControllerType

WeaponController._backpackTrove = WeaponController._serviceTrove:Extend()
WeaponController._characterTrove = WeaponController._serviceTrove:Extend()

local function setHudVisible(self: WeaponControllerType, visible: boolean)
	if self._weaponHud then
		self._weaponHud.Enabled = visible
	end
	if self._ammoFrame then
		self._ammoFrame.Visible = visible
	end
	if self._crosshair then
		self._crosshair.Visible = visible
		if self._hitmarkerImage and not visible then
			HitmarkerEffect.hide(self._hitmarkerImage)
		end
		if self._reloadingLabel then
			self._reloadingLabel.Visible = visible
				and self._latestState ~= nil
				and self._latestState.isReloading == true
		end
	end
end

local function renderWeaponState(self: WeaponControllerType, value: any)
	if type(value) ~= "table" then
		setHudVisible(self, false)
		return
	end

	local state = value :: WeaponState
	if
		type(state.ammo) ~= "number"
		or type(state.capacity) ~= "number"
		or type(state.equipped) ~= "boolean"
		or type(state.isReloading) ~= "boolean"
		or not Format.isFiniteNumber(state.ammo)
		or not Format.isFiniteNumber(state.capacity)
	then
		self._latestState = nil
		setHudVisible(self, false)
		return
	end
	local wasReloading = self._latestState and self._latestState.isReloading == true
	self._latestState = state
	if state.isReloading == true and not wasReloading then
		SoundController:playWeaponSound("Reload")
	end

	if self._clipAmmoLabel then
		self._clipAmmoLabel.Text = Format.formatCount(state.ammo)
	end
	if self._totalAmmoLabel then
		self._totalAmmoLabel.Text = Format.formatCount(state.capacity)
	end
	setHudVisible(self, state.equipped == true and self._weaponsEnabled)
end

local function restoreCamera(self: WeaponControllerType)
	if self._previousCameraMode then
		player.CameraMode = self._previousCameraMode
		self._previousCameraMode = nil
	end
	local distance = self._previousCameraDistance
	self._previousCameraDistance = nil
	local minimumZoom = self._previousCameraMinZoom
	self._previousCameraMinZoom = nil
	if distance and minimumZoom and distance > minimumZoom then
		self._pendingCameraMinZoom = minimumZoom
		player.CameraMinZoomDistance = math.min(distance, player.CameraMaxZoomDistance)
		task.spawn(function()
			RunService.RenderStepped:Wait()
			if self._pendingCameraMinZoom == minimumZoom then
				player.CameraMinZoomDistance = minimumZoom
				self._pendingCameraMinZoom = nil
			end
		end)
	end
end

local function enterFirstPerson(self: WeaponControllerType, tool: Tool)
	if self._pendingCameraMinZoom then
		player.CameraMinZoomDistance = self._pendingCameraMinZoom
		self._pendingCameraMinZoom = nil
	end
	self._equippedTool = tool
	if not self._previousCameraMode then
		self._previousCameraMode = player.CameraMode
		self._previousCameraMinZoom = player.CameraMinZoomDistance
		local camera = Workspace.CurrentCamera
		if camera then
			self._previousCameraDistance = (camera.CFrame.Position - camera.Focus.Position).Magnitude
		end
	end
	player.CameraMode = Enum.CameraMode.LockFirstPerson
end

local leaveEquippedTool: (self: WeaponControllerType, expectedTool: Tool?) -> ()

local function reconcileToolParent(self: WeaponControllerType, tool: Tool)
	if tool.Parent == player.Character then
		if self._equippedTool ~= tool then
			leaveEquippedTool(self)
			enterFirstPerson(self, tool)
			SoundController:playWeaponSound("Equip")
		end
	elseif self._equippedTool == tool then
		leaveEquippedTool(self, tool)
	end
end

local function deferToolParentReconciliation(self: WeaponControllerType, tool: Tool)
	task.defer(function()
		if tool:IsDescendantOf(game) then
			reconcileToolParent(self, tool)
		elseif self._equippedTool == tool then
			leaveEquippedTool(self, tool)
		end
	end)
end

function leaveEquippedTool(self: WeaponControllerType, expectedTool: Tool?)
	if expectedTool and self._equippedTool ~= expectedTool then
		return
	end
	self._equippedTool = nil
	self._nextPredictedShotAt = 0
	restoreCamera(self)
	setHudVisible(self, false)
end

local function playMuzzleEffect(tool: Tool)
	MuzzleEffect.play(tool)
end

local function createTracer(self: WeaponControllerType, effect: any, playFireSound: boolean?)
	if type(effect) ~= "table" then
		return
	end
	local origin = effect.origin
	local destination = effect.destination
	if
		type(effect.shooterUserId) ~= "number"
		or typeof(origin) ~= "Vector3"
		or typeof(destination) ~= "Vector3"
		or not Format.isFiniteVector(origin)
		or not Format.isFiniteVector(destination)
	then
		return
	end

	local tracerTemplate = self._tracerTemplate
	if not tracerTemplate then
		warn("Could not find weapon tracer")
		return
	end

	TracerEffect.render(tracerTemplate, origin, destination)

	if playFireSound then
		SoundController:playWeaponSound("Fire")
	end
end

local function showHitmarker(self: WeaponControllerType)
	local hitImage = self._hitmarkerImage
	if not hitImage then
		return
	end

	HitmarkerEffect.show(hitImage)
end

local function showDamageIndicator(self: WeaponControllerType, effect: any)
	if type(effect) ~= "table" then
		return
	end
	local position = effect.position
	local damage = effect.damage
	local playerGui = self._playerGui
	if
		not playerGui
		or type(damage) ~= "number"
		or typeof(position) ~= "Vector3"
		or not Format.isFiniteNumber(damage)
		or not Format.isFiniteVector(position)
	then
		return
	end

	local anchorTemplate = self._damageAnchorTemplate
	if not anchorTemplate then
		warn("Could not find damage indicator anchor")
		return
	end

	local billboardTemplate = self._damageIndicatorTemplate
	if not billboardTemplate then
		warn("Could not find damage indicator")
		return
	end

	DamageIndicatorEffect.render(playerGui, anchorTemplate, billboardTemplate, position, Format.formatCount(damage))
end

local function isCurrentDamageEffect(self: WeaponControllerType, effect: any): boolean
	return type(effect) == "table"
		and self._weaponsEnabled
		and self._equippedTool ~= nil
		and effect.tool == self._equippedTool
end

local function stopObservingTool(self: WeaponControllerType, tool: Tool)
	local toolTrove = self._toolTroves[tool]
	if not toolTrove then
		return
	end

	leaveEquippedTool(self, tool)
	self._toolTroves[tool] = nil
	MuzzleEffect.cleanup(tool)
	self._serviceTrove:Remove(toolTrove :: any)
end

local function sendAttackRequest(self: WeaponControllerType, tool: Tool)
	local camera = Workspace.CurrentCamera
	local state = self._latestState
	local now = os.clock()
	if
		not camera
		or not self._weaponsEnabled
		or self._equippedTool ~= tool
		or not state
		or not state.equipped
		or state.isReloading
		or state.ammo <= 0
		or now < self._nextPredictedShotAt
	then
		return
	end
	self._nextPredictedShotAt = now + WeaponData.cooldown

	local origin = WeaponUtil.getMuzzlePosition(tool, camera.CFrame.Position)

	local cameraTarget = camera.CFrame.Position + camera.CFrame.LookVector * PREDICTED_TRACE_DISTANCE
	local direction = cameraTarget - origin
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local excludedInstances: { Instance } = { tool }
	if player.Character then
		table.insert(excludedInstances, player.Character)
	end
	raycastParams.FilterDescendantsInstances = excludedInstances
	local result = Workspace:Raycast(origin, direction, raycastParams)
	createTracer(self, {
		origin = origin,
		destination = if result then result.Position else origin + direction,
		shooterUserId = player.UserId,
	}, true)
	playMuzzleEffect(tool)

	self._attackRequestSignal:Fire({
		tool = tool,
		cameraOrigin = camera.CFrame.Position,
		aimDirection = camera.CFrame.LookVector,
	})
end

local function observeTool(self: WeaponControllerType, tool: Tool)
	if tool.Name ~= WeaponData.weaponName or self._toolTroves[tool] then
		return
	end

	local toolTrove = self._serviceTrove:Extend()
	self._toolTroves[tool] = toolTrove
	toolTrove:Connect(tool.Equipped, function()
		reconcileToolParent(self, tool)
	end)
	toolTrove:Connect(tool.Unequipped, function()
		leaveEquippedTool(self, tool)
	end)
	toolTrove:Connect(tool.Activated, function()
		sendAttackRequest(self, tool)
	end)
	toolTrove:Connect(tool:GetPropertyChangedSignal("Parent"), function()
		deferToolParentReconciliation(self, tool)
	end)
	toolTrove:Connect(tool.Destroying, function()
		leaveEquippedTool(self, tool)
	end)
	toolTrove:Connect(tool.AncestryChanged, function()
		if not tool:IsDescendantOf(game) then
			stopObservingTool(self, tool)
		end
	end)
	deferToolParentReconciliation(self, tool)
end

local function observeTools(self: WeaponControllerType, container: Instance, containerTrove: TroveType)
	for _, child in container:GetChildren() do
		if child:IsA("Tool") then
			observeTool(self, child)
		end
	end
	containerTrove:Connect(container.ChildAdded, function(child)
		if child:IsA("Tool") then
			observeTool(self, child)
		end
	end)
end

local function observeBackpack(self: WeaponControllerType, backpack: Backpack)
	self._backpackTrove:Clean()
	if backpack:IsDescendantOf(game) then
		observeTools(self, backpack, self._backpackTrove)
	end
end

local function observeCharacter(self: WeaponControllerType, character: Model)
	leaveEquippedTool(self)
	self._characterTrove:Clean()
	setHudVisible(self, false)
	if character:IsDescendantOf(game) then
		observeTools(self, character, self._characterTrove)
	end
end

local function connectHud(self: WeaponControllerType)
	local playerGui = player:WaitForChild("PlayerGui")
	local weaponHud = playerGui:WaitForChild("WeaponHUD", 10)
	if not playerGui:IsA("PlayerGui") or not weaponHud or not weaponHud:IsA("ScreenGui") then
		warn("Could not find PlayerGui.WeaponHUD")
		return
	end
	local ammoFrame = weaponHud:FindFirstChild("Ammo")
	local crosshair = weaponHud:FindFirstChild("Crosshair")
	if not ammoFrame or not ammoFrame:IsA("Frame") or not crosshair or not crosshair:IsA("Frame") then
		warn("WeaponHUD must contain Ammo and Crosshair frames")
		return
	end
	local clipAmmoLabel = ammoFrame:FindFirstChild("ClipAmmo")
	local totalAmmoLabel = ammoFrame:FindFirstChild("TotalAmmo")
	local hitmarkerImage = crosshair:FindFirstChild("TargetHitImage")
	local reloadingLabel = crosshair:FindFirstChild("ReloadingLabel")
	if
		not clipAmmoLabel
		or not clipAmmoLabel:IsA("TextLabel")
		or not totalAmmoLabel
		or not totalAmmoLabel:IsA("TextLabel")
		or not hitmarkerImage
		or not hitmarkerImage:IsA("ImageLabel")
		or not reloadingLabel
		or not reloadingLabel:IsA("TextLabel")
	then
		warn("WeaponHUD does not match the required UI contract")
		return
	end

	self._playerGui = playerGui
	self._ammoFrame = ammoFrame
	self._crosshair = crosshair
	self._clipAmmoLabel = clipAmmoLabel
	self._totalAmmoLabel = totalAmmoLabel
	self._hitmarkerImage = hitmarkerImage
	self._reloadingLabel = reloadingLabel
	self._weaponHud = weaponHud
	crosshair.AnchorPoint = Vector2.zero
	crosshair.Position = UDim2.fromScale(0.5, 0.5)
	hitmarkerImage.Visible = false
	setHudVisible(self, false)
	if self._weaponStateProperty and self._weaponStateProperty:IsReady() then
		renderWeaponState(self, self._weaponStateProperty:Get())
	end
end

local function connectEffectTemplates(self: WeaponControllerType)
	local tracerTemplate = effects:FindFirstChild("WeaponTracer")
	local damageAnchorTemplate = effects:FindFirstChild("DamageIndicatorAnchor")
	local damageIndicatorTemplate = billboards:FindFirstChild("DamageIndicator")
	if
		not tracerTemplate
		or not tracerTemplate:IsA("BasePart")
		or not damageAnchorTemplate
		or not damageAnchorTemplate:IsA("BasePart")
		or not damageIndicatorTemplate
		or not damageIndicatorTemplate:IsA("BillboardGui")
	then
		warn("Weapon presentation assets do not match the required template contract")
		return
	end
	self._tracerTemplate = tracerTemplate
	self._damageAnchorTemplate = damageAnchorTemplate
	self._damageIndicatorTemplate = damageIndicatorTemplate
end

local function connectSignals(self: WeaponControllerType)
	self._weaponComm = Comm.ClientComm.new(ReplicatedStorage, false, NetData.weapon.namespace)
	self._attackRequestSignal = self._weaponComm:GetSignal(NetData.weapon.attackRequest)
	self._shotEffectSignal = self._weaponComm:GetSignal(NetData.weapon.shotEffect)
	self._damageEffectSignal = self._weaponComm:GetSignal(NetData.weapon.damageEffect)
	self._weaponStateProperty = self._weaponComm:GetProperty(NetData.weapon.weaponState)
	self._serviceTrove:Add(self._shotEffectSignal:Connect(function(effect: any)
		if type(effect) == "table" and effect.shooterUserId == player.UserId then
			return
		end
		createTracer(self, effect, true)
		if type(effect) == "table" and typeof(effect.tool) == "Instance" and effect.tool:IsA("Tool") then
			playMuzzleEffect(effect.tool)
		end
	end))
	self._serviceTrove:Add(self._damageEffectSignal:Connect(function(effect: any)
		if not isCurrentDamageEffect(self, effect) then
			return
		end
		showHitmarker(self)
		showDamageIndicator(self, effect)
	end))
	self._serviceTrove:Add(self._weaponStateProperty:Observe(function(value: any)
		if
			type(value) == "table"
			and value.equipped == false
			and self._equippedTool
			and self._equippedTool.Parent ~= player.Character
		then
			leaveEquippedTool(self, self._equippedTool)
		end
		renderWeaponState(self, value)
	end))

	local roundComm = Comm.ClientComm.new(ReplicatedStorage, false, NetData.round.namespace)
	local roundStateProperty = roundComm:GetProperty(NetData.round.state)
	self._serviceTrove:Add(roundStateProperty:Observe(function(value: any)
		self._weaponsEnabled = type(value) == "table"
			and (value.state == "RoundActive" or value.state == "RoundClearDelay")
		if self._latestState then
			renderWeaponState(self, self._latestState)
		else
			setHudVisible(self, false)
		end
	end))
end

local function connectEvents(self: WeaponControllerType)
	self._serviceTrove:Connect(player.ChildAdded, function(child)
		if child:IsA("Backpack") then
			observeBackpack(self, child)
		end
	end)
	self._serviceTrove:Connect(player.CharacterAdded, function(character)
		observeCharacter(self, character)
	end)
	self._serviceTrove:Connect(player.CharacterRemoving, function()
		self._characterTrove:Clean()
		leaveEquippedTool(self)
	end)
end

function WeaponController.onStart(self: WeaponControllerType): ()
	connectEffectTemplates(self)
	connectSignals(self)
	connectEvents(self)
	task.spawn(connectHud, self)

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		observeBackpack(self, backpack)
	end
	if player.Character then
		observeCharacter(self, player.Character)
	end
end

return WeaponController
