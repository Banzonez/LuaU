--!strict

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local BananaConfig = require(script.Parent.Parent.Configs.BananaConfig)

local assetsFolder = ServerStorage:FindFirstChild("Assets")
assert(assetsFolder, "ServerStorage.Assets is missing.")
local bananaModelsFolder = assetsFolder:FindFirstChild("BananaModels")
assert(bananaModelsFolder, "ServerStorage.Assets.BananaModels is missing.")

local BANANA_TAG = "SpawnedBanana"
local SMALL_CRATE_TAG = assert(BananaConfig.getName(3), "Small crate tag is missing from BananaConfig.")
local LARGE_CRATE_TAG = assert(BananaConfig.getName(4), "Large crate tag is missing from BananaConfig.")
local MAX_PLACEMENT_ATTEMPTS = 30
local RAYCAST_MARGIN = 100
local GROUND_CLEARANCE = 0.1
local SINGLE_BANANA_HEIGHT = 1
local PARACHUTE_FALL_SPEED = 5
local MINIMUM_GROUND_NORMAL_Y = 0.7

local RNG = Random.new()
local Spawner = {}

local function getModelRootPart(model: Model): BasePart?
	local rootPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)

	if rootPart then
		model.PrimaryPart = rootPart
	end

	return rootPart
end

local function weldModel(model: Model, rootPart: BasePart)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
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
end

local function configureModelParts(model: Model, rootPart: BasePart, anchored: boolean)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
		end
	end

	rootPart.Anchored = anchored
end

local function applyParachuteFall(model: Model, rootPart: BasePart)
	configureModelParts(model, rootPart, false)

	local canSetNetworkOwner = rootPart:CanSetNetworkOwnership()
	if canSetNetworkOwner then
		rootPart:SetNetworkOwner(nil)
	end

	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero

	local attachment = Instance.new("Attachment")
	attachment.Name = "ParachuteAttachment"
	attachment.Parent = rootPart

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = "ParachuteVelocity"
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VectorVelocity = Vector3.new(0, -PARACHUTE_FALL_SPEED, 0)
	linearVelocity.ForceLimitsEnabled = false
	linearVelocity.Parent = rootPart
end

local function cacheBananaTemplates(): { [string]: { Model } }
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
	end

	return templatesByName
end

local bananaTemplates = cacheBananaTemplates()

local function getRandomBanana(): (Model?, string?)
	local totalWeight = 0

	for _, bananaName in ipairs(BananaConfig.TagsNames) do
		local chance = BananaConfig.Chances[bananaName]

		if typeof(chance) == "number" and chance > 0 then
			totalWeight += chance
		end
	end

	if totalWeight <= 0 then
		warn("BananaConfig does not contain any positive banana chances.")
		return nil, nil
	end

	local selectedNumber = RNG:NextNumber(0, totalWeight)
	local accumulatedWeight = 0

	for _, bananaName in ipairs(BananaConfig.TagsNames) do
		local chance = BananaConfig.Chances[bananaName]

		if typeof(chance) ~= "number" or chance <= 0 then
			continue
		end

		accumulatedWeight += chance

		if selectedNumber <= accumulatedWeight then
			local templates = bananaTemplates[bananaName]

			if not templates or #templates == 0 then
				warn(
					`No Model tagged "{bananaName}" exists directly inside {bananaModelsFolder:GetFullName()}.`
				)

				return nil, nil
			end

			local bananaTemplate = templates[RNG:NextInteger(1, #templates)]
			return bananaTemplate:Clone(), bananaName
		end
	end

	return nil, nil
end

local function getObjectPlacement(
	map: Model,
	bananaModel: Model,
	bananaContainer: Folder,
	mapBoundingCFrame: CFrame,
	mapBoundingSize: Vector3,
	heightOffset: number
): CFrame?
	local bananaBoundingCFrame, bananaBoundingSize = bananaModel:GetBoundingBox()
	local bananaPivot = bananaModel:GetPivot()

	-- Preserve templates whose pivot is not centered on their geometry.
	local pivotToBoundingBox = bananaPivot:ToObjectSpace(bananaBoundingCFrame)

	local groundContainer = map:FindFirstChild("Ground") or map

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { groundContainer }
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = {
		map,
		bananaContainer,
	}
	overlapParams.RespectCanCollide = false

	for _ = 1, MAX_PLACEMENT_ATTEMPTS do
		local localX = RNG:NextNumber(
			-mapBoundingSize.X / 2,
			mapBoundingSize.X / 2
		)

		local localZ = RNG:NextNumber(
			-mapBoundingSize.Z / 2,
			mapBoundingSize.Z / 2
		)

		local sampledPosition = mapBoundingCFrame:PointToWorldSpace(
			Vector3.new(localX, 0, localZ)
		)

		local rayOrigin = Vector3.new(
			sampledPosition.X,
			mapBoundingCFrame.Position.Y
				+ mapBoundingSize.Y / 2
				+ RAYCAST_MARGIN,
			sampledPosition.Z
		)

		local rayLength = mapBoundingSize.Y + RAYCAST_MARGIN * 2
		local rayDirection = Vector3.new(0, -rayLength, 0)

		local result = Workspace:Raycast(
			rayOrigin,
			rayDirection,
			raycastParams
		)

		if not result then
			continue
		end

		if result.Normal.Y < MINIMUM_GROUND_NORMAL_Y then
			continue
		end

		local randomYRotation = math.rad(RNG:NextNumber(0, 360))

		local targetBoundingCFrame =
			CFrame.new(
				result.Position
					+ Vector3.yAxis
						* (bananaBoundingSize.Y / 2 + GROUND_CLEARANCE + heightOffset)
			)
			* CFrame.Angles(0, randomYRotation, 0)

		local overlapSize = Vector3.new(
			math.max(bananaBoundingSize.X - 0.05, 0.05),
			math.max(bananaBoundingSize.Y - 0.1, 0.05),
			math.max(bananaBoundingSize.Z - 0.05, 0.05)
		)

		local overlappingParts = Workspace:GetPartBoundsInBox(
			targetBoundingCFrame,
			overlapSize,
			overlapParams
		)

		local blocked = false

		for _, overlappingPart in ipairs(overlappingParts) do
			if overlappingPart ~= result.Instance then
				blocked = true
				break
			end
		end

		if blocked then
			continue
		end

		return targetBoundingCFrame * pivotToBoundingBox:Inverse()
	end

	return nil
end

local function spawnBanana(
	map: Model,
	bananaContainer: Folder,
	mapBoundingCFrame: CFrame,
	mapBoundingSize: Vector3
): Model?
	local bananaModel, bananaName = getRandomBanana()

	if not bananaModel or not bananaName then
		return nil
	end

	local rootPart = getModelRootPart(bananaModel)
	if not rootPart then
		warn(`{bananaModel.Name} does not contain a BasePart.`)
		bananaModel:Destroy()
		return nil
	end

	weldModel(bananaModel, rootPart)

	local isSingleBanana = bananaName ~= SMALL_CRATE_TAG and bananaName ~= LARGE_CRATE_TAG

	local placementCFrame = getObjectPlacement(
		map,
		bananaModel,
		bananaContainer,
		mapBoundingCFrame,
		mapBoundingSize,
		if isSingleBanana then SINGLE_BANANA_HEIGHT else 0
	)

	if not placementCFrame then
		bananaModel:Destroy()
		return nil
	end

	bananaModel:PivotTo(placementCFrame)
	bananaModel.Parent = bananaContainer

	bananaModel:SetAttribute("Rotates", isSingleBanana)

	if bananaName == SMALL_CRATE_TAG then
		bananaModel:PivotTo(bananaModel:GetPivot() + Vector3.new(0, 25, 0))
		applyParachuteFall(bananaModel, rootPart)
	else
		configureModelParts(bananaModel, rootPart, true)
	end

	CollectionService:AddTag(bananaModel, BANANA_TAG)

	return bananaModel
end

local function getSpawnedBananaCount(bananaContainer: Folder): number
	return #bananaContainer:GetChildren()
end

function Spawner.spawnBananasInMap(map: Model)
	if not map:IsA("Model") or not map.Parent then
		warn("Spawner.spawnBananasInMap expected a parented Model.")
		return
	end

	local mapBoundingCFrame, mapBoundingSize = map:GetBoundingBox()

	local bananaContainer = Instance.new("Folder")
	bananaContainer.Name = (`{map.Name}_SpawnedBananas`)
	bananaContainer.Parent = Workspace
	local mapDestroyingConnection = map.Destroying:Connect(function()
		bananaContainer:Destroy()
	end)

	for _ = 1, BananaConfig.MAX_BANANAS_SPAWNED do
		if not map.Parent then
			break
		end

		spawnBanana(
			map,
			bananaContainer,
			mapBoundingCFrame,
			mapBoundingSize
		)
	end

	while map.Parent do
		task.wait(BananaConfig.SPAWN_RATE)

		if not map.Parent then
			break
		end

		local spawnedCount = getSpawnedBananaCount(bananaContainer)

		if spawnedCount >= BananaConfig.MAX_BANANAS_SPAWNED then
			continue
		end

		spawnBanana(
			map,
			bananaContainer,
			mapBoundingCFrame,
			mapBoundingSize
		)
	end

	mapDestroyingConnection:Disconnect()
	if bananaContainer.Parent then
		bananaContainer:Destroy()
	end
end

return Spawner
