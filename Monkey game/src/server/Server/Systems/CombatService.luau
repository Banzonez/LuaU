local debris = game:GetService("Debris")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage = game:GetService("ServerStorage")
local workspace = game:GetService("Workspace")

local bananasSpawner = require(script.Parent.Parent.Utils.BananasSpawner)
local ragdollUtils = require(script.Parent.Parent.Utils.RagdollUtils)
local matchService = require(script.Parent.MatchService)
local progressService = require(script.Parent.ProgressService)

local sharedFolder = replicatedStorage:WaitForChild("Shared")
local sharedUtilsFolder = sharedFolder:FindFirstChild("Utils") :: Folder
local soundUtils = require(sharedUtilsFolder:FindFirstChild("SoundUtils"))
local eventsFolder = sharedFolder:WaitForChild("Events")
local inputEvent = eventsFolder:WaitForChild("InputEvent") :: RemoteEvent
local matchEvent = eventsFolder:WaitForChild("MatchEvent") :: RemoteEvent

local assetsFolder = serverStorage:WaitForChild("Assets")
local vfxFolder = assetsFolder:FindFirstChild("VFX")
local soundsFolder = serverStorage:FindFirstChild("Sounds")

local glovesFolder = assetsFolder:WaitForChild("SlapGloves")
local _normalGlovesFolder = glovesFolder:WaitForChild("Normal")
local _pastelGlovesFolder = glovesFolder:WaitForChild("Pastel")

local ACTION_NAME = "Punch"
local EQUIPPED_GLOVE_ATTRIBUTE = "EquippedGlove"
local EQUIPPED_GLOVE_NAME = "CombatGlove"
local REST_GLOVE_MOTOR_NAME = "CombatGloveRestMotor"
local ATTACK_GLOVE_MOTOR_NAME = "CombatGloveAttackMotor"
local DEFAULT_GLOVE = "Slap Glove Normal"
local PUNCH_ANIMATION_ID = "rbxassetid://110154207964571"
local PUNCH_ANIMATION_SPEED = 0.75
local PUNCH_COOLDOWN = 0.6
local HITBOX_RADIUS = 13
local HITBOX_ANGLE = 135
local HITBOX_COS_THRESHOLD = math.cos(math.rad(HITBOX_ANGLE / 2))
local MATCH_BANANAS_FOLDER = "MatchBananas"
local HIT_VFX_NAME = "HitVFX"
local IFRAME_VFX_NAME = "IFrameVFX"
local HIT_VFX_LIFETIME = 1.25
local RAGDOLL_DURATION = 2.5
local RECOVERY_IFRAME_DURATION = 3
local KNOCKBACK_HORIZONTAL_SPEED = 30
local KNOCKBACK_UPWARD_SPEED = 12
local KNOCKBACK_TILT_SPEED = 4
local SERVER_OWNERSHIP_DURATION = 0.2
local HIT_VFX_HEIGHT = 1
local GLOVE_MOTOR_NAMES = {
	[REST_GLOVE_MOTOR_NAME] = true,
	[ATTACK_GLOVE_MOTOR_NAME] = true,
}

local ATTACK_ROTATION = CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(-90), 0, 0)
local REST_HANDLE_ROTATION = CFrame.Angles(0, 0, math.rad(45)) * ATTACK_ROTATION
local REST_HANDLE_C0 = CFrame.new(0, -0.25, 0.65) * REST_HANDLE_ROTATION
local ATTACK_GRIP_C0 = CFrame.new(0, -1.95, 0) * ATTACK_ROTATION

local punchAnimation = Instance.new("Animation")
punchAnimation.AnimationId = PUNCH_ANIMATION_ID

type GloveStatus = "Idle" | "Attacking"
type StunResult = "Hit" | "Blocked" | "Invalid"

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

type TargetState = {
	character: Model,
	recoveryId: number,
	invulnerableUntil: number,
}

type CombatService = {
	equipGlove: (player: Player, gloveName: string) -> boolean,
	init: () -> (),
}

local initialized = false
local playerStates: { [Player]: PlayerState } = {}
local lastPunchTimes: { [Player]: number } = {}
local targetStates: { [Player]: TargetState } = {}
local combatService: CombatService = {} :: CombatService

local function getGloveTemplate(gloveName: string, gloveFolder: Folder): Tool?
	gloveFolder = gloveFolder or glovesFolder
	local template = gloveFolder:FindFirstChild(gloveName)
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
		remaining -= removed

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

local function getHitVfxPosition(character: Model, rootPart: BasePart): Vector3
	local head = character:FindFirstChild("Head", true)
	if head and head:IsA("BasePart") then
		return head.Position + Vector3.yAxis * (head.Size.Y / 2 + HIT_VFX_HEIGHT)
	end

	return rootPart.Position + Vector3.yAxis * HIT_VFX_HEIGHT
end

local function preparePart(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

local function playHitVfx(position: Vector3)
	local template = vfxFolder and vfxFolder:FindFirstChild(HIT_VFX_NAME)
	if not template or (not template:IsA("Model") and not template:IsA("BasePart")) then
		return
	end

	if template:IsA("BasePart") then
		local vfx = template:Clone()
		preparePart(vfx)
		vfx.CFrame = CFrame.new(position) * vfx.CFrame.Rotation
		vfx.Parent = workspace
		debris:AddItem(vfx, HIT_VFX_LIFETIME)
		return
	end

	if template:IsA("Model") then
		local vfx = template:Clone()
		for _, descendant in ipairs(vfx:GetDescendants()) do
			if descendant:IsA("BasePart") then
				preparePart(descendant)
			end
		end
		vfx:PivotTo(CFrame.new(position) * vfx:GetPivot().Rotation)
		vfx.Parent = workspace
		debris:AddItem(vfx, HIT_VFX_LIFETIME)
	end
end

local function prepareAttachedPart(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

local function weldToPart(part: BasePart, attachmentPart: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = attachmentPart
	weld.Part1 = part
	weld.Parent = part
end

local function attachIFrameVfx(character: Model, attachmentPart: BasePart)
	local template = vfxFolder and vfxFolder:FindFirstChild(IFRAME_VFX_NAME)
	if not template then
		return
	end

	local previousVfx = character:FindFirstChild(IFRAME_VFX_NAME)
	if previousVfx then
		previousVfx:Destroy()
	end

	local vfx = template:Clone()
	vfx.Name = IFRAME_VFX_NAME

	if vfx:IsA("Attachment") then
		vfx.CFrame = CFrame.identity
		vfx.Parent = attachmentPart
	elseif vfx:IsA("BasePart") then
		prepareAttachedPart(vfx)
		vfx.CFrame = attachmentPart.CFrame * vfx.CFrame.Rotation
		vfx.Parent = character
		weldToPart(vfx, attachmentPart)
	elseif vfx:IsA("Model") then
		vfx.Parent = character
		vfx:PivotTo(attachmentPart.CFrame * vfx:GetPivot().Rotation)
		for _, descendant in ipairs(vfx:GetDescendants()) do
			if descendant:IsA("BasePart") then
				prepareAttachedPart(descendant)
				weldToPart(descendant, attachmentPart)
			elseif descendant:IsA("Highlight") then
				descendant.Adornee = character
			end
		end
	else
		vfx.Parent = attachmentPart
	end

	debris:AddItem(vfx, RECOVERY_IFRAME_DURATION)
end

local function playCombatSound(soundName: string, position: Vector3)
	if not soundsFolder then
		return
	end

	local soundData = soundUtils.getNamedData(soundsFolder, soundName)
	if soundData then
		matchEvent:FireAllClients({
			action = "PlaySpatialSound",
			sound = soundData,
			position = position,
		})
	end
end

local function applyKnockback(attackerRoot: BasePart, character: Model, targetRoot: BasePart)
	local direction = targetRoot.Position - attackerRoot.Position
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude <= 0 then
		direction = attackerRoot.CFrame.LookVector
		direction = Vector3.new(direction.X, 0, direction.Z)
	end
	if direction.Magnitude <= 0 then
		return
	end

	if targetRoot:CanSetNetworkOwnership() then
		targetRoot:SetNetworkOwner(nil)
	end

	local velocityChange = direction.Unit * KNOCKBACK_HORIZONTAL_SPEED + Vector3.yAxis * KNOCKBACK_UPWARD_SPEED
	local movedAssemblies: { [BasePart]: boolean } = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local assemblyRoot = descendant.AssemblyRootPart
			if not movedAssemblies[assemblyRoot] then
				movedAssemblies[assemblyRoot] = true
				assemblyRoot:ApplyImpulse(velocityChange * assemblyRoot.AssemblyMass)
			end
		end
	end

	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		local tiltImpulse = direction.Unit * KNOCKBACK_TILT_SPEED * torso.AssemblyMass
		local impulsePosition = torso.AssemblyCenterOfMass + Vector3.yAxis * (torso.Size.Y * 0.4)
		torso:ApplyImpulseAtPosition(tiltImpulse, impulsePosition)
	end

	task.delay(SERVER_OWNERSHIP_DURATION, function()
		if targetRoot.Parent and targetRoot:CanSetNetworkOwnership() then
			targetRoot:SetNetworkOwnershipAuto()
		end
	end)
end

local function stunTarget(attackerState: PlayerState, targetPlayer: Player, targetRoot: BasePart): StunResult
	local character = targetPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return "Invalid"
	end

	local now = os.clock()
	local previousTargetState = targetStates[targetPlayer]
	if previousTargetState
		and previousTargetState.character == character
		and now < previousTargetState.invulnerableUntil
	then
		playCombatSound(soundUtils.Names.SlapBlocked, targetRoot.Position)
		return "Blocked"
	end

	if not ragdollUtils.enable(humanoid, GLOVE_MOTOR_NAMES) then
		return "Invalid"
	end

	local recoveryId = 1
	if previousTargetState and previousTargetState.character == character then
		recoveryId = previousTargetState.recoveryId + 1
	end
	local targetState: TargetState = {
		character = character,
		recoveryId = recoveryId,
		invulnerableUntil = math.huge,
	}
	targetStates[targetPlayer] = targetState

	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local vfxParent = if torso and torso:IsA("BasePart") then torso else targetRoot
	attachIFrameVfx(character, vfxParent)
	applyKnockback(attackerState.rootPart, character, targetRoot)
	playHitVfx(getHitVfxPosition(character, targetRoot))
	playCombatSound(soundUtils.Names.SlapHit, targetRoot.Position)

	task.delay(RAGDOLL_DURATION, function()
		local currentState = targetStates[targetPlayer]
		if not currentState or currentState ~= targetState or currentState.recoveryId ~= recoveryId then
			return
		end

		ragdollUtils.disable(humanoid)
		currentState.invulnerableUntil = os.clock() + RECOVERY_IFRAME_DURATION
	end)

	return "Hit"
end

local function hitClosestTarget(player: Player, state: PlayerState)
	local targetPlayer, targetRoot = findClosestTarget(state)
	if not targetPlayer or not targetRoot then
		return
	end
	local dropPosition = targetRoot.Position
	if stunTarget(state, targetPlayer, targetRoot) ~= "Hit" then
		return
	end
	if matchService.isActivePlayer(player) then
		progressService.award(player, "LandingPunches")
	end

	local matchBananas = targetPlayer:FindFirstChild(MATCH_BANANAS_FOLDER)
	if not matchBananas or not matchBananas:IsA("Folder") then
		return
	end

	local amountToDrop = math.floor(getMatchBananaPoints(matchBananas) / 2)
	if amountToDrop <= 0 then
		return
	end

	local spawned = bananasSpawner.spawnDroppedBananas(dropPosition, amountToDrop, targetPlayer)
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
		or humanoid.PlatformStand
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
	playCombatSound(soundUtils.Names.SlapSwing, state.rootPart.Position)
	hitClosestTarget(player, state)

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
		targetStates[player] = nil
	end)
end

return combatService
