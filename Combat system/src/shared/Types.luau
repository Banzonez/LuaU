--!strict

export type CombatState =
	"Idle"
	| "Attacking"
	| "UsingAbility"
	| "UsingUlt"
	| "AirFrame"
	| "Stunned"

export type AbilityCooldowns = {
	[string]: number,
}

export type PlayerCombatState = {
	State: CombatState,
	ClickCombo: number,
	NextClickTime: number,
	ComboExpiresAt: number,
	AbilitiesCooldowns: AbilityCooldowns,
	UltCooldowns: AbilityCooldowns,
}

export type StyleSettings = {
	AbilityCooldowns: AbilityCooldowns,
	ClickComboCooldown: number,
	ClickCooldown: number,
	ComboResetTime: number,
	ClicksToFinishCombo: number,
	HitboxRadius: number,
	MAX_ANGLE_DEGREES: number,
	ClickDamage: number,
	ClickStunTime: number,
	LastClickStunTime: number,
	UltSettings: {
		AbilityCooldowns: AbilityCooldowns,
		ClickComboCooldown: number,
		ClickCooldown: number,
	},
}

return {}
