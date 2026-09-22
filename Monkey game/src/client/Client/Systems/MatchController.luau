local contentProvider = game:GetService("ContentProvider")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

local shared = replicatedStorage:WaitForChild("Shared")
local matchEvent: RemoteEvent = shared:WaitForChild("Events"):WaitForChild("MatchEvent")
local soundUtils = require(shared:WaitForChild("Utils"):WaitForChild("SoundUtils"))
local guiAnimator = require(script.Parent.Parent.Utils.GuiAnimator)
local countdownImagesFolder = replicatedStorage:WaitForChild("Assets"):WaitForChild("CountdownImages")

type MatchEventData = {
	action: string?,
	soundName: string?,
	position: Vector3?,
	phase: string?,
	seconds: number?,
	map: Model?,
}

local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local matchGui = playerGui:WaitForChild("MatchGui") :: ScreenGui

local mainFrame = matchGui:WaitForChild("MainFrame") :: Frame
local mainText = mainFrame:WaitForChild("TextLabel") :: TextLabel
local GO_TWEEN_DURATION = 2
local CENTER_POSITION = UDim2.fromScale(0.5, 0.5)
local GO_START_POSITION = UDim2.fromScale(0, 0.5)
local GO_END_POSITION = UDim2.fromScale(1, 0.5)

local countdownImages: { [string]: GuiObject } = {}
local countdownAnimators: { [GuiObject]: any } = {}
local activeCountdownImage: GuiObject?
local goTween: Tween?

for _, imageName in ipairs({ "1", "2", "3", "GO" }) do
	local image = countdownImagesFolder:WaitForChild(imageName):Clone() :: GuiObject
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = CENTER_POSITION
	image.Visible = false
	image.Parent = nil
	countdownImages[imageName] = image
	if imageName ~= "GO" then
		countdownAnimators[image] = guiAnimator.new(image, "PopIn", {
			Duration = 0.2,
			StartScale = Vector2.new(0.8, 0.8),
			ShowSound = nil,
			HideSound = nil,
		})
	end
end

local texts: { [string]: string } = {
	Intermission = "Collecting bananas in: ",
	MatchStarting = "",
	Match = "Seconds to end: ",
}

local matchController = {}

local function hideCountdownImage(keepGoMoving: boolean?)
	if keepGoMoving and goTween and goTween.PlaybackState == Enum.PlaybackState.Playing then
		mainText.Visible = true
		return
	end

	local tween = goTween
	goTween = nil
	if tween then
		tween:Cancel()
	end

	if activeCountdownImage then
		local animator = countdownAnimators[activeCountdownImage]
		if animator then
			animator:Stop()
		else
			activeCountdownImage.Visible = false
		end
		activeCountdownImage.Parent = nil
		activeCountdownImage = nil
	end

	mainText.Visible = true
end

local function showCountdownImage(imageName: string)
	local image = countdownImages[imageName]
	if activeCountdownImage ~= image then
		hideCountdownImage()
		activeCountdownImage = image
	end

	mainText.Visible = false
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = CENTER_POSITION
	image.BackgroundTransparency = 1
	if image:IsA("ImageLabel") or image:IsA("ImageButton") then
		image.ImageTransparency = 0
	end
	image.Parent = matchGui
	countdownAnimators[image]:Show()
end

local function showGoImage()
	hideCountdownImage()

	local image = countdownImages.GO
	activeCountdownImage = image
	mainText.Visible = false
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = GO_START_POSITION
	image.BackgroundTransparency = 1
	if image:IsA("ImageLabel") or image:IsA("ImageButton") then
		image.ImageTransparency = 0
	end
	image.Visible = true
	image.Parent = matchGui

	local tween = tweenService:Create(
		image,
		TweenInfo.new(GO_TWEEN_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
		{ Position = GO_END_POSITION }
	)
	goTween = tween
	tween.Completed:Once(function()
		if goTween ~= tween then
			return
		end

		goTween = nil
		if activeCountdownImage == image then
			image.Visible = false
			image.Parent = nil
			activeCountdownImage = nil
		end
		mainText.Visible = true
	end)
	tween:Play()
end

local function formatCountdown(totalSeconds: number): string
	totalSeconds = math.max(math.floor(totalSeconds), 0)

	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local seconds = totalSeconds % 60

	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, seconds)
	end

	return string.format("%02d:%02d", minutes, seconds)
end

matchController.init = function()
	matchGui.Enabled = true
	hideCountdownImage()
	task.spawn(contentProvider.PreloadAsync, contentProvider, countdownImagesFolder:GetChildren())

	matchEvent.OnClientEvent:Connect(function(data: MatchEventData)
		if data.action == "PlaySound" and data.soundName then
			soundUtils.play(data.soundName)
			return
		end
		if data.action == "PlaySpatialSound" and data.soundName and data.position then
			soundUtils.playSpatial(data.soundName, data.position)
			return
		end
		local phase = data.phase
		local seconds = data.seconds
		local _map = data.map

		local text = phase and texts[phase]
		if not text or seconds == nil then
			return
		end

		if phase == "MatchStarting" then
			if data.soundName then
				soundUtils.play(data.soundName)
			end
			if seconds > 0 then
				showCountdownImage(tostring(seconds))
			else
				showGoImage()
			end
			return
		end

		hideCountdownImage(phase == "Match")
		mainText.Text = text .. formatCountdown(seconds)
	end)
end

return matchController
