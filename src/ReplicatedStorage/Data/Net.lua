--!strict

local Net = table.freeze({
	weapon = table.freeze({
		namespace = "Weapon",
		attackRequest = "AttackRequest",
		weaponState = "WeaponState",
		shotEffect = "ShotEffect",
		damageEffect = "DamageEffect",
	}),
	round = table.freeze({
		namespace = "Round",
		state = "State",
	}),
})

return Net
