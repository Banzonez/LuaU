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
	LastSpacePressed: number,
	LastUppercut: number,
	AbilitiesCooldowns: AbilityCooldowns,
	UltCooldowns: AbilityCooldowns,
}

export type AttackSettings = {
	hitboxSize: Vector3,
	hitboxOffset: CFrame,
	activeDuration: number,
	maxTargets: number,
}

export type AttackSettingsOverrides = {
	hitboxSize: Vector3?,
	hitboxOffset: CFrame?,
	activeDuration: number?,
	maxTargets: number?,
}

export type Ability = {
	settings: {
		targetMode: "area" | "singleTarget",
		duration: number,
		maxTargets: number,
	},
	execute: () -> (),
}

export type StyleSettings = {
	AbilityCooldowns: AbilityCooldowns,
	ClickComboCooldown: number,
	ClickCooldown: number,
	ComboResetTime: number,
	ClicksToFinishCombo: number,
	Attacks: { [string]: AttackSettings },
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

export type StyleSettingsOverrides = {
	AbilityCooldowns: AbilityCooldowns?,
	ClickComboCooldown: number?,
	ClickCooldown: number?,
	ComboResetTime: number?,
	ClicksToFinishCombo: number?,
	Attacks: { [string]: AttackSettingsOverrides }?,
	MAX_ANGLE_DEGREES: number?,
	ClickDamage: number?,
	ClickStunTime: number?,
	LastClickStunTime: number?,
	UltSettings: {
		AbilityCooldowns: AbilityCooldowns?,
		ClickComboCooldown: number?,
		ClickCooldown: number?,
	}?,
}

return {}
