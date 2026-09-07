--!strict

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local BANANA_TAG = "SpawnedBanana"
local ROTATION_SPEED = math.rad(60)
local BOB_SPEED = 2
local BOB_HEIGHT = 0.35

type BananaAnimation = {
	origin: CFrame,
	elapsed: number,
	rotation: number,
}

local RNG = Random.new()
local rotatingBananas: { [Model]: BananaAnimation } = {}
local initialized = false
local controller = {}

local function trackBanana(instance: Instance)
	if instance:IsA("Model") and instance:GetAttribute("Rotates") == true then
		rotatingBananas[instance] = {
			origin = instance:GetPivot(),
			elapsed = RNG:NextNumber(0, math.pi * 2),
			rotation = 0,
		}
	end
end

local function untrackBanana(instance: Instance)
	if instance:IsA("Model") then
		rotatingBananas[instance] = nil
	end
end

local function updateBananas(deltaTime: number)
	for banana, animation in pairs(rotatingBananas) do
		if banana.Parent then
			animation.elapsed += deltaTime
			animation.rotation += ROTATION_SPEED * deltaTime

			local verticalOffset = math.sin(animation.elapsed * BOB_SPEED) * BOB_HEIGHT
			banana:PivotTo(
				animation.origin
					* CFrame.new(0, verticalOffset, 0)
					* CFrame.Angles(0, animation.rotation, 0)
			)
		else
			rotatingBananas[banana] = nil
		end
	end
end

function controller.init()
	if initialized then
		return
	end
	initialized = true

	CollectionService:GetInstanceAddedSignal(BANANA_TAG):Connect(trackBanana)
	CollectionService:GetInstanceRemovedSignal(BANANA_TAG):Connect(untrackBanana)

	for _, instance in ipairs(CollectionService:GetTagged(BANANA_TAG)) do
		trackBanana(instance)
	end

	RunService.PreRender:Connect(updateBananas)
end

return controller
