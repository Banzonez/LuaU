--!strict

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BananaConfig = require(script.Parent.Parent.Configs.BananaConfig)

local soundsFolder = ServerStorage:FindFirstChild("Sounds")
assert(soundsFolder, "ServerStorage.Sounds is missing.")
local bananaCollectSounds = soundsFolder:FindFirstChild("BananaCollect")
assert(bananaCollectSounds, "ServerStorage.Sounds.BananaCollect is missing.")

local BANANA_TAG = "SpawnedBanana"
local SMALL_CRATE_TAG = assert(BananaConfig.getName(3), "Small crate tag is missing from BananaConfig.")
local COLLECTABLE_ATTRIBUTE = "BananasCollectable"
local MATCH_BANANAS_FOLDER = "MatchBananas"
local SPATIAL_CHECK_INTERVAL = 0.1
local GROUND_CHECK_DISTANCE = 1
local MINIMUM_GROUND_NORMAL_Y = 0.7

local bananaTweenInfo = TweenInfo.new(.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
type BananaState = {
	rootPart: BasePart,
	map: Model,
	points: number,
	falling: boolean,
	raycastParams: RaycastParams?,
	overlapParams: OverlapParams,
}

local RNG = Random.new()
local collectionSounds: { Sound } = {}
local bananaStates: { [Model]: BananaState } = {}
local spatialCheckAccumulator = 0
local initialized = false
local Handler = {}

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

local function tweenModelScale(model: Model, targetScale: number, tweenInfo: TweenInfo): Tween
	targetScale = targetScale <= 0 and 0.001 or targetScale

	local scaleValue = Instance.new("NumberValue")
	scaleValue.Value = model:GetScale()

	local connection = scaleValue:GetPropertyChangedSignal("Value"):Connect(function()
		if model.Parent then
			model:ScaleTo(scaleValue.Value)
		end
	end)

	local tween = TweenService:Create(scaleValue, tweenInfo, {
		Value = targetScale,
	})

	tween.Completed:Once(function()
		connection:Disconnect()

		if model.Parent then
			model:ScaleTo(targetScale)
		end

		scaleValue:Destroy()
	end)

	tween:Play()
	return tween
end

local function collectBanana(banana: Model, state: BananaState, player: Player)
	local matchBananas = player:FindFirstChild(MATCH_BANANAS_FOLDER)
	if not matchBananas or not matchBananas:IsA("Folder") or banana:GetAttribute("Collectable") == false then
		return
	end
	banana:SetAttribute("Collectable", false)

	local collectedBanana = Instance.new("StringValue")
	collectedBanana.Name = banana.Name
	collectedBanana.Value = tostring(state.points)
	collectedBanana.Parent = matchBananas

	playCollectionSound()

	local bananaTween = tweenModelScale(banana, 0, bananaTweenInfo)
	bananaTween.Completed:Wait()

	CollectionService:RemoveTag(banana, BANANA_TAG)
	banana:Destroy()
end

local function checkForCharacter(banana: Model, state: BananaState)
	if state.map:GetAttribute(COLLECTABLE_ATTRIBUTE) ~= true then
		return
	end

	local boundingCFrame, boundingSize = banana:GetBoundingBox()
	local touchingParts = Workspace:GetPartBoundsInBox(boundingCFrame, boundingSize, state.overlapParams)

	for _, part in ipairs(touchingParts) do
		local player = getPlayerFromPart(part)
		if player then
			collectBanana(banana, state, player)
			return
		end
	end
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
	local result = Workspace:Raycast(boundingCFrame.Position, Vector3.new(0, -rayLength, 0), raycastParams)

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

	local isFalling = CollectionService:HasTag(instance, SMALL_CRATE_TAG)
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

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { instance }

	bananaStates[instance] = {
		rootPart = rootPart,
		map = map,
		points = pointsAttribute,
		falling = isFalling,
		raycastParams = raycastParams,
		overlapParams = overlapParams,
	}
end

local function updateBananas(deltaTime: number)
	spatialCheckAccumulator += deltaTime
	if spatialCheckAccumulator < SPATIAL_CHECK_INTERVAL then
		return
	end
	spatialCheckAccumulator %= SPATIAL_CHECK_INTERVAL

	for banana, state in pairs(bananaStates) do
		if not banana.Parent then
			bananaStates[banana] = nil
		else
			checkCrateGround(banana, state)
			checkForCharacter(banana, state)
		end
	end
end

function Handler.init()
	if initialized then
		return
	end
	initialized = true

	for _, instance in ipairs(bananaCollectSounds:GetChildren()) do
		if instance:IsA("Sound") then
			table.insert(collectionSounds, instance)
		end
	end

	CollectionService:GetInstanceAddedSignal(BANANA_TAG):Connect(trackBanana)
	CollectionService:GetInstanceRemovedSignal(BANANA_TAG):Connect(function(instance)
		bananaStates[instance :: Model] = nil
	end)

	for _, instance in ipairs(CollectionService:GetTagged(BANANA_TAG)) do
		trackBanana(instance)
	end

	RunService.Heartbeat:Connect(updateBananas)
end

return Handler
