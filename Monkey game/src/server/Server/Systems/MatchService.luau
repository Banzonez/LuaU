--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local BananasSpawner = require(script.Parent.Parent.Utils.BananasSpawner)

local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
assert(sharedFolder, "ReplicatedStorage.Shared is missing.")
local eventsFolder = sharedFolder:FindFirstChild("Events")
assert(eventsFolder, "ReplicatedStorage.Shared.Events is missing.")
local matchEvent = eventsFolder:FindFirstChild("MatchEvent")
assert(matchEvent and matchEvent:IsA("RemoteEvent"), "ReplicatedStorage.Shared.Events.MatchEvent must be a RemoteEvent")

local assetsFolder = ServerStorage:FindFirstChild("Assets")
assert(assetsFolder, "ServerStorage.Assets is missing.")
local mapsFolder = assetsFolder:FindFirstChild("Maps")
assert(mapsFolder, "ServerStorage.Assets.Maps is missing.")

local intermissionModel = Workspace:FindFirstChild("Lobby")
assert(intermissionModel and intermissionModel:IsA("Model"), "Workspace.Lobby must be a Model")

local soundsFolder = ServerStorage:FindFirstChild("Sounds")
assert(soundsFolder, "ServerStorage.Sounds is missing.")
local victorySound = soundsFolder:FindFirstChild("Victory sound (at the end of round)")
assert(victorySound and victorySound:IsA("Sound"), "The match victory sound is missing from ServerStorage.Sounds.")

local INTERMISSION_DURATION = 5 -- 30
local MATCH_DURATION = 5 * 2 -- 60
local MATCH_START_COUNTDOWN = 3
local RESPAWN_IN_MATCH = true -- Set to false to leave match respawning to your game.
local CHARACTER_ASSURANCE = 0.1
local MAP_CFRAME = CFrame.new(Vector3.new(50, 300, 0))

local activeMap: Model?
local started = false
local phase = "Intermission"
local participatingPlayers: { [Player]: boolean } = {}
local MatchService = {}

local function getSpawnCFrame(model: Model): CFrame
	local spawns = model:FindFirstChild("Spawns")
	if spawns then
		local validSpawns = {}

		for _, descendant in ipairs(spawns:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(validSpawns, descendant)
			end
		end

		if #validSpawns > 0 then
			return validSpawns[math.random(1, #validSpawns)].CFrame
		end
	end

	local spawn = model:FindFirstChild("Spawn")
	if spawn and spawn:IsA("BasePart") then
		return spawn.CFrame
	end

	return model:GetPivot()
end

local function moveCharacterToModel(player: Player, model: Model)
	local character = player.Character
	if not character or not character.Parent then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart or not rootPart:IsA("BasePart") then
		warn(("Cannot move %s: custom character needs Humanoid and HumanoidRootPart"):format(player.Name))
		return
	end

	local spawnCFrame = getSpawnCFrame(model)

	-- Keep the character upright even if a spawn part or model pivot is rotated.
	local lookVector = Vector3.new(spawnCFrame.LookVector.X, 0, spawnCFrame.LookVector.Z)

	if lookVector.Magnitude < 0.001 then
		lookVector = Vector3.zAxis
	else
		lookVector = lookVector.Unit
	end

	local position = spawnCFrame.Position
		+ Vector3.yAxis * (humanoid.HipHeight + rootPart.Size.Y / 2 + CHARACTER_ASSURANCE)

	rootPart.CFrame = CFrame.lookAt(position, position + lookVector)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
end

local function movePlayersToModel(playersToMove: { Player }, model: Model)
	for _, player in ipairs(playersToMove) do
		if player.Parent == Players then
			moveCharacterToModel(player, model)
		end
	end
end

local function shouldRespawnInMatch(player: Player): boolean
	return RESPAWN_IN_MATCH
		and (phase == "MatchStarting" or phase == "Match")
		and participatingPlayers[player] == true
		and player.Parent == Players
end

local function respawnPlayer(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if not humanoid or humanoid.Health <= 0 then
		player:LoadCharacterAsync()
	end
end

local function connectCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			task.spawn(respawnPlayer, player)
		end)
	end

	local destination = if phase == "Intermission"
			or not participatingPlayers[player]
			or not shouldRespawnInMatch(player)
		then intermissionModel
		else activeMap

	if destination then
		task.defer(moveCharacterToModel, player, destination)
	end
end

local function connectPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		connectCharacter(player, character)
	end)

	if player.Character then
		connectCharacter(player, player.Character)
	end
end

local function sendCountdown(phase: string, seconds: number, map: Model?)
	matchEvent:FireAllClients({
		phase = phase,
		seconds = seconds,
		map = map,
	})
end

local function destroyActiveMap()
	if activeMap then
		activeMap:Destroy()
		activeMap = nil
	end
end

local function chooseMap(): Model
	local maps = {}
	for _, instance in ipairs(mapsFolder:GetChildren()) do
		if instance:IsA("Model") then
			table.insert(maps, instance)
		end
	end
	assert(#maps > 0, "ServerStorage.Assets.Maps must contain at least one Model")

	local selectedMap = maps[math.random(1, #maps)]:Clone()
	selectedMap:PivotTo(MAP_CFRAME)
	selectedMap.Parent = Workspace
	activeMap = selectedMap
	return selectedMap
end

local function runIntermission()
	phase = "Intermission"
	table.clear(participatingPlayers)
	movePlayersToModel(Players:GetPlayers(), intermissionModel)

	for seconds = INTERMISSION_DURATION, 0, -1 do
		sendCountdown("Intermission", seconds, nil)
		task.wait(1)
	end
end

local function runMatch()
	destroyActiveMap()
	local selectedMap = chooseMap()
	phase = "MatchStarting"
	local playersForMatch = Players:GetPlayers()
	table.clear(participatingPlayers)
	for _, player in ipairs(playersForMatch) do
		participatingPlayers[player] = true
	end

	-- Configure match characters here
	movePlayersToModel(playersForMatch, selectedMap)
	for seconds = MATCH_START_COUNTDOWN, 0, -1 do
		sendCountdown("MatchStarting", seconds, selectedMap)
		if seconds > 0 then
			task.wait(1)
		end
	end

	task.spawn(BananasSpawner.spawnBananasInMap, selectedMap)

	phase = "Match"
	for seconds = MATCH_DURATION, 0, -1 do
		sendCountdown("Match", seconds, selectedMap)
		if seconds > 0 then
			task.wait(1)
		end
	end

	local clone = victorySound:Clone()
	clone.Parent = SoundService
	clone:Play()
	clone.Ended:Connect(function()
		clone:Destroy()
	end)

	destroyActiveMap()
	phase = "Intermission"
	table.clear(participatingPlayers)
end

function MatchService.init()
	if started then
		return
	end
	started = true

	for _, player in ipairs(Players:GetPlayers()) do
		connectPlayer(player)
	end
	Players.PlayerAdded:Connect(connectPlayer)

	task.spawn(function()
		while true do
			runIntermission()
			runMatch()
		end
	end)
end

return MatchService
