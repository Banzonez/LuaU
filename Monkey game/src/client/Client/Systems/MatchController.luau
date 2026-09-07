local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MatchEvent: RemoteEvent = Shared:WaitForChild("Events"):WaitForChild("MatchEvent")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local MatchGui: ScreenGui? = PlayerGui:WaitForChild("MatchGui")
assert(MatchGui, "MatchGui doesn't exist.")

local MainFrame = MatchGui:WaitForChild("MainFrame")
local MainText: TextLabel = MainFrame.TextLabel
local UIScale = MainFrame:FindFirstChildOfClass("UIScale")
if not UIScale then
	UIScale = Instance.new("UIScale")
	UIScale.Scale = 1
	UIScale.Parent = MainFrame
end

local textInfo = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true)
local textPopUpIntervale = 0.002

local scaleTween = TweenService:Create(UIScale, textInfo, { Scale = 1.2 })
local centralScaleTween = TweenService:Create(UIScale, textInfo, { Scale = 1.5 })
local rotateTween = TweenService:Create(MainText, textInfo, { Rotation = MainText.Rotation + 10 })

local texts = {
	Intermission = "Collecting bananas in: ",
	MatchStarting = "",
	Match = "Seconds to end: ",
}

local matchController = {}

matchController.init = function()
	MatchGui.Enabled = true

	MatchEvent.OnClientEvent:Connect(function(data)
		-- map can be used for specific visual for each map, or other things
		local phase = data.phase
		local seconds = data.seconds
		local _map = data.map

		local text = texts[phase]
		if text then
			local concatenedText = text .. tostring(seconds)
               local processText = ""
               
			task.spawn(function()
				for i = 1, string.len(concatenedText) do
					local newChar = string.sub(concatenedText, i, i)
					processText = processText .. newChar

					MainText.Text = processText
					task.wait(textPopUpIntervale)
				end
			end)

			if phase == "MatchStarting" then
                    if not MainFrame:GetAttribute("OldPos") then
				     MainFrame:SetAttribute("OldPos", MainFrame.Position)
                    end

				MainFrame.Position = UDim2.fromScale(0.5, 0.5)
				centralScaleTween:Play()
			else
				local oldPos = MainFrame:GetAttribute("OldPos")
				if oldPos then
					MainFrame.Position = oldPos
				end

				MainFrame:SetAttribute("OldPos", nil)
				scaleTween:Play()
			end

			rotateTween:Play()
		end
	end)
end

return matchController
