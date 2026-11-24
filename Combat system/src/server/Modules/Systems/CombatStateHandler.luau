--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)

type movementData = {
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	autoRotate: boolean,
	jumpEnabled: boolean,
}

local playerStates: { [Player]: Types.PlayerCombatState } = {}
local characterStates: { [Model]: Types.PlayerCombatState } = {}
local movement: { [Model]: movementData } = {}
local pendingWalkSpeed: { [Model]: number? } = {}
local connections: { [Model]: { RBXScriptConnection } } = {}
local motion: {
	[Model]: {
		position: Vector3,
		updatedAt: number,
		allowance: number,
		authorized: number,
		blockedUntil: number,
		verticalCredit: number,
		authorizedUntil: number,
	},
} =
	{}
local revision = 0
local initialized = false
local states = { changed = Instance.new("BindableEvent") }

local function basicState(): Types.PlayerCombatState
	return {
		State = "Idle",
		actionId = 0,
		ClickCombo = 0,
		NextClickTime = 0,
		ComboExpiresAt = 0,
		LastUppercut = 0,
		AbilitiesCooldowns = {},
		nextDashTime = 0,
		stateExpiresAt = 0,
		ultCharge = 0,
		ultExpiresAt = 0,
	}
end

local function saveMovement(humanoid: Humanoid): movementData
	return {
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		autoRotate = humanoid.AutoRotate,
		jumpEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
	}
end

local function updateMovement(character: Model, state: Types.CombatState, walkSpeed: number?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	local locked = state ~= "Idle"
	character:SetAttribute("CombatJumpLocked", locked)

	if not humanoid then
		pendingWalkSpeed[character] = if locked then walkSpeed else nil

		return
	end

	pendingWalkSpeed[character] = nil
	local saved = movement[character]

	if not saved then
		if not locked then
			return
		end

		saved = saveMovement(humanoid)
		movement[character] = saved
	end

	humanoid.Jump = false
	humanoid.JumpPower = if locked then 0 else saved.jumpPower
	humanoid.JumpHeight = if locked then 0 else saved.jumpHeight
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, not locked and saved.jumpEnabled)
	humanoid.AutoRotate = if state == "Stunned" then false else saved.autoRotate
	humanoid.WalkSpeed = if state == "Idle" then saved.walkSpeed else (walkSpeed or 0)
	if not locked then
		movement[character] = nil
	end
end

function states.removeCharacter(character: Model)
	if not characterStates[character] then
		return
	end

	local removed = characterStates[character]
	updateMovement(character, "Idle")
	character:SetAttribute("CombatState", "Idle")
	character:SetAttribute("UltCharge", 0)
	character:SetAttribute("UltExpiresAt", 0)
	characterStates[character] = nil
	motion[character] = nil
	local player = Players:GetPlayerFromCharacter(character)

	if player then
		playerStates[player] = nil
	end

	movement[character] = nil
	local characterConnections = connections[character]
	connections[character] = nil

	if characterConnections then
		for _, connection in ipairs(characterConnections) do
			connection:Disconnect()
		end
	end

	states.changed:Fire(character, "Removed", removed.actionId, removed)
end

function states.getCharacterState(character: Model): Types.PlayerCombatState
	local existing = characterStates[character]

	if existing then
		return existing
	end

	local player = Players:GetPlayerFromCharacter(character)
	local state: Types.PlayerCombatState = if player then (playerStates[player] or basicState()) else basicState()
	revision += 1
	state.actionId = revision
	characterStates[character] = state

	if player then
		playerStates[player] = state
	end

	character:SetAttribute("CombatState", state.State)
	character:SetAttribute("CombatJumpLocked", false)
	local characterConnections = {}
	connections[character] = characterConnections
	table.insert(
		characterConnections,
		character.Destroying:Connect(function()
			states.removeCharacter(character)
		end)
	)

	local function attachHumanoid(humanoid: Humanoid)
		if state.State ~= "Idle" then
			updateMovement(character, state.State, pendingWalkSpeed[character])
		end

		table.insert(
			characterConnections,
			humanoid.Died:Connect(function()
				states.removeCharacter(character)
			end)
		)
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		attachHumanoid(humanoid)
	else
		local waiting: RBXScriptConnection?
		waiting = character.ChildAdded:Connect(function(child)
			if child:IsA("Humanoid") then
				if waiting then
					waiting:Disconnect()
				end

				attachHumanoid(child)
			end
		end)

		if waiting then
			table.insert(characterConnections, waiting)
		end
	end

	return state
end

function states.peekCharacterState(character: Model): Types.PlayerCombatState?
	return characterStates[character]
end

function states.resetCharacter(character: Model)
	states.removeCharacter(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if character.Parent and humanoid and humanoid.Health > 0 then
		states.getCharacterState(character)
	end
end

function states.authorizeMovement(character: Model, distance: number)
	local root = character:FindFirstChild("HumanoidRootPart")

	if not root or not root:IsA("BasePart") then
		return
	end

	local record = motion[character]

	if not record then
		record = {
			position = root.Position,
			updatedAt = os.clock(),
			allowance = 0,
			authorized = 0,
			blockedUntil = 0,
			verticalCredit = 5,
			authorizedUntil = 0,
		}
		motion[character] = record
	end

	record.authorized = math.min(300, record.authorized + math.max(0, distance))
	record.authorizedUntil = os.clock() + 1.5
end

function states.acceptTeleport(character: Model)
	motion[character] = nil
	states.authorizeMovement(character, 0)
end

function states.validMovement(character: Model): boolean
	if not Players:GetPlayerFromCharacter(character) then
		return true
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not root or not root:IsA("BasePart") or not humanoid then
		return false
	end

	local position = root.Position

	if
		position.X ~= position.X
		or position.Y ~= position.Y
		or position.Z ~= position.Z
		or math.abs(position.X) > 1000000
		or math.abs(position.Y) > 1000000
		or math.abs(position.Z) > 1000000
	then
		return false
	end

	local record = motion[character]

	if not record then
		states.authorizeMovement(character, 0)

		return false
	end

	local now = os.clock()
	local elapsed = math.min(now - record.updatedAt, 0.5)
	local offset = position - record.position
	local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
	local walk = math.max(16, humanoid.WalkSpeed)
	local budget = math.min(10, record.allowance + elapsed * walk * 1.5)

	if now > record.authorizedUntil then
		record.authorized = 0
	end

	local verticalBudget = math.min(10, record.verticalCredit + elapsed * 500)

	if horizontal > budget + record.authorized + 5 or math.abs(offset.Y) > verticalBudget + record.authorized + 5 then
		record.blockedUntil = now + 0.5
		root.CFrame = CFrame.new(record.position) * root.CFrame.Rotation
		root.AssemblyLinearVelocity = Vector3.zero
		record.updatedAt = now

		return false
	end

	record.authorized = math.max(0, record.authorized - math.max(0, horizontal - budget))
	record.allowance = math.max(-5, budget - horizontal)
	record.verticalCredit = math.max(-5, verticalBudget - math.abs(offset.Y))
	record.position = position
	record.updatedAt = now

	return now >= record.blockedUntil
end

function states:GetPlayerState(player: Player): Types.PlayerCombatState
	local character = player.Character

	if character then
		return states.getCharacterState(character)
	end

	local state = playerStates[player]

	if not state then
		state = basicState()

		if player.Parent == Players then
			playerStates[player] = state
		end
	end

	return state
end

function states.setCharacterState(character: Model, state: Types.CombatState, duration: number?, walkSpeed: number?)
	if not character.Parent then
		return
	end

	local playerState = states.getCharacterState(character)

	playerState.State = state
	revision += 1
	playerState.actionId = revision
	playerState.stateExpiresAt = if duration and duration > 0 then os.clock() + duration else 0
	updateMovement(character, state, walkSpeed)
	character:SetAttribute("CombatState", state)
	states.changed:Fire(character, state, playerState.actionId)
end

function states:SetTemporaryState(player: Player, state: Types.CombatState, duration: number)
	local character = player.Character

	if character and player.Parent == Players then
		states.setCharacterState(character, state, duration)
	end
end

function states:StunHumanoid(humanoid: Humanoid, duration: number)
	local character = humanoid.Parent

	if not character or not character:IsA("Model") or humanoid.Health <= 0 or duration <= 0 then
		return
	end

	local state = states.getCharacterState(character)
	local remaining = if state.State == "Stunned" then state.stateExpiresAt - os.clock() else 0
	state.ClickCombo = 0
	state.ComboExpiresAt = 0
	states.setCharacterState(character, "Stunned", math.max(duration, remaining))
end

local function setupPlayer(player: Player)
	local function characterAdded(character: Model)
		playerStates[player] = basicState()
		states.getCharacterState(character)
		states.acceptTeleport(character)
	end

	player.CharacterAdded:Connect(characterAdded)
	player.CharacterRemoving:Connect(function(character)
		states.removeCharacter(character)
	end)

	if player.Character then
		characterAdded(player.Character)
	end
end

function states.init()
	if initialized then
		return
	end

	initialized = true
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player: Player)
		if player.Character then
			states.removeCharacter(player.Character)
		end

		playerStates[player] = nil
	end)

	RunService.Heartbeat:Connect(function()
		local currentTime = os.clock()

		for character, state in pairs(characterStates) do
			states.validMovement(character)

			if state.State ~= "Idle" and state.stateExpiresAt > 0 and currentTime >= state.stateExpiresAt then
				states.setCharacterState(character, "Idle")
			end

			if state.ultExpiresAt > 0 and workspace:GetServerTimeNow() >= state.ultExpiresAt then
				state.ultExpiresAt = 0
				character:SetAttribute("UltExpiresAt", 0)
			end
		end
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end
end

return states
