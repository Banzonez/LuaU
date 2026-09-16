--!strict

local ContextActionService = game:GetService("ContextActionService")
local replicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = replicatedStorage:WaitForChild("Shared")
local eventsFolder = sharedFolder:WaitForChild("Events")
local inputEvent = eventsFolder:WaitForChild("InputEvent") :: RemoteEvent

local ACTION_NAME = "Punch"
local initialized = false

local inputController = {}

local function handlePunch(
	_actionName: string,
	inputState: Enum.UserInputState,
	_inputObject: InputObject
): Enum.ContextActionResult
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

	ContextActionService:BindAction(ACTION_NAME, handlePunch, true, Enum.UserInputType.MouseButton1)
	ContextActionService:SetTitle(ACTION_NAME, "Punch")
end

return inputController
