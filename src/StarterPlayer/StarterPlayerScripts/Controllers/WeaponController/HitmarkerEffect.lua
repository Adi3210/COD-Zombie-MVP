--!strict

local HITMARKER_DURATION = 0.12

local currentId = 0
local HitmarkerEffect = {}

function HitmarkerEffect.hide(image: ImageLabel): ()
	currentId += 1
	image.Visible = false
end

function HitmarkerEffect.show(image: ImageLabel): ()
	currentId += 1
	local hitmarkerId = currentId
	image.Visible = true
	task.delay(HITMARKER_DURATION, function()
		if currentId == hitmarkerId then
			image.Visible = false
		end
	end)
end

return HitmarkerEffect
