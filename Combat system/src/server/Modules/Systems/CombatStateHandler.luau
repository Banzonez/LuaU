--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))

type StateHandler = {
	init: () -> (),
	GetPlayerState: (self: StateHandler, player: Player) -> Types.PlayerCombatState,
	SetTemporaryState: (self: StateHandler, player: Player, state: Types.CombatState, duration: number) -> (),
	StunHumanoid: (self: StateHandler, humanoid: Humanoid, duration: number) -> (),
}

type StunData = {
	WalkSpeed: number,
	JumpPower: number,
	JumpHeight: number,
	AutoRotate: boolean,
}

local playerStates: { [Player]: Types.PlayerCombatState } = {}
local stateTokens: { [Player]: number } = {}
local stunTokens: { [Humanoid]: number } = {}
local stunData: { [Humanoid]: StunData } = {}
local states = {} :: StateHandler

local function basicState(): Types.PlayerCombatState
	return {
		State = "Idle",
		ClickCombo = 0,
		NextClickTime = 0,
		ComboExpiresAt = 0,
		AbilitiesCooldowns = {},
		UltCooldowns = {},
	}
end

local function resetState(playerState: Types.PlayerCombatState): ()
	playerState.State = "Idle"
	playerState.ClickCombo = 0
	playerState.NextClickTime = 0
	playerState.ComboExpiresAt = 0
	table.clear(playerState.AbilitiesCooldowns)
	table.clear(playerState.UltCooldowns)
end

function states:GetPlayerState(player: Player): Types.PlayerCombatState
	local playerState = playerStates[player]
	if not playerState then
		playerState = basicState()
		playerStates[player] = playerState
	end

	return playerState
end

local function nextStateToken(player: Player): number
	local token = (stateTokens[player] or 0) + 1
	stateTokens[player] = token
	return token
end

function states:SetTemporaryState(player: Player, state: Types.CombatState, duration: number): ()
	local playerState = self:GetPlayerState(player)
	local token = nextStateToken(player)

	playerState.State = state

	task.delay(duration, function()
		if stateTokens[player] == token and playerState.State == state then
			playerState.State = "Idle"
		end
	end)
end

function states:StunHumanoid(humanoid: Humanoid, duration: number): ()
	if humanoid.Health <= 0 or not humanoid.Parent then
		return
	end

	local character = humanoid.Parent
	local player = if character:IsA("Model") then Players:GetPlayerFromCharacter(character) else nil
	local savedStun = stunData[humanoid]

	if not savedStun then
		savedStun = {
			WalkSpeed = humanoid.WalkSpeed,
			JumpPower = humanoid.JumpPower,
			JumpHeight = humanoid.JumpHeight,
			AutoRotate = humanoid.AutoRotate,
		}
		stunData[humanoid] = savedStun
	end

	local token = (stunTokens[humanoid] or 0) + 1
	stunTokens[humanoid] = token

	if player then
		local playerState = self:GetPlayerState(player)
		nextStateToken(player)
		playerState.State = "Stunned"
	end

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false

	task.delay(duration, function()
		if stunTokens[humanoid] ~= token then
			return
		end

		if player then
			local playerState = self:GetPlayerState(player)
			if playerState.State == "Stunned" then
				playerState.State = "Idle"
			end
		end

		local currentStun = stunData[humanoid]
		if currentStun and humanoid.Parent then
			humanoid.WalkSpeed = currentStun.WalkSpeed
			humanoid.JumpPower = currentStun.JumpPower
			humanoid.JumpHeight = currentStun.JumpHeight
			humanoid.AutoRotate = currentStun.AutoRotate
		end

		stunTokens[humanoid] = nil
		stunData[humanoid] = nil
	end)
end

local function setupPlayer(player: Player): ()
	states:GetPlayerState(player)

	player.CharacterAdded:Connect(function()
		nextStateToken(player)
		resetState(states:GetPlayerState(player))
	end)
end

states.init = function(): ()
	Players.PlayerAdded:Connect(setupPlayer)

	Players.PlayerRemoving:Connect(function(player)
		playerStates[player] = nil
		stateTokens[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end
end

return states
