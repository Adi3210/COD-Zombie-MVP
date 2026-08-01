--!strict

local MUZZLE_FLASH_DURATION = 0.09
local MUZZLE_FLASH_IMAGES = {
	"rbxassetid://103740493",
	"rbxassetid://103804266",
	"rbxassetid://103804383",
}

local effectIds: { [Tool]: number } = {}
local MuzzleEffect = {}

function MuzzleEffect.cleanup(tool: Tool): ()
	effectIds[tool] = nil
end

function MuzzleEffect.play(tool: Tool): ()
	local flare = tool:FindFirstChild("Flare", true)
	local muzzleFlash = flare and flare:FindFirstChild("MuzzleFlash")
	local image = muzzleFlash and muzzleFlash:FindFirstChild("Img")
	local handle = tool:FindFirstChild("Handle")
	local muzzleLight = handle and handle:FindFirstChild("Flash")

	effectIds[tool] = (effectIds[tool] or 0) + 1
	local effectId = effectIds[tool]
	if muzzleFlash and muzzleFlash:IsA("BillboardGui") then
		muzzleFlash.Enabled = true
	end
	if muzzleLight and muzzleLight:IsA("Light") then
		muzzleLight.Enabled = true
	end

	task.spawn(function()
		if image and image:IsA("ImageLabel") then
			for _, imageId in MUZZLE_FLASH_IMAGES do
				if effectIds[tool] ~= effectId then
					return
				end
				image.Image = imageId
				task.wait(MUZZLE_FLASH_DURATION / #MUZZLE_FLASH_IMAGES)
			end
		else
			task.wait(MUZZLE_FLASH_DURATION)
		end

		if effectIds[tool] ~= effectId then
			return
		end
		if muzzleFlash and muzzleFlash:IsA("BillboardGui") then
			muzzleFlash.Enabled = false
		end
		if muzzleLight and muzzleLight:IsA("Light") then
			muzzleLight.Enabled = false
		end
		effectIds[tool] = nil
	end)
end

return MuzzleEffect
