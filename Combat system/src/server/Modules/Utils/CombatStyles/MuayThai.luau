--!strict

local basicStyle = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

local function styleSettings(): Types.StyleSettings
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
		HitboxRadius = 5,
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

function basicStyle.new(player: Player, settings: Types.StyleSettings?): Types.CombatStyle
	local self = {} :: Types.CombatStyle

	self.Player = player
	self.Settings = settings or styleSettings()
	self.StyleName = "MuayThai"
	self.Abilities = {
		["1"] = function()
			return "success"
		end,

		["2"] = function()
			return "success"
		end,

		["3"] = function()
			return "success"
		end,

		["4"] = function()
			return "success"
		end,
	}

	return self
end

return basicStyle
