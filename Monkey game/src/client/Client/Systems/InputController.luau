local contextActionService = game:GetService("ContextActionService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local userInputService = game:GetService("UserInputService")

local sharedFolder = replicatedStorage:WaitForChild("Shared")
local eventsFolder = sharedFolder:WaitForChild("Events")
local inputEvent = eventsFolder:WaitForChild("InputEvent") :: RemoteEvent
local soundUtils = require(sharedFolder:WaitForChild("Utils"):WaitForChild("SoundUtils"))

local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("MobileSlap")
local button: ImageButton = gui:WaitForChild("Mobile slap tool")

local ACTION_NAME = "Punch"
local PUNCH_COOLDOWN = 0.6
local initialized = false
local isMobile = userInputService.TouchEnabled
	and not (userInputService.MouseEnabled and userInputService.KeyboardEnabled)
local lastSwingTime = 0

local inputController = {}

local function playLocalSwingSound()
	local now = os.clock()
	if now - lastSwingTime < PUNCH_COOLDOWN then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	lastSwingTime = now
	soundUtils.playSpatial(soundUtils.names.slapSwing, rootPart.Position)
end

local function handlePunch(_, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		playLocalSwingSound()
		inputEvent:FireServer(ACTION_NAME)
	end

	return Enum.ContextActionResult.Sink
end

function inputController.init()
	if initialized then
		return
	end
	initialized = true

	if not isMobile then
		button.Visible = false
		contextActionService:BindAction(ACTION_NAME, handlePunch, true, Enum.UserInputType.MouseButton1)
		contextActionService:SetTitle(ACTION_NAME, "Punch")
		return
	end

	button.Activated:Connect(function()
		handlePunch(ACTION_NAME, Enum.UserInputState.Begin)
	end)
end

return inputController
