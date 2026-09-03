-- Connected Discord-GitHub
-- Discord: banzonez | Roblox: demolitoor2br
-- This script is the main handler of the parkour in the game, after you click "Play" in the lobby.
--!strict

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Systems = assert(script.Parent, "ParkourService must be inside Server/Systems")
local Server = assert(Systems.Parent, "Systems must be inside the Server folder")
local Config = Server:WaitForChild("Config")
local Utils = Server:WaitForChild("Utils")

type ParkourSettings = {
	CAN_GENERATE: boolean,
	DISTANCE_BETWEEN: Vector3,
	MAX_AHEAD_OF_FIRST: number,
	BIOME_DURATION: number,
	DELETE_BUFFER: number,
	PLATFORMS_TO_REST: number,
	PLATFORMS_TO_OBBY: number,
	CHANCE_TO_GET_COIN: number,
	COIN_INCREASE: number,
	POINTS_INCREASE: number,
	currentBiome: {
		folder: Instance?,
		startedAt: number,
	},
}

type PlatformTracker = {
	getPlatformIdFrom: (Player) -> number?,
}

type NPCConfigurator = {
	configureNPCsFrom: (Instance) -> any,
}

type Initializer = {
	configureMachines: () -> (),
}

type CutsceneTracker = {
	trackPlayers: () -> (),
}

local function requireModule(parent: Instance, name: string): any
	local child = parent:WaitForChild(name)
	assert(child:IsA("ModuleScript"), name .. " must be a ModuleScript")
	local succeeded, result = pcall(require, child)
	if not succeeded then
		error(("Could not load %s: %s"):format(child:GetFullName(), tostring(result)))
	end
	return result
end

local ParkourConfig = requireModule(Config, "ParkourConfig") :: ParkourSettings
local PlayerPlatformUtil = requireModule(Utils, "PlayerPlatformUtil") :: PlatformTracker
local NPCSetup = requireModule(Utils, "NPCSetup") :: NPCConfigurator
local PlatformCutsceneUtil = requireModule(Utils, "PlatformCutsceneUtil") :: CutsceneTracker
local VendingUtil = requireModule(Utils, "VendingUtil") :: Initializer

local TemplateFolders: {[string]: Instance} = {
	Platform = ServerStorage:WaitForChild("Platforms"),
	Obby = ServerStorage:WaitForChild("Obbys"),
	Rest = ServerStorage:WaitForChild("Rests"),
}

local PlatformVFX = ServerStorage:WaitForChild("PlatformUnlocked")
local FastRestart = ServerScriptService:WaitForChild("FastRestart") :: BindableEvent
local BadgeEvent = ServerScriptService:WaitForChild("BadgeEvent") :: BindableEvent

local GENERATION_INTERVAL = 0.35
local MOTION_STEP = 1 / 30
local PLACEMENT_ATTEMPTS = 6
local TOUCH_INTERVAL = 0.12
local MAX_CHECKPOINT_SKIP = 2
local TOUCH_TOLERANCE = Vector3.new(5, 8, 5)
local OVERLAP_PADDING = Vector3.new(0.4, 0.2, 0.4)
local SPAWN_TAGS = { "Platform", "Obby", "Rest" }
local TAU: number = 6.283185307179586

type SpawnType = "Platform" | "Obby" | "Rest"

type Motion = {
	BasePivot: CFrame,
	Height: number,
	AngularSpeed: number,
	Phase: number,
}

type PieceData = {
	Object: Instance,
	Id: number,
	Kind: SpawnType,
	Connections: {RBXScriptConnection},
	Rewarded: {[Player]: boolean},
	CanReward: boolean,
	UnlocksGeneration: boolean,
	Highlight: Highlight?,
}

type GeneratorState = {
	Random: Random,
	Running: boolean,
	Resetting: boolean,
	NextId: number,
	OldestId: number,
	LastPiece: Instance,
	LastType: SpawnType,
	Biome: Instance?,
	BiomeStartedAt: number,
	Pieces: {[number]: PieceData},
	Motion: {[Instance]: Motion},
	Progress: {[Player]: number},
	LastTouch: {[Player]: number},
	Connections: {RBXScriptConnection},
	MotionAccumulator: number,
	Overlap: OverlapParams,
	InitialPlatform: Instance,
}

local Generator = {}
Generator.__index = Generator

-- One state object owns every connection and generated piece, which makes restart
-- cleanup deterministic and prevents module-level tables from surviving reinitialization.
type Generator = typeof(setmetatable({} :: GeneratorState, Generator))

local function getPivot(object: Instance): CFrame
	if object:IsA("PVInstance") then
		return object:GetPivot()
	end

	local part = object:FindFirstChildWhichIsA("BasePart", true)
	return if part then part.CFrame else CFrame.identity
end

local function pivotTo(object: Instance, target: CFrame)
	if object:IsA("PVInstance") then
		object:PivotTo(target)
		return
	end

	local part = object:FindFirstChildWhichIsA("BasePart", true)
	if part then
		part.CFrame = target
	end
end

local function getBounds(object: Instance): (CFrame?, Vector3?)
	if object:IsA("Model") then
		return object:GetBoundingBox()
	end

	if object:IsA("BasePart") then
		return object.CFrame, object.Size
	end

	return nil, nil
end

local function findMarker(object: Instance, name: string): CFrame?
	local marker = object:FindFirstChild(name, true)
	if marker and marker:IsA("Attachment") then
		return marker.WorldCFrame
	end
	if marker and marker:IsA("BasePart") then
		return marker.CFrame
	end
	return nil
end

local function isSpawnable(object: Instance): boolean
	return object:IsA("Model") or object:IsA("BasePart")
end

local function getCharacterFromHit(hit: BasePart): Model?
	local current: Instance? = hit
	while current and current ~= Workspace do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getNumberAttribute(instance: Instance, name: string, fallback: number): number
	local value = instance:GetAttribute(name)
	if typeof(value) == "number" and value == value then
		return value
	end
	return fallback
end

local function weightedChoice(random: Random, objects: {Instance}): Instance?
	-- Designers can tune variety with a numeric Weight attribute; absent weights are 1.
	local totalWeight = 0
	for _, object in objects do
		if isSpawnable(object) then
			totalWeight += math.max(0, getNumberAttribute(object, "Weight", 1))
		end
	end

	if totalWeight <= 0 then
		return nil
	end

	local roll = random:NextNumber(0, totalWeight)
	for _, object in objects do
		if not isSpawnable(object) then
			continue
		end

		roll -= math.max(0, getNumberAttribute(object, "Weight", 1))
		if roll <= 0 then
			return object
		end
	end

	return nil
end

function Generator.new(): Generator
	local initial = Workspace:WaitForChild("InitialPlatform")
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.RespectCanCollide = true

	local self: GeneratorState = {
		Random = Random.new(),
		Running = false,
		Resetting = false,
		NextId = 1,
		OldestId = 0,
		LastPiece = initial,
		LastType = "Platform",
		Biome = nil,
		BiomeStartedAt = 0,
		Pieces = {},
		Motion = {},
		Progress = {},
		LastTouch = {},
		Connections = {},
		MotionAccumulator = 0,
		Overlap = overlap,
		InitialPlatform = initial,
	}

	return setmetatable(self, Generator)
end

function Generator._spawnType(self: Generator, id: number): SpawnType
	if id % ParkourConfig.PLATFORMS_TO_REST == 0 then
		return "Rest"
	end
	if id % ParkourConfig.PLATFORMS_TO_OBBY == 0 then
		return "Obby"
	end
	return "Platform"
end

function Generator._statusFolder(self: Generator, kind: SpawnType): Instance?
	local status = Workspace:GetAttribute("Status")
	if status ~= "Neutral" and status ~= "Good" and status ~= "Bad" then
		warn("[ParkourService] Workspace.Status must be Neutral, Good, or Bad")
		return nil
	end

	local folder = TemplateFolders[kind]:FindFirstChild(status)
	if not folder then
		warn(("[ParkourService] Missing %s/%s template folder"):format(kind, status))
	end
	return folder
end

function Generator._pickBiome(self: Generator, parent: Instance): Instance?
	local choices = {}
	for _, child in parent:GetChildren() do
		if child:IsA("Folder") and #child:GetChildren() > 0 then
			table.insert(choices, child)
		end
	end

	if #choices == 0 then
		return nil
	end
	return choices[self.Random:NextInteger(1, #choices)]
end

function Generator._template(self: Generator, kind: SpawnType): Instance?
	local folder = self:_statusFolder(kind)
	if not folder then
		return nil
	end

	if kind ~= "Platform" then
		return weightedChoice(self.Random, folder:GetChildren())
	end

	local now = Workspace:GetServerTimeNow()
	local biomeExpired = not self.Biome
		or self.Biome.Parent ~= folder
		or now - self.BiomeStartedAt >= ParkourConfig.BIOME_DURATION

	if biomeExpired then
		self.Biome = self:_pickBiome(folder)
		self.BiomeStartedAt = now
		ParkourConfig.currentBiome.folder = self.Biome
		ParkourConfig.currentBiome.startedAt = DateTime.now().UnixTimestamp
	end

	return if self.Biome then weightedChoice(self.Random, self.Biome:GetChildren()) else nil
end

function Generator._stableExit(self: Generator, piece: Instance): CFrame
	local currentPivot = getPivot(piece)
	local marker = findMarker(piece, "FinalPoint")
	local motion = self.Motion[piece]

	if not marker then
		return if motion then motion.BasePivot else currentPivot
	end

	-- The marker offset is converted to object space before replacing the live,
	-- animated pivot. New pieces therefore do not inherit the current bobbing frame.
	local markerOffset = currentPivot:ToObjectSpace(marker)
	return (if motion then motion.BasePivot else currentPivot) * markerOffset
end

function Generator._scalePlatform(self: Generator, object: Instance)
	local scale = self.Random:NextNumber(1, 1.35)
	if object:IsA("Model") then
		object:ScaleTo(object:GetScale() * scale)
	elseif object:IsA("BasePart") then
		object.Size *= Vector3.new(scale, 1, scale)
	end
end

function Generator._targetPivot(self: Generator, object: Instance, origin: CFrame, kind: SpawnType): CFrame
	local offset = ParkourConfig.DISTANCE_BETWEEN
	-- DISTANCE_BETWEEN is a world-space course direction. Using only the exit position
	-- keeps a randomly rotated platform from turning every later section of the course.
	local targetStart = CFrame.new(origin.Position + offset)

	if kind == "Platform" then
		local jitter = Vector3.new(
			self.Random:NextNumber(-2, 2),
			self.Random:NextNumber(-1, 1),
			self.Random:NextNumber(0, 2)
		)
		targetStart *= CFrame.new(jitter)
		local yaw = self.Random:NextNumber(0, 1) * TAU
		targetStart *= CFrame.Angles(0, yaw, 0)
	end

	local pivot = getPivot(object)
	local startMarker = findMarker(object, "StartPoint")
	if not startMarker then
		return targetStart
	end

	-- If S = P * L, solving for the desired pivot gives P = S * inverse(L).
	-- This aligns a template's StartPoint with the preceding FinalPoint.
	local localMarker = pivot:ToObjectSpace(startMarker)
	return targetStart * localMarker:Inverse()
end

function Generator._overlaps(self: Generator, object: Instance, previous: Instance): boolean
	local boxCFrame, boxSize = getBounds(object)
	if not boxCFrame or not boxSize then
		return true
	end

	local querySize = Vector3.new(
		math.max(0.1, boxSize.X - OVERLAP_PADDING.X),
		math.max(0.1, boxSize.Y - OVERLAP_PADDING.Y),
		math.max(0.1, boxSize.Z - OVERLAP_PADDING.Z)
	)

	-- Reusing one OverlapParams avoids allocating filter objects in the hot loop.
	self.Overlap.FilterDescendantsInstances = { object, previous }
	return #Workspace:GetPartBoundsInBox(boxCFrame, querySize, self.Overlap) > 0
end

function Generator._place(self: Generator, template: Instance, kind: SpawnType): Instance?
	local origin = self:_stableExit(self.LastPiece)

	for _ = 1, PLACEMENT_ATTEMPTS do
		local object = template:Clone()
		if kind == "Platform" then
			self:_scalePlatform(object)
		end

		pivotTo(object, self:_targetPivot(object, origin, kind))
		object.Parent = Workspace

		if not self:_overlaps(object, self.LastPiece) then
			return object
		end
		object:Destroy()
	end

	warn(("[ParkourService] Could not place %s without an overlap"):format(template:GetFullName()))
	return nil
end

function Generator._highlight(self: Generator, object: Instance): Highlight
	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillTransparency = 0.8
	highlight.OutlineTransparency = 0.65
	highlight.FillColor = Color3.fromRGB(216, 216, 216)
	highlight.OutlineColor = Color3.fromRGB(180, 180, 180)
	highlight.Parent = object
	return highlight
end

function Generator._addMotion(self: Generator, object: Instance)
	for _, descendant in object:GetDescendants() do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			return
		end
	end

	if object:IsA("BasePart") and not object.Anchored then
		return
	end

	local period = self.Random:NextNumber(2.2, 4.5)
	self.Motion[object] = {
		BasePivot = getPivot(object),
		Height = self.Random:NextNumber(0.15, 1.4),
		AngularSpeed = (2 * math.pi) / period,
		Phase = self.Random:NextNumber(0, 2 * math.pi),
	}
end

function Generator._insidePiece(self: Generator, character: Model, piece: Instance): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false
	end

	local boxCFrame, boxSize = getBounds(piece)
	if not boxCFrame or not boxSize then
		return false
	end

	-- Touched can be influenced through client-owned character physics. Checking the
	-- root in the piece's local bounding box makes a forged, distant touch useless.
	local point = boxCFrame:PointToObjectSpace(root.Position)
	local half = boxSize * 0.5 + TOUCH_TOLERANCE
	return math.abs(point.X) <= half.X
		and math.abs(point.Y) <= half.Y
		and math.abs(point.Z) <= half.Z
end

function Generator._validProgress(self: Generator, player: Player, character: Model, data: PieceData): boolean
	if player.Character ~= character or not self:_insidePiece(character, data.Object) then
		return false
	end

	local previous = self.Progress[player] or 0
	-- Normal play advances one piece at a time; a tolerance of two permits long jumps
	-- without allowing an arbitrary checkpoint ID to be accepted.
	if data.Id <= previous or data.Id > previous + MAX_CHECKPOINT_SKIP then
		return false
	end

	local now = os.clock()
	if now - (self.LastTouch[player] or 0) < TOUCH_INTERVAL then
		return false
	end

	self.Progress[player] = data.Id
	self.LastTouch[player] = now
	return true
end

function Generator._giveBonus(self: Generator, player: Player)
	local credits = player:GetAttribute("Credits")
	local points = player:GetAttribute("Points")
	local currentCredits = if typeof(credits) == "number" then credits else 0
	local currentPoints = if typeof(points) == "number" then points else 0
	-- The live game contains the misspelled attribute; the corrected spelling is also
	-- accepted so existing purchases keep working during a future migration.
	local ownsDoublePoints = player:GetAttribute("SucessfullySpawned") == true
		or player:GetAttribute("SuccessfullySpawned") == true
	local multiplier = if ownsDoublePoints then 2 else 1
	local wonCoin = self.Random:NextNumber() < ParkourConfig.CHANCE_TO_GET_COIN / 100

	if wonCoin then
		player:SetAttribute("Credits", currentCredits + ParkourConfig.COIN_INCREASE)
	end
	player:SetAttribute("Points", currentPoints + ParkourConfig.POINTS_INCREASE * multiplier)
	BadgeEvent:Fire(player, "Point")
end

function Generator._playUnlockVFX(self: Generator, object: Instance)
	local effect = PlatformVFX:Clone()
	pivotTo(effect, getPivot(object))
	effect.Parent = Workspace

	task.delay(1, function()
		if effect.Parent then
			effect:Destroy()
		end
	end)
end

function Generator._touched(self: Generator, data: PieceData, hit: BasePart)
	local character = getCharacterFromHit(hit)
	local player = if character then Players:GetPlayerFromCharacter(character) else nil
	if not character or not player or not self:_validProgress(player, character, data) then
		return
	end

	if data.UnlocksGeneration then
		data.UnlocksGeneration = false
		ParkourConfig.CAN_GENERATE = true
	end

	if not data.CanReward or data.Rewarded[player] then
		return
	end

	data.Rewarded[player] = true
	if data.Highlight then
		data.Highlight:Destroy()
		data.Highlight = nil
	end
	self:_giveBonus(player)
	self:_playUnlockVFX(data.Object)
end

function Generator._connectTouches(self: Generator, data: PieceData)
	local function connect(part: BasePart)
		table.insert(data.Connections, part.Touched:Connect(function(hit: BasePart)
			self:_touched(data, hit)
		end))
	end

	if data.Object:IsA("BasePart") then
		connect(data.Object)
	end
	for _, descendant in data.Object:GetDescendants() do
		if descendant:IsA("BasePart") then
			connect(descendant)
		end
	end
end

function Generator._register(self: Generator, object: Instance, id: number, kind: SpawnType, canReward: boolean)
	local data: PieceData = {
		Object = object,
		Id = id,
		Kind = kind,
		Connections = {},
		Rewarded = {},
		CanReward = canReward,
		UnlocksGeneration = kind == "Platform" and self.LastType == "Obby",
		Highlight = if canReward then self:_highlight(object) else nil,
	}

	object:SetAttribute("ID", id)
	CollectionService:AddTag(object, kind)
	self.Pieces[id] = data
	self:_connectTouches(data)
end

function Generator._configureCutscenePlatform(self: Generator, object: Instance)
	CollectionService:AddTag(object, "CutscenePlatform")

	local trigger = Instance.new("Part")
	trigger.Name = "CutsceneTrigger"
	trigger.Anchored = true
	trigger.Transparency = 1
	trigger.CanCollide = false
	trigger.CanQuery = false
	trigger.CanTouch = false
	trigger.Size = Vector3.new(17, 1, 17)
	trigger.CFrame = getPivot(object) * CFrame.new(0, -2, 0)
	trigger.Parent = object
end

function Generator._spawn(self: Generator)
	local kind: SpawnType = self:_spawnType(self.NextId)
	local template = self:_template(kind)

	-- A missing special folder should not permanently stop the endless course.
	if not template and kind ~= "Platform" then
		kind = "Platform"
		template = self:_template(kind)
	end
	if not template then
		return
	end

	local object = self:_place(template, kind)
	if not object then
		return
	end

	local id: number = self.NextId
	local previousType: SpawnType = self.LastType
	self:_register(object, id, kind, kind == "Platform")

	if kind == "Platform" then
		self:_addMotion(object)
		if previousType == "Obby" then
			ParkourConfig.CAN_GENERATE = false
		end
		if id == ParkourConfig.PLATFORMS_TO_REST - 4 then
			self:_configureCutscenePlatform(object)
		end
	elseif kind == "Rest" then
		ParkourConfig.CAN_GENERATE = false
		task.spawn(function()
			local ok, message = pcall(NPCSetup.configureNPCsFrom, object)
			if not ok then
				warn("[ParkourService] NPC setup failed:", message)
			end
		end)
	end

	if object.Name == "Final_Obby" then
		CollectionService:AddTag(object, "FINAL_OBBY")
		ParkourConfig.CAN_GENERATE = false
	end

	self.LastPiece = object
	self.LastType = kind
	self.NextId = id + 1
end

function Generator._playerRange(self: Generator): (number?, number?)
	local furthest: number? = nil
	local slowest: number? = nil

	for _, player in Players:GetPlayers() do
		local id = PlayerPlatformUtil.getPlatformIdFrom(player)
		if id then
			furthest = if furthest then math.max(furthest, id) else id
			slowest = if slowest then math.min(slowest, id) else id
		end
	end

	return furthest, slowest
end

function Generator._remove(self: Generator, data: PieceData, destroy: boolean)
	for _, connection in data.Connections do
		connection:Disconnect()
	end

	self.Motion[data.Object] = nil
	self.Pieces[data.Id] = nil
	table.clear(data.Rewarded)

	if destroy then
		data.Object:Destroy()
	end
end

function Generator._cleanup(self: Generator, slowest: number)
	local cutoff = math.floor(slowest - ParkourConfig.DELETE_BUFFER)
	-- IDs are monotonic, so a cursor removes each old piece once instead of repeatedly
	-- scanning every CollectionService tag on every generation step.
	while self.OldestId < cutoff do
		local id = self.OldestId
		self.OldestId += 1
		local data = self.Pieces[id]
		if not data then
			continue
		end

		if data.Object == self.InitialPlatform then
			self:_remove(data, false)
			data.Object.Parent = ServerStorage
		else
			self:_remove(data, true)
		end
	end
end

function Generator._generationStep(self: Generator)
	if self.Resetting or not ParkourConfig.CAN_GENERATE then
		return
	end

	local furthest, slowest = self:_playerRange()
	if not furthest then
		return
	end
	if slowest then
		self:_cleanup(slowest)
	end
	if self.NextId - furthest >= ParkourConfig.MAX_AHEAD_OF_FIRST then
		return
	end

	self:_spawn()
end

function Generator._updateMotion(self: Generator, deltaTime: number)
	self.MotionAccumulator = self.MotionAccumulator + deltaTime
	if self.MotionAccumulator < MOTION_STEP then
		return
	end
	self.MotionAccumulator = self.MotionAccumulator % MOTION_STEP

	local now = Workspace:GetServerTimeNow()
	for object, motion in self.Motion do
		if not object.Parent then
			self.Motion[object] = nil
			continue
		end

		local height = (math.sin(now * motion.AngularSpeed + motion.Phase) + 1) * 0.5 * motion.Height
		pivotTo(object, motion.BasePivot * CFrame.new(0, height, 0))
	end
end

function Generator._clearCourse(self: Generator)
	local records = {}
	for _, data in self.Pieces do
		table.insert(records, data)
	end

	for _, data in records do
		self:_remove(data, data.Object ~= self.InitialPlatform)
	end

	-- Tagged pieces not owned by this instance can remain after a Studio hot reload.
	local initial: Instance = self.InitialPlatform
	for _, tag in SPAWN_TAGS do
		for _, object in CollectionService:GetTagged(tag) do
			if object ~= initial and object:IsDescendantOf(Workspace) then
				object:Destroy()
			end
		end
	end
end

function Generator._reset(self: Generator)
	if self.Resetting then
		return
	end
	self.Resetting = true
	ParkourConfig.CAN_GENERATE = false
	task.wait(0.6)

	self:_clearCourse()
	local initial: Instance = self.InitialPlatform
	initial.Parent = Workspace
	initial:SetAttribute("ID", 0)
	CollectionService:AddTag(initial, "Platform")

	self.NextId = 1
	self.OldestId = 0
	self.LastPiece = initial
	self.LastType = "Platform"
	self.Biome = nil
	self.BiomeStartedAt = 0
	self.MotionAccumulator = 0
	table.clear(self.Progress)
	table.clear(self.LastTouch)
	ParkourConfig.currentBiome.folder = nil
	ParkourConfig.currentBiome.startedAt = 0
	self:_register(initial, 0, "Platform", false)

	ParkourConfig.CAN_GENERATE = true
	self.Resetting = false
end

function Generator.start(self: Generator)
	if self.Running then
		return
	end
	self.Running = true

	self.InitialPlatform:SetAttribute("ID", 0)
	CollectionService:AddTag(self.InitialPlatform, "Platform")
	self:_register(self.InitialPlatform, 0, "Platform", false)

	table.insert(self.Connections, RunService.Heartbeat:Connect(function(deltaTime: number)
		-- All moving platforms share one throttled scheduler rather than one event per part.
		self:_updateMotion(deltaTime)
	end))

	table.insert(self.Connections, FastRestart.Event:Connect(function()
		task.spawn(function()
			self:_reset()
		end)
	end))

	table.insert(self.Connections, Players.PlayerRemoving:Connect(function(player: Player)
		self.Progress[player] = nil
		self.LastTouch[player] = nil
		for _, data in self.Pieces do
			data.Rewarded[player] = nil
		end
	end))

	VendingUtil.configureMachines()
	PlatformCutsceneUtil.trackPlayers()

	task.spawn(function()
		while self.Running do
			-- A malformed template can fail one iteration without killing future generation.
			local ok, message = xpcall(function()
				self:_generationStep()
			end, debug.traceback)
			if not ok then
				warn("[ParkourService] Generation step failed:\n" .. tostring(message))
			end
			task.wait(GENERATION_INTERVAL)
		end
	end)
end

function Generator.destroy(self: Generator)
	if not self.Running then
		return
	end
	self.Running = false

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)

	for _, data in self.Pieces do
		for _, connection in data.Connections do
			connection:Disconnect()
		end
	end
	table.clear(self.Motion)
	table.clear(self.Progress)
	table.clear(self.LastTouch)
end

local ParkourService = {}
local activeGenerator: Generator? = nil

function ParkourService.init()
	if activeGenerator then
		return
	end

	local generator = Generator.new()
	activeGenerator = generator
	generator:start()
end

function ParkourService.destroy()
	if not activeGenerator then
		return
	end

	activeGenerator:destroy()
	activeGenerator = nil
end

return ParkourService