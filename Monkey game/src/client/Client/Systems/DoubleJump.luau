local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")

local player = players.LocalPlayer

local assets = replicatedStorage:WaitForChild("Assets")
local jumpVfx = assets:WaitForChild("AirJumpVFX")
local jumpVfxTemplate = jumpVfx :: BasePart

local doubleJump = {}

local JUMP_RELEASE_FRAMES = 8
local AIR_TURN_RATE = math.rad(1800)
local AIR_TURN_RESPONSIVENESS = 80
local AIR_TURN_MAX_TORQUE = 100000
local MINIMUM_JUMPING_DURATION = 0.1
local MINIMUM_MOVE_DIRECTION_MAGNITUDE = 0.001

local RESET_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Landed] = true,
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Swimming] = true,
}

local AIR_ROTATION_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
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

	local rootPart = character:WaitForChild("HumanoidRootPart")
	assert(rootPart:IsA("BasePart"), "The character's HumanoidRootPart must be a BasePart.")
	local humanoidRootPart = rootPart :: BasePart

	local characterVfx = character:FindFirstChild(jumpVfxTemplate.Name)
	if not characterVfx or not characterVfx:IsA("BasePart") then
		characterVfx = newVfx(character)
	end
	local vfxPart = characterVfx :: BasePart
	local airTurnAttachment = Instance.new("Attachment")
	airTurnAttachment.Name = "AirTurnAttachment"
	airTurnAttachment.Parent = humanoidRootPart

	local airTurnAlignOrientation = Instance.new("AlignOrientation")
	airTurnAlignOrientation.Name = "AirTurnAlignOrientation"
	airTurnAlignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	airTurnAlignOrientation.AlignType = Enum.AlignType.AllAxes
	airTurnAlignOrientation.Attachment0 = airTurnAttachment
	airTurnAlignOrientation.MaxAngularVelocity = AIR_TURN_RATE
	airTurnAlignOrientation.MaxTorque = AIR_TURN_MAX_TORQUE
	airTurnAlignOrientation.Responsiveness = AIR_TURN_RESPONSIVENESS
	airTurnAlignOrientation.Enabled = false
	airTurnAlignOrientation.Parent = humanoidRootPart

	local autoRotateBeforeAir: boolean? = nil
	local currentState = humanoid:GetState()
	local jumpingAttemptId = 0

	local function setAirTurnEnabled(shouldEnable: boolean)
		if shouldEnable and not airTurnAlignOrientation.Enabled then
			autoRotateBeforeAir = humanoid.AutoRotate
			humanoid.AutoRotate = false
			airTurnAlignOrientation.Enabled = true
		elseif not shouldEnable and airTurnAlignOrientation.Enabled then
			airTurnAlignOrientation.Enabled = false
		end

		if not shouldEnable and autoRotateBeforeAir ~= nil and humanoid.Parent then
			humanoid.AutoRotate = autoRotateBeforeAir
			autoRotateBeforeAir = nil
		end
	end

	local function stopAirTurn(restoreAutoRotate: boolean)
		local wasTurning = airTurnAlignOrientation.Enabled
		setAirTurnEnabled(false)

		if wasTurning and restoreAutoRotate and humanoidRootPart.Parent then
			local angularVelocity = humanoidRootPart.AssemblyAngularVelocity
			humanoidRootPart.AssemblyAngularVelocity = Vector3.new(0, angularVelocity.Y, 0)
		end
	end

	local function updateAirTurn()
		if humanoid.PlatformStand or humanoid.Health <= 0 then
			setAirTurnEnabled(false)
			return
		end

		local shiftLockActive = userInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		setAirTurnEnabled(currentState == Enum.HumanoidStateType.Jumping or currentState == Enum.HumanoidStateType.Freefall)
		if shiftLockActive then
			setAirTurnEnabled(false)
		end
	end

	local function disable()
		if not enabled then
			return
		end

		enabled = false
		configuredContainers[vfxPart] = nil
		stopAirTurn(humanoid.Health > 0 and not humanoid.PlatformStand)
		airTurnAlignOrientation:Destroy()
		airTurnAttachment:Destroy()

		for _, connection in pairs(connections) do
			connection:Disconnect()
		end

		table.clear(connections)
	end

	table.insert(
		connections,
		humanoid.StateChanged:Connect(function(_, newState)
			currentState = newState
			if RESET_STATES[newState] then
				jumpingAttemptId += 1
				stopAirTurn(true)
				doubleJumpAvailable = false
				doubleJumpUsed = false
				firstJumpStarted = false
			elseif AIR_ROTATION_STATES[newState] then
				if newState == Enum.HumanoidStateType.Jumping then
					jumpingAttemptId += 1
					local attemptId = jumpingAttemptId
					task.delay(MINIMUM_JUMPING_DURATION, function()
						if enabled and attemptId == jumpingAttemptId and currentState == Enum.HumanoidStateType.Jumping then
							updateAirTurn()
						end
					end)
				end

				if newState == Enum.HumanoidStateType.Jumping and not doubleJumpUsed then
					firstJumpStarted = true
				end
			else
				stopAirTurn(false)
			end
		end)
	)

	table.insert(
		connections,
		runService.PreSimulation:Connect(function()
			updateAirTurn()
			if not airTurnAlignOrientation.Enabled then
				return
			end

			local moveDirection = humanoid.MoveDirection
			local horizontalMoveDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z)
			if horizontalMoveDirection.Magnitude < MINIMUM_MOVE_DIRECTION_MAGNITUDE then
				return
			end

			airTurnAlignOrientation.CFrame = CFrame.lookAt(Vector3.zero, horizontalMoveDirection.Unit)
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
