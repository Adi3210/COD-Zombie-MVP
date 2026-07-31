--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local assets = ReplicatedStorage:WaitForChild("Assets")
local weapons = assets:WaitForChild("Weapons")

local STARTER_PISTOL_NAME = "Starter Pistol"

local playerConnections: { [Player]: RBXScriptConnection? } = {}

local WeaponService = {}

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

local function grantStarterPistol(player: Player, character: Model)
	if player.Character ~= character then
		return
	end

	local backpack = getBackpack(player)
	if not backpack then
		warn("Could not find a Backpack for " .. player.Name)
		return
	end

	if player.Character ~= character then
		return
	end

	local tool = weapons:FindFirstChild(STARTER_PISTOL_NAME)
	local toolClone = tool and tool:Clone()
	if toolClone then
		toolClone.Parent = backpack
	end
end

local function setupPlayer(player: Player)
	if playerConnections[player] then
		return
	end

	playerConnections[player] = player.CharacterAdded:Connect(function(character)
		grantStarterPistol(player, character)
	end)

	if player.Character then
		grantStarterPistol(player, player.Character)
	end
end

local function removePlayer(player: Player)
	local connection = playerConnections[player]
	if not connection then
		return
	end

	playerConnections[player] = nil
	connection:Disconnect()
end

function WeaponService.onStart(): ()
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(removePlayer)

	for _, player in Players:GetPlayers() do
		setupPlayer(player)
	end
end

return WeaponService
