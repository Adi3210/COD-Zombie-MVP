--!strict

local Net = table.freeze({
	weapon = table.freeze({
		namespace = "Weapon",
		attackRequest = "AttackRequest",
	}),
	round = table.freeze({
		namespace = "Round",
		state = "State",
	}),
})

return Net
