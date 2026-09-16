--!strict

local replicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local tweenService = game:GetService("TweenService")

local shared = replicatedStorage:WaitForChild("Shared")
local matchEvent: RemoteEvent = shared:WaitForChild("Events"):WaitForChild("MatchEvent")

type MatchEventData = {
	phase: string?,
	seconds: number?,
	map: Model?,
}

local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local matchGui = playerGui:WaitForChild("MatchGui") :: ScreenGui

local mainFrame = matchGui:WaitForChild("MainFrame") :: Frame
local mainText = mainFrame:WaitForChild("TextLabel") :: TextLabel
local uiScale: UIScale = mainFrame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
if uiScale.Parent == nil then
	uiScale.Scale = 1
	uiScale.Parent = mainFrame
end

local textInfo = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true)

local centralScaleTween = tweenService:Create(uiScale, textInfo, { Scale = 1.5 })
local rotateTween = tweenService:Create(mainText, textInfo, { Rotation = mainText.Rotation + 10 })

local texts: { [string]: string } = {
	Intermission = "Collecting bananas in: ",
	MatchStarting = "",
	Match = "Seconds to end: ",
}

local matchController = {}

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

	matchEvent.OnClientEvent:Connect(function(data: MatchEventData)
		local phase = data.phase
		local seconds = data.seconds
		local _map = data.map

		local text = phase and texts[phase]
		if text and seconds then
			local countdown = if phase == "MatchStarting" then tostring(seconds) else formatCountdown(seconds)
			local concatenedText = text .. countdown
			mainText.Text = concatenedText

			if phase == "MatchStarting" then
				if not mainFrame:GetAttribute("OldPos") then
					mainFrame:SetAttribute("OldPos", mainFrame.Position)
				end

				mainFrame.Position = UDim2.fromScale(0.5, 0.5)
				centralScaleTween:Play()
				rotateTween:Play()
			else
				local oldPos = mainFrame:GetAttribute("OldPos")
				if typeof(oldPos) == "UDim2" then
					mainFrame.Position = oldPos
				end

				mainFrame:SetAttribute("OldPos", nil)
			end
		end
	end)
end

return matchController