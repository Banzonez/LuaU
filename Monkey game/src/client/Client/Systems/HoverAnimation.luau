local tweenService = game:GetService("TweenService")
local players = game:GetService("Players")

local player = players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local tweenInfo = TweenInfo.new(
	0.25,
	Enum.EasingStyle.Quint,
	Enum.EasingDirection.Out
)

local SIZE_OFFSET = 15

local activeTweens: { [GuiButton]: Tween } = {}

local hoverSound = Instance.new("Sound")
hoverSound.Looped = false
hoverSound.SoundId = "rbxassetid://107511012621133"
hoverSound.Parent = script

local function stopTween(gui: GuiButton)
	local tween = activeTweens[gui]

	if tween then
		tween:Cancel()
		activeTweens[gui] = nil
	end
end

local function animate(gui: GuiButton, targetSize: UDim2)
	stopTween(gui)

	local tween = tweenService:Create(gui, tweenInfo, {
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

local function setupButton(button: Instance)
	if not button:IsA("GuiButton") then
		return
	end

	if button:GetAttribute("HoverSetup") then
		return
	end

	button:SetAttribute("HoverSetup", true)

	local normalSize = button.Size
	local hoverSize = normalSize + UDim2.fromOffset(SIZE_OFFSET, SIZE_OFFSET)

	local function resetButton()
		animate(button, normalSize)
		button:SetAttribute("Hovered", false)
	end
	
	button.MouseEnter:Connect(function()
		button:SetAttribute("Hovered", true)
		animate(button, hoverSize)
	end)

	button.MouseLeave:Connect(function()
		resetButton()
	end)
end

local hoverAnimation = {}

function hoverAnimation.init()
	for _, gui in ipairs(playerGui:GetDescendants()) do
		setupButton(gui)
	end

	playerGui.DescendantAdded:Connect(setupButton)
end

return hoverAnimation
