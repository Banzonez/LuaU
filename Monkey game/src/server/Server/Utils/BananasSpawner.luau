--!strict

local collectionService = game:GetService("CollectionService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage = game:GetService("ServerStorage")
local workspace = game:GetService("Workspace")

local bananaConfig = require(script.Parent.Parent.Configs.BananaConfig)
local bananaModelUtils = require(script.Parent.BananaModelUtils)

local assetsFolder = serverStorage:FindFirstChild("Assets")
local bananaModelsFolder = assetsFolder:FindFirstChild("BananaModels")
local vfxFolder = assetsFolder:FindFirstChild("VFX")

local sharedFolder = replicatedStorage:FindFirstChild("Shared")
local eventsFolder = sharedFolder:FindFirstChild("Events")
local matchEvent = eventsFolder:FindFirstChild("MatchEvent")

local BANANA_TAG = "SpawnedBanana"
local NORMAL_BANANA_TAG = assert(bananaConfig.getName(1), "Normal banana tag is missing from BananaConfig.")
local SMALL_CRATE_TAG = assert(bananaConfig.getName(3), "Small crate tag is missing from BananaConfig.")
local LARGE_CRATE_TAG = assert(bananaConfig.getName(4), "Large crate tag is missing from BananaConfig.")
local BANANA_TYPE_ATTRIBUTE = "BananaType"
local DROPPED_BANANA_ATTRIBUTE = "DroppedBanana"
local MATCH_START_TIME_ATTRIBUTE = "BananasMatchStartedAt"
local MAX_PLACEMENT_ATTEMPTS = 30
local RAYCAST_MARGIN = 100
local GROUND_CLEARANCE = 0.1
local SINGLE_BANANA_HEIGHT = -.5
local AIRDROP_HEIGHT = 25
local PARACHUTE_FALL_SPEED = 5
local PARACHUTE_ROTATION_SPEED = math.rad(5)
local MINIMUM_GROUND_NORMAL_Y = 0.7
local MINIMUM_AIRDROP_DISTANCE = 10
local DROP_LIFETIME = 10
local DROP_BLINKS = 3
local DROP_BLINK_INTERVAL = 0.15
local DROP_COLLECT_DELAY = 0.6
local DROP_SPAWN_RADIUS = 5
local DROP_SPAWN_HEIGHT = 3
local DROP_HORIZONTAL_SPEED = 12
local DROP_UPWARD_SPEED = 15
local DROP_SPAWN_INTERVAL = 0.01
local MAX_DROPPED_BANANA_MODELS = 8
local AIRDROP_VFX = vfxFolder:FindFirstChild("AirdropVFX")

local CRATE_LIMITS: { [string]: number } = {
	[SMALL_CRATE_TAG] = bananaConfig.MAX_SMALL_CRATES,
	[LARGE_CRATE_TAG] = bananaConfig.MAX_CRATES,
}

type CrateState = {
	maximum: number,
	spawned: number,
	interval: number,
	failedAttempts: number,
}
type SpawnContext = {
	container: Folder,
	mapCFrame: CFrame,
	mapSize: Vector3,
	raycastParams: RaycastParams,
	overlapParams: OverlapParams,
	crates: { [string]: CrateState },
	airdropPositions: { Vector3 },
}

type BananaSpawner = {
	spawnBananasInMap: (map: Model, matchDuration: number) -> (),
	spawnDroppedBananas: (position: Vector3, amount: number, targetPlayer: Player) -> number,
	canCollectDroppedBanana: (banana: Model, player: Player) -> boolean,
	getDroppedBananaRotation: (banana: Model) -> CFrame?,
}

local RNG = Random.new()
local bananaTemplates: { [string]: { Model } } = {}
local droppedBananaOwners: { [Model]: Player } = setmetatable({}, { __mode = "k" }) :: any
local droppedBananaRotations: { [Model]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local activeContext: SpawnContext? = nil
local bananaSpawner: BananaSpawner = {} :: BananaSpawner

local function cacheTemplates(): { [string]: { Model } }
	local templatesByName: { [string]: { Model } } = {}

	for _, bananaName in ipairs(bananaConfig.TagsNames) do
		local templates = {}
		for _, instance in ipairs(collectionService:GetTagged(bananaName)) do
			if instance:IsA("Model")
				and instance.Parent == bananaModelsFolder
				and instance:FindFirstChildWhichIsA("BasePart", true)
			then
				table.insert(templates, instance)
			end
		end
		templatesByName[bananaName] = templates
		if #templates == 0 then
			warn(`No valid Model tagged "{bananaName}" exists directly inside {bananaModelsFolder:GetFullName()}.`)
		end
	end

	return templatesByName
end

local function canSpawn(context: SpawnContext, bananaName: string): boolean
	local crate = context.crates[bananaName]
	return not crate or crate.spawned < crate.maximum
end

local function getSpawnedBananaCount(context: SpawnContext): number
	local count = 0

	for _, banana in ipairs(context.container:GetChildren()) do
		if banana:GetAttribute(DROPPED_BANANA_ATTRIBUTE) ~= true then
			count += 1
		end
	end

	return count
end

local function getRandomBananaName(): string?
	local totalWeight = 0

	for _, chance in pairs(bananaConfig.Chances) do
		if chance > 0 then
			totalWeight += chance
		end
	end

	if totalWeight == 0 then
		return nil
	end

	local selectedWeight = RNG:NextNumber(0, totalWeight)
	local accumulatedWeight = 0
	for bananaName, chance in pairs(bananaConfig.Chances) do
		if chance <= 0 then
			continue
		end

		accumulatedWeight += chance
		if selectedWeight <= accumulatedWeight then
			return bananaName
		end
	end

	return nil
end

local function cloneBanana(bananaName: string): Model?
	local templates = bananaTemplates[bananaName]
	if not templates or #templates == 0 then
		return nil
	end

	return templates[RNG:NextInteger(1, #templates)]:Clone()
end

local function setDroppedBananasVisible(bananas: { Model }, visible: boolean)
	for _, banana in ipairs(bananas) do
		if not banana.Parent or banana:GetAttribute("Collectable") == false then
			continue
		end

		for _, descendant in ipairs(banana:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant.Name ~= "Part" then
				descendant.Transparency = if visible then 0 else 1
			end
		end
	end
end

local function expireDroppedBananas(bananas: { Model })
	local blinkDuration = DROP_BLINKS * DROP_BLINK_INTERVAL * 2
	task.delay(DROP_LIFETIME - blinkDuration, function()
		for _ = 1, DROP_BLINKS do
			setDroppedBananasVisible(bananas, false)
			task.wait(DROP_BLINK_INTERVAL)
			setDroppedBananasVisible(bananas, true)
			task.wait(DROP_BLINK_INTERVAL)
		end

		for _, banana in ipairs(bananas) do
			if banana.Parent then
				banana:Destroy()
			end
		end
	end)
end

local function applyParachuteFall(rootPart: BasePart)
	local canSetNetworkOwner = rootPart:CanSetNetworkOwnership()
	if canSetNetworkOwner then
		rootPart:SetNetworkOwner(nil)
	end

	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero

	local attachment = Instance.new("Attachment")
	attachment.Name = "ParachuteAttachment"
	attachment.Axis = Vector3.yAxis
	attachment.SecondaryAxis = Vector3.xAxis
	attachment.Parent = rootPart

	local alignment = Instance.new("AlignOrientation")
	alignment.Name = "ParachuteAlignment"
	alignment.Attachment0 = attachment
	alignment.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignment.AlignType = Enum.AlignType.PrimaryAxisParallel
	alignment.PrimaryAxis = Vector3.yAxis
	alignment.RigidityEnabled = true
	alignment.Parent = rootPart

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "ParachuteVelocity"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = Vector3.new(0, -PARACHUTE_FALL_SPEED, 0)
	velocity.ForceLimitsEnabled = false
	velocity.Parent = rootPart

	local rotation = Instance.new("AngularVelocity")
	rotation.Name = "ParachuteRotation"
	rotation.Attachment0 = attachment
	rotation.RelativeTo = Enum.ActuatorRelativeTo.World
	rotation.AngularVelocity = Vector3.new(0, PARACHUTE_ROTATION_SPEED, 0)
	rotation.MaxTorque = math.huge
	rotation.Parent = rootPart
end

local function isAirdropPositionAvailable(context: SpawnContext, position: Vector3): boolean
	for _, previousPosition in ipairs(context.airdropPositions) do
		local offset = Vector2.new(position.X - previousPosition.X, position.Z - previousPosition.Z)
		if offset.Magnitude < MINIMUM_AIRDROP_DISTANCE then
			return false
		end
	end

	return true
end

local function getPlacement(
	context: SpawnContext,
	banana: Model,
	heightOffset: number,
	isAirdrop: boolean
): (CFrame?, Vector3?)
	local boundingCFrame, boundingSize = banana:GetBoundingBox()
	local pivotToBounds = banana:GetPivot():ToObjectSpace(boundingCFrame)

	for _ = 1, MAX_PLACEMENT_ATTEMPTS do
		local localX = RNG:NextNumber(-context.mapSize.X / 2, context.mapSize.X / 2)
		local localZ = RNG:NextNumber(-context.mapSize.Z / 2, context.mapSize.Z / 2)
		local sampledPosition = context.mapCFrame:PointToWorldSpace(Vector3.new(localX, 0, localZ))
		local rayOrigin = Vector3.new(
			sampledPosition.X,
			context.mapCFrame.Position.Y + context.mapSize.Y / 2 + RAYCAST_MARGIN,
			sampledPosition.Z
		)
		local result = workspace:Raycast(
			rayOrigin,
			Vector3.new(0, -(context.mapSize.Y + RAYCAST_MARGIN * 2), 0),
			context.raycastParams
		)

		if not result
			or result.Normal.Y < MINIMUM_GROUND_NORMAL_Y
			or (isAirdrop and not isAirdropPositionAvailable(context, result.Position))
		then
			continue
		end

		local targetBounds = CFrame.new(
			result.Position + Vector3.yAxis * (boundingSize.Y / 2 + GROUND_CLEARANCE + heightOffset)
		) * CFrame.Angles(0, math.rad(RNG:NextNumber(0, 360)), 0)
		local overlapSize = Vector3.new(
			math.max(boundingSize.X - 0.05, 0.05),
			math.max(boundingSize.Y - 0.1, 0.05),
			math.max(boundingSize.Z - 0.05, 0.05)
		)
		local blocked = false

		for _, part in ipairs(workspace:GetPartBoundsInBox(targetBounds, overlapSize, context.overlapParams)) do
			if part ~= result.Instance then
				blocked = true
				break
			end
		end

		if not blocked then
			return targetBounds * pivotToBounds:Inverse(), result.Position
		end
	end

	return nil, nil
end

local function createAirdropMarker(map: Model, position: Vector3, markerAirdrop: Model)
	local marker = Instance.new("Part")
	marker.Name = "AirdropLandingPosition"
	marker.Size = Vector3.new(1, 0.1, 1)
	marker.Position = position
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanQuery = false
	marker.CanTouch = false
	marker.Transparency = 1
	marker.Parent = map

	if AIRDROP_VFX and AIRDROP_VFX:IsA("BasePart") then
		local clone = AIRDROP_VFX:Clone()
		clone.Anchored = true
		clone.CanCollide = false
		clone.CanQuery = false
		clone.CanTouch = false
		clone.CFrame = CFrame.new(position + Vector3.yAxis * (clone.Size.Y / 2 + GROUND_CLEARANCE))
			* clone.CFrame.Rotation
		clone.Parent = marker
	end

	markerAirdrop.Destroying:Once(function()
		if marker.Parent then
			marker:Destroy()
		end
	end)
end

local function spawnBanana(context: SpawnContext, forcedName: string?): boolean
	local bananaName = forcedName or getRandomBananaName()
	if not bananaName or not canSpawn(context, bananaName) then
		return false
	end

	local banana = cloneBanana(bananaName)
	if not banana then
		return false
	end

	local isSmallCrate = bananaName == SMALL_CRATE_TAG
	local isSingleBanana = not isSmallCrate and bananaName ~= LARGE_CRATE_TAG
	local rootPart = bananaModelUtils.prepare(banana, not isSmallCrate)
	if not rootPart then
		warn(`{banana.Name} does not contain a BasePart.`)
		banana:Destroy()
		return false
	end

	local placement, landingPosition = getPlacement(
		context,
		banana,
		if isSingleBanana then SINGLE_BANANA_HEIGHT else 0,
		isSmallCrate
	)
	if not placement or not landingPosition then
		banana:Destroy()
		return false
	end

	banana:PivotTo(if isSmallCrate then placement + Vector3.new(0, AIRDROP_HEIGHT, 0) else placement)
	banana:SetAttribute(BANANA_TYPE_ATTRIBUTE, bananaName)
	banana:SetAttribute("Rotates", isSingleBanana)

	banana.Parent = context.container
	if isSmallCrate then
		table.insert(context.airdropPositions, landingPosition)
		applyParachuteFall(rootPart)
		createAirdropMarker(context.container.Parent :: Model, landingPosition, banana)
	end

	local crate = context.crates[bananaName]
	if crate then
		crate.spawned += 1
		crate.failedAttempts = 0
	end

	if isSmallCrate and crate then
		matchEvent:FireAllClients({
			action = "Airdrop",
			currentAirdrop = crate.spawned,
			maxAirdrops = crate.maximum,
			landingPosition = landingPosition,
		})
	elseif bananaName == LARGE_CRATE_TAG and crate then
		matchEvent:FireAllClients({
			action = "Crate",
			currentAirdrop = crate.spawned,
			maxAirdrops = crate.maximum,
		})
	end

	collectionService:AddTag(banana, BANANA_TAG)
	return true
end

local function processGuaranteedSpawns(context: SpawnContext, elapsedTime: number)
	for bananaName, crate in pairs(context.crates) do
		while crate.spawned < crate.maximum and elapsedTime >= crate.interval * (crate.spawned + 1) do
			if not spawnBanana(context, bananaName) then
				crate.failedAttempts += 1
				break
			end
		end
	end
end

local function createContext(map: Model, matchDuration: number): SpawnContext
	local mapCFrame, mapSize = map:GetBoundingBox()
	local container = Instance.new("Folder")
	container.Name = "SpawnedBananas"
	container.Parent = map

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { map:FindFirstChild("Ground", true) or map }
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { map }
	overlapParams.RespectCanCollide = false

	local crates: { [string]: CrateState } = {}
	for bananaName, maximum in pairs(CRATE_LIMITS) do
		crates[bananaName] = {
			maximum = maximum,
			spawned = 0,
			interval = if maximum > 0 then matchDuration / (maximum + 1) else math.huge,
			failedAttempts = 0,
		}
	end

	return {
		container = container,
		mapCFrame = mapCFrame,
		mapSize = mapSize,
		raycastParams = raycastParams,
		overlapParams = overlapParams,
		crates = crates,
		airdropPositions = {},
	}
end

function bananaSpawner.spawnBananasInMap(map: Model, matchDuration: number)
	local context = createContext(map, matchDuration)
	activeContext = context

	for _ = 1, bananaConfig.MAX_BANANAS_SPAWNED do
		spawnBanana(context, nil)
	end

	local elapsedTime = 0
	while map.Parent do
		task.wait(bananaConfig.SPAWN_RATE)
		if not map.Parent then
			break
		end

		local matchStartTime = map:GetAttribute(MATCH_START_TIME_ATTRIBUTE)
		if typeof(matchStartTime) == "number" then
			elapsedTime = math.max(workspace:GetServerTimeNow() - matchStartTime, 0)
			processGuaranteedSpawns(context, elapsedTime)
		end

		if getSpawnedBananaCount(context) < bananaConfig.MAX_BANANAS_SPAWNED then
			spawnBanana(context, nil)
		end
	end

	if activeContext == context then
		activeContext = nil
	end

	for bananaName, crate in pairs(context.crates) do
		local missing = crate.maximum - crate.spawned
		if missing > 0 and crate.failedAttempts > 0 then
			warn(`{missing} guaranteed "{bananaName}" objects could not be placed before the match ended.`)
		end
	end
end

function bananaSpawner.canCollectDroppedBanana(banana: Model, player: Player): boolean
	return droppedBananaOwners[banana] ~= player
end

function bananaSpawner.getDroppedBananaRotation(banana: Model): CFrame?
	return droppedBananaRotations[banana]
end

function bananaSpawner.spawnDroppedBananas(position: Vector3, amount: number, targetPlayer: Player): number
	local context = activeContext
	local templates = bananaTemplates[NORMAL_BANANA_TAG]
	local totalPoints = math.floor(amount)
	if totalPoints <= 0 or not context or not context.container.Parent or not templates or #templates == 0 then
		return 0
	end

	local spawnAmount = math.min(totalPoints, MAX_DROPPED_BANANA_MODELS)
	local pointsPerBanana = math.floor(totalPoints / spawnAmount)
	local remainder = totalPoints % spawnAmount
	local angleOffset = RNG:NextNumber(0, math.pi * 2)

	task.spawn(function()
		local droppedBananas: { Model } = {}

		for index = 1, spawnAmount do
			if not context.container.Parent then
				break
			end

			local banana = cloneBanana(NORMAL_BANANA_TAG)
			if not banana then
				break
			end

			local rootPart = bananaModelUtils.prepare(banana, false)
			if not rootPart then
				banana:Destroy()
				break
			end

			local angle = angleOffset + ((index - 1) / spawnAmount) * math.pi * 2
			local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local spawnPosition = position
				+ direction * DROP_SPAWN_RADIUS
				+ Vector3.yAxis * DROP_SPAWN_HEIGHT
			local boundingCFrame = banana:GetBoundingBox()
			local pivotToBounds = banana:GetPivot():ToObjectSpace(boundingCFrame)
			local spawnPivot = CFrame.new(spawnPosition)
				* CFrame.Angles(0, RNG:NextNumber(0, math.pi * 2), 0)
				* pivotToBounds:Inverse()
			local uprightRotation = spawnPivot.Rotation
			local points = pointsPerBanana + (if index <= remainder then 1 else 0)

			banana:PivotTo(spawnPivot)
			banana:SetAttribute(BANANA_TYPE_ATTRIBUTE, NORMAL_BANANA_TAG)
			banana:SetAttribute(DROPPED_BANANA_ATTRIBUTE, true)
			banana:SetAttribute("Collectable", false)
			banana:SetAttribute("Points", points)
			banana:SetAttribute("Rotates", false)
			banana.Parent = context.container
			droppedBananaOwners[banana] = targetPlayer
			droppedBananaRotations[banana] = uprightRotation
			collectionService:AddTag(banana, BANANA_TAG)

			if rootPart:CanSetNetworkOwnership() then
				rootPart:SetNetworkOwner(nil)
			end
			rootPart:ApplyImpulse(
				(direction * DROP_HORIZONTAL_SPEED + Vector3.yAxis * DROP_UPWARD_SPEED) * rootPart.AssemblyMass
			)

			task.delay(DROP_COLLECT_DELAY, function()
				if banana.Parent then
					banana:SetAttribute("Collectable", true)
				end
			end)

			table.insert(droppedBananas, banana)
			if index < spawnAmount then
				task.wait(DROP_SPAWN_INTERVAL)
			end
		end

		if #droppedBananas > 0 then
			expireDroppedBananas(droppedBananas)
		end
	end)

	return totalPoints
end

bananaTemplates = cacheTemplates()

return bananaSpawner
