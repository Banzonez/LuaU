--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local CombatUtil = require(script.Parent.Parent.Utils.CombatUtil)
local CombatService = require(script.Parent.CombatService)
local CombatSetup = require(script.Parent.CombatSetup)
local StateHandler = require(script.Parent.CombatStateHandler)

local MAX_PER_PLAYER = 3
local MAX_TOTAL = 12
local SPAWN_COOLDOWN = 1
local THINK_INTERVAL = 0.2

type npcData = { owner: Player, mode: string, humanoid: Humanoid, root: BasePart, expiresAt: number }

local npcs: { [Model]: npcData } = {}
local lastSpawn: { [Player]: number } = {}
local accumulator = 0
local initialized = false
local npcHandler = {}

local function clearOwned(player: Player)
	for model, record in pairs(npcs) do
		if record.owner == player then
			npcs[model] = nil
			StateHandler.removeCharacter(model)
			model:Destroy()
		end
	end
end

local function spawnNpc(player: Player, mode: string)
	if mode == "Clear" then
		clearOwned(player)

		return
	end

	if mode ~= "Block" and mode ~= "Attack" and mode ~= "Mixed" then
		return
	end

	local currentTime = os.clock()

	if currentTime - (lastSpawn[player] or -math.huge) < SPAWN_COOLDOWN then
		return
	end

	lastSpawn[player] = currentTime
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not root or not root:IsA("BasePart") then
		return
	end

	local total, owned = 0, 0

	for _, record in pairs(npcs) do
		total += 1

		if record.owner == player then
			owned += 1
		end
	end

	if owned >= MAX_PER_PLAYER or total >= MAX_TOTAL then
		return
	end

	local template = ServerStorage:FindFirstChild("CombatNpc")

	if not template or not template:IsA("Model") or not template.Archivable then
		return
	end

	local model = template:Clone()
	model.Name = mode .. " Dummy"
	model:SetAttribute("TrainingOwner", player.UserId)

	for _, instance in ipairs(model:GetDescendants()) do
		if instance:IsA("LuaSourceContainer") then
			instance:Destroy()
		elseif instance:IsA("BasePart") then
			instance.Anchored = false
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local npcRoot = model:FindFirstChild("HumanoidRootPart")

	if not humanoid or not npcRoot or not npcRoot:IsA("BasePart") then
		model:Destroy()

		return
	end

	model.PrimaryPart = npcRoot
	local position = root.Position + root.CFrame.LookVector * 9 + root.CFrame.RightVector * (owned - 1) * 4
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character :: Model, model, template }
	params.RespectCanCollide = true
	local ground = workspace:Raycast(position + Vector3.new(0, 15, 0), Vector3.new(0, -60, 0), params)

	if not ground then
		model:Destroy()

		return
	end

	position = ground.Position + Vector3.new(0, humanoid.HipHeight + npcRoot.Size.Y / 2, 0)

	model:PivotTo(CFrame.lookAt(position, Vector3.new(root.Position.X, position.Y, root.Position.Z)))
	local overlap = OverlapParams.new()
	overlap.FilterDescendantsInstances = { character :: Model, model, template }
	overlap.RespectCanCollide = true

	if
		#workspace:GetPartBoundsInBox(CFrame.new(position + Vector3.new(0, 1, 0)), Vector3.new(4, 3, 4), overlap) > 0
	then
		model:Destroy()

		return
	end

	humanoid.Health = humanoid.MaxHealth
	model.Parent = workspace
	local canSet = npcRoot:CanSetNetworkOwnership()

	if canSet then
		npcRoot:SetNetworkOwner(nil)
	end

	npcs[model] = { owner = player, mode = mode, humanoid = humanoid, root = npcRoot, expiresAt = currentTime + 180 }
	local object = CombatSetup.createCharacterObj(model)
	local idle = CombatUtil.getAnimation(object.Style.StyleName, "Idle")

	if idle then
		local animator = humanoid:FindFirstChildOfClass("Animator")

		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end

		local track = animator:LoadAnimation(idle)
		track.Priority = Enum.AnimationPriority.Idle
		track.Looped = true
		track:Play()
	end
	model.Destroying:Connect(function()
		npcs[model] = nil
		StateHandler.removeCharacter(model)
	end)
end

local function trainingTarget(owner: Player, root: BasePart): BasePart?
	local character = owner.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local target = character and character:FindFirstChild("HumanoidRootPart")

	return if humanoid
			and humanoid.Health > 0
			and target
			and target:IsA("BasePart")
			and (target.Position - root.Position).Magnitude <= 60
		then target
		else nil
end

function npcHandler.init()
	if initialized then
		return
	end

	initialized = true

	CombatService.setNpcRequest(spawnNpc)
	Players.PlayerRemoving:Connect(function(player: Player)
		clearOwned(player)
		lastSpawn[player] = nil
	end)

	RunService.Heartbeat:Connect(function(delta: number)
		accumulator += delta

		if accumulator < THINK_INTERVAL then
			return
		end

		accumulator = 0

		for model, record in pairs(npcs) do
			if not model.Parent or record.humanoid.Health <= 0 or os.clock() >= record.expiresAt then
				npcs[model] = nil
				StateHandler.removeCharacter(model)
				model:Destroy()
				continue
			end

			local target = trainingTarget(record.owner, record.root)
			local state = StateHandler.getCharacterState(model)

			if target and (state.State == "Idle" or state.State == "Blocking") then
				local position = record.root.Position
				local blocking = record.mode == "Block"
					or (record.mode == "Mixed" and math.floor(os.clock() * 2) % 3 == 0)
				CombatService.setBlocking(model, blocking)

				if not blocking and (target.Position - position).Magnitude <= 4 then
					CombatService.tryAttack(model)
				end
			elseif not target then
				CombatService.setBlocking(model, false)
			end
		end
	end)
end

return npcHandler
