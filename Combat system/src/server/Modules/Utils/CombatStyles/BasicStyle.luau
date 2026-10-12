--!strict

local basicStyle = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local function attackSettings(): Types.AttackSettings
	return {
		hitboxSize = Vector3.new(4, 4, 4),
		hitboxOffset = CFrame.new(0, 0, -3),
		activeDuration = 0.3,
		maxTargets = 1,
	}
end

function basicStyle.getSettings(): Types.StyleSettings
	return {
		AbilityCooldowns = {
			["1"] = 4,
			["2"] = 6,
			["3"] = 8,
			["4"] = 7,
		},

		-- The final cooldown is applied after the animation has ended.
		ClickComboCooldown = 0.25,
		-- The normal cooldown is applied after the animation has ended.
		ClickCooldown = 0.1,
		ComboResetTime = 1.25,
		ClicksToFinishCombo = 4,
		Attacks = {
			Click1 = attackSettings(),
			Click2 = attackSettings(),
			Click3 = attackSettings(),
			Click4 = attackSettings(),
			Uppercut = attackSettings(),
		},
		MAX_ANGLE_DEGREES = 60,
		ClickDamage = 5,
		ClickStunTime = 0.05,
		LastClickStunTime = 0.15,

		UltSettings = {
			AbilityCooldowns = {
				["1"] = 2,
				["2"] = 15,
				["3"] = 20,
				["4"] = 9,
			},

			ClickComboCooldown = 0,
			ClickCooldown = 0.1,
		},
	}
end

function basicStyle.new(player: Player, settings: Types.StyleSettingsOverrides?)
	local abilities: { [string]: Types.Ability } = {
		["1"] = {
			settings = { targetMode = "singleTarget", duration = 0, maxTargets = 1 },
			execute = function() end,
		},
		["2"] = {
			settings = { targetMode = "area", duration = 0, maxTargets = 3 },
			execute = function() end,
		},
		["3"] = {
			settings = { targetMode = "singleTarget", duration = 0, maxTargets = 1 },
			execute = function() end,
		},
		["4"] = {
			settings = { targetMode = "area", duration = 0, maxTargets = 3 },
			execute = function() end,
		},
	}
	return {
		Player = player,
		Settings = settings or basicStyle.getSettings(),
		StyleName = "BasicStyle",
		Abilities = abilities,
	}
end

return basicStyle
