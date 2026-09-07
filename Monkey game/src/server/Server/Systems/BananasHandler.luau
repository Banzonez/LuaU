--!strict

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local BananaConfig = require(script.Parent.Parent.Configs.BananaConfig)

local soundsFolder = ServerStorage:FindFirstChild("Sounds")
assert(soundsFolder, "ServerStorage.Sounds is missing.")
local bananaCollectSounds = soundsFolder:FindFirstChild("BananaCollect")
assert(bananaCollectSounds, "ServerStorage.Sounds.BananaCollect is missing.")

local BANANA_TAG = "SpawnedBanana"
local SMALL_CRATE_TAG = assert(BananaConfig.getName(3), "Small crate tag is missing from BananaConfig.")
local PARACHUTE_ROTATION_SPEED = math.rad(10)
local SPATIAL_CHECK_INTERVAL = 0.1
local GROUND_CHECK_DISTANCE = 1
local MINIMUM_GROUND_NORMAL_Y = 0.7

type BananaState = {
	rootPart: BasePart?,
	falling: boolean,
	collected: boolean,
	points: number?,
	rayParams: RaycastParams?,
	overlapParams: OverlapParams,
}

local RNG = Random.new()
local collectionSounds: { Sound } = {}
local bananaStates: { [Model]: BananaState } = {}
local initialized = false
local spatialCheckAccumulator = 0
local handler = {}

for _, instance in ipairs(bananaCollectSounds:GetChildren()) do
	if instance:IsA("Sound") then
		table.insert(collectionSounds, instance)
	end
end

local function getPlayerFromPart(part: BasePart): Player?
	local ancestor: Instance? = part

	while ancestor do
		if ancestor:IsA("Model") then
			local player = Players:GetPlayerFromCharacter(ancestor)
			local humanoid = ancestor:FindFirstChildOfClass("Humanoid")
			if player and humanoid and humanoid.Health > 0 then
				return player
			end
		end

		ancestor = ancestor.Parent
	end

	return nil
end

local function playCollectionSound()
	if #collectionSounds == 0 then
		return
	end

	local sound = collectionSounds[RNG:NextInteger(1, #collectionSounds)]:Clone()
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, math.max(sound.TimeLength + 1, 5))
end

local function collectBanana(banana: Model, state: BananaState, player: Player)
	if state.collected then
		return
	end

	local points = state.points
	if not points then
		return
	end

	state.collected = true
	CollectionService:RemoveTag(banana, BANANA_TAG)

	local bananasAttribute = player:GetAttribute("Bananas")
	local currentBananas = if typeof(bananasAttribute) == "number" then bananasAttribute else 0

	player:SetAttribute("Bananas", currentBananas + points)
	playCollectionSound()
	banana:Destroy()
end

local function checkForCharacter(banana: Model, state: BananaState)
	if state.collected or not state.points or not banana.Parent then
		return
	end

	local boundingCFrame, boundingSize = banana:GetBoundingBox()
	local touchingParts = Workspace:GetPartBoundsInBox(
		boundingCFrame,
		boundingSize,
		state.overlapParams
	)

	for _, part in ipairs(touchingParts) do
		local player = getPlayerFromPart(part)
		if player then
			collectBanana(banana, state, player)
			return
		end
	end
end

local function stopCrateFall(banana: Model, state: BananaState, groundPosition: Vector3)
	local rootPart = state.rootPart
	if not rootPart then
		return
	end

	state.falling = false
	banana:SetAttribute("ReachedGround", true)

	local parachuteVelocity = rootPart:FindFirstChild("ParachuteVelocity")
	if parachuteVelocity then
		parachuteVelocity:Destroy()
	end

	local parachuteAttachment = rootPart:FindFirstChild("ParachuteAttachment")
	if parachuteAttachment then
		parachuteAttachment:Destroy()
	end

	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero

	local boundingCFrame, boundingSize = banana:GetBoundingBox()
	local groundedY = groundPosition.Y + boundingSize.Y / 2
	banana:PivotTo(
		banana:GetPivot() + Vector3.new(0, groundedY - boundingCFrame.Position.Y, 0)
	)

	for _, descendant in ipairs(banana:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
		end
	end

	rootPart.Anchored = true
end

local function checkCrateGround(banana: Model, state: BananaState)
	local rootPart = state.rootPart
	local rayParams = state.rayParams
	if not state.falling or not rootPart or not rootPart.Parent or not rayParams then
		return
	end

	if rootPart.AssemblyLinearVelocity.Y > 0 then
		return
	end

	local boundingCFrame, boundingSize = banana:GetBoundingBox()
	local fallDistancePerCheck = math.max(-rootPart.AssemblyLinearVelocity.Y, 0)
		* SPATIAL_CHECK_INTERVAL
	local rayLength = boundingSize.Y / 2 + GROUND_CHECK_DISTANCE + fallDistancePerCheck
	local result = Workspace:Raycast(
		boundingCFrame.Position,
		Vector3.new(0, -rayLength, 0),
		rayParams
	)

	if not result or result.Normal.Y < MINIMUM_GROUND_NORMAL_Y then
		return
	end

	if getPlayerFromPart(result.Instance) then
		return
	end

	local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
	if hitModel and CollectionService:HasTag(hitModel, BANANA_TAG) then
		return
	end

	stopCrateFall(banana, state, result.Position)
end

local function trackBanana(instance: Instance)
	if not instance:IsA("Model") or bananaStates[instance] then
		return
	end

	local rootPart = instance.PrimaryPart
	if not rootPart then
		local candidate = instance:FindFirstChildWhichIsA("BasePart", true)
		if candidate and candidate:IsA("BasePart") then
			rootPart = candidate
		end
	end
	local isSmallCrate = CollectionService:HasTag(instance, SMALL_CRATE_TAG)
	local pointsAttribute = instance:GetAttribute("Points")
	local points = if typeof(pointsAttribute) == "number" then pointsAttribute else nil

	if not points then
		warn(`{instance:GetFullName()} needs a numeric Points attribute.`)
	end

	local rayParams: RaycastParams = nil
	if isSmallCrate then
		rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { instance }
		rayParams.IgnoreWater = true
		rayParams.RespectCanCollide = true
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { instance }

	local state: BananaState = {
		rootPart = rootPart,
		falling = isSmallCrate and instance:GetAttribute("ReachedGround") ~= true,
		collected = false,
		points = points,
		rayParams = rayParams,
		overlapParams = overlapParams,
	}

	bananaStates[instance] = state

	if state.falling then
		if rootPart then
			rootPart.AssemblyAngularVelocity = Vector3.new(0, PARACHUTE_ROTATION_SPEED, 0)
		else
			warn(`Falling crate {instance:GetFullName()} does not contain a BasePart.`)
			state.falling = false
		end
	end
end

local function untrackBanana(instance: Instance)
	if instance:IsA("Model") then
		bananaStates[instance] = nil
	end
end

local function updateBananas(deltaTime: number)
	spatialCheckAccumulator += deltaTime
	local shouldCheckSpace = spatialCheckAccumulator >= SPATIAL_CHECK_INTERVAL

	if shouldCheckSpace then
		spatialCheckAccumulator %= SPATIAL_CHECK_INTERVAL
	end

	for banana, state in pairs(bananaStates) do
		if not banana.Parent then
			bananaStates[banana] = nil
			continue
		end

		if shouldCheckSpace then
			checkCrateGround(banana, state)
			checkForCharacter(banana, state)
		end
	end
end

function handler.init()
	if initialized then
		return
	end
	initialized = true

	CollectionService:GetInstanceAddedSignal(BANANA_TAG):Connect(trackBanana)
	CollectionService:GetInstanceRemovedSignal(BANANA_TAG):Connect(untrackBanana)

	for _, instance in ipairs(CollectionService:GetTagged(BANANA_TAG)) do
		trackBanana(instance)
	end

	RunService.Heartbeat:Connect(updateBananas)
end

return handler
