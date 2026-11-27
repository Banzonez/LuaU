--!strict

export type CombatState = "Idle" | "Attacking" | "UsingAbility" | "UsingUlt" | "Blocking" | "Dashing" | "Stunned"

export type AbilityCooldowns = { [string]: number }

export type PlayerCombatState = {
	State: CombatState,
	actionId: number,
	ClickCombo: number,
	NextClickTime: number,
	ComboExpiresAt: number,
	LastUppercut: number,
	AbilitiesCooldowns: AbilityCooldowns,
	nextDashTime: number,
	guard: number,
	guardRegenAt: number,
	stateExpiresAt: number,
	ultCharge: number,
	ultExpiresAt: number,
}

export type AttackSettings = {
	useHitMarker: boolean?,
	waitForLanding: boolean?,
	hitboxSize: Vector3,
	hitboxOffset: CFrame,
	activeDuration: number,
	maxTargets: number,
	damage: number,
	stunTime: number,
	maxAngle: number,
	hitDelay: number,
	recovery: number,
	knockback: Vector3,
	guardBreak: boolean,
	guardDamage: number?,
	animation: string,
}

export type AttackSettingsOverrides = {
	useHitMarker: boolean?,
	waitForLanding: boolean?,
	hitboxSize: Vector3?,
	hitboxOffset: CFrame?,
	activeDuration: number?,
	maxTargets: number?,
	damage: number?,
	stunTime: number?,
	maxAngle: number?,
	hitDelay: number?,
	recovery: number?,
	knockback: Vector3?,
	guardBreak: boolean?,
	guardDamage: number?,
	animation: string?,
}

export type Ability = {
	settings: {
		name: string,
		targetMode: "area" | "singleTarget",
		duration: number,
		cooldown: number,
		dashSpeed: number,
		dashDuration: number,
		launchSpeed: number,
		ultGuardBreak: boolean?,
		attack: AttackSettings,
	},
	execute: ((character: Model) -> ())?,
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
	attackWalkSpeed: number,
	blockWalkSpeed: number,
	blockAngle: number,
	guardBreakStun: number,
	dashSpeed: number,
	dashDuration: number,
	dashCooldown: number,
	variantCooldown: number,
	ultDuration: number,
	ultActivationTime: number,
	ultRequired: number,
	ultDamageMultiplier: number,
	ultCooldownMultiplier: number,
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
	attackWalkSpeed: number?,
	blockWalkSpeed: number?,
	blockAngle: number?,
	guardBreakStun: number?,
	dashSpeed: number?,
	dashDuration: number?,
	dashCooldown: number?,
	variantCooldown: number?,
	ultDuration: number?,
	ultActivationTime: number?,
	ultRequired: number?,
	ultDamageMultiplier: number?,
	ultCooldownMultiplier: number?,
	UltSettings: {
		AbilityCooldowns: AbilityCooldowns?,
		ClickComboCooldown: number?,
		ClickCooldown: number?,
	}?,
}

return {}
