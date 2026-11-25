--!strict

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local StateHandler = require(script.Parent.Parent.Systems.CombatStateHandler)
local CombatSetup = require(script.Parent.Parent.Systems.CombatSetup)

local DEBUG_HITBOXES = false
local animationFallbacks = {
	Downcut = "Click4",
	DashFront = "Click1",
	Ability1 = "Click1",
	Ability2 = "Click2",
	Ability3 = "Click3",
	Ability4 = "Click4",
}

type activeAttack = {
	actionId: number,
	settings: Types.AttackSettings,
	startsAt: number,
	state: Types.PlayerCombatState,
	previousPose: CFrame?,
	endsAt: number?,
	hitHumanoids: { [Humanoid]: boolean },
	hitCount: number,
	params: OverlapParams,
	connections: { RBXScriptConnection },
	debugPart: Part?,
	onHit: ((Model, number) -> ())?,
}

type movementData =
	{ actionId: number, root: BasePart, velocity: LinearVelocity, attachment: Attachment, endsAt: number }
type ownerData = { character: Model, player: Player?, automatic: boolean, endsAt: number }
type animationCache = {
	actionId: number,
	animator: Animator,
	cache: { [Animation]: AnimationTrack },
	playing: AnimationTrack?,
}

local tracks: { [Model]: animationCache } = {}
local attacks: { [Model]: activeAttack } = {}
local movers: { [Model]: movementData } = {}
local owners: { [BasePart]: ownerData } = {}
local initialized = false
local utils = {}

local function getRoot(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")

	return if root and root:IsA("BasePart") then root else nil
end

local function restoreOwner(root: BasePart)
	local saved = owners[root]
	owners[root] = nil

	if not saved or not root.Parent or root.Anchored then
		return
	end

	local canSet = root:CanSetNetworkOwnership()

	if canSet then
		local player = saved.player

		if saved.automatic then
			root:SetNetworkOwnershipAuto()
		elseif player and player.Parent == Players and player.Character == saved.character then
			root:SetNetworkOwner(player)
		else
			root:SetNetworkOwner(nil)
		end
	end
end

local function takeOwnership(character: Model, root: BasePart, duration: number)
	if root.Anchored then
		return
	end

	local canSet = root:CanSetNetworkOwnership()

	if not canSet then
		return
	end

	local saved = owners[root]
	owners[root] = {
		character = character,
		player = if saved then saved.player else root:GetNetworkOwner(),
		automatic = if saved then saved.automatic else root:GetNetworkOwnershipAuto(),
		endsAt = math.max(if saved then saved.endsAt else 0, os.clock() + duration),
	}
	root:SetNetworkOwner(nil)
end

local function stopMovement(character: Model)
	local movement = movers[character]
	movers[character] = nil

	if not movement then
		return
	end

	movement.velocity:Destroy()
	movement.attachment:Destroy()

	if
		movement.root.Parent
		and StateHandler.peekCharacterState(character)
		and StateHandler.getCharacterState(character).State ~= "Stunned"
	then
		local current = movement.root.AssemblyLinearVelocity
		movement.root.AssemblyLinearVelocity = Vector3.new(0, current.Y, 0)
	end
end

function utils.getAnimation(styleName: string, animationName: string, rigType: Enum.HumanoidRigType?): Animation?
	local folder = ReplicatedStorage:FindFirstChild("AnimationsIds")

	if not folder then
		return nil
	end

	local style = folder:FindFirstChild(styleName)
	local basic = folder:FindFirstChild("MuayThai")
	local function findClip(parent: Instance?, name: string): Animation?
		local slot = parent and parent:FindFirstChild(name)
		if not slot or not slot:IsA("Animation") then
			return nil
		end

		if slot.AnimationId == "" and RunService:IsStudio() then
			local clip = slot:FindFirstChildOfClass("KeyframeSequence")
			if clip then
				slot.AnimationId = game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(clip)
			end
		end

		return if slot.AnimationId ~= "" then slot else nil
	end

	local function findInStyle(parent: Instance?, name: string): Animation?
		local overrides = parent and rigType and parent:FindFirstChild(rigType.Name)
		if overrides and overrides:FindFirstChild(name) then
			return findClip(overrides, name)
		end

		return findClip(parent, name)
	end

	local animation = findInStyle(style, animationName) or findInStyle(basic, animationName)
	local fallback = animationFallbacks[animationName]

	return animation or (if fallback then findInStyle(basic, fallback) else nil)
end

local function getTrack(character: Model, animation: Animation): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")

	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	local existingAnimator = humanoid:FindFirstChildOfClass("Animator")
	local animator: Animator

	if existingAnimator then
		animator = existingAnimator
	else
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local existingCache = tracks[character]
	local cached: animationCache

	if existingCache and existingCache.animator == animator then
		cached = existingCache
	else
		if existingCache then
			for _, track in pairs(existingCache.cache) do
				track:Destroy()
			end
		end

		cached = { animator = animator, cache = {}, playing = nil, actionId = 0 }
		tracks[character] = cached
	end

	local track = cached.cache[animation]

	if track then
		return track
	end

	local success, loaded = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success then
		return nil
	end

	loaded.Priority = Enum.AnimationPriority.Action
	cached.cache[animation] = loaded

	return loaded
end

function utils.stopAnimation(character: Model)
	local cached = tracks[character]

	if cached and cached.playing then
		local track = cached.playing
		cached.playing = nil
		track:Stop(0.1)
	end
end

function utils.playAnimation(
	character: Model,
	styleName: string,
	animationName: string,
	looped: boolean?
): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animation = utils.getAnimation(styleName, animationName, if humanoid then humanoid.RigType else nil)

	if not animation then
		return nil
	end

	local track = getTrack(character, animation)

	if not track then
		return nil
	end

	utils.stopAnimation(character)
	track.Looped = looped == true
	local cached = tracks[character]

	if cached then
		cached.playing = track
		cached.actionId = StateHandler.getCharacterState(character).actionId
	end

	track:Play(0.08)

	return track
end

function utils.cancelAttack(character: Model)
	local attack = attacks[character]
	attacks[character] = nil

	if not attack then
		return
	end

	for _, connection in ipairs(attack.connections) do
		connection:Disconnect()
	end

	if attack.debugPart then
		attack.debugPart:Destroy()
	end
end

local function clearCharacter(character: Model)
	utils.cancelAttack(character)
	stopMovement(character)
	utils.stopAnimation(character)
	local root = getRoot(character)

	if root then
		restoreOwner(root)
	end

	local cached = tracks[character]
	tracks[character] = nil

	if cached then
		for _, track in pairs(cached.cache) do
			track:Destroy()
		end
	end
end

local function targetData(part: BasePart): (Model?, Humanoid?, BasePart?)
	local current: Instance? = part

	while current and current ~= workspace do
		if current:IsA("Model") then
			local humanoid = current:FindFirstChildOfClass("Humanoid")
			local root = getRoot(current)

			if humanoid and root then
				return current, humanoid, root
			end
		end

		current = current.Parent
	end

	return nil, nil, nil
end

local function updateDebug(attack: activeAttack, hitboxCFrame: CFrame)
	if not DEBUG_HITBOXES or not RunService:IsStudio() then
		return
	end

	local part = attack.debugPart

	if not part then
		local created = Instance.new("Part")
		created.Name = "CombatHitboxDebug"
		created.Anchored = true
		created.CanCollide = false
		created.CanTouch = false
		created.CanQuery = false
		created.Transparency = 0.65
		created.Color = Color3.fromRGB(220, 65, 65)
		attack.debugPart = created
		part = created
	end

	assert(part)
	part.Size = attack.settings.hitboxSize
	part.CFrame = hitboxCFrame
	part.Parent = workspace
end

local function hasLineOfSight(character: Model, target: Model, from: Vector3, to: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, target }
	params.RespectCanCollide = true
	local excluded: { Instance } = { character, target }

	for _ = 1, 16 do
		local result = workspace:Raycast(from, to - from, params)

		if not result then
			return true
		end

		local part = result.Instance
		local model: Model? = nil

		if part:IsA("BasePart") then
			model = targetData(part)
		end

		if not model then
			return false
		end

		table.insert(excluded, model)
		params.FilterDescendantsInstances = excluded
	end

	return false
end

local function applyHit(
	character: Model,
	target: Model,
	humanoid: Humanoid,
	root: BasePart,
	settings: Types.AttackSettings
): number
	local attackerRoot = getRoot(character)

	if not attackerRoot then
		return 0
	end

	if target:FindFirstChildOfClass("ForceField") then
		return 0
	end

	local targetState = StateHandler.getCharacterState(target)
	local targetObj = CombatSetup.getCharacterObj(target) or CombatSetup.createCharacterObj(target)

	if targetState.State == "Blocking" then
		local offset = attackerRoot.Position - root.Position
		local horizontal = Vector3.new(offset.X, 0, offset.Z)
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		local frontal = horizontal.Magnitude < 0.01
			or look:Dot(horizontal.Unit) >= math.cos(math.rad(targetObj.Settings.blockAngle))
		if frontal then
			if not settings.guardBreak then
				return 0
			end

			StateHandler:StunHumanoid(humanoid, targetObj.Settings.guardBreakStun)
		end
	end

	local health = humanoid.Health
	humanoid:TakeDamage(settings.damage)
	local damage = health - humanoid.Health

	if damage <= 0 then
		return 0
	end

	StateHandler:StunHumanoid(humanoid, settings.stunTime)

	if settings.knockback.Magnitude > 0 and not root.Anchored then
		StateHandler.authorizeMovement(target, settings.knockback.Magnitude * 0.5)
		takeOwnership(target, root, 0.2)
		root.AssemblyLinearVelocity = attackerRoot.CFrame:VectorToWorldSpace(settings.knockback)
	end

	return damage
end

local function queryAttack(character: Model, attack: activeAttack, pose: CFrame?)
	local attackerHumanoid = character:FindFirstChildOfClass("Humanoid")
	local state = attack.state

	if
		attacks[character] ~= attack
		or StateHandler.peekCharacterState(character) ~= state
		or state.actionId ~= attack.actionId
		or not attackerHumanoid
		or attackerHumanoid.Health <= 0
	then
		utils.cancelAttack(character)

		return
	end

	local root = getRoot(character)

	if not root then
		return
	end

	local settings = attack.settings

	if not StateHandler.validMovement(character) then
		utils.cancelAttack(character)

		return
	end

	local attackPose = pose or root.CFrame
	local trainingOwner = character:GetAttribute("TrainingOwner")
	local hitboxCFrame = attackPose * settings.hitboxOffset
	updateDebug(attack, hitboxCFrame)
	local seen: { [Humanoid]: boolean } = {}
	local targets: { { character: Model, humanoid: Humanoid, root: BasePart, distance: number } } = {}

	for _, part in ipairs(workspace:GetPartBoundsInBox(hitboxCFrame, settings.hitboxSize, attack.params)) do
		local target, humanoid, targetRoot = targetData(part)

		if
			not target
			or not humanoid
			or not targetRoot
			or target == character
			or humanoid.Health <= 0
			or target:FindFirstChildOfClass("ForceField") ~= nil
			or seen[humanoid]
			or attack.hitHumanoids[humanoid]
		then
			continue
		end

		seen[humanoid] = true

		if trainingOwner ~= nil then
			local player = Players:GetPlayerFromCharacter(target)

			if not player or player.UserId ~= trainingOwner then
				continue
			end
		end

		local offset = targetRoot.Position - attackPose.Position
		local distance = offset.Magnitude

		if distance > 0.01 and attackPose.LookVector:Dot(offset / distance) < math.cos(math.rad(settings.maxAngle)) then
			continue
		end

		if not hasLineOfSight(character, target, attackPose.Position, targetRoot.Position) then
			continue
		end

		table.insert(targets, { character = target, humanoid = humanoid, root = targetRoot, distance = distance })
	end

	table.sort(targets, function(first, second)
		return first.distance < second.distance
	end)

	for _, target in ipairs(targets) do
		if
			attacks[character] ~= attack
			or StateHandler.peekCharacterState(character) ~= state
			or state.actionId ~= attack.actionId
			or attackerHumanoid.Health <= 0
			or attack.hitCount >= settings.maxTargets
		then
			break
		end

		attack.hitHumanoids[target.humanoid] = true
		attack.hitCount += 1
		local damage = applyHit(character, target.character, target.humanoid, target.root, settings)

		if damage > 0 and attack.onHit then
			attack.onHit(target.character, damage)
		end
	end

	if attack.hitCount >= settings.maxTargets then
		utils.cancelAttack(character)
	end
end

local function openAttack(character: Model, attack: activeAttack)
	if
		attacks[character] ~= attack
		or attack.endsAt
		or StateHandler.peekCharacterState(character) ~= attack.state
		or attack.state.actionId ~= attack.actionId
	then
		return
	end

	local root = getRoot(character)
	attack.previousPose = if root then root.CFrame else nil
	attack.endsAt = os.clock() + attack.settings.activeDuration
	queryAttack(character, attack, attack.previousPose)
end

function utils.startAttack(
	character: Model,
	styleName: string,
	settings: Types.AttackSettings,
	onHit: ((Model, number) -> ())?
)
	utils.cancelAttack(character)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local attack: activeAttack = {
		state = StateHandler.getCharacterState(character),
		previousPose = nil,
		actionId = StateHandler.getCharacterState(character).actionId,
		settings = table.clone(settings),
		startsAt = os.clock() + settings.hitDelay,
		endsAt = nil,
		hitHumanoids = {},
		hitCount = 0,
		params = params,
		connections = {},
		debugPart = nil,
		onHit = onHit,
	}
	attacks[character] = attack
	local track = utils.playAnimation(character, styleName, settings.animation)

	if track and settings.useHitMarker then
		table.insert(
			attack.connections,
			track:GetMarkerReachedSignal("Hit"):Connect(function()
				openAttack(character, attack)
			end)
		)
		table.insert(
			attack.connections,
			track.Stopped:Connect(function()
				if attacks[character] == attack then
					utils.cancelAttack(character)
				end
			end)
		)
	end
end

function utils.move(character: Model, direction: Vector3, speed: number, duration: number)
	stopMovement(character)
	local root = getRoot(character)
	local horizontal = Vector3.new(direction.X, 0, direction.Z)

	if not root or root.Anchored or horizontal.Magnitude < 0.01 or duration <= 0 then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "CombatMovement"
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(horizontal.Unit.X * speed, horizontal.Unit.Z * speed)
	velocity.ForceLimitsEnabled = true
	velocity.MaxForce = root.AssemblyMass * 10000
	velocity.Parent = root
	movers[character] = {
		actionId = StateHandler.getCharacterState(character).actionId,
		root = root,
		velocity = velocity,
		attachment = attachment,
		endsAt = os.clock() + duration,
	}
	StateHandler.authorizeMovement(character, speed * duration + 5)
	takeOwnership(character, root, duration + 0.1)
end

function utils.launch(character: Model, speed: number)
	local root = getRoot(character)

	if root and not root.Anchored then
		StateHandler.authorizeMovement(character, speed * 0.5)
		takeOwnership(character, root, 0.2)
		root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, speed, root.AssemblyLinearVelocity.Z)
	end
end

function utils.preloadAnimations(folder: Instance)
	local animations = {}

	for _, instance in ipairs(folder:GetDescendants()) do
		if instance:IsA("Animation") then
			table.insert(animations, instance)
		end
	end

	if #animations > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(animations)
		end)
	end
end

function utils.getAnimationDuration(player: Player, animation: Animation): number?
	local track = if player.Character then getTrack(player.Character, animation) else nil

	return if track and track.Length > 0 then track.Length else nil
end

function utils.init()
	if initialized then
		return
	end

	initialized = true
	StateHandler.changed.Event:Connect(
		function(character: Model, state: string, actionId: number?, _removed: Types.PlayerCombatState?)
			if state == "Removed" then
				if StateHandler.peekCharacterState(character) == nil then
					clearCharacter(character)
				end
			elseif actionId then
				local attack = attacks[character]
				local movement = movers[character]
				local cached = tracks[character]

				if attack and attack.actionId < actionId then
					utils.cancelAttack(character)
				end

				if movement and movement.actionId < actionId then
					stopMovement(character)
				end

				if cached and cached.actionId < actionId then
					utils.stopAnimation(character)
				end
			end
		end
	)
	RunService.Heartbeat:Connect(function(delta: number)
		local currentTime = os.clock()

		for character, attack in pairs(attacks) do
			local humanoid = character:FindFirstChildOfClass("Humanoid")

			if
				not character.Parent
				or not humanoid
				or humanoid.Health <= 0
				or StateHandler.peekCharacterState(character) ~= attack.state
				or attack.state.actionId ~= attack.actionId
			then
				utils.cancelAttack(character)
			elseif attack.endsAt and currentTime >= attack.endsAt then
				utils.cancelAttack(character)
			elseif attack.endsAt then
				local root = getRoot(character)

				if root then
					local previous = attack.previousPose or root.CFrame
					local distance = (root.Position - previous.Position).Magnitude
					local steps = math.clamp(math.ceil(distance / 2), 1, 6)

					for step = 1, steps do
						queryAttack(character, attack, previous:Lerp(root.CFrame, step / steps))
					end

					attack.previousPose = root.CFrame
				end
			elseif currentTime >= attack.startsAt then
				if attack.settings.waitForLanding then
					local root = getRoot(character)
					local params = RaycastParams.new()
					params.FilterDescendantsInstances = { character }
					params.RespectCanCollide = true

					if
						root
						and root.AssemblyLinearVelocity.Y <= 0
						and workspace:Raycast(
							root.Position,
							Vector3.new(0, -(humanoid.HipHeight + root.Size.Y / 2 + 2), 0),
							params
						)
					then
						openAttack(character, attack)
					end
				elseif not attack.settings.useHitMarker then
					openAttack(character, attack)
				elseif
					currentTime
					>= attack.startsAt
						- attack.settings.hitDelay
						+ attack.settings.recovery
						- attack.settings.activeDuration
				then
					utils.cancelAttack(character)
				end
			end
		end

		for character, movement in pairs(movers) do
			if
				not character.Parent
				or not movement.root.Parent
				or currentTime >= movement.endsAt
				or not StateHandler.peekCharacterState(character)
				or StateHandler.getCharacterState(character).actionId ~= movement.actionId
			then
				stopMovement(character)
			else
				local velocity = movement.root.AssemblyLinearVelocity
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { character }
				params.RespectCanCollide = true

				if
					Vector3.new(velocity.X, 0, velocity.Z).Magnitude > 0.01
					and workspace:Blockcast(
						movement.root.CFrame,
						Vector3.new(2, 2, 2),
						Vector3.new(velocity.X, 0, velocity.Z) * delta + Vector3.new(velocity.X, 0, velocity.Z).Unit * 1,
						params
					)
				then
					stopMovement(character)
				end
			end
		end

		for root, saved in pairs(owners) do
			if not root.Parent or currentTime >= saved.endsAt then
				restoreOwner(root)
			end
		end
	end)

	local animations = ReplicatedStorage:FindFirstChild("AnimationsIds")

	if animations then
		task.spawn(utils.preloadAnimations, animations)
	end
end

return utils
