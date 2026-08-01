--!strict

local SoundService = game:GetService("SoundService")

type SoundControllerType = {
	onStart: (self: SoundControllerType) -> (),
	playWeaponSound: (self: SoundControllerType, soundName: string) -> (),
}

local SoundController = {} :: SoundControllerType

function SoundController.playWeaponSound(_self: SoundControllerType, soundName: string): ()
	local weaponSound = SoundService:FindFirstChild("WeaponSound")
	local sound = weaponSound and weaponSound:FindFirstChild(soundName)
	if not sound or not sound:IsA("Sound") then
		warn("Could not find weapon sound " .. soundName)
		return
	end

	SoundService:PlayLocalSound(sound)
end

function SoundController.onStart(_self: SoundControllerType): () end

return SoundController
