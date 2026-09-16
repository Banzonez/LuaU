--!strict

local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage = game:GetService("ServerStorage")
local workspace = game:GetService("Workspace")

local bananasSpawner = require(script.Parent.Parent.Utils.BananasSpawner)

local sharedFolder = replicatedStorage:WaitForChild("Shared")
local eventsFolder = sharedFolder:WaitForChild("Events")
local inputEvent = eventsFolder:WaitForChild("InputEvent") :: RemoteEvent

local assetsFolder = serverStorage:WaitForChild("Assets")
local glovesFolder = assetsFolder:WaitForChild("SlapGloves")

local ACTION_NAME = "Punch"
local EQUIPPED_GLOVE_ATTRIBUTE = "EquippedGlove"
local EQUIPPED_GLOVE_NAME = "CombatGlove"
local REST_GLOVE_MOTOR_NAME = "CombatGloveRestMotor"
local ATTACK_GLOVE_MOTOR_NAME = "CombatGloveAttackMotor"
local DEFAULT_GLOVE = "Slap Glove Normal"
local PUNCH_ANIMATION_ID = "rbxassetid://110154207964571"
local PUNCH_ANIMATION_SPEED = 1
local PUNCH_COOLDOWN = 0.6
local HITBOX_RADIUS = 13
local HITBOX_ANGLE = 135
local HITBOX_COS_THRESHOLD = math.cos(math.rad(HITBOX_ANGLE / 2))
local MATCH_BANANAS_FOLDER = "MatchBananas"

local ATTACK_ROTATION = CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(-90), 0, 0)
local REST_HANDLE_ROTATION = CFrame.Angles(0, 0, math.rad(45)) * ATTACK_ROTATION
local REST_HANDLE_C0 = CFrame.new(0, -0.25, 0.65) * REST_HANDLE_ROTATION
local ATTACK_GRIP_C0 = CFrame.new(0, -1.95, 0) * ATTACK_ROTATION

local punchAnimation = Instance.new("Animation")
punchAnimation.AnimationId = PUNCH_ANIMATION_ID

type GloveStatus = "Idle" | "Attacking"

type PlayerState = {
	character: Model,
	rootPart: BasePart,
	restPart: BasePart,
	rightArm: BasePart,
	gloveName: string?,
	glove: Model?,
	handle: BasePart?,
	grip: CFrame,
	restMotor: Motor6D?,
	attackMotor: Motor6D?,
	animationTrack: AnimationTrack?,
	status: GloveStatus,
	attackId: number,
}

type CombatService = {
	equipGlove: (player: Player, gloveName: string) -> boolean,
	init: () -> (),
}

local initialized = false
local playerStates: { [Player]: PlayerState } = {}
local lastPunchTimes: { [Player]: number } = {}
local combatService: CombatService = {} :: CombatService

local function getGloveTemplate(gloveName: string): Tool?
	local template = glovesFolder:FindFirstChild(gloveName)
	if template and template:IsA("Tool") then
		return template
	end

	return nil
end

local function getRightArm(character: Model): BasePart?
	local rightArm = character:FindFirstChild("RightArm")
	if rightArm and rightArm:IsA("BasePart") then
		return rightArm
	end

	if rightArm and rightArm:IsA("Model") then
		local armPart = rightArm:FindFirstChild("RightArm")
		if armPart and armPart:IsA("BasePart") then
			return armPart
		end
	end

	return nil
end

local function getRestPart(character: Model): BasePart?
	for _, partName in ipairs({ "UpperTorso", "Torso" }) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			return part
		end

		if part and part:IsA("Model") then
			local modelPart = part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart", true)
			if modelPart then
				return modelPart
			end
		end
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	return if rootPart and rootPart:IsA("BasePart") then rootPart else nil
end

local function getTargetData(part: BasePart): (Player?, Humanoid?, BasePart?)
	local ancestor: Instance? = part

	while ancestor do
		if ancestor:IsA("Model") then
			local player = players:GetPlayerFromCharacter(ancestor)
			if player then
				local humanoid = ancestor:FindFirstChildOfClass("Humanoid")
				local rootPart = ancestor:FindFirstChild("HumanoidRootPart")
				if humanoid and rootPart and rootPart:IsA("BasePart") then
					return player, humanoid, rootPart
				end

				return nil, nil, nil
			end
		end

		ancestor = ancestor.Parent
	end

	return nil, nil, nil
end

local function getMatchBananaPoints(folder: Folder): number
	local total = 0

	for _, entry in ipairs(folder:GetChildren()) do
		if entry:IsA("StringValue") then
			local points = tonumber(entry.Value)
			if points and points > 0 then
				total += points
			end
		end
	end

	return total
end

local function removeMatchBananaPoints(folder: Folder, amount: number)
	local remaining = amount

	for _, entry in ipairs(folder:GetChildren()) do
		if remaining <= 0 then
			break
		end
		if not entry:IsA("StringValue") then
			continue
		end

		local points = tonumber(entry.Value) or 0
		if points <= 0 then
			continue
		end

		local removed = math.min(points, remaining)
		local newValue = points - removed

		if newValue > 0 then
			entry.Value = tostring(newValue)
		else
			entry:Destroy()
		end
	end
end

local function findClosestTarget(state: PlayerState): (Player?, BasePart?)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { state.character }

	local attackerPlayer = players:GetPlayerFromCharacter(state.character)
	local lookVector = state.rootPart.CFrame.LookVector
	local horizontalLookVector = Vector3.new(lookVector.X, 0, lookVector.Z)
	if horizontalLookVector.Magnitude <= 0 then
		return nil, nil
	end
	horizontalLookVector = horizontalLookVector.Unit
	local closestPlayer: Player? = nil
	local closestRoot: BasePart? = nil
	local closestDistance = math.huge
	local checkedPlayers: { [Player]: boolean } = {}

	for _, part in ipairs(workspace:GetPartBoundsInRadius(state.rootPart.Position, HITBOX_RADIUS, overlapParams)) do
		local targetPlayer, targetHumanoid, targetRoot = getTargetData(part)
		if not targetPlayer or checkedPlayers[targetPlayer] then
			continue
		end
		checkedPlayers[targetPlayer] = true

		if targetPlayer == attackerPlayer
			or not targetHumanoid
			or targetHumanoid.Health <= 0
			or not targetRoot
		then
			continue
		end

		local offset = targetRoot.Position - state.rootPart.Position
		local distance = offset.Magnitude
		local horizontalOffset = Vector3.new(offset.X, 0, offset.Z)
		if distance > HITBOX_RADIUS
			or horizontalOffset.Magnitude <= 0
			or horizontalLookVector:Dot(horizontalOffset.Unit) < HITBOX_COS_THRESHOLD
		then
			continue
		end

		if distance < closestDistance then
			closestPlayer = targetPlayer
			closestRoot = targetRoot
			closestDistance = distance
		end
	end

	return closestPlayer, closestRoot
end

local function hitClosestTarget(state: PlayerState)
	local targetPlayer, targetRoot = findClosestTarget(state)
	if not targetPlayer or not targetRoot then
		return
	end

	local matchBananas = targetPlayer:FindFirstChild(MATCH_BANANAS_FOLDER)
	if not matchBananas or not matchBananas:IsA("Folder") then
		return
	end

	local amountToDrop = math.floor(getMatchBananaPoints(matchBananas) / 2)
	if amountToDrop <= 0 then
		return
	end

	local spawned = bananasSpawner.spawnDroppedBananas(targetRoot.Position, amountToDrop, targetPlayer)
	if spawned > 0 then
		removeMatchBananaPoints(matchBananas, spawned)
	end
end

local function loadPunchTrack(humanoid: Humanoid): AnimationTrack?
	local animator: Animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	if animator.Parent == nil then
		animator.Parent = humanoid
	end

	local success, result = pcall(function()
		return animator:LoadAnimation(punchAnimation)
	end)
	if not success then
		warn(("Could not load punch animation: %s"):format(tostring(result)))
		return nil
	end

	local animationTrack = result :: AnimationTrack
	animationTrack.Looped = false
	animationTrack.Priority = Enum.AnimationPriority.Action
	return animationTrack
end

local function createGlove(template: Tool): (Model?, BasePart?, CFrame?)
	local toolClone = template:Clone()
	local grip = toolClone.Grip
	local glove = Instance.new("Model")
	glove.Name = EQUIPPED_GLOVE_NAME

	for _, child in ipairs(toolClone:GetChildren()) do
		child.Parent = glove
	end
	toolClone:Destroy()

	local handle = glove:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		glove:Destroy()
		return nil, nil, nil
	end

	for _, descendant in ipairs(glove:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end

	glove.PrimaryPart = handle
	return glove, handle, grip
end

local function mountGlove(state: PlayerState, status: GloveStatus)
	local restMotor = state.restMotor
	local attackMotor = state.attackMotor
	if not restMotor or not attackMotor then
		return
	end

	if status == "Attacking" then
		restMotor.Enabled = false
		attackMotor.Enabled = true
	else
		attackMotor.Enabled = false
		restMotor.Enabled = true
	end

	state.status = status
end

local function replaceGlove(player: Player, gloveName: string): boolean
	local state = playerStates[player]
	local template = getGloveTemplate(gloveName)
	if not state or not template then
		return false
	end

	local glove, handle, grip = createGlove(template)
	if not glove or not handle or not grip then
		warn(("Glove template %q needs a BasePart named Handle."):format(gloveName))
		return false
	end

	glove:PivotTo(state.restPart.CFrame * REST_HANDLE_C0 * grip.Rotation:Inverse())
	glove.Parent = state.character

	local previousGlove = state.glove or state.character:FindFirstChild(EQUIPPED_GLOVE_NAME)
	if state.restMotor then
		state.restMotor:Destroy()
	end
	if state.attackMotor then
		state.attackMotor:Destroy()
	end

	if previousGlove and previousGlove ~= glove then
		previousGlove:Destroy()
	end

	local restMotor = Instance.new("Motor6D")
	restMotor.Name = REST_GLOVE_MOTOR_NAME
	restMotor.Part0 = state.restPart
	restMotor.Part1 = handle
	restMotor.C0 = REST_HANDLE_C0
	restMotor.C1 = grip.Rotation
	restMotor.Enabled = false
	restMotor.Parent = state.restPart

	local attackMotor = Instance.new("Motor6D")
	attackMotor.Name = ATTACK_GLOVE_MOTOR_NAME
	attackMotor.Part0 = state.rightArm
	attackMotor.Part1 = handle
	attackMotor.C0 = ATTACK_GRIP_C0
	attackMotor.C1 = grip
	attackMotor.Enabled = false
	attackMotor.Parent = state.rightArm

	state.gloveName = gloveName
	state.glove = glove
	state.handle = handle
	state.grip = grip
	state.restMotor = restMotor
	state.attackMotor = attackMotor
	mountGlove(state, state.status)
	return true
end

local function attachSelectedGlove(player: Player)
	local equippedGlove = player:GetAttribute(EQUIPPED_GLOVE_ATTRIBUTE)
	local gloveName = if typeof(equippedGlove) == "string" then equippedGlove else DEFAULT_GLOVE
	if not getGloveTemplate(gloveName) then
		gloveName = DEFAULT_GLOVE
		player:SetAttribute(EQUIPPED_GLOVE_ATTRIBUTE, gloveName)
	end

	replaceGlove(player, gloveName)
end

local function finishPunch(player: Player, state: PlayerState, attackId: number)
	if playerStates[player] ~= state or state.attackId ~= attackId then
		return
	end

	mountGlove(state, "Idle")
end

local function startPunch(player: Player)
	local state = playerStates[player]
	if not state or state.character ~= player.Character or state.status ~= "Idle" then
		return
	end

	local humanoid = state.character:FindFirstChildOfClass("Humanoid")
	local animationTrack = state.animationTrack
	if not humanoid
		or humanoid.Health <= 0
		or not state.restMotor
		or not state.attackMotor
		or not state.handle
		or not animationTrack
	then
		return
	end

	local now = os.clock()
	if now - (lastPunchTimes[player] or 0) < PUNCH_COOLDOWN then
		return
	end
	lastPunchTimes[player] = now

	state.attackId += 1
	local attackId = state.attackId
	mountGlove(state, "Attacking")
	hitClosestTarget(state)

	animationTrack.Stopped:Once(function()
		finishPunch(player, state, attackId)
	end)
	animationTrack:Play(0.05, 1, PUNCH_ANIMATION_SPEED)
end

local function onCharacterAdded(player: Player, character: Model)
	task.defer(function()
		if player.Character ~= character then
			return
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local restPart = getRestPart(character)
		local rightArm = getRightArm(character)
		if not rootPart or not rootPart:IsA("BasePart") or not humanoid or not restPart or not rightArm then
			warn(("Cannot prepare combat for %s: character rig is incomplete."):format(player.Name))
			return
		end

		local state: PlayerState = {
			character = character,
			rootPart = rootPart,
			restPart = restPart,
			rightArm = rightArm,
			gloveName = nil,
			glove = nil,
			handle = nil,
			grip = CFrame.identity,
			restMotor = nil,
			attackMotor = nil,
			animationTrack = nil,
			status = "Idle",
			attackId = 0,
		}
		playerStates[player] = state
		lastPunchTimes[player] = nil

		attachSelectedGlove(player)
		state.animationTrack = loadPunchTrack(humanoid)
	end)
end

local function onPlayerAdded(player: Player)
	local selectedGlove = player:GetAttribute(EQUIPPED_GLOVE_ATTRIBUTE)
	if typeof(selectedGlove) ~= "string" or not getGloveTemplate(selectedGlove) then
		player:SetAttribute(EQUIPPED_GLOVE_ATTRIBUTE, DEFAULT_GLOVE)
	end

	player:GetAttributeChangedSignal(EQUIPPED_GLOVE_ATTRIBUTE):Connect(function()
		local gloveName = player:GetAttribute(EQUIPPED_GLOVE_ATTRIBUTE)
		local state = playerStates[player]
		if typeof(gloveName) == "string" and state and state.gloveName ~= gloveName then
			replaceGlove(player, gloveName)
		end
	end)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end

function combatService.equipGlove(player: Player, gloveName: string): boolean
	if player.Parent ~= players or not getGloveTemplate(gloveName) then
		return false
	end

	local state = playerStates[player]
	local glove = state and state.glove
	if player:GetAttribute(EQUIPPED_GLOVE_ATTRIBUTE) == gloveName then
		if state and (state.gloveName ~= gloveName or not glove or not glove.Parent) then
			return replaceGlove(player, gloveName)
		end

		return true
	end

	player:SetAttribute(EQUIPPED_GLOVE_ATTRIBUTE, gloveName)
	return true
end

function combatService.init()
	if initialized then
		return
	end
	initialized = true

	inputEvent.OnServerEvent:Connect(function(player, action)
		if action == ACTION_NAME then
			startPunch(player)
		end
	end)

	for _, player in ipairs(players:GetPlayers()) do
		onPlayerAdded(player)
	end

	players.PlayerAdded:Connect(onPlayerAdded)
	players.PlayerRemoving:Connect(function(player)
		playerStates[player] = nil
		lastPunchTimes[player] = nil
	end)
end

return combatService
