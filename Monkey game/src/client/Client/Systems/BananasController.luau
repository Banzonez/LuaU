--!strict

local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

local guiAnimator = require(script.Parent.Parent.Utils.GuiAnimator)

local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local matchGui = playerGui:WaitForChild("MatchGui") :: ScreenGui
local matchEvent: RemoteEvent =
	replicatedStorage:WaitForChild("Shared"):WaitForChild("Events"):WaitForChild("MatchEvent")

local airdropFrame = matchGui:WaitForChild("Airdrop")
assert(airdropFrame:IsA("Frame"), "MatchGui.Airdrop must be a Frame.")
local airdropText = airdropFrame:WaitForChild("TextLabel")
assert(airdropText:IsA("TextLabel"), "MatchGui.Airdrop.TextLabel must be a TextLabel.")

local crateFrame = matchGui:WaitForChild("Crate") :: Frame
local crateText = crateFrame:WaitForChild("TextLabel") :: TextLabel

local bananaFrame = matchGui:WaitForChild("BananaCounter") :: Frame
local bananaText = bananaFrame:WaitForChild("Counter") :: TextLabel

local POP_DISTANCE = 50
local AIRDROP_MESSAGE_DURATION = 2
local COLLECTION_DURATION = 0.35
local COLLECTION_ARC_HEIGHT = 0
local COLLECTION_ROTATION = math.rad(180)
local MINIMUM_MODEL_SCALE = 0.001
local BANANA_TAG = "SpawnedBanana"
local ROTATION_SPEED = math.rad(60)
local BOB_SPEED = 2
local BOB_HEIGHT = 0.35
local RNG = Random.new()

type IdleAnimation = {
	origin: CFrame,
	phase: number,
}

type CollectionAnimation = {
	targetPart: BasePart,
	startPosition: Vector3,
	startRotation: CFrame,
	startScale: number,
	duration: number,
	elapsed: number,
}

type MatchEventData = {
	action: string?,
	currentAirdrop: number?,
	maxAirdrops: number?,
	banana: Model?,
	collector: Player?,
	duration: number?,
	pos: Vector3?,
	points: number?,
}

local collectingBananas: { [Model]: CollectionAnimation } = {}
local rotatingBananas: { [Model]: IdleAnimation } = {}
local animationTime = 0
local notificationIds = {
	Airdrop = 0,
	Crate = 0,
}

local popInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)

local airdropAnimator = guiAnimator.new(airdropFrame, "PopIn")
local crateAnimator = guiAnimator.new(crateFrame, "PopIn")

local function trackBanana(instance: Instance)
	if not instance:IsA("Model") or instance:GetAttribute("Rotates") ~= true then
		return
	end

	rotatingBananas[instance] = {
		origin = instance:GetPivot(),
		phase = RNG:NextNumber(0, math.pi * 2),
	}
end

local function updateIdleAnimations(deltaTime: number)
	animationTime += deltaTime

	for banana, animation in pairs(rotatingBananas) do
		if not banana.Parent or banana:GetAttribute("Rotates") ~= true or collectingBananas[banana] then
			rotatingBananas[banana] = nil
			continue
		end

		local verticalOffset = math.sin(animationTime * BOB_SPEED + animation.phase) * BOB_HEIGHT
		banana:PivotTo(
			animation.origin
				* CFrame.new(0, verticalOffset, 0)
				* CFrame.Angles(0, animationTime * ROTATION_SPEED, 0)
		)
	end
end

local initialized = false
local Controller = {}

local function showMessage(
	airdropFrame: Frame,
	airdropText: TextLabel,
	airdropAnimator: any,
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

local function updateCollectionAnimations(deltaTime: number)
	for banana, animation in pairs(collectingBananas) do
		if not banana.Parent or not animation.targetPart.Parent then
			collectingBananas[banana] = nil
			continue
		end

		animation.elapsed = math.min(animation.elapsed + deltaTime, animation.duration)
		local alpha = animation.elapsed / animation.duration
		local moveAlpha = tweenService:GetValue(alpha, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local scaleAlpha = tweenService:GetValue(alpha, Enum.EasingStyle.Cubic, Enum.EasingDirection.In)
		local targetPosition = animation.targetPart.Position
		local position = animation.startPosition:Lerp(targetPosition, moveAlpha)
			+ Vector3.yAxis * (math.sin(alpha * math.pi) * COLLECTION_ARC_HEIGHT)
		local rotation = animation.startRotation * CFrame.Angles(0, COLLECTION_ROTATION * alpha, 0)

		banana:ScaleTo(math.max(animation.startScale * (1 - scaleAlpha), MINIMUM_MODEL_SCALE))
		banana:PivotTo(CFrame.new(position) * rotation)

		if alpha >= 1 then
			collectingBananas[banana] = nil
		end
	end
end

local function animateBananaCollect(banana: Model, collector: Player, duration: number)
	local character = collector.Character
	local targetPart = character and character:FindFirstChild("HumanoidRootPart")
	if not targetPart or not targetPart:IsA("BasePart") then
		return
	end

	local startPivot = banana:GetPivot()
	collectingBananas[banana] = {
		targetPart = targetPart,
		startPosition = startPivot.Position,
		startRotation = startPivot.Rotation,
		startScale = banana:GetScale(),
		duration = duration,
		elapsed = 0,
	}
end

local function createText(points: number): TextLabel
	local textLabel = Instance.new("TextLabel")
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.Size = UDim2.fromOffset(100, 50)
	textLabel.BackgroundTransparency = 1
	textLabel.TextScaled = true
	textLabel.Text = "+" .. tostring(points)
	textLabel.TextColor3 = Color3.fromRGB(235, 232, 106)
	textLabel.TextStrokeTransparency = 0
	textLabel.ZIndex = 100
	textLabel.Visible = true

	return textLabel
end

local function showUICollect(position: Vector3, parent: Instance, points: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local screenPosition: Vector3
	local isOnScreen: boolean
	if matchGui.IgnoreGuiInset then
		screenPosition, isOnScreen = camera:WorldToViewportPoint(position)
	else
		screenPosition, isOnScreen = camera:WorldToScreenPoint(position)
	end

	if not isOnScreen or screenPosition.Z <= 0 then
		return
	end

	local uiPosition = Vector2.new(screenPosition.X, screenPosition.Y)

	-- Camera projection returns screen coordinates, but a GuiObject's
	-- Position is relative to its immediate parent.
	if parent:IsA("GuiObject") then
		uiPosition -= parent.AbsolutePosition
	end

	local text = createText(points)
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromOffset(uiPosition.X, uiPosition.Y)
	text.Parent = parent

	local targetPosition = UDim2.fromOffset(
		uiPosition.X,
		uiPosition.Y - POP_DISTANCE
	)

	local tween = tweenService:Create(text, popInfo, {
		Position = targetPosition,
	})

	tween.Completed:Once(function()
		text:Destroy()
	end)

	tween:Play()
end

local function changeBananaText(matchFolder: Folder)
	local points = 0
	for _, instance in ipairs(matchFolder:GetChildren()) do
		if instance:IsA("StringValue") then
			points += tonumber(instance.Value) or 0
		end
	end

	bananaText.Text = tostring(points)
end

local function connectBananaEntry(instance: Instance, matchFolder: Folder)
	if instance:IsA("StringValue") then
		instance:GetPropertyChangedSignal("Value"):Connect(function()
			changeBananaText(matchFolder)
		end)
	end
end

local function connectMatchFolder(instance: Instance)
	if instance.Name ~= "MatchBananas" or not instance:IsA("Folder") then
		return
	end

	for _, entry in ipairs(instance:GetChildren()) do
		connectBananaEntry(entry, instance)
	end

	changeBananaText(instance)
	instance.ChildAdded:Connect(function(entry)
		connectBananaEntry(entry, instance)
		changeBananaText(instance)
	end)
	instance.ChildRemoved:Connect(function()
		changeBananaText(instance)
	end)
end

function Controller.init()
	if initialized then
		return
	end
	initialized = true

	airdropFrame.Visible = false
	crateFrame.Visible = false
	bananaFrame.Visible = true

	bananaText.Text = "0"

	matchEvent.OnClientEvent:Connect(function(data: MatchEventData)
		if data.action == "Airdrop" then
			if not data.currentAirdrop or not data.maxAirdrops then
				return
			end

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
			if not data.currentAirdrop or not data.maxAirdrops then
				return
			end

			showMessage(
				crateFrame,
				crateText,
				crateAnimator,
				"CRATE SPAWNED",
				"Crate",
				data.currentAirdrop,
				data.maxAirdrops
			)
		elseif data.action == "BananaCollect" then
			local banana = data.banana
			local collector = data.collector
			local points = data.points
			local position = data.pos
			if banana and collector and points and position then
				local duration = data.duration or COLLECTION_DURATION
				animateBananaCollect(banana, collector, duration)

				if collector == player then
					showUICollect(position, matchGui, points)
				end
			end
		end
	end)

	collectionService:GetInstanceAddedSignal(BANANA_TAG):Connect(trackBanana)
	collectionService:GetInstanceRemovedSignal(BANANA_TAG):Connect(function(instance)
		rotatingBananas[instance :: Model] = nil
	end)

	for _, instance in ipairs(collectionService:GetTagged(BANANA_TAG)) do
		trackBanana(instance)
	end

	runService.PreRender:Connect(function(deltaTime)
		updateIdleAnimations(deltaTime)
		updateCollectionAnimations(deltaTime)
	end)

	local matchFolder = player:FindFirstChild("MatchBananas")
	if matchFolder then
		connectMatchFolder(matchFolder)
	end
	player.ChildAdded:Connect(connectMatchFolder)
end

return Controller
