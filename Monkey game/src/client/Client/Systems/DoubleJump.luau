--!strict

local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

local player = players.LocalPlayer

local assets = replicatedStorage:WaitForChild("Assets")
local jumpVfx = assets:WaitForChild("AirJumpVFX")
assert(jumpVfx:IsA("BasePart"), "ReplicatedStorage.Assets.AirJumpVFX must be a BasePart.")
local jumpVfxTemplate = jumpVfx :: BasePart

local doubleJump = {}

local JUMP_RELEASE_FRAMES = 8

local RESET_STATES: { [Enum.HumanoidStateType]: boolean } = {
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

local function newVfx(character: Model): BasePart
	local rootPart = character:WaitForChild("HumanoidRootPart")
	assert(rootPart:IsA("BasePart"), "The character's HumanoidRootPart must be a BasePart.")

	local vfx = jumpVfxTemplate:Clone()
	local boundingCFrame, boundingSize = character:GetBoundingBox()
	vfx.CFrame = CFrame.new(boundingCFrame.Position - Vector3.yAxis * (boundingSize.Y / 2)) * vfx.CFrame.Rotation
	vfx.Anchored = false
	vfx.CanCollide = false
	vfx.CanQuery = false
	vfx.CanTouch = false
	vfx.Massless = true
	vfx.Parent = character

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = vfx
	weld.Parent = vfx

	return vfx
end

local configuredContainers: { [Instance]: { ParticleEmitter } } = {}
local function emitVfx(container: Instance)
	local particleEmitters = configuredContainers[container]
	if not particleEmitters then
		particleEmitters = {}
		for _, instance in pairs(container:GetDescendants()) do
			if instance:IsA("ParticleEmitter") then
				table.insert(particleEmitters, instance)
			end
		end
		configuredContainers[container] = particleEmitters
	end

	for _, particle: ParticleEmitter in pairs(particleEmitters) do
		particle:Emit(1)
	end
end

function doubleJump.enable(humanoid: Humanoid): Cleanup
	assert(runService:IsClient(), "DoubleJump.enable must be called from the client")

	local doubleJumpAvailable = false
	local doubleJumpUsed = false
	local firstJumpStarted = false
	local enabled = true
	local jumpRequestedThisFrame = false
	local jumpRequestActive = false
	local releasedFrames = 0
	local connections: { RBXScriptConnection } = {}

	local character = humanoid.Parent
	assert(character and character:IsA("Model"), "The humanoid must be parented to a character model.")

	local characterVfx = character:FindFirstChild(jumpVfxTemplate.Name)
	if not characterVfx or not characterVfx:IsA("BasePart") then
		characterVfx = newVfx(character)
	end
	local vfxPart = characterVfx :: BasePart

	local function disable()
		if not enabled then
			return
		end

		enabled = false
		configuredContainers[vfxPart] = nil

		for _, connection in pairs(connections) do
			connection:Disconnect()
		end

		table.clear(connections)
	end

	table.insert(
		connections,
		humanoid.StateChanged:Connect(function(_, newState)
			if RESET_STATES[newState] then
				doubleJumpAvailable = false
				doubleJumpUsed = false
				firstJumpStarted = false
			elseif newState == Enum.HumanoidStateType.Jumping and not doubleJumpUsed then
				firstJumpStarted = true
			end
		end)
	)

	local function processJumpRequest()
		if not doubleJumpAvailable or doubleJumpUsed or not canDoubleJump(humanoid) then
			return
		end

		emitVfx(vfxPart)

		doubleJumpAvailable = false
		doubleJumpUsed = true
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end

	table.insert(
		connections,
		userInputService.JumpRequest:Connect(function()
			jumpRequestedThisFrame = true
		end)
	)

	table.insert(
		connections,
		runService.PostSimulation:Connect(function()
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
		end)
	)

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
	disableDoubleJump = doubleJump.enable(humanoid)
end

doubleJump.init = function()
	player.CharacterAdded:Connect(onCharacterAdded)

	if player.Character then
		onCharacterAdded(player.Character)
	end
end

return doubleJump
