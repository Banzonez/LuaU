--!strict

export type CombatAction = "Clicks" | "Abilities" | "Ult"

export type CombatState =
	"Idle"
	| "Attacking"
	| "UsingAbility"
	| "UsingUlt"
	| "AirFrame"
	| "Stunned"

export type AbilityResult = "success" | "failed"

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

export type CombatStyle = {
	Player: Player,
	StyleName: string,
	Settings: StyleSettings,
	Abilities: {
		[string]: () -> AbilityResult,
	},
}

export type CombatStyleModule = {
	new: (player: Player, settings: StyleSettings?) -> CombatStyle,
}

export type CombatObject = {
	Style: CombatStyle,
	Settings: StyleSettings,
	State: PlayerCombatState,
	SetStyle: (
		self: CombatObject,
		player: Player,
		styleName: string,
		settings: StyleSettings?
	) -> boolean,
}

export type PlayerAnimationCache = {
	Animator: Animator,
	Tracks: {
		[Animation]: AnimationTrack,
	},
	PlayingTrack: AnimationTrack?,
}

return {}
