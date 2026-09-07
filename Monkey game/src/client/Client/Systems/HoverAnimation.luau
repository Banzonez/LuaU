local module = {}

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local PlayerGui = player:WaitForChild("PlayerGui")

local tweenInfo = TweenInfo.new(
	0.25,
	Enum.EasingStyle.Quint,
	Enum.EasingDirection.Out
)

local sizeOffset = 15

local activeTweens = {}

local hoverSound = Instance.new("Sound")
hoverSound.Looped = false
hoverSound.SoundId = "rbxassetid://107511012621133"
hoverSound.Parent = script

local function stopTween(gui)
	local tween = activeTweens[gui]

	if tween then
		tween:Cancel()
		activeTweens[gui] = nil
	end
end

local function animate(gui, targetSize)
	stopTween(gui)

	local tween = TweenService:Create(gui, tweenInfo, {
		Size = targetSize
	})

	activeTweens[gui] = tween

	tween.Completed:Connect(function()
		if activeTweens[gui] == tween then
			activeTweens[gui] = nil
		end
	end)
	
	hoverSound:Play()
	tween:Play()
end

local function setupButton(button)
	if not button:IsA("GuiButton") then
		return
	end

	if button:GetAttribute("HoverSetup") then
		return
	end

	button:SetAttribute("HoverSetup", true)

	local normalSize = button.Size
	local hoverSize = normalSize + UDim2.fromOffset(sizeOffset, sizeOffset)
	
	local bindableEvent = Instance.new("BindableEvent")
	bindableEvent.Parent = button
	bindableEvent.Name = "HoverEvent"
	
	bindableEvent.Event:Connect(function(...) 
		animate(button, normalSize)
		button:SetAttribute("Hovered", false)
	end)
	
	button.MouseEnter:Connect(function()
		button:SetAttribute("Hovered", true)
		animate(button, hoverSize)
	end)

	button.MouseLeave:Connect(function()
		bindableEvent:Fire()
	end)
end

function module.init()
	for _, gui in pairs(PlayerGui:GetDescendants()) do
		setupButton(gui)
	end

	PlayerGui.DescendantAdded:Connect(setupButton)
end

return module
