--!strict

local combat = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local events = ReplicatedStorage:WaitForChild("Events")
local combatEvent = events:WaitForChild("CombatEvent")

assert(combatEvent:IsA("RemoteEvent"), "CombatEvent must be a RemoteEvent.")

local validInputs: { [EnumItem]: boolean } = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

local function inputBegan(input: InputObject, gameProcessedEvent: boolean): ()
	if gameProcessedEvent or not player.Character then
		return
	end

	local inputKey = if validInputs[input.UserInputType] then input.UserInputType else nil
	if inputKey then
		combatEvent:FireServer("Clicks", inputKey)
	end
end

combat.init = function(): ()
	UserInputService.InputBegan:Connect(inputBegan)
end

return combat
