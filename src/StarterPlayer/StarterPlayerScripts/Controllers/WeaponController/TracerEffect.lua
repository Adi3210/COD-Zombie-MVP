--!strict

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local TRACER_SPEED = 300

local TracerEffect = {}

function TracerEffect.render(template: BasePart, origin: Vector3, destination: Vector3): ()
	local distance = (destination - origin).Magnitude
	if distance <= 0 then
		return
	end

	local tracer = template:Clone()
	tracer.Position = origin
	tracer.Parent = Workspace

	local duration = math.clamp(distance / TRACER_SPEED, 0.03, 0.3)
	local tween =
		TweenService:Create(tracer, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Position = destination })
	tween.Completed:Once(function()
		tracer:Destroy()
	end)
	tween:Play()
	task.delay(duration + 0.25, function()
		if tracer.Parent then
			tracer:Destroy()
		end
	end)
end

return TracerEffect
