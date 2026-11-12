--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local StateHandler = require(script.Parent.CombatStateHandler)
local basicStyle = require(script.Parent.Parent.Utils.CombatStyles.BasicStyle)

local combatStyles = script.Parent.Parent.Utils.CombatStyles

type combatStyle = {
	Player: Player?,
	Settings: Types.StyleSettings,
	StyleName: string,
	Abilities: { [string]: Types.Ability },
}

type combatObject = {
	character: Model,
	Style: combatStyle,
	Settings: Types.StyleSettings,
	State: Types.PlayerCombatState,
	SetStyle: (
		self: combatObject,
		player: Player,
		styleName: string,
		settings: Types.StyleSettingsOverrides?
	) -> boolean,
}

local characterObjs: { [Model]: combatObject } = {}
local initialized = false
local setup = {}

local function mergeCooldowns(
	defaults: Types.AbilityCooldowns,
	overrides: Types.AbilityCooldowns?
): Types.AbilityCooldowns
	local cooldowns = table.clone(defaults)

	if overrides then
		for key, value in pairs(overrides) do
			cooldowns[key] = value
		end
	end

	return cooldowns
end

local function mergeAttack(
	defaults: Types.AttackSettings,
	override: Types.AttackSettingsOverrides
): Types.AttackSettings
	return {
		waitForLanding = if override.waitForLanding == nil then defaults.waitForLanding else override.waitForLanding,
		hitboxSize = override.hitboxSize or defaults.hitboxSize,
		useHitMarker = if override.useHitMarker == nil then defaults.useHitMarker else override.useHitMarker,
		hitboxOffset = override.hitboxOffset or defaults.hitboxOffset,
		activeDuration = override.activeDuration or defaults.activeDuration,
		maxTargets = override.maxTargets or defaults.maxTargets,
		damage = override.damage or defaults.damage,
		stunTime = override.stunTime or defaults.stunTime,
		maxAngle = override.maxAngle or defaults.maxAngle,
		hitDelay = override.hitDelay or defaults.hitDelay,
		recovery = override.recovery or defaults.recovery,
		knockback = override.knockback or defaults.knockback,
		guardBreak = if override.guardBreak == nil then defaults.guardBreak else override.guardBreak,
		animation = override.animation or defaults.animation,
	}
end

local function getSettings(settings: Types.StyleSettingsOverrides?): Types.StyleSettings
	local defaults = basicStyle.getSettings()

	if not settings then
		return defaults
	end

	local attacks: { [string]: Types.AttackSettings } = {}

	for name, attack in pairs(defaults.Attacks) do
		attacks[name] = table.clone(attack)

		if string.match(name, "^Click%d+$") and settings.ClickDamage then
			attacks[name].damage = settings.ClickDamage
		end

		if string.match(name, "^Click%d+$") and settings.ClickStunTime then
			attacks[name].stunTime = settings.ClickStunTime
		end

		if
			name == "Click" .. tostring(settings.ClicksToFinishCombo or defaults.ClicksToFinishCombo)
			and settings.LastClickStunTime
		then
			attacks[name].stunTime = settings.LastClickStunTime
		end

		if settings.MAX_ANGLE_DEGREES then
			attacks[name].maxAngle = settings.MAX_ANGLE_DEGREES
		end
	end

	if settings.Attacks then
		for name, attack in pairs(settings.Attacks) do
			attacks[name] = mergeAttack(attacks[name] or defaults.Attacks.Click1, attack)
		end
	end

	local ult = settings.UltSettings or defaults.UltSettings

	return {
		AbilityCooldowns = mergeCooldowns(defaults.AbilityCooldowns, settings.AbilityCooldowns),
		ClickComboCooldown = settings.ClickComboCooldown or defaults.ClickComboCooldown,
		ClickCooldown = settings.ClickCooldown or defaults.ClickCooldown,
		ComboResetTime = settings.ComboResetTime or defaults.ComboResetTime,
		ClicksToFinishCombo = settings.ClicksToFinishCombo or defaults.ClicksToFinishCombo,
		Attacks = attacks,
		MAX_ANGLE_DEGREES = settings.MAX_ANGLE_DEGREES or defaults.MAX_ANGLE_DEGREES,
		ClickDamage = settings.ClickDamage or defaults.ClickDamage,
		ClickStunTime = settings.ClickStunTime or defaults.ClickStunTime,
		LastClickStunTime = settings.LastClickStunTime or defaults.LastClickStunTime,
		attackWalkSpeed = settings.attackWalkSpeed or defaults.attackWalkSpeed,
		blockWalkSpeed = settings.blockWalkSpeed or defaults.blockWalkSpeed,
		blockAngle = settings.blockAngle or defaults.blockAngle,
		guardBreakStun = settings.guardBreakStun or defaults.guardBreakStun,
		dashSpeed = settings.dashSpeed or defaults.dashSpeed,
		dashDuration = settings.dashDuration or defaults.dashDuration,
		dashCooldown = settings.dashCooldown or defaults.dashCooldown,
		variantCooldown = settings.variantCooldown or defaults.variantCooldown,
		ultDuration = settings.ultDuration or defaults.ultDuration,
		ultActivationTime = settings.ultActivationTime or defaults.ultActivationTime,
		ultRequired = settings.ultRequired or defaults.ultRequired,
		ultDamageMultiplier = settings.ultDamageMultiplier or defaults.ultDamageMultiplier,
		ultCooldownMultiplier = settings.ultCooldownMultiplier or defaults.ultCooldownMultiplier,
		UltSettings = {
			AbilityCooldowns = mergeCooldowns(defaults.UltSettings.AbilityCooldowns, ult.AbilityCooldowns),
			ClickComboCooldown = ult.ClickComboCooldown or defaults.UltSettings.ClickComboCooldown,
			ClickCooldown = ult.ClickCooldown or defaults.UltSettings.ClickCooldown,
		},
	}
end

local function validNumber(value: number, minimum: number, maximum: number, field: string)
	assert(value == value and value >= minimum and value <= maximum, "Invalid combat setting: " .. field)
end

local function validateAttack(attack: Types.AttackSettings, name: string)
	validNumber(attack.damage, 0, 10000, name .. ".damage")
	validNumber(attack.maxTargets, 1, 100, name .. ".maxTargets")
	assert(attack.maxTargets % 1 == 0, "maxTargets must be an integer")
	validNumber(attack.hitDelay, 0, 10, name .. ".hitDelay")
	validNumber(attack.activeDuration, 0.01, 10, name .. ".activeDuration")
	validNumber(attack.recovery, attack.hitDelay + attack.activeDuration, 20, name .. ".recovery")
	validNumber(attack.stunTime, 0, 20, name .. ".stunTime")
	validNumber(attack.maxAngle, 0, 180, name .. ".maxAngle")

	for _, component in ipairs({ attack.hitboxSize.X, attack.hitboxSize.Y, attack.hitboxSize.Z }) do
		validNumber(component, 0.1, 100, name .. ".hitboxSize")
	end

	for _, component in ipairs({ attack.knockback.X, attack.knockback.Y, attack.knockback.Z }) do
		validNumber(component, -500, 500, name .. ".knockback")
	end

	for _, component in ipairs({ attack.hitboxOffset:GetComponents() }) do
		validNumber(component, -100, 100, name .. ".hitboxOffset")
	end
end

local function createStyle(player: Player?, styleName: string, settings: Types.StyleSettingsOverrides?): combatStyle?
	local styleModule = combatStyles:FindFirstChild(styleName)

	if not styleModule or not styleModule:IsA("ModuleScript") then
		return nil
	end

	local styleFactory = require(styleModule) :: {
		new: (
			Player?,
			Types.StyleSettingsOverrides?
		) -> {
			Player: Player?,
			StyleName: string,
			Settings: Types.StyleSettingsOverrides?,
			Abilities: { [string]: Types.Ability }?,
		},
	}
	local style = styleFactory.new(player, settings)
	local overrides = style.Settings or settings
	style.Settings = getSettings(overrides)
	local abilities: { [string]: Types.Ability } = style.Abilities or {}
	style.Abilities = abilities
	local resolved = style.Settings :: Types.StyleSettings
	validNumber(resolved.ClicksToFinishCombo, 1, 20, "ClicksToFinishCombo")
	assert(resolved.ClicksToFinishCombo % 1 == 0, "Combo length must be an integer")

	for _, field in ipairs({
		"ClickCooldown",
		"ClickComboCooldown",
		"ComboResetTime",
		"attackWalkSpeed",
		"blockWalkSpeed",
		"guardBreakStun",
		"dashSpeed",
		"dashDuration",
		"dashCooldown",
		"variantCooldown",
		"ultDuration",
		"ultActivationTime",
		"ultDamageMultiplier",
		"ultCooldownMultiplier",
	}) do
		validNumber((resolved :: any)[field], 0, 500, field)
	end

	validNumber(resolved.ultRequired, 1, 10000, "ultRequired")
	validNumber(resolved.dashDuration, 0.01, 5, "dashDuration")
	validNumber(resolved.ultDuration, 0.01, 500, "ultDuration")
	validNumber(resolved.ultActivationTime, 0.01, 20, "ultActivationTime")
	validNumber(resolved.blockAngle, 0, 180, "blockAngle")
	validNumber(resolved.UltSettings.ClickCooldown, 0, 500, "UltSettings.ClickCooldown")
	validNumber(resolved.UltSettings.ClickComboCooldown, 0, 500, "UltSettings.ClickComboCooldown")

	for name, attack in pairs(resolved.Attacks) do
		validateAttack(attack, name)
	end

	for index = 1, resolved.ClicksToFinishCombo do
		assert(resolved.Attacks["Click" .. index], "Missing combo attack")
	end

	for key, ability in pairs(abilities) do
		local configured = ability.settings
		validateAttack(configured.attack, "Ability" .. key)
		validNumber(configured.cooldown, 0, 500, "ability cooldown")
		validNumber(configured.duration, configured.attack.recovery, 20, "ability duration")
		validNumber(configured.dashSpeed, 0, 200, "ability dash speed")
		validNumber(configured.dashDuration, 0, configured.duration, "ability dash duration")
		validNumber(configured.launchSpeed, 0, 200, "ability launch speed")
		resolved.AbilityCooldowns[key] = if overrides
				and overrides.AbilityCooldowns
				and overrides.AbilityCooldowns[key] ~= nil
			then overrides.AbilityCooldowns[key]
			else configured.cooldown
	end

	for _, cooldown in pairs(resolved.AbilityCooldowns) do
		validNumber(cooldown, 0, 500, "AbilityCooldowns")
	end

	for _, cooldown in pairs(resolved.UltSettings.AbilityCooldowns) do
		validNumber(cooldown, 0, 500, "UltSettings.AbilityCooldowns")
	end

	return style :: combatStyle
end

function setup.SetStyle(
	self: combatObject,
	player: Player,
	styleName: string,
	settings: Types.StyleSettingsOverrides?
): boolean
	if player.Character ~= self.character or characterObjs[self.character] ~= self then
		return false
	end

	if self.State.State ~= "Idle" or self.State.ultExpiresAt > workspace:GetServerTimeNow() then
		return false
	end

	local style = createStyle(player, styleName, settings)

	if not style then
		return false
	end

	self.Style = style
	self.Settings = style.Settings
	table.clear(self.State.AbilitiesCooldowns)
	self.State.ClickCombo = 0
	self.State.ComboExpiresAt = 0
	self.State.ultCharge = 0

	if player.Character then
		player.Character:SetAttribute("CombatStyle", style.StyleName)
		player.Character:SetAttribute("UltCharge", 0)
	end

	return true
end

function setup.createCharacterObj(
	character: Model,
	styleName: string?,
	settings: Types.StyleSettingsOverrides?
): combatObject
	local player = Players:GetPlayerFromCharacter(character)
	local style = createStyle(player, styleName or "BasicStyle", settings)
	assert(style, "Combat style module was not found.")
	local combat: combatObject = {
		character = character,
		Style = style,
		Settings = style.Settings,
		State = StateHandler.getCharacterState(character),
		SetStyle = setup.SetStyle,
	}
	characterObjs[character] = combat
	character:SetAttribute("CombatStyle", style.StyleName)

	return combat
end

function setup.getCharacterObj(character: Model): combatObject?
	return characterObjs[character]
end

function setup:CreateObj(player: Player, settings: Types.StyleSettingsOverrides?): combatObject
	local character = player.Character
	assert(character, "Player has no character.")

	return setup.createCharacterObj(character, nil, settings)
end

function setup:GetPlayerObj(player: Player): combatObject?
	return if player.Character then characterObjs[player.Character] else nil
end

function setup.init()
	if initialized then
		return
	end

	initialized = true
	StateHandler.changed.Event:Connect(
		function(character: Model, state: string, _actionId: number?, _removed: Types.PlayerCombatState?)
			if
				state == "Removed"
				and characterObjs[character]
				and characterObjs[character].State.actionId <= (_actionId or -1)
			then
				characterObjs[character] = nil
			end
		end
	)
end

return setup
