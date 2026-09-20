local collectionService = game:GetService("CollectionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")

local guiAnimator = require(script.Parent.Parent.Utils.GuiAnimator)
local soundUtils = require(replicatedStorage:WaitForChild("Shared"):WaitForChild("Utils"):WaitForChild("SoundUtils"))

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
local POP_LIFETIME = 2
local POP_FADE_DELAY = POP_LIFETIME / 2
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
	startedAt: number,
}

type CollectionAnimation = {
	targetPart: BasePart,
	startPosition: Vector3,
	startRotation: CFrame,
	startScale: number,
	duration: number,
	elapsed: number,
}

type CollectionPopup = {
	label: TextLabel,
	worldPosition: Vector3,
	elapsed: number,
}

type SoundData = {
	soundId: string,
	volume: number,
	playbackSpeed: number,
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
	sound: SoundData?,
}

local collectingBananas: { [Model]: CollectionAnimation } = {}
local collectionPopups: { CollectionPopup } = {}
local rotatingBananas: { [Model]: IdleAnimation } = {}
local rotatingBananaConnections: { [Model]: RBXScriptConnection } = {}
local animationTime = 0
local notificationIds = {
	Airdrop = 0,
	Crate = 0,
}

local airdropAnimator = guiAnimator.new(airdropFrame, "PopIn")
local crateAnimator = guiAnimator.new(crateFrame, "PopIn")

local function trackBanana(instance: Instance)
	if not instance:IsA("Model") then
		return
	end

	if not rotatingBananaConnections[instance] then
		rotatingBananaConnections[instance] = instance:GetAttributeChangedSignal("Rotates"):Connect(function()
			trackBanana(instance)
		end)
	end

	if instance:GetAttribute("Rotates") == true then
		rotatingBananas[instance] = {
			origin = instance:GetPivot(),
			phase = RNG:NextNumber(0, math.pi * 2),
			startedAt = animationTime,
		}
	else
		rotatingBananas[instance] = nil
	end
end

local function updateIdleAnimations(deltaTime: number)
	animationTime += deltaTime

	for banana, animation in pairs(rotatingBananas) do
		if not banana.Parent or banana:GetAttribute("Rotates") ~= true or collectingBananas[banana] then
			rotatingBananas[banana] = nil
			continue
		end

		local verticalOffset = math.sin(animationTime * BOB_SPEED + animation.phase) * BOB_HEIGHT
		local rotation = CFrame.Angles(0, (animationTime - animation.startedAt) * ROTATION_SPEED, 0)
		local position = animation.origin.Position + Vector3.yAxis * verticalOffset
		banana:PivotTo(CFrame.new(position) * rotation * animation.origin.Rotation)
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
	textLabel.TextTransparency = 0
	textLabel.TextStrokeTransparency = 0
	textLabel.ZIndex = 100
	textLabel.Visible = true

	return textLabel
end

local function showUICollect(position: Vector3, points: number)
	local text = createText(points)
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Parent = matchGui
	table.insert(collectionPopups, {
		label = text,
		worldPosition = position,
		elapsed = 0,
	})
end

local function updateCollectionPopups(deltaTime: number)
	local camera = workspace.CurrentCamera

	for index = #collectionPopups, 1, -1 do
		local popup = collectionPopups[index]
		popup.elapsed += deltaTime

		if popup.elapsed >= POP_LIFETIME or not popup.label.Parent then
			popup.label:Destroy()
			table.remove(collectionPopups, index)
			continue
		end

		if not camera then
			popup.label.Visible = false
			continue
		end

		local screenPosition: Vector3
		local isOnScreen: boolean
		if matchGui.IgnoreGuiInset then
			screenPosition, isOnScreen = camera:WorldToViewportPoint(popup.worldPosition)
		else
			screenPosition, isOnScreen = camera:WorldToScreenPoint(popup.worldPosition)
		end

		local progress = popup.elapsed / POP_LIFETIME
		local fadeProgress = math.clamp(
			(popup.elapsed - POP_FADE_DELAY) / (POP_LIFETIME - POP_FADE_DELAY),
			0,
			1
		)
		popup.label.Visible = isOnScreen and screenPosition.Z > 0
		popup.label.Position = UDim2.fromOffset(screenPosition.X, screenPosition.Y - POP_DISTANCE * progress)
		popup.label.TextTransparency = fadeProgress
		popup.label.TextStrokeTransparency = fadeProgress
	end
end

local function changeBananaText(matchFolder: Folder)
	local points = 0
	for _, instance in ipairs(matchFolder:GetChildren()) do
		if instance:IsA("StringValue") then
			points += tonumber(instance.Value) or 0
		end
	end

	bananaText.Text = tostring(points)

	if points <= 0 then
		bananaFrame.Visible = false
	else
		bananaFrame.Visible = true
	end
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
	bananaFrame.Visible = false

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
				if data.sound then
					soundUtils.playSpatialData(data.sound, position)
				end

				if collector == player then
					showUICollect(position, points)
				end
			end
		end
	end)

	collectionService:GetInstanceAddedSignal(BANANA_TAG):Connect(trackBanana)
	collectionService:GetInstanceRemovedSignal(BANANA_TAG):Connect(function(instance)
		if instance:IsA("Model") then
			rotatingBananas[instance] = nil
			local connection = rotatingBananaConnections[instance]
			if connection then
				connection:Disconnect()
				rotatingBananaConnections[instance] = nil
			end
		end
	end)

	for _, instance in ipairs(collectionService:GetTagged(BANANA_TAG)) do
		trackBanana(instance)
	end

	runService.PreRender:Connect(function(deltaTime)
		updateIdleAnimations(deltaTime)
		updateCollectionAnimations(deltaTime)
		updateCollectionPopups(deltaTime)
	end)

	local matchFolder = player:FindFirstChild("MatchBananas")
	if matchFolder then
		connectMatchFolder(matchFolder)
	end
	player.ChildAdded:Connect(connectMatchFolder)
end

return Controller
