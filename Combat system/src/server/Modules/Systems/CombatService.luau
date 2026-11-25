--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatSetup = require(script.Parent.CombatSetup)
local CombatStateHandler = require(script.Parent.CombatStateHandler)
local CombatUtil = require(script.Parent.Parent.Utils.CombatUtil)

local events = ReplicatedStorage:FindFirstChild("Events")

if not events then
	events = Instance.new("Folder")
	events.Name = "Events"
	events.Parent = ReplicatedStorage
end

assert(events:IsA("Folder"), "Events must be a Folder.")
local event = events:FindFirstChild("CombatEvent")

if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "CombatEvent"
	event.Parent = events
end

assert(event:IsA("RemoteEvent"), "CombatEvent must be a RemoteEvent.")
local combatEvent: RemoteEvent = event

local REQUEST_CAPACITY = 30
local REQUEST_REFILL = 20

local requests: { [Player]: { tokens: number, updatedAt: number } } = {}
local waitingForFall: { [Model]: boolean } = {}
local initialized = false
local npcRequest: ((Player, string) -> ())? = nil
local combatService = {}

local function rootOf(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")

	return if root and root:IsA("BasePart") then root else nil
end

local function alive(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	return character:IsDescendantOf(workspace) and humanoid ~= nil and humanoid.Health > 0 and rootOf(character) ~= nil
end

local function allowRequest(player: Player): boolean
	local currentTime = os.clock()
	local record = requests[player]

	if not record then
		record = { tokens = REQUEST_CAPACITY, updatedAt = currentTime }
		requests[player] = record
	end

	record.tokens = math.min(REQUEST_CAPACITY, record.tokens + (currentTime - record.updatedAt) * REQUEST_REFILL)
	record.updatedAt = currentTime

	if record.tokens < 1 then
		return false
	end

	record.tokens -= 1

	return true
end

local function getObject(character: Model)
	return CombatSetup.getCharacterObj(character) or CombatSetup.createCharacterObj(character)
end

local function sendState(character: Model)
	local player = Players:GetPlayerFromCharacter(character)

	if not player or not alive(character) then
		return
	end

	local object = getObject(character)
	local state = object.State
	local abilities: { [string]: string } = {}

	for key, ability in pairs(object.Style.Abilities) do
		abilities[key] = ability.settings.name
	end

	combatEvent:FireClient(player, "State", {
		character = character,
		actionId = state.actionId,
		abilities = abilities,
		abilityCooldowns = table.clone(state.AbilitiesCooldowns),
		nextClickTime = state.NextClickTime,
		uppercutFrom = math.max(state.NextClickTime, state.LastUppercut + object.Settings.variantCooldown),
		uppercutUntil = if state.ClickCombo == 1 and object.Settings.ClicksToFinishCombo >= 2
			then state.ComboExpiresAt
			else 0,
		nextDashTime = state.nextDashTime,
		ultCharge = state.ultCharge,
		ultRequired = object.Settings.ultRequired,
		ultExpiresAt = state.ultExpiresAt,
		ultDuration = object.Settings.ultDuration,
		styleName = object.Style.StyleName,
	})
end

local function onHit(character: Model, target: Model, damage: number)
	if not alive(character) then
		return
	end

	local object = getObject(character)
	local state = object.State

	if state.ultExpiresAt <= workspace:GetServerTimeNow() then
		local gain = if Players:GetPlayerFromCharacter(target) then damage else damage * 0.5
		state.ultCharge = math.min(object.Settings.ultRequired, state.ultCharge + gain)
		character:SetAttribute("UltCharge", state.ultCharge)
		sendState(character)
	end
end

function combatService.tryAttack(character: Model, uppercut: boolean?, fallingInput: boolean?): boolean
	if waitingForFall[character] or not alive(character) or not CombatStateHandler.validMovement(character) then
		return false
	end

	local object = getObject(character)
	local state = object.State
	local currentTime = workspace:GetServerTimeNow()

	if state.State ~= "Idle" or currentTime < state.NextClickTime then
		return false
	end

	if currentTime > state.ComboExpiresAt then
		state.ClickCombo = 0
	end

	local combo = state.ClickCombo % object.Settings.ClicksToFinishCombo + 1
	local name = "Click" .. combo
	local root = rootOf(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	assert(root and humanoid)
	local variantReady = combo == 2 and currentTime - state.LastUppercut >= object.Settings.variantCooldown

	if
		variantReady
		and fallingInput
		and (humanoid.FloorMaterial ~= Enum.Material.Air or root.AssemblyLinearVelocity.Y >= -3)
	then
		-- Input can reach the server before the character's jump replicates.
		local revision = state.actionId
		local deadline = currentTime + 0.5
		waitingForFall[character] = true

		repeat
			task.wait()
			currentTime = workspace:GetServerTimeNow()
		until currentTime >= deadline
			or state.actionId ~= revision
			or not alive(character)
			or (humanoid.FloorMaterial == Enum.Material.Air and root.AssemblyLinearVelocity.Y < -3)

		waitingForFall[character] = nil
		if
			state.actionId ~= revision
			or CombatStateHandler.peekCharacterState(character) ~= state
			or not alive(character)
			or not CombatStateHandler.validMovement(character)
		then
			return false
		end
	end

	if variantReady and humanoid.FloorMaterial == Enum.Material.Air and root.AssemblyLinearVelocity.Y < -3 then
		name = "Downcut"
	elseif variantReady and uppercut and humanoid.FloorMaterial ~= Enum.Material.Air then
		name = "Uppercut"
	end

	local configured = object.Settings.Attacks[name]

	if not configured then
		return false
	end

	local attack = table.clone(configured)
	local variant = name == "Uppercut" or name == "Downcut"
	local finisher = combo == object.Settings.ClicksToFinishCombo or variant
	local ultimate = state.ultExpiresAt > currentTime
	local extraCooldown = if finisher then object.Settings.ClickComboCooldown else object.Settings.ClickCooldown

	if ultimate then
		attack.damage *= object.Settings.ultDamageMultiplier
		extraCooldown = if finisher
			then object.Settings.UltSettings.ClickComboCooldown
			else object.Settings.UltSettings.ClickCooldown
	end

	state.ClickCombo = if finisher then 0 else combo
	state.ComboExpiresAt = currentTime + object.Settings.ComboResetTime
	state.NextClickTime = currentTime + attack.recovery + extraCooldown

	if variant then
		state.LastUppercut = currentTime
	end

	CombatStateHandler.setCharacterState(character, "Attacking", attack.recovery, object.Settings.attackWalkSpeed)
	if name == "Uppercut" then
		humanoid.Jump = false
		local velocity = root.AssemblyLinearVelocity
		if velocity.Y > 0 then
			root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		end
	end

	CombatUtil.startAttack(character, object.Style.StyleName, attack, function(target, damage)
		onHit(character, target, damage)
	end)

	sendState(character)

	return true
end

function combatService.setBlocking(character: Model, blocking: boolean): boolean
	if not alive(character) then
		return false
	end

	if not blocking then
		local state = CombatStateHandler.peekCharacterState(character)

		if state and state.State == "Blocking" then
			CombatStateHandler.setCharacterState(character, "Idle")
		end

		return true
	end

	if not CombatStateHandler.validMovement(character) then
		return false
	end

	local object = getObject(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if object.State.State ~= "Idle" or not humanoid or humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end

	CombatStateHandler.setCharacterState(character, "Blocking", nil, object.Settings.blockWalkSpeed)
	CombatUtil.playAnimation(character, object.Style.StyleName, "Block", true)

	return true
end

function combatService.tryDash(character: Model, direction: Vector3, dashName: string?): boolean
	if dashName and dashName ~= "Front" and dashName ~= "Back" and dashName ~= "Left" and dashName ~= "Right" then
		return false
	end

	if not alive(character) or not CombatStateHandler.validMovement(character) then
		return false
	end

	if
		direction.X ~= direction.X
		or direction.Y ~= direction.Y
		or direction.Z ~= direction.Z
		or math.abs(direction.X) > 1.1
		or math.abs(direction.Y) > 0.1
		or math.abs(direction.Z) > 1.1
	then
		return false
	end

	local horizontal = Vector3.new(direction.X, 0, direction.Z)

	if horizontal.Magnitude < 0.5 or horizontal.Magnitude > 1.1 then
		return false
	end

	local object = getObject(character)
	local state = object.State
	local currentTime = workspace:GetServerTimeNow()

	if state.State ~= "Idle" or currentTime < state.nextDashTime then
		return false
	end

	local root = rootOf(character)
	assert(root)
	local localDirection = root.CFrame:VectorToObjectSpace(horizontal.Unit)
	local name = (
		if math.abs(localDirection.Z) >= math.abs(localDirection.X)
			then (if localDirection.Z < 0 then "Front" else "Back")
			else (if localDirection.X < 0 then "Left" else "Right")
	)

	if root.Anchored then
		return false
	end

	local duration = object.Settings.dashDuration
	state.nextDashTime = currentTime + object.Settings.dashCooldown
	state.ClickCombo = 0
	local attack = object.Settings.Attacks.DashFront
	local recovery = if name == "Front" and attack then math.max(duration, attack.recovery) else duration
	CombatStateHandler.setCharacterState(character, "Dashing", recovery)

	if name == "Front" and attack then
		attack = table.clone(attack)

		if state.ultExpiresAt > currentTime then
			attack.damage *= object.Settings.ultDamageMultiplier
		end

		CombatUtil.startAttack(character, object.Style.StyleName, attack, function(target, damage)
			onHit(character, target, damage)
		end)
	else
		CombatUtil.playAnimation(character, object.Style.StyleName, "Dash" .. name)
	end

	CombatUtil.move(character, horizontal.Unit, object.Settings.dashSpeed, duration)
	sendState(character)

	return true
end

function combatService.tryAbility(character: Model, key: string): boolean
	if not alive(character) or not CombatStateHandler.validMovement(character) then
		return false
	end

	local object = getObject(character)
	local state = object.State
	local ability = object.Style.Abilities[key]
	local currentTime = workspace:GetServerTimeNow()

	if not ability or state.State ~= "Idle" or currentTime < (state.AbilitiesCooldowns[key] or 0) then
		return false
	end

	local settings = ability.settings
	local attack = table.clone(settings.attack)
	local cooldown = object.Settings.AbilityCooldowns[key]

	if state.ultExpiresAt > currentTime then
		attack.damage *= object.Settings.ultDamageMultiplier
		cooldown = object.Settings.UltSettings.AbilityCooldowns[key] or cooldown * object.Settings.ultCooldownMultiplier
	end

	if settings.targetMode == "singleTarget" then
		attack.maxTargets = 1
	end

	state.AbilitiesCooldowns[key] = currentTime + cooldown
	state.ClickCombo = 0
	state.ComboExpiresAt = 0
	CombatStateHandler.setCharacterState(
		character,
		"UsingAbility",
		math.max(settings.duration, attack.recovery),
		object.Settings.attackWalkSpeed
	)
	CombatUtil.startAttack(character, object.Style.StyleName, attack, function(target, damage)
		onHit(character, target, damage)
	end)

	local root = rootOf(character)

	if root and settings.dashSpeed > 0 then
		CombatUtil.move(character, root.CFrame.LookVector, settings.dashSpeed, settings.dashDuration)
	end

	if settings.launchSpeed > 0 then
		CombatUtil.launch(character, settings.launchSpeed)
	end

	local execute = ability.execute

	if execute then
		local success, message = pcall(function()
			execute(character)

			return true
		end)

		if not success then
			warn("Ability " .. key .. " failed: " .. tostring(message))
		end
	end

	sendState(character)

	return true
end

function combatService.tryUlt(character: Model): boolean
	if not alive(character) or not CombatStateHandler.validMovement(character) then
		return false
	end

	local object = getObject(character)
	local state = object.State
	local currentTime = workspace:GetServerTimeNow()

	if state.State ~= "Idle" or state.ultExpiresAt > currentTime or state.ultCharge < object.Settings.ultRequired then
		return false
	end

	state.ultCharge = 0
	state.ultExpiresAt = currentTime + object.Settings.ultDuration
	character:SetAttribute("UltCharge", 0)
	character:SetAttribute("UltExpiresAt", state.ultExpiresAt)
	CombatStateHandler.setCharacterState(character, "UsingUlt", object.Settings.ultActivationTime)
	CombatUtil.playAnimation(character, object.Style.StyleName, "Ult")
	sendState(character)

	return true
end

function combatService.setNpcRequest(handler: (Player, string) -> ())
	npcRequest = handler
end

function combatService.init()
	if initialized then
		return
	end

	initialized = true
	Players.PlayerRemoving:Connect(function(player)
		requests[player] = nil
	end)

	combatEvent.OnServerEvent:Connect(function(player: Player, action: unknown, value: unknown, option: unknown)
		if type(action) ~= "string" or #action > 16 then
			return
		end

		local character = player.Character

		if not character or not alive(character) then
			return
		end

		if action == "Block" and value == false then
			if character:GetAttribute("CombatState") == "Blocking" then
				combatService.setBlocking(character, false)
			end

			return
		end

		if not allowRequest(player) then
			return
		end

		if action == "Ready" then
			sendState(character)
		elseif action == "Clicks" then
			if
				(value == Enum.UserInputType.MouseButton1 or value == Enum.UserInputType.Touch)
				and (option == nil or type(option) == "boolean" or option == "Downcut")
			then
				combatService.tryAttack(character, option == true, option == "Downcut")
			end
		elseif action == "Block" and type(value) == "boolean" then
			combatService.setBlocking(character, value)
		elseif action == "Dash" and typeof(value) == "Vector3" then
			if option ~= nil and type(option) ~= "string" then
				return
			end

			local dashName = if type(option) == "string" then option else nil
			combatService.tryDash(character, value, dashName)
		elseif
			action == "Ability"
			and type(value) == "string"
			and (value == "1" or value == "2" or value == "3" or value == "4")
		then
			combatService.tryAbility(character, value)
		elseif action == "Ult" then
			combatService.tryUlt(character)
		elseif action == "Npc" and type(value) == "string" and npcRequest then
			npcRequest(player, value)
		end
	end)
end

return combatService
