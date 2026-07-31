--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Comm = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Comm"))
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))

local Net = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Net"))
local Weapon = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Weapon"))

type TroveType = typeof(Trove.new())
type WeaponControllerType = {
	ServiceTrove: TroveType,
	BackpackTrove: TroveType,
	CharacterTrove: TroveType,
	ToolTroves: { [Tool]: TroveType },
	ClientComm: any,
	AttackRequestSignal: any,
	onStart: (self: WeaponControllerType) -> (),
}

local player = Players.LocalPlayer

local WeaponController = {
	ServiceTrove = Trove.new(),
	BackpackTrove = nil :: any,
	CharacterTrove = nil :: any,
	ToolTroves = {},
	ClientComm = nil :: any,
	AttackRequestSignal = nil :: any,
} :: WeaponControllerType

WeaponController.BackpackTrove = WeaponController.ServiceTrove:Extend()
WeaponController.CharacterTrove = WeaponController.ServiceTrove:Extend()

local function stopObservingTool(self: WeaponControllerType, tool: Tool)
	local toolTrove = self.ToolTroves[tool]
	if not toolTrove then
		return
	end

	self.ToolTroves[tool] = nil
	self.ServiceTrove:Remove(toolTrove :: any)
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
	self.AttackRequestSignal:Fire(attackRequest)
end

local function observeTool(self: WeaponControllerType, tool: Tool)
	if tool.Name ~= Weapon.weaponName or self.ToolTroves[tool] then
		return
	end

	local toolTrove = self.ServiceTrove:Extend()
	self.ToolTroves[tool] = toolTrove
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
	self.BackpackTrove:Clean()
	if not backpack:IsDescendantOf(game) then
		return
	end

	self.BackpackTrove:Connect(backpack.AncestryChanged, function()
		if not backpack:IsDescendantOf(game) then
			self.BackpackTrove:Clean()
		end
	end)
	observeTools(self, backpack, self.BackpackTrove)
end

local function observeCharacter(self: WeaponControllerType, character: Model)
	self.CharacterTrove:Clean()
	if not character:IsDescendantOf(game) then
		return
	end

	self.CharacterTrove:Connect(character.AncestryChanged, function()
		if not character:IsDescendantOf(game) then
			self.CharacterTrove:Clean()
		end
	end)
	observeTools(self, character, self.CharacterTrove)
end

function WeaponController.onStart(self: WeaponControllerType): ()
	self.ClientComm = Comm.ClientComm.new(ReplicatedStorage, false, Net.weapon.namespace)
	self.AttackRequestSignal = self.ClientComm:GetSignal(Net.weapon.attackRequest)

	self.ServiceTrove:Connect(player.ChildAdded, function(child)
		if child:IsA("Backpack") then
			observeBackpack(self, child)
		end
	end)
	self.ServiceTrove:Connect(player.CharacterAdded, function(character)
		observeCharacter(self, character)
	end)
	self.ServiceTrove:Connect(player.CharacterRemoving, function()
		self.CharacterTrove:Clean()
	end)

	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		observeBackpack(self, backpack)
	end

	if player.Character then
		observeCharacter(self, player.Character)
	end
end

return WeaponController
