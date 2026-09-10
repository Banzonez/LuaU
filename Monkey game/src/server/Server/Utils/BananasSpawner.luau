--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local BananaConfig = require(script.Parent.Parent.Configs.BananaConfig)

local assetsFolder = ServerStorage:FindFirstChild("Assets")
assert(assetsFolder, "ServerStorage.Assets is missing.")
local bananaModelsFolder = assetsFolder:FindFirstChild("BananaModels")
assert(bananaModelsFolder, "ServerStorage.Assets.BananaModels is missing.")
local vfxFolder = assetsFolder:FindFirstChild("VFX")
assert(vfxFolder, "VFX not found in Assets.")
local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
assert(sharedFolder, "ReplicatedStorage.Shared is missing.")
local eventsFolder = sharedFolder:FindFirstChild("Events")
assert(eventsFolder, "ReplicatedStorage.Shared.Events is missing.")
local matchEvent = eventsFolder:FindFirstChild("MatchEvent")
assert(matchEvent and matchEvent:IsA("RemoteEvent"), "ReplicatedStorage.Shared.Events.MatchEvent must be a RemoteEvent.")

local BANANA_TAG = "SpawnedBanana"
local SMALL_CRATE_TAG = assert(BananaConfig.getName(3), "Small crate tag is missing from BananaConfig.")
local LARGE_CRATE_TAG = assert(BananaConfig.getName(4), "Large crate tag is missing from BananaConfig.")
local MATCH_START_TIME_ATTRIBUTE = "BananasMatchStartedAt"
local MAX_PLACEMENT_ATTEMPTS = 30
local RAYCAST_MARGIN = 100
local GROUND_CLEARANCE = 0.1
local SINGLE_BANANA_HEIGHT = 1
local AIRDROP_HEIGHT = 25
local PARACHUTE_FALL_SPEED = 5
local PARACHUTE_ROTATION_SPEED = math.rad(5)
local MINIMUM_GROUND_NORMAL_Y = 0.7
local MINIMUM_AIRDROP_DISTANCE = 10
local AIRDROP_VFX: BasePart = vfxFolder:FindFirstChild("AirdropVFX")

local CRATE_LIMITS: { [string]: number } = {
	[SMALL_CRATE_TAG] = BananaConfig.MAX_SMALL_CRATES,
	[LARGE_CRATE_TAG] = BananaConfig.MAX_CRATES,
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

local RNG = Random.new()
local bananaTemplates: { [string]: { Model } } = {}
local Spawner = {}

local function cacheTemplates(): { [string]: { Model } }
	local templatesByName: { [string]: { Model } } = {}

	for _, bananaName in ipairs(BananaConfig.TagsNames) do
		local templates = {}
		for _, instance in ipairs(CollectionService:GetTagged(bananaName)) do
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

local function getRandomBananaName(): string?
	local totalWeight = 0

	for _, chance in pairs(BananaConfig.Chances) do
		if chance > 0 then
			totalWeight += chance
		end
	end

	if totalWeight == 0 then
		return nil
	end

	local selectedWeight = RNG:NextNumber(0, totalWeight)
	local accumulatedWeight = 0
	for bananaName, chance in pairs(BananaConfig.Chances) do
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

local function prepareModel(model: Model, anchored: boolean): BasePart?
	local rootPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not rootPart then
		return nil
	end

	model.PrimaryPart = rootPart
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false

			if descendant ~= rootPart then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "BananaWeld"
				weld.Part0 = rootPart
				weld.Part1 = descendant
				weld.Parent = rootPart
			end
		end
	end

	rootPart.Anchored = anchored
	return rootPart
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
		local result = Workspace:Raycast(
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

		for _, part in ipairs(Workspace:GetPartBoundsInBox(targetBounds, overlapSize, context.overlapParams)) do
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

local function createAirdropMarker(map: Model, position: Vector3)
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

	if AIRDROP_VFX then
		local clone = AIRDROP_VFX:Clone()
		clone.Anchored = true
		clone:PivotTo(marker.CFrame)
		clone.Parent = marker
	end
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
	local rootPart = prepareModel(banana, not isSmallCrate)
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
	banana:SetAttribute("Rotates", isSingleBanana)
	banana:SetAttribute("Airdrop", isSmallCrate)

	banana.Parent = context.container
	if isSmallCrate then
		table.insert(context.airdropPositions, landingPosition)
		createAirdropMarker(context.container.Parent :: Model, landingPosition)
		applyParachuteFall(rootPart)
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
		})
	elseif bananaName == LARGE_CRATE_TAG and crate then
		matchEvent:FireAllClients({
			action = "Crate",
			currentAirdrop = crate.spawned,
			maxAirdrops = crate.maximum,
		})
	end

	CollectionService:AddTag(banana, BANANA_TAG)
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
	raycastParams.FilterDescendantsInstances = { map:FindFirstChild("Ground") or map }
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

function Spawner.spawnBananasInMap(map: Model, matchDuration: number)
	local context = createContext(map, matchDuration)

	for _ = 1, BananaConfig.MAX_BANANAS_SPAWNED do
		spawnBanana(context, nil)
	end

	local elapsedTime = 0
	while map.Parent do
		task.wait(BananaConfig.SPAWN_RATE)
		if not map.Parent then
			break
		end

		local matchStartTime = map:GetAttribute(MATCH_START_TIME_ATTRIBUTE)
		local matchStarted = typeof(matchStartTime) == "number"
		if matchStarted then
			elapsedTime = math.max(Workspace:GetServerTimeNow() - matchStartTime, 0)
			processGuaranteedSpawns(context, elapsedTime)
		end

		if #context.container:GetChildren() < BananaConfig.MAX_BANANAS_SPAWNED then
			spawnBanana(context, nil)
		end
	end

	for bananaName, crate in pairs(context.crates) do
		local missing = crate.maximum - crate.spawned
		if missing > 0 and crate.failedAttempts > 0 then
			warn(`{missing} guaranteed "{bananaName}" objects could not be placed before the match ended.`)
		end
	end
end

bananaTemplates = cacheTemplates()

return Spawner
