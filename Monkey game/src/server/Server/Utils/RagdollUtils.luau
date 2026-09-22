--!strict

local physicsService = game:GetService("PhysicsService")
local workspace = game:GetService("Workspace")

local RAGDOLL_FOLDER_NAME = "CombatRagdoll"
local RAGDOLL_COLLISION_GROUP = "CombatRagdoll"
local GROUND_CHECK_DISTANCE = 20
local GROUND_CLEARANCE = 0.1
local RECOVERY_RAYCAST_HEIGHT = 4
local RECOVERY_RAYCAST_DISTANCE = 50
local RECOVERY_CLEARANCE = 0.1

type BallSocketProfile = {
	upperAngle: number,
	twistAngle: number,
	frictionTorque: number,
}

type JointConstraint = Constraint

type JointData = {
	motor: Motor6D,
	attachment0: Attachment,
	attachment1: Attachment,
	constraint: JointConstraint,
	wasEnabled: boolean,
}

type RagdollData = {
	character: Model,
	folder: Folder,
	joints: { JointData },
	attachments: { Attachment },
	bodyParts: { [BasePart]: boolean },
	bodyPartCollisionGroups: { [BasePart]: string },
	networkRoots: { BasePart },
	autoRotate: boolean,
	platformStand: boolean,
	requiresNeck: boolean,
	gettingUpEnabled: boolean,
	active: boolean,
}

type RagdollUtils = {
	prepare: (humanoid: Humanoid, excludedMotorNames: { [string]: boolean }) -> boolean,
	enable: (humanoid: Humanoid, excludedMotorNames: { [string]: boolean }) -> boolean,
	applyImpulse: (humanoid: Humanoid, velocityChange: Vector3) -> boolean,
	disable: (humanoid: Humanoid) -> (),
}

local BALL_SOCKET_PROFILES: { [string]: BallSocketProfile } = {
	root = {
		upperAngle = 15,
		twistAngle = 10,
		frictionTorque = 0,
	},
	neck = {
		upperAngle = 30,
		twistAngle = 20,
		frictionTorque = 0,
	},
	shoulder = {
		upperAngle = 50,
		twistAngle = 30,
		frictionTorque = 0,
	},
	hip = {
		upperAngle = 30,
		twistAngle = 20,
		frictionTorque = 0,
	},
	default = {
		upperAngle = 35,
		twistAngle = 20,
		frictionTorque = 0,
	},
}

local EXCLUDED_RAGDOLL_PART_NAMES: { [string]: boolean } = {
	Tongue = true,
	Head = true,
	["Left Leg"] = true,
	["Right Leg"] = true,
	LeftUpperLeg = true,
	RightUpperLeg = true,
	LeftLowerLeg = true,
	RightLowerLeg = true,
	LeftFoot = true,
	RightFoot = true,
}

local preparedRagdolls: { [Humanoid]: RagdollData } = {}
local ragdollUtils: RagdollUtils = {} :: RagdollUtils

if not physicsService:IsCollisionGroupRegistered(RAGDOLL_COLLISION_GROUP) then
	physicsService:RegisterCollisionGroup(RAGDOLL_COLLISION_GROUP)
end
physicsService:CollisionGroupSetCollidable(RAGDOLL_COLLISION_GROUP, RAGDOLL_COLLISION_GROUP, false)

local function containsJointKeyword(jointName: string, keyword: string): boolean
	return string.find(jointName, keyword, 1, true) ~= nil
end

local function isExcludedRagdollPart(part: BasePart): boolean
	local parent = part.Parent
	return EXCLUDED_RAGDOLL_PART_NAMES[part.Name] == true
		or (parent ~= nil and EXCLUDED_RAGDOLL_PART_NAMES[parent.Name] == true)
end

local function getJointName(motor: Motor6D): string
	return string.lower(motor.Name)
end

local function usesHingeConstraint(motor: Motor6D): boolean
	local jointName = getJointName(motor)
	return containsJointKeyword(jointName, "ankle") or containsJointKeyword(jointName, "foot")
end

local function getBallSocketProfile(motor: Motor6D): BallSocketProfile
	local jointName = getJointName(motor)

	if
		containsJointKeyword(jointName, "root")
		or containsJointKeyword(jointName, "waist")
	then
		return BALL_SOCKET_PROFILES.root
	end
	if containsJointKeyword(jointName, "neck") then
		return BALL_SOCKET_PROFILES.neck
	end
	if containsJointKeyword(jointName, "shoulder") then
		return BALL_SOCKET_PROFILES.shoulder
	end
	if containsJointKeyword(jointName, "hip") then
		return BALL_SOCKET_PROFILES.hip
	end

	return BALL_SOCKET_PROFILES.default
end

local function createConstraint(
	folder: Folder,
	motor: Motor6D,
	attachment0: Attachment,
	attachment1: Attachment
): JointConstraint
	if usesHingeConstraint(motor) then
		local hinge = Instance.new("HingeConstraint")
		hinge.Name = motor.Name .. "RagdollHinge"
		hinge.Attachment0 = attachment0
		hinge.Attachment1 = attachment1
		hinge.LimitsEnabled = true
		hinge.LowerAngle = -40
		hinge.UpperAngle = 40
		hinge.Restitution = 0
		hinge.Enabled = false
		hinge.Parent = folder
		return hinge
	end

	local profile = getBallSocketProfile(motor)
	local socket = Instance.new("BallSocketConstraint")
	socket.Name = motor.Name .. "RagdollSocket"
	socket.Attachment0 = attachment0
	socket.Attachment1 = attachment1
	socket.LimitsEnabled = true
	socket.UpperAngle = profile.upperAngle
	socket.TwistLimitsEnabled = true
	socket.TwistLowerAngle = -profile.twistAngle
	socket.TwistUpperAngle = profile.twistAngle
	socket.MaxFrictionTorque = profile.frictionTorque
	socket.Restitution = 0
	socket.Enabled = false
	socket.Parent = folder
	return socket
end

local function createJoint(folder: Folder, motor: Motor6D, part0: BasePart, part1: BasePart): JointData
	local attachment0 = Instance.new("Attachment")
	attachment0.Name = motor.Name .. "RagdollAttachment0"
	attachment0.CFrame = motor.C0
	attachment0.Parent = part0

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = motor.Name .. "RagdollAttachment1"
	attachment1.CFrame = motor.C1
	attachment1.Parent = part1

	return {
		motor = motor,
		attachment0 = attachment0,
		attachment1 = attachment1,
		constraint = createConstraint(folder, motor, attachment0, attachment1),
		wasEnabled = true,
	}
end

local function destroyRagdollData(data: RagdollData)
	for _, attachment in ipairs(data.attachments) do
		if attachment.Parent then
			attachment:Destroy()
		end
	end

	if data.folder.Parent then
		data.folder:Destroy()
	end
end

local function prepareRagdoll(
	humanoid: Humanoid,
	character: Model,
	excludedMotorNames: { [string]: boolean }
): RagdollData?
	local existingData = preparedRagdolls[humanoid]
	if existingData then
		return existingData
	end

	local folder = Instance.new("Folder")
	folder.Name = RAGDOLL_FOLDER_NAME
	folder.Parent = character

	local joints: { JointData } = {}
	local attachments: { Attachment } = {}
	local bodyParts: { [BasePart]: boolean } = {}
	local bodyPartCollisionGroups: { [BasePart]: string } = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			bodyParts[descendant] = descendant.CanCollide
			bodyPartCollisionGroups[descendant] = descendant.CollisionGroup
		elseif descendant:IsA("Motor6D") and not excludedMotorNames[descendant.Name] then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			if part0 and part1 and not isExcludedRagdollPart(part0) and not isExcludedRagdollPart(part1) then
				local joint = createJoint(folder, descendant, part0, part1)
				table.insert(joints, joint)
				table.insert(attachments, joint.attachment0)
				table.insert(attachments, joint.attachment1)
			end
		end
	end

	if #joints == 0 then
		folder:Destroy()
		return nil
	end

	local data: RagdollData = {
		character = character,
		folder = folder,
		joints = joints,
		attachments = attachments,
		bodyParts = bodyParts,
		bodyPartCollisionGroups = bodyPartCollisionGroups,
		networkRoots = {},
		autoRotate = humanoid.AutoRotate,
		platformStand = humanoid.PlatformStand,
		requiresNeck = humanoid.RequiresNeck,
		gettingUpEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp),
		active = false,
	}
	preparedRagdolls[humanoid] = data

	humanoid.Destroying:Once(function()
		if preparedRagdolls[humanoid] == data then
			preparedRagdolls[humanoid] = nil
			destroyRagdollData(data)
		end
	end)

	return data
end

local function stopAssemblies(data: RagdollData)
	local stoppedAssemblies: { [BasePart]: boolean } = {}
	for part in pairs(data.bodyParts) do
		if not part.Parent then
			continue
		end

		local assemblyRoot = part.AssemblyRootPart
		if not stoppedAssemblies[assemblyRoot] then
			stoppedAssemblies[assemblyRoot] = true
			assemblyRoot.AssemblyLinearVelocity = Vector3.zero
			assemblyRoot.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function liftCharacterAboveGround(data: RagdollData, humanoid: Humanoid)
	local rootPart = data.character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { data.character }
	local rayResult = workspace:Raycast(rootPart.Position, -Vector3.yAxis * GROUND_CHECK_DISTANCE, raycastParams)
	if not rayResult then
		return
	end

	local expectedHeight = humanoid.HipHeight + rootPart.Size.Y / 2
	local actualHeight = rootPart.Position.Y - rayResult.Position.Y
	local liftAmount = expectedHeight - actualHeight + GROUND_CLEARANCE
	if liftAmount > 0 then
		data.character:PivotTo(data.character:GetPivot() + Vector3.yAxis * liftAmount)
	end
end

local function giveServerOwnership(data: RagdollData)
	table.clear(data.networkRoots)
	local ownedAssemblies: { [BasePart]: boolean } = {}

	for part in pairs(data.bodyParts) do
		if not part.Parent then
			continue
		end

		local assemblyRoot = part.AssemblyRootPart
		if ownedAssemblies[assemblyRoot] then
			continue
		end
		ownedAssemblies[assemblyRoot] = true

		if assemblyRoot:CanSetNetworkOwnership() then
			assemblyRoot:SetNetworkOwner(nil)
			table.insert(data.networkRoots, assemblyRoot)
		end
	end
end

local function restoreAutomaticOwnership(data: RagdollData)
	for _, assemblyRoot in ipairs(data.networkRoots) do
		if assemblyRoot.Parent and assemblyRoot:CanSetNetworkOwnership() then
			assemblyRoot:SetNetworkOwnershipAuto()
		end
	end
	table.clear(data.networkRoots)
end

local function pivotCharacterUpright(data: RagdollData, humanoid: Humanoid)
	local rootInstance = data.character:FindFirstChild("HumanoidRootPart")
	if not rootInstance or not rootInstance:IsA("BasePart") then
		return
	end

	local rootPosition = rootInstance.Position
	local lookVector = rootInstance.CFrame.LookVector
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude <= 0.001 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { data.character }
	local rayOrigin = rootPosition + Vector3.yAxis * RECOVERY_RAYCAST_HEIGHT
	local rayDirection = -Vector3.yAxis * RECOVERY_RAYCAST_DISTANCE
	local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	local standPosition = rootPosition
	if rayResult then
		local standHeight = humanoid.HipHeight + rootInstance.Size.Y / 2 + RECOVERY_CLEARANCE
		standPosition = Vector3.new(rootPosition.X, rayResult.Position.Y + standHeight, rootPosition.Z)
	end

	local uprightRootCFrame = CFrame.lookAt(standPosition, standPosition + flatLook)
	local pivotDelta = uprightRootCFrame * rootInstance.CFrame:Inverse()
	data.character:PivotTo(pivotDelta * data.character:GetPivot())
end

function ragdollUtils.prepare(humanoid: Humanoid, excludedMotorNames: { [string]: boolean }): boolean
	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return false
	end

	return prepareRagdoll(humanoid, character, excludedMotorNames) ~= nil
end

function ragdollUtils.enable(humanoid: Humanoid, excludedMotorNames: { [string]: boolean }): boolean
	local character = humanoid.Parent
	if not character or not character:IsA("Model") or humanoid.Health <= 0 then
		return false
	end

	local data = prepareRagdoll(humanoid, character, excludedMotorNames)
	if not data or data.active then
		return false
	end

	data.autoRotate = humanoid.AutoRotate
	data.platformStand = humanoid.PlatformStand
	data.requiresNeck = humanoid.RequiresNeck
	data.gettingUpEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp)
	data.active = true

	humanoid.RequiresNeck = false
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
	stopAssemblies(data)
	liftCharacterAboveGround(data, humanoid)

	for part in pairs(data.bodyParts) do
		if part.Parent then
			data.bodyParts[part] = part.CanCollide
			data.bodyPartCollisionGroups[part] = part.CollisionGroup
			part.CollisionGroup = RAGDOLL_COLLISION_GROUP
			part.CanCollide = true
		end
	end
	local enabledJointCount = 0
	for _, joint in ipairs(data.joints) do
		local motor = joint.motor
		if not motor.Parent or not motor.Part0 or not motor.Part1 then
			continue
		end

		joint.wasEnabled = motor.Enabled
		joint.attachment0.CFrame = motor.C0
		joint.attachment1.CFrame = motor.C1
		joint.constraint.Enabled = motor.Enabled
		motor.Enabled = false
		if joint.constraint.Enabled then
			enabledJointCount += 1
		end
	end

	if enabledJointCount == 0 then
		ragdollUtils.disable(humanoid)
		return false
	end

	stopAssemblies(data)
	giveServerOwnership(data)
	return true
end

function ragdollUtils.applyImpulse(humanoid: Humanoid, velocityChange: Vector3): boolean
	local data = preparedRagdolls[humanoid]
	if not data or not data.active then
		return false
	end

	local movedAssemblies: { [BasePart]: boolean } = {}
	for part in pairs(data.bodyParts) do
		if not part.Parent then
			continue
		end

		local assemblyRoot = part.AssemblyRootPart
		if not movedAssemblies[assemblyRoot] then
			movedAssemblies[assemblyRoot] = true
			assemblyRoot.AssemblyAngularVelocity = Vector3.zero
			assemblyRoot:ApplyImpulse(velocityChange * assemblyRoot.AssemblyMass)
		end
	end

	return next(movedAssemblies) ~= nil
end

function ragdollUtils.disable(humanoid: Humanoid)
	local data = preparedRagdolls[humanoid]
	if not data or not data.active then
		return
	end
	data.active = false

	stopAssemblies(data)
	for _, joint in ipairs(data.joints) do
		joint.constraint.Enabled = false
		if joint.motor.Parent then
			joint.motor.Enabled = joint.wasEnabled
		end
	end

	pivotCharacterUpright(data, humanoid)

	for part, canCollide in pairs(data.bodyParts) do
		if part.Parent then
			part.CanCollide = canCollide
			part.CollisionGroup = data.bodyPartCollisionGroups[part]
		end
	end
	restoreAutomaticOwnership(data)

	if humanoid.Parent then
		humanoid.RequiresNeck = data.requiresNeck
		humanoid.AutoRotate = data.autoRotate
		humanoid.PlatformStand = data.platformStand
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, data.gettingUpEnabled)
		if humanoid.Health > 0 then
			humanoid:ChangeState(Enum.HumanoidStateType.Landed)
		end
	end
end

return ragdollUtils
