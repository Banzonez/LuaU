--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

local basicStyle = {}

local function attackSettings(animation: string): Types.AttackSettings
	return {
		hitboxSize = Vector3.new(4, 5, 5),
		hitboxOffset = CFrame.new(0, 0, -3),
		activeDuration = 0.12,
		maxTargets = 1,
		damage = 5,
		stunTime = 0.45,
		maxAngle = 75,
		hitDelay = 0.18,
		recovery = 0.45,
		knockback = Vector3.zero,
		guardBreak = false,
		guardDamage = 1,
		animation = animation,
	}
end

function basicStyle.getSettings(): Types.StyleSettings
	local attacks: { [string]: Types.AttackSettings } = {}

	for index = 1, 4 do
		attacks["Click" .. index] = attackSettings("Click" .. index)
	end

	attacks.Click4.recovery = 0.8
	attacks.Click4.stunTime = 0.8
	attacks.Click4.damage = 8
	attacks.Click4.guardDamage = 2
	attacks.Click4.knockback = Vector3.new(0, 12, -35)

	attacks.Uppercut = attackSettings("Uppercut")
	attacks.Uppercut.recovery = 0.85
	attacks.Uppercut.stunTime = 0.85
	attacks.Uppercut.damage = 8
	attacks.Uppercut.guardDamage = 2
	attacks.Uppercut.knockback = Vector3.new(0, 55, -5)

	attacks.Downcut = attackSettings("Downcut")
	attacks.Downcut.hitboxSize = Vector3.new(6, 8, 6)
	attacks.Downcut.hitboxOffset = CFrame.new(0, -2, -2)
	attacks.Downcut.recovery = 0.85
	attacks.Downcut.stunTime = 0.9
	attacks.Downcut.damage = 8
	attacks.Downcut.guardDamage = 2
	attacks.Downcut.knockback = Vector3.new(0, -55, -8)

	attacks.DashFront = attackSettings("DashFront")
	attacks.DashFront.damage = 4
	attacks.DashFront.hitDelay = 0.12
	attacks.DashFront.recovery = 0.5
	attacks.DashFront.activeDuration = 0.2

	return {
		AbilityCooldowns = { ["1"] = 4, ["2"] = 6, ["3"] = 8, ["4"] = 7 },
		ClickComboCooldown = 0.25,
		ClickCooldown = 0.1,
		ComboResetTime = 1,
		ClicksToFinishCombo = 4,
		Attacks = attacks,
		MAX_ANGLE_DEGREES = 75,
		ClickDamage = 5,
		ClickStunTime = 0.45,
		LastClickStunTime = 0.8,
		attackWalkSpeed = 8,
		blockWalkSpeed = 6,
		blockAngle = 75,
		guardBreakStun = 1.2,
		dashSpeed = 55,
		dashDuration = 0.25,
		dashCooldown = 1.5,
		variantCooldown = 1.5,
		ultDuration = 20,
		ultActivationTime = 0.6,
		ultRequired = 200,
		ultDamageMultiplier = 1.4,
		ultCooldownMultiplier = 0.7,
		UltSettings = {
			AbilityCooldowns = { ["1"] = 2, ["2"] = 4, ["3"] = 5, ["4"] = 5 },
			ClickComboCooldown = 0.15,
			ClickCooldown = 0.05,
		},
	}
end

function basicStyle.new(player: Player?, settings: Types.StyleSettingsOverrides?)
	local abilities: { [string]: Types.Ability } = {}
	local names = { "Straight Strike", "Knee Rush", "Spinning Kick", "Aerial Slam" }

	for index, name in ipairs(names) do
		local attack = attackSettings("Ability" .. index)
		attack.guardDamage = ({ 2, 4, 3, 6 })[index]
		attack.damage = ({ 11, 13, 15, 17 })[index]
		attack.recovery = 0.8
		attack.stunTime = 0.7
		attack.hitDelay = 0.25
		abilities[tostring(index)] = {
			settings = {
				name = name,
				targetMode = "singleTarget",
				duration = 0.8,
				cooldown = ({ 4, 6, 8, 7 })[index],
				dashSpeed = 0,
				dashDuration = 0,
				launchSpeed = 0,
				attack = attack,
			},
		}
	end

	abilities["1"].settings.attack.hitboxSize = Vector3.new(4, 5, 8)
	abilities["1"].settings.attack.hitboxOffset = CFrame.new(0, 0, -4)
	abilities["2"].settings.ultGuardBreak = true
	abilities["2"].settings.dashSpeed = 40
	abilities["2"].settings.dashDuration = 0.3
	abilities["2"].settings.attack.activeDuration = 0.25
	abilities["2"].settings.attack.knockback = Vector3.new(0, 15, -25)
	abilities["3"].settings.ultGuardBreak = true
	abilities["3"].settings.targetMode = "area"
	abilities["3"].settings.attack.hitboxSize = Vector3.new(10, 5, 10)
	abilities["3"].settings.attack.hitboxOffset = CFrame.identity
	abilities["3"].settings.attack.maxTargets = 4
	abilities["3"].settings.attack.maxAngle = 180
	abilities["4"].settings.targetMode = "area"
	abilities["4"].settings.duration = 1
	abilities["4"].settings.launchSpeed = 28
	abilities["4"].settings.attack.hitDelay = 0.15
	abilities["4"].settings.attack.waitForLanding = true
	abilities["4"].settings.attack.recovery = 1
	abilities["4"].settings.attack.hitboxSize = Vector3.new(10, 8, 10)
	abilities["4"].settings.attack.hitboxOffset = CFrame.new(0, -2, 0)
	abilities["4"].settings.attack.maxTargets = 4
	abilities["4"].settings.attack.maxAngle = 180
	abilities["4"].settings.ultGuardBreak = true
	abilities["4"].settings.attack.knockback = Vector3.new(0, -25, -10)

	return {
		Player = player,
		Settings = settings or basicStyle.getSettings(),
		StyleName = "BasicStyle",
		Abilities = abilities,
	}
end

return basicStyle
