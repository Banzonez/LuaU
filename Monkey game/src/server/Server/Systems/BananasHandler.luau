--!strict

local collectionService = game:GetService("CollectionService")
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local serverStorage = game:GetService("ServerStorage")
local soundService = game:GetService("SoundService")
local workspace = game:GetService("Workspace")

local bananaConfig = require(script.Parent.Parent.Configs.BananaConfig)
local bananasSpawner = require(script.Parent.Parent.Utils.BananasSpawner)

local soundsFolder = serverStorage:WaitForChild("Sounds")
local bananaCollectSounds = soundsFolder:WaitForChild("BananaCollect")
local sharedFolder = replicatedStorage:WaitForChild("Shared")
local eventsFolder = sharedFolder:WaitForChild("Events")
local matchEvent = eventsFolder:WaitForChild("MatchEvent") :: RemoteEvent

local BANANA_TAG = "SpawnedBanana"
local BANANA_TYPE_ATTRIBUTE = "BananaType"
local DROPPED_BANANA_ATTRIBUTE = "DroppedBanana"
local NORMAL_BANANA_TAG = bananaConfig.TagsNames[1]
local GOLD_BANANA_TAG = bananaConfig.TagsNames[2]
local SMALL_CRATE_TAG = bananaConfig.TagsNames[3]
local LARGE_CRATE_TAG = bananaConfig.TagsNames[4]
local COLLECTABLE_ATTRIBUTE = "BananasCollectable"
local MATCH_BANANAS_FOLDER = "MatchBananas"
local SPATIAL_CHECK_INTERVAL = 0.1
local GROUND_CHECK_DISTANCE = 1
local MINIMUM_GROUND_NORMAL_Y = 0.3
local COLLECTION_ANIMATION_DURATION = 0.35
local COLLECTION_DESTROY_DELAY = 0.45

local COLLECTION_SOUND_NAMES = {
	[NORMAL_BANANA_TAG] = "Normal banana collect 1",
	[GOLD_BANANA_TAG] = "Gold banana collect 2",
	[SMALL_CRATE_TAG] = "Air drop banana collect 3",
	[LARGE_CRATE_TAG] = "Banana crate collect 4",
}

type BananaState = {
	rootPart: BasePart,
	map: Model,
	points: number,
	bananaType: string?,
	falling: boolean,
	raycastParams: RaycastParams?,
}

local collectionSounds: { [string]: Sound } = {}
local bananaStates: { [Model]: BananaState } = {}
local collectionOverlapParams = OverlapParams.new()
local spatialCheckAccumulator = 0
local initialized = false
local bananasHandler = {}

local function getPlayerFromPart(part: BasePart): Player?
	local ancestor: Instance? = part

	while ancestor do
		if ancestor:IsA("Model") then
			local player = players:GetPlayerFromCharacter(ancestor)
			local humanoid = ancestor:FindFirstChildOfClass("Humanoid")
			if player and humanoid and humanoid.Health > 0 then
				return player
			end
		end
		ancestor = ancestor.Parent
	end

	return nil
end

local function getBananaType(banana: Model): string?
	local bananaType = banana:GetAttribute(BANANA_TYPE_ATTRIBUTE)
	if typeof(bananaType) == "string" then
		return bananaType
	end

	for _, tagName in ipairs(bananaConfig.TagsNames) do
		if collectionService:HasTag(banana, tagName) then
			return tagName
		end
	end

	return nil
end

local function playCollectionSound(bananaType: string?)
	if not bananaType then
		return
	end

	local template = collectionSounds[bananaType]
	if not template then
		return
	end

	local sound = template:Clone()
	sound.Parent = soundService
	sound:Play()
	debris:AddItem(sound, math.max(sound.TimeLength + 1, 5))
end

local function collectBanana(banana: Model, state: BananaState, player: Player)
	local matchBananas = player:FindFirstChild(MATCH_BANANAS_FOLDER)
	if not matchBananas
		or not matchBananas:IsA("Folder")
		or banana:GetAttribute("Collectable") == false
		or not bananasSpawner.canCollectDroppedBanana(banana, player)
	then
		return
	end

	banana:SetAttribute("Collectable", false)
	banana:SetAttribute("Rotates", false)

	state.falling = false
	state.rootPart.Anchored = true
	state.rootPart.AssemblyLinearVelocity = Vector3.zero
	state.rootPart.AssemblyAngularVelocity = Vector3.zero

	local collectedBanana = Instance.new("StringValue")
	collectedBanana.Name = banana.Name
	collectedBanana.Value = tostring(state.points)
	collectedBanana.Parent = matchBananas

	playCollectionSound(state.bananaType)
	collectionService:RemoveTag(banana, BANANA_TAG)

	matchEvent:FireAllClients({
		action = "BananaCollect",
		banana = banana,
		collector = player,
		pos = banana:GetPivot().Position,
		points = state.points,
		duration = COLLECTION_ANIMATION_DURATION,
	})

	task.delay(COLLECTION_DESTROY_DELAY, function()
		if banana.Parent then
			banana:Destroy()
		end
	end)
end

local function stopCrateFall(banana: Model, state: BananaState, groundPosition: Vector3)
	state.falling = false
	banana:SetAttribute("ReachedGround", true)

	for _, name in ipairs({
		"ParachuteAlignment",
		"ParachuteRotation",
		"ParachuteVelocity",
		"ParachuteAttachment",
	}) do
		local instance = state.rootPart:FindFirstChild(name)
		if instance then
			instance:Destroy()
		end
	end

	state.rootPart.AssemblyLinearVelocity = Vector3.zero
	state.rootPart.AssemblyAngularVelocity = Vector3.zero

	local boundingCFrame, boundingSize = banana:GetBoundingBox()
	local groundedY = groundPosition.Y + boundingSize.Y / 2
	banana:PivotTo(banana:GetPivot() + Vector3.new(0, groundedY - boundingCFrame.Position.Y, 0))

	state.rootPart.Anchored = true
end

local function checkCrateGround(banana: Model, state: BananaState)
	local raycastParams = state.raycastParams
	if not state.falling or not raycastParams then
		return
	end

	local boundingCFrame, boundingSize = banana:GetBoundingBox()
	local traveledDistance = math.max(-state.rootPart.AssemblyLinearVelocity.Y, 0) * SPATIAL_CHECK_INTERVAL
	local rayLength = boundingSize.Y / 2 + GROUND_CHECK_DISTANCE + traveledDistance
	local result = workspace:Raycast(boundingCFrame.Position, Vector3.new(0, -rayLength, 0), raycastParams)

	if not result or result.Normal.Y < MINIMUM_GROUND_NORMAL_Y or getPlayerFromPart(result.Instance) then
		return
	end

	stopCrateFall(banana, state, result.Position)
end

local function trackBanana(instance: Instance)
	if not instance:IsA("Model") then
		return
	end

	local rootPart = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
	local map = instance:FindFirstAncestorOfClass("Model")
	local pointsAttribute = instance:GetAttribute("Points")
	if not rootPart or not map or typeof(pointsAttribute) ~= "number" then
		warn(`{instance:GetFullName()} needs a map, BasePart, and numeric Points attribute.`)
		return
	end

	local isFalling = (collectionService:HasTag(instance, SMALL_CRATE_TAG)
		or instance:GetAttribute(DROPPED_BANANA_ATTRIBUTE) == true)
		and instance:GetAttribute("ReachedGround") ~= true
	local raycastParams: RaycastParams? = nil
	if isFalling then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { instance }
		params.IgnoreWater = true
		params.RespectCanCollide = true
		raycastParams = params
	end

	bananaStates[instance] = {
		rootPart = rootPart,
		map = map,
		points = pointsAttribute,
		bananaType = getBananaType(instance),
		falling = isFalling,
		raycastParams = raycastParams,
	}
end

local function getTrackedBanana(part: BasePart): (Model?, BananaState?)
	local ancestor: Instance? = part

	while ancestor do
		if ancestor:IsA("Model") then
			local state = bananaStates[ancestor]
			if state then
				return ancestor, state
			end
		end
		ancestor = ancestor.Parent
	end

	return nil, nil
end

local function checkForCollections()
	local collectableBananas: { Instance } = {}

	for banana, state in pairs(bananaStates) do
		if banana.Parent
			and state.map:GetAttribute(COLLECTABLE_ATTRIBUTE) == true
			and banana:GetAttribute("Collectable") ~= false
		then
			table.insert(collectableBananas, banana)
		end
	end

	if #collectableBananas == 0 then
		return
	end

	collectionOverlapParams.FilterType = Enum.RaycastFilterType.Include
	collectionOverlapParams.FilterDescendantsInstances = collectableBananas

	for _, player in ipairs(players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid or humanoid.Health <= 0 then
			continue
		end

		local characterCFrame, characterSize = character:GetBoundingBox()
		local checkedBananas: { [Model]: boolean } = {}
		for _, part in ipairs(workspace:GetPartBoundsInBox(characterCFrame, characterSize, collectionOverlapParams)) do
			local banana, state = getTrackedBanana(part)
			if banana and state and not checkedBananas[banana] then
				checkedBananas[banana] = true
				collectBanana(banana, state, player)
			end
		end
	end
end

local function updateBananas(deltaTime: number)
	spatialCheckAccumulator += deltaTime

	local updateSpatialChecks = spatialCheckAccumulator >= SPATIAL_CHECK_INTERVAL
	if not updateSpatialChecks then
		return
	end

	spatialCheckAccumulator %= SPATIAL_CHECK_INTERVAL

	for banana, state in pairs(bananaStates) do
		if not banana.Parent then
			bananaStates[banana] = nil
		else
			checkCrateGround(banana, state)
		end
	end

	checkForCollections()
end

function bananasHandler.init()
	if initialized then
		return
	end
	initialized = true

	for bananaType, soundName in pairs(COLLECTION_SOUND_NAMES) do
		local sound = bananaCollectSounds:FindFirstChild(soundName)
		if sound and sound:IsA("Sound") then
			collectionSounds[bananaType] = sound
		else
			warn(`Sound "{soundName}" is missing from {bananaCollectSounds:GetFullName()}.`)
		end
	end

	collectionService:GetInstanceAddedSignal(BANANA_TAG):Connect(trackBanana)
	collectionService:GetInstanceRemovedSignal(BANANA_TAG):Connect(function(instance)
		bananaStates[instance :: Model] = nil
	end)

	for _, instance in ipairs(collectionService:GetTagged(BANANA_TAG)) do
		trackBanana(instance)
	end

	runService.Heartbeat:Connect(updateBananas)
end

return bananasHandler
