--!strict

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local DoubleJump = {}

local JUMP_RELEASE_FRAMES = 8

local RESET_STATES = {
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Landed] = true,
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Swimming] = true,
}

export type Cleanup = () -> ()

local function canDoubleJump(humanoid: Humanoid): boolean
	return humanoid.Health > 0
		and humanoid.FloorMaterial == Enum.Material.Air
		and humanoid:GetState() == Enum.HumanoidStateType.Freefall
end

function DoubleJump.Enable(humanoid: Humanoid): Cleanup
	assert(RunService:IsClient(), "DoubleJump.Enable must be called from the client")

	local doubleJumpAvailable = false
	local doubleJumpUsed = false
	local firstJumpStarted = false
	local enabled = true
	local jumpRequestedThisFrame = false
	local jumpRequestActive = false
	local releasedFrames = 0
	local connections: { RBXScriptConnection } = {}

	local function disable()
		if not enabled then
			return
		end

		enabled = false

		for _, connection in pairs(connections) do
			connection:Disconnect()
		end

		table.clear(connections)
	end

	table.insert(connections, humanoid.StateChanged:Connect(function(_, newState)
		if RESET_STATES[newState] then
			doubleJumpAvailable = false
			doubleJumpUsed = false
			firstJumpStarted = false
		elseif newState == Enum.HumanoidStateType.Jumping and not doubleJumpUsed then
			firstJumpStarted = true
		end
	end))

	local function processJumpRequest()
		if not doubleJumpAvailable or doubleJumpUsed or not canDoubleJump(humanoid) then
			return
		end

		doubleJumpAvailable = false
		doubleJumpUsed = true
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	table.insert(connections, UserInputService.JumpRequest:Connect(function()
		jumpRequestedThisFrame = true
	end))

	table.insert(connections, RunService.PostSimulation:Connect(function()
		if jumpRequestedThisFrame then
			releasedFrames = 0

			if not jumpRequestActive then
				jumpRequestActive = true
				processJumpRequest()
			end
		elseif jumpRequestActive then
			releasedFrames += 1

			if releasedFrames >= JUMP_RELEASE_FRAMES then
				jumpRequestActive = false
				releasedFrames = 0
				doubleJumpAvailable = firstJumpStarted and not doubleJumpUsed
			end
		end

		jumpRequestedThisFrame = false
	end))

	table.insert(connections, humanoid.Died:Connect(disable))
	table.insert(connections, humanoid.Destroying:Connect(disable))

	return disable
end

local disableDoubleJump: Cleanup? = nil

local function onCharacterAdded(character: Model)
	if disableDoubleJump then
		disableDoubleJump()
	end

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	disableDoubleJump = DoubleJump.Enable(humanoid)
end

DoubleJump.init = function()
	player.CharacterAdded:Connect(onCharacterAdded)

	if player.Character then
		onCharacterAdded(player.Character)
	end
end

return DoubleJump
