--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local utilsFolder = ServerScriptService:WaitForChild("Server"):WaitForChild("Modules"):WaitForChild("Utils")
local combatStyles = utilsFolder:WaitForChild("CombatStyles")
local StateHandler = require(script.Parent:WaitForChild("CombatStateHandler"))
local basicStyleModule = combatStyles:FindFirstChild("BasicStyle")
assert(basicStyleModule and basicStyleModule:IsA("ModuleScript"), "BasicStyle module was not found.")
local basicStyle = require(basicStyleModule)

type CombatStyle = {
	Settings: Types.StyleSettings,
	StyleName: string,
	Abilities: { [string]: Types.Ability },
}

type CombatObject = {
	Style: CombatStyle,
	Settings: Types.StyleSettings,
	State: Types.PlayerCombatState,
	SetStyle: (self: CombatObject, player: Player, styleName: string, settings: Types.StyleSettingsOverrides?) -> boolean,
}

local playerObjs: { [Player]: CombatObject } = {}
local setup = {}

local function mergeCooldowns(defaults: Types.AbilityCooldowns, overrides: Types.AbilityCooldowns?): Types.AbilityCooldowns
	local cooldowns = table.clone(defaults)
	if overrides then
		for key, value in pairs(overrides) do
			cooldowns[key] = value
		end
	end
	return cooldowns
end

local function mergeAttacks(defaults: { [string]: Types.AttackSettings }, overrides: { [string]: Types.AttackSettingsOverrides }?): { [string]: Types.AttackSettings }
	local attacks: { [string]: Types.AttackSettings } = {}
	for name, attack in pairs(defaults) do
		attacks[name] = table.clone(attack)
	end
	if overrides then
		for name, attack in pairs(overrides) do
			local defaultAttack = defaults[name] or defaults.Click1
			attacks[name] = {
				hitboxSize = attack.hitboxSize or defaultAttack.hitboxSize,
				hitboxOffset = attack.hitboxOffset or defaultAttack.hitboxOffset,
				activeDuration = attack.activeDuration or defaultAttack.activeDuration,
				maxTargets = attack.maxTargets or defaultAttack.maxTargets,
			}
		end
	end
	return attacks
end

local function getSettings(settings: Types.StyleSettingsOverrides?): Types.StyleSettings
	local defaults = basicStyle.getSettings()
	if not settings then
		return defaults
	end

	local ultSettings = settings.UltSettings or defaults.UltSettings
	return {
		AbilityCooldowns = mergeCooldowns(defaults.AbilityCooldowns, settings.AbilityCooldowns),
		ClickComboCooldown = settings.ClickComboCooldown or defaults.ClickComboCooldown,
		ClickCooldown = settings.ClickCooldown or defaults.ClickCooldown,
		ComboResetTime = settings.ComboResetTime or defaults.ComboResetTime,
		ClicksToFinishCombo = settings.ClicksToFinishCombo or defaults.ClicksToFinishCombo,
		Attacks = mergeAttacks(defaults.Attacks, settings.Attacks),
		MAX_ANGLE_DEGREES = settings.MAX_ANGLE_DEGREES or defaults.MAX_ANGLE_DEGREES,
		ClickDamage = settings.ClickDamage or defaults.ClickDamage,
		ClickStunTime = settings.ClickStunTime or defaults.ClickStunTime,
		LastClickStunTime = settings.LastClickStunTime or defaults.LastClickStunTime,
		UltSettings = {
			AbilityCooldowns = mergeCooldowns(defaults.UltSettings.AbilityCooldowns, ultSettings.AbilityCooldowns),
			ClickComboCooldown = ultSettings.ClickComboCooldown or defaults.UltSettings.ClickComboCooldown,
			ClickCooldown = ultSettings.ClickCooldown or defaults.UltSettings.ClickCooldown,
		},
	}
end

local function createStyle(player: Player, styleName: string, settings: Types.StyleSettingsOverrides?): CombatStyle?
	local styleModule = combatStyles:FindFirstChild(styleName)
	if not styleModule or not styleModule:IsA("ModuleScript") then
		warn("Combat style not found: " .. styleName .. ".")
		return nil
	end

	local styleFactory = require(styleModule) :: {
		new: (Player, Types.StyleSettingsOverrides?) -> {
			StyleName: string,
			Settings: Types.StyleSettingsOverrides?,
			Abilities: { [string]: Types.Ability }?,
		},
	}
	local style = styleFactory.new(player, settings)
	style.Settings = getSettings(style.Settings or settings)
	style.Abilities = style.Abilities or {}
	return style :: CombatStyle
end

function setup.SetStyle(
	self: CombatObject,
	player: Player,
	styleName: string,
	settings: Types.StyleSettingsOverrides?
): boolean
	local newStyle = createStyle(player, styleName, settings)
	if not newStyle then
		return false
	end

	self.Style = newStyle
	self.Settings = newStyle.Settings
	self.State = StateHandler:GetPlayerState(player)
	return true
end

function setup:CreateObj(player: Player, settings: Types.StyleSettingsOverrides?): CombatObject
	local style = createStyle(player, "BasicStyle", settings)
	assert(style, "Could not create the default combat style.")

	local combat: CombatObject = {
		Style = style,
		Settings = style.Settings,
		State = StateHandler:GetPlayerState(player),
		SetStyle = setup.SetStyle,
	}

	playerObjs[player] = combat
	return combat
end

function setup:GetPlayerObj(player: Player): CombatObject?
	return playerObjs[player]
end

setup.init = function(): ()
	Players.PlayerRemoving:Connect(function(player)
		playerObjs[player] = nil
	end)
end

return setup
