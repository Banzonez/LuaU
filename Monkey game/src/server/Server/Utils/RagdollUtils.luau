--!strict

local physicsService = game:GetService("PhysicsService")

local RAGDOLL_FOLDER_NAME = "CombatRagdoll"
local RAGDOLL_COLLISION_GROUP = "CombatRagdoll"
local JOINT_UPPER_ANGLE = 55
local JOINT_LOWER_TWIST_ANGLE = -30
local JOINT_UPPER_TWIST_ANGLE = 30
local JOINT_FRICTION_TORQUE = 15

type RagdollData = {
	folder: Folder,
	motors: { Motor6D },
	attachments: { Attachment },
	partCollisions: { [BasePart]: boolean },
	partCollisionGroups: { [BasePart]: string },
	autoRotate: boolean,
	platformStand: boolean,
	requiresNeck: boolean,
	gettingUpEnabled: boolean,
}

type RagdollUtils = {
	enable: (humanoid: Humanoid, excludedMotorNames: { [string]: boolean }) -> boolean,
	disable: (humanoid: Humanoid) -> (),
}

local activeRagdolls: { [Humanoid]: RagdollData } = {}
local ragdollUtils: RagdollUtils = {} :: RagdollUtils

if not physicsService:IsCollisionGroupRegistered(RAGDOLL_COLLISION_GROUP) then
	physicsService:RegisterCollisionGroup(RAGDOLL_COLLISION_GROUP)
end
physicsService:CollisionGroupSetCollidable(RAGDOLL_COLLISION_GROUP, RAGDOLL_COLLISION_GROUP, false)

local function addConstraint(folder: Folder, motor: Motor6D): (Attachment?, Attachment?)
	local part0 = motor.Part0
	local part1 = motor.Part1
	if not part0 or not part1 then
		return nil, nil
	end

	local attachment0 = Instance.new("Attachment")
	attachment0.CFrame = motor.C0 * motor.Transform
	attachment0.Parent = part0

	local attachment1 = Instance.new("Attachment")
	attachment1.CFrame = motor.C1
	attachment1.Parent = part1

	local constraint = Instance.new("BallSocketConstraint")
	constraint.Attachment0 = attachment0
	constraint.Attachment1 = attachment1
	constraint.LimitsEnabled = true
	constraint.UpperAngle = JOINT_UPPER_ANGLE
	constraint.TwistLimitsEnabled = true
	constraint.TwistLowerAngle = JOINT_LOWER_TWIST_ANGLE
	constraint.TwistUpperAngle = JOINT_UPPER_TWIST_ANGLE
	constraint.MaxFrictionTorque = JOINT_FRICTION_TORQUE
	constraint.Restitution = 0
	constraint.Parent = folder

	local noCollision = Instance.new("NoCollisionConstraint")
	noCollision.Part0 = part0
	noCollision.Part1 = part1
	noCollision.Parent = folder

	return attachment0, attachment1
end

function ragdollUtils.enable(humanoid: Humanoid, excludedMotorNames: { [string]: boolean }): boolean
	if activeRagdolls[humanoid] then
		return false
	end

	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return false
	end

	local folder = Instance.new("Folder")
	folder.Name = RAGDOLL_FOLDER_NAME
	folder.Parent = character

	local motors: { Motor6D } = {}
	local attachments: { Attachment } = {}
	local partCollisions: { [BasePart]: boolean } = {}
	local partCollisionGroups: { [BasePart]: string } = {}

	for _, descendant in ipairs(character:GetDescendants()) do
		local part0 = if descendant:IsA("Motor6D") then descendant.Part0 else nil
		local part1 = if descendant:IsA("Motor6D") then descendant.Part1 else nil
		if
			descendant:IsA("Motor6D")
			and descendant.Enabled
			and not excludedMotorNames[descendant.Name]
			and part0
			and part1
		then
			table.insert(motors, descendant)
			partCollisions[part0] = part0.CanCollide
			partCollisions[part1] = part1.CanCollide
			partCollisionGroups[part0] = part0.CollisionGroup
			partCollisionGroups[part1] = part1.CollisionGroup
			local attachment0, attachment1 = addConstraint(folder, descendant)
			if attachment0 and attachment1 then
				table.insert(attachments, attachment0)
				table.insert(attachments, attachment1)
			end
		end
	end

	if #motors == 0 then
		folder:Destroy()
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and not rootPart:IsA("BasePart") then
		rootPart = nil
	end
	for part, canCollide in pairs(partCollisions) do
		part.CollisionGroup = RAGDOLL_COLLISION_GROUP
		if part ~= rootPart then
			part.CanCollide = true
		end
	end

	local data: RagdollData = {
		folder = folder,
		motors = motors,
		attachments = attachments,
		partCollisions = partCollisions,
		partCollisionGroups = partCollisionGroups,
		autoRotate = humanoid.AutoRotate,
		platformStand = humanoid.PlatformStand,
		requiresNeck = humanoid.RequiresNeck,
		gettingUpEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.GettingUp),
	}
	activeRagdolls[humanoid] = data
	humanoid.Destroying:Once(function()
		activeRagdolls[humanoid] = nil
	end)

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid.RequiresNeck = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)

	for _, motor in ipairs(motors) do
		motor.Enabled = false
	end

	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	return true
end

function ragdollUtils.disable(humanoid: Humanoid)
	local data = activeRagdolls[humanoid]
	if not data then
		return
	end
	activeRagdolls[humanoid] = nil

	if data.folder.Parent then
		data.folder:Destroy()
	end
	for _, attachment in ipairs(data.attachments) do
		if attachment.Parent then
			attachment:Destroy()
		end
	end

	for _, motor in ipairs(data.motors) do
		if motor.Parent then
			motor.Enabled = true
		end
	end

	for part, canCollide in pairs(data.partCollisions) do
		if part.Parent then
			part.CanCollide = canCollide
			part.CollisionGroup = data.partCollisionGroups[part]
		end
	end

	if humanoid.Parent then
		humanoid.AutoRotate = data.autoRotate
		humanoid.PlatformStand = data.platformStand
		humanoid.RequiresNeck = data.requiresNeck
		humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, data.gettingUpEnabled)
		if data.gettingUpEnabled then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
end

return ragdollUtils
