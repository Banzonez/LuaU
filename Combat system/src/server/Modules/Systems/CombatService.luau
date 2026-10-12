--!strict

local combatService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local events = ReplicatedStorage:FindFirstChild("Events")
if not events then
	events = Instance.new("Folder")
	events.Name = "Events"
	events.Parent = ReplicatedStorage
end

local combatEvent = events:FindFirstChild("CombatEvent")
if not combatEvent then
	combatEvent = Instance.new("RemoteEvent")
	combatEvent.Name = "CombatEvent"
	combatEvent.Parent = events
end

assert(combatEvent:IsA("RemoteEvent"), "CombatEvent must be a RemoteEvent.")

local animationsFolder = ReplicatedStorage:FindFirstChild("AnimationsIds")
local BASIC_STYLE_ANIMATIONS = "MuayThai"
if not animationsFolder then
	warn("AnimationsIds folder was not found in ReplicatedStorage.")
end

local utilsFolder = ServerScriptService:WaitForChild("Server"):WaitForChild("Modules"):WaitForChild("Utils")
local Systems = script.Parent
local CombatSetup = require(Systems:WaitForChild("CombatSetup"))
local CombatStateHandler = require(Systems:WaitForChild("CombatStateHandler"))
local CombatUtil = require(utilsFolder:WaitForChild("CombatUtil"))

local validClickInputs: { [EnumItem]: boolean } = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
	[Enum.KeyCode.Space] = true,
}

local function getAnimation(styleName: string, animationName: string): Animation?
	animationsFolder = animationsFolder or ReplicatedStorage:FindFirstChild("AnimationsIds")
	if not animationsFolder then
		return nil
	end

	local styleAnimations = animationsFolder:FindFirstChild(styleName)
	local animation = styleAnimations and styleAnimations:FindFirstChild(animationName)
	if animation and animation:IsA("Animation") then
		return animation
	end

	local basicAnimations = animationsFolder:FindFirstChild(BASIC_STYLE_ANIMATIONS)
	animation = basicAnimations and basicAnimations:FindFirstChild(animationName)
	if animation and animation:IsA("Animation") then
		return animation
	end

	return nil
end

local function isValidClickRequest(action: unknown, inputKey: unknown): boolean
	return action == "Clicks" and typeof(inputKey) == "EnumItem" and validClickInputs[inputKey :: EnumItem] == true
end

local function handleClick(player: Player, isSpaceClicked: boolean): ()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local playerState = CombatStateHandler:GetPlayerState(player)
	if playerState.State == "Stunned" or playerState.State == "UsingAbility" or playerState.State == "UsingUlt" then
		return
	end

	if isSpaceClicked then
		playerState.LastSpacePressed = os.clock()
		return
	end

	local currentTime = os.clock()
	if currentTime < playerState.NextClickTime then
		return
	end

	local playerObj = CombatSetup:GetPlayerObj(player) or CombatSetup:CreateObj(player)
	local settings = playerObj.Settings

	if currentTime > playerState.ComboExpiresAt then
		playerState.ClickCombo = 0
	end

	local clickCombo = playerState.ClickCombo + 1
	if clickCombo > settings.ClicksToFinishCombo then
		clickCombo = 1
	end

	local isUppercut = playerState.LastSpacePressed > 0 and currentTime - playerState.LastSpacePressed <= 0.1
	local animationName = if isUppercut then "Uppercut" else "Click" .. clickCombo
	local animation = getAnimation(playerObj.Style.StyleName, animationName)
	if not animation and isUppercut then
		isUppercut = false
		animationName = "Click" .. clickCombo
		animation = getAnimation(playerObj.Style.StyleName, animationName)
	end

	if not animation then
		warn("Missing " .. animationName .. " animation.")
		return
	end

	local animationDuration = CombatUtil.getAnimationDuration(player, animation)
	if not animationDuration then
		return
	end

	local isFinisher = clickCombo == settings.ClicksToFinishCombo
	local extraCooldown = if isFinisher then settings.ClickComboCooldown else settings.ClickCooldown
	local stunBuffer = if isFinisher then settings.LastClickStunTime else settings.ClickStunTime

	playerState.ClickCombo = if isFinisher then 0 else clickCombo
	playerState.ComboExpiresAt = currentTime + settings.ComboResetTime
	playerState.NextClickTime = currentTime + animationDuration + extraCooldown

	-- The attacker stays in this state until the current animation finishes.
	CombatStateHandler:SetTemporaryState(player, "Attacking", animationDuration)

	local played = CombatUtil.playClickAnimation(
		player,
		animation,
		settings.MAX_ANGLE_DEGREES,
		settings.ClickDamage,
		animationDuration + stunBuffer,
		settings.Attacks[animationName] or settings.Attacks.Click1
	)

	if not played then
		playerState.ClickCombo = 0
		playerState.NextClickTime = currentTime
		playerState.ComboExpiresAt = 0
	elseif isUppercut then
		playerState.LastUppercut = currentTime
	end
end

combatService.init = function(): ()
	if animationsFolder then
		CombatUtil.preloadAnimations(animationsFolder)
	end

	combatEvent.OnServerEvent:Connect(function(player: Player, action: unknown, inputKey: unknown)
		if not isValidClickRequest(action, inputKey) then
			return
		end

		handleClick(player, inputKey == Enum.KeyCode.Space)
	end)
end

return combatService
