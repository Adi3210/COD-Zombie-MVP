--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Comm"))
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))

local NetData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Net"))
local WeaponData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Weapon"))

type TroveType = typeof(Trove.new())
type WeaponControllerType = {
	_serviceTrove: TroveType,
	_backpackTrove: TroveType,
	_characterTrove: TroveType,
	_toolTroves: { [Tool]: TroveType },
	_weaponComm: any,
	_attackRequestSignal: any,
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
} :: WeaponControllerType

WeaponController._backpackTrove = WeaponController._serviceTrove:Extend()
WeaponController._characterTrove = WeaponController._serviceTrove:Extend()

local function stopObservingTool(self: WeaponControllerType, tool: Tool)
	local toolTrove = self._toolTroves[tool]
	if not toolTrove then
		return
	end

	self._toolTroves[tool] = nil
	self._serviceTrove:Remove(toolTrove :: any)
end

local function sendAttackRequest(self: WeaponControllerType, tool: Tool)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local attackRequest = {
		tool = tool,
		cameraOrigin = camera.CFrame.Position,
		aimDirection = camera.CFrame.LookVector,
	}
	self._attackRequestSignal:Fire(attackRequest)
end

local function observeTool(self: WeaponControllerType, tool: Tool)
	if tool.Name ~= WeaponData.weaponName or self._toolTroves[tool] then
		return
	end

	local toolTrove = self._serviceTrove:Extend()
	self._toolTroves[tool] = toolTrove
	toolTrove:Connect(tool.Activated, function()
		sendAttackRequest(self, tool)
	end)
	toolTrove:Connect(tool.AncestryChanged, function()
		if not tool:IsDescendantOf(game) then
			stopObservingTool(self, tool)
		end
	end)

	if not tool:IsDescendantOf(game) then
		stopObservingTool(self, tool)
	end
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
	if not backpack:IsDescendantOf(game) then
		return
	end

	self._backpackTrove:Connect(backpack.AncestryChanged, function()
		if not backpack:IsDescendantOf(game) then
			self._backpackTrove:Clean()
		end
	end)
	observeTools(self, backpack, self._backpackTrove)
end

local function observeCharacter(self: WeaponControllerType, character: Model)
	self._characterTrove:Clean()
	if not character:IsDescendantOf(game) then
		return
	end

	self._characterTrove:Connect(character.AncestryChanged, function()
		if not character:IsDescendantOf(game) then
			self._characterTrove:Clean()
		end
	end)
	observeTools(self, character, self._characterTrove)
end

local function connectSignals(self: WeaponControllerType)
	self._weaponComm = Comm.ClientComm.new(ReplicatedStorage, false, NetData.weapon.namespace)
	self._attackRequestSignal = self._weaponComm:GetSignal(NetData.weapon.attackRequest)
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
	end)
end

function WeaponController.onStart(self: WeaponControllerType): ()
	connectSignals(self)
	connectEvents(self)

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		observeBackpack(self, backpack)
	end

	if player.Character then
		observeCharacter(self, player.Character)
	end
end

return WeaponController
