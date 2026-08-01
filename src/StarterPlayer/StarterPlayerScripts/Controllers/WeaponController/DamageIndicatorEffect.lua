--!strict

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DURATION = 0.5

local DamageIndicatorEffect = {}

function DamageIndicatorEffect.render(
	playerGui: PlayerGui,
	anchorTemplate: BasePart,
	billboardTemplate: BillboardGui,
	position: Vector3,
	damageTextValue: string
): ()
	local anchor = anchorTemplate:Clone()
	anchor.Position = position
	anchor.Parent = Workspace

	local billboard = billboardTemplate:Clone()
	billboard.Adornee = anchor
	billboard.Parent = playerGui

	local damageText = billboard:FindFirstChild("DamageText")
	local shadow = billboard:FindFirstChild("Shadow")
	if not damageText or not damageText:IsA("TextLabel") or not shadow or not shadow:IsA("TextLabel") then
		billboard:Destroy()
		anchor:Destroy()
		warn("DamageIndicator must contain DamageText and Shadow labels")
		return
	end
	damageText.Text = damageTextValue
	shadow.Text = damageTextValue

	local tween = TweenService:Create(
		billboard,
		TweenInfo.new(DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffsetWorldSpace = Vector3.new(0, 3, 0) }
	)
	local fade = TweenService:Create(damageText, TweenInfo.new(DURATION), {
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	local shadowFade = TweenService:Create(shadow, TweenInfo.new(DURATION), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween.Completed:Once(function()
		billboard:Destroy()
		anchor:Destroy()
	end)
	tween:Play()
	fade:Play()
	shadowFade:Play()
	task.delay(DURATION + 0.25, function()
		if billboard.Parent then
			billboard:Destroy()
		end
		if anchor.Parent then
			anchor:Destroy()
		end
	end)
end

return DamageIndicatorEffect
