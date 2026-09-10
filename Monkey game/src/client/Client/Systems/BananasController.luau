local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GuiAnimator = require(script.Parent.Parent.Utils.GuiAnimator)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local matchGui = playerGui:WaitForChild("MatchGui")
local matchEvent: RemoteEvent =
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Events"):WaitForChild("MatchEvent")

local airdropFrame = matchGui:WaitForChild("Airdrop")
assert(airdropFrame:IsA("Frame"), "MatchGui.Airdrop must be a Frame.")
local airdropText = airdropFrame:WaitForChild("TextLabel")
assert(airdropText:IsA("TextLabel"), "MatchGui.Airdrop.TextLabel must be a TextLabel.")

local crateFrame = matchGui:WaitForChild("Crate")
local crateText = crateFrame:WaitForChild("TextLabel")

local BANANA_TAG = "SpawnedBanana"
local ROTATION_SPEED = math.rad(60)
local BOB_SPEED = 2
local BOB_HEIGHT = 0.35
local AIRDROP_MESSAGE_DURATION = 2
type BananaAnimation = {
	origin: CFrame,
	phase: number,
}

local RNG = Random.new()
local rotatingBananas: { [Model]: BananaAnimation } = {}
local animationTime = 0
local notificationIds = {
	Airdrop = 0,
	Crate = 0,
}

local airdropAnimator = GuiAnimator.new(airdropFrame, "PopIn")
local crateAnimator = GuiAnimator.new(crateFrame, "PopIn")

local initialized = false
local Controller = {}

local function showMessage(
	airdropFrame,
	airdropText,
	airdropAnimator,
	text: string,
	action: string,
	currentAirdrop: number,
	maxAirdrops: number
)
	notificationIds[action] += 1

	local currentNotification = notificationIds[action]
	airdropText.Text = `{text} {currentAirdrop}/{maxAirdrops}`
	airdropAnimator:Play()

	task.delay(AIRDROP_MESSAGE_DURATION, function()
		if currentNotification == notificationIds[action] and airdropFrame.Parent then
			airdropAnimator:Return()
		end
	end)
end

local function trackBanana(instance: Instance)
	if not instance:IsA("Model") then
		return
	end

	if instance:GetAttribute("Rotates") == true then
		rotatingBananas[instance] = {
			origin = instance:GetPivot(),
			phase = RNG:NextNumber(0, math.pi * 2),
		}
	end
end

local function updateBananas(deltaTime: number)
	animationTime += deltaTime

	for banana, animation in pairs(rotatingBananas) do
		if not banana.Parent then
			rotatingBananas[banana] = nil
			continue
		end

		local verticalOffset = math.sin(animationTime * BOB_SPEED + animation.phase) * BOB_HEIGHT
		banana:PivotTo(
			animation.origin * CFrame.new(0, verticalOffset, 0) * CFrame.Angles(0, animationTime * ROTATION_SPEED, 0)
		)
	end
end

function Controller.init()
	if initialized then
		return
	end
	initialized = true

	airdropFrame.Visible = false
	crateFrame.Visible = false

	matchEvent.OnClientEvent:Connect(function(data)
		if data.action == "Airdrop" then
			showMessage(
				airdropFrame,
				airdropText,
				airdropAnimator,
				"AIRDROP COMING",
				"Airdrop",
				data.currentAirdrop,
				data.maxAirdrops
			)
		elseif data.action == "Crate" then
			showMessage(
				crateFrame,
				crateText,
				crateAnimator,
				"CRATE COMIING",
				"Crate",
				data.currentAirdrop,
				data.maxAirdrops
			)
		end
	end)

	CollectionService:GetInstanceAddedSignal(BANANA_TAG):Connect(trackBanana)
	CollectionService:GetInstanceRemovedSignal(BANANA_TAG):Connect(function(instance)
		rotatingBananas[instance :: Model] = nil
	end)

	for _, instance in ipairs(CollectionService:GetTagged(BANANA_TAG)) do
		trackBanana(instance)
	end

	RunService.PreRender:Connect(updateBananas)
end

return Controller
