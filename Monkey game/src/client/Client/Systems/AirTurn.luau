local runService = game:GetService("RunService")
local players = game:GetService("Players")

local player = players.LocalPlayer
local gameSettings = UserSettings().GameSettings

local AIR_TURN_RATE = math.rad(900)
local AIR_TURN_GAIN = 10
local AIR_TURN_ACCELERATION = math.rad(9000)
local AIR_TURN_MAX_TORQUE = 10000000
local MINIMUM_JUMPING_DURATION = 0.1
local MINIMUM_MOVE_DIRECTION_MAGNITUDE = 0.001

local airTurn = {}

function airTurn.enable(humanoid: Humanoid): () -> ()
	assert(runService:IsClient(), "AirTurn.enable must be called from the client")

	local character = humanoid.Parent
	assert(character and character:IsA("Model"), "The humanoid must be parented to a character model.")

	local rootPart = character:WaitForChild("HumanoidRootPart")
	assert(rootPart:IsA("BasePart"), "The character's HumanoidRootPart must be a BasePart.")
	local humanoidRootPart = rootPart :: BasePart

	local airTurnAttachment = Instance.new("Attachment")
	airTurnAttachment.Name = "AirTurnAttachment"
	airTurnAttachment.Parent = humanoidRootPart

	local airTurnAngularVelocity = Instance.new("AngularVelocity")
	airTurnAngularVelocity.Name = "AirTurnAngularVelocity"
	airTurnAngularVelocity.Attachment0 = airTurnAttachment
	airTurnAngularVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	airTurnAngularVelocity.MaxTorque = AIR_TURN_MAX_TORQUE
	airTurnAngularVelocity.Enabled = false
	airTurnAngularVelocity.Parent = humanoidRootPart

	local enabled = true
	local connections: { RBXScriptConnection } = {}
	local autoRotateBeforeAir: boolean? = nil
	local currentState = humanoid:GetState()
	local jumpingStartedAt: number? = if currentState == Enum.HumanoidStateType.Jumping then os.clock() else nil
	local jumpQualified = false

	local function setAirTurnEnabled(shouldEnable: boolean)
		if shouldEnable and not airTurnAngularVelocity.Enabled then
			autoRotateBeforeAir = humanoid.AutoRotate
			humanoid.AutoRotate = false
			airTurnAngularVelocity.Enabled = true
		elseif not shouldEnable and airTurnAngularVelocity.Enabled then
			airTurnAngularVelocity.Enabled = false
			airTurnAngularVelocity.AngularVelocity = Vector3.zero
			if humanoidRootPart.Parent then
				local angularVelocity = humanoidRootPart.AssemblyAngularVelocity
				humanoidRootPart.AssemblyAngularVelocity = Vector3.new(angularVelocity.X, 0, angularVelocity.Z)
			end
		end

		if not shouldEnable and autoRotateBeforeAir ~= nil and humanoid.Parent then
			if humanoid.Health > 0 and not humanoid.PlatformStand then
				humanoid.AutoRotate = autoRotateBeforeAir
			end
			autoRotateBeforeAir = nil
		end
	end

	local function updateAirTurn(deltaTime: number)
		if currentState == Enum.HumanoidStateType.Jumping and jumpingStartedAt then
			jumpQualified = jumpQualified or os.clock() - jumpingStartedAt >= MINIMUM_JUMPING_DURATION
		end

		local isAirborne = currentState == Enum.HumanoidStateType.Jumping
			or currentState == Enum.HumanoidStateType.Freefall
		local cameraControlsRotation = gameSettings.RotationType == Enum.RotationType.CameraRelative
		if not isAirborne or not jumpQualified or cameraControlsRotation or humanoid.PlatformStand or humanoid.Health <= 0 then
			setAirTurnEnabled(false)
			return
		end

		local moveDirection = humanoid.MoveDirection
		local horizontalMoveDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z)
		local lookDirection = humanoidRootPart.CFrame.LookVector
		local horizontalLookDirection = Vector3.new(lookDirection.X, 0, lookDirection.Z)
		if
			horizontalMoveDirection.Magnitude < MINIMUM_MOVE_DIRECTION_MAGNITUDE
			or horizontalLookDirection.Magnitude < MINIMUM_MOVE_DIRECTION_MAGNITUDE
		then
			setAirTurnEnabled(false)
			return
		end

		local facingDirection = horizontalLookDirection.Unit
		local targetDirection = horizontalMoveDirection.Unit
		local yawError = math.atan2(facingDirection:Cross(targetDirection).Y, facingDirection:Dot(targetDirection))
		local desiredTurnRate = math.clamp(yawError * AIR_TURN_GAIN, -AIR_TURN_RATE, AIR_TURN_RATE)
		local currentTurnRate = airTurnAngularVelocity.AngularVelocity.Y
		local maxRateChange = AIR_TURN_ACCELERATION * deltaTime
		local turnRate = currentTurnRate + math.clamp(desiredTurnRate - currentTurnRate, -maxRateChange, maxRateChange)
		airTurnAngularVelocity.AngularVelocity = Vector3.yAxis * turnRate
		setAirTurnEnabled(true)
	end

	local function disable()
		if not enabled then
			return
		end

		enabled = false
		setAirTurnEnabled(false)
		airTurnAngularVelocity:Destroy()
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
			if newState == Enum.HumanoidStateType.Jumping then
				jumpingStartedAt = os.clock()
				jumpQualified = false
				setAirTurnEnabled(false)
			elseif newState == Enum.HumanoidStateType.Freefall then
				if jumpingStartedAt then
					jumpQualified = jumpQualified or os.clock() - jumpingStartedAt >= MINIMUM_JUMPING_DURATION
				end
			else
				jumpingStartedAt = nil
				jumpQualified = false
				setAirTurnEnabled(false)
			end
		end)
	)

	table.insert(connections, runService.PreSimulation:Connect(updateAirTurn))
	table.insert(connections, humanoid.Died:Connect(disable))
	table.insert(connections, humanoid.Destroying:Connect(disable))

	return disable
end

local disableAirTurn: (() -> ())? = nil

local function onCharacterAdded(character: Model)
	if disableAirTurn then
		disableAirTurn()
	end

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	if player.Character ~= character then
		return
	end

	disableAirTurn = airTurn.enable(humanoid)
end

function airTurn.init()
	player.CharacterAdded:Connect(onCharacterAdded)

	if player.Character then
		onCharacterAdded(player.Character)
	end
end

return airTurn
