local runService = game:GetService("RunService")
local players = game:GetService("Players")

local player = players.LocalPlayer
local gameSettings = UserSettings().GameSettings

local AIR_TURN_RATE = math.rad(1800)
local AIR_TURN_RESPONSIVENESS = 80
local AIR_TURN_MAX_TORQUE = 100000
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

	local enabled = true
	local connections: { RBXScriptConnection } = {}
	local autoRotateBeforeAir: boolean? = nil
	local currentState = humanoid:GetState()

	local function setAirTurnEnabled(shouldEnable: boolean)
		if shouldEnable and not airTurnAlignOrientation.Enabled then
			autoRotateBeforeAir = humanoid.AutoRotate
			humanoid.AutoRotate = false
			airTurnAlignOrientation.Enabled = true
		elseif not shouldEnable and airTurnAlignOrientation.Enabled then
			airTurnAlignOrientation.Enabled = false
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

	local function updateAirTurn()
		local isAirborne = currentState == Enum.HumanoidStateType.Jumping
			or currentState == Enum.HumanoidStateType.Freefall
		local cameraControlsRotation = gameSettings.RotationType == Enum.RotationType.CameraRelative
		if not isAirborne or cameraControlsRotation or humanoid.PlatformStand or humanoid.Health <= 0 then
			setAirTurnEnabled(false)
			return
		end

		local moveDirection = humanoid.MoveDirection
		local horizontalMoveDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z)
		if horizontalMoveDirection.Magnitude < MINIMUM_MOVE_DIRECTION_MAGNITUDE then
			setAirTurnEnabled(false)
			return
		end

		airTurnAlignOrientation.CFrame = CFrame.lookAt(Vector3.zero, horizontalMoveDirection.Unit)
		setAirTurnEnabled(true)
	end

	local function disable()
		if not enabled then
			return
		end

		enabled = false
		setAirTurnEnabled(false)
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
			if newState ~= Enum.HumanoidStateType.Jumping and newState ~= Enum.HumanoidStateType.Freefall then
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
