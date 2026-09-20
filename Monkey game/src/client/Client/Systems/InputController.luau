local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local replicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = replicatedStorage:WaitForChild("Shared")
local eventsFolder = sharedFolder:WaitForChild("Events")
local inputEvent = eventsFolder:WaitForChild("InputEvent") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("MobileSlap")
local button: ImageButton = gui:WaitForChild("Mobile slap tool")

local ACTION_NAME = "Punch"
local initialized = false
local isMobile = UserInputService.TouchEnabled
	and not (UserInputService.MouseEnabled and UserInputService.KeyboardEnabled)

local inputController = {}

local function handlePunch(_, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
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
		ContextActionService:BindAction(ACTION_NAME, handlePunch, true, Enum.UserInputType.MouseButton1)
		ContextActionService:SetTitle(ACTION_NAME, "Punch")
		return
	end

	button.Activated:Connect(function()
		handlePunch(ACTION_NAME, Enum.UserInputState.Begin)
	end)
end

return inputController
