--!strict

local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage = game:GetService("ServerStorage")
local workspace = game:GetService("Workspace")

local bananasSpawner = require(script.Parent.Parent.Utils.BananasSpawner)

local sharedFolder = replicatedStorage:FindFirstChild("Shared")
local eventsFolder = sharedFolder:FindFirstChild("Events")
local matchEvent = eventsFolder:FindFirstChild("MatchEvent")

local assetsFolder = serverStorage:FindFirstChild("Assets")
local mapsFolder = assetsFolder:FindFirstChild("Maps")
local crownTemplate = assetsFolder:FindFirstChild("Crown")

local intermissionModel = workspace:FindFirstChild("Lobby")

local INTERMISSION_DURATION = 10
local MATCH_DURATION = 5 * 60
local MATCH_START_COUNTDOWN = 3
local RESPAWN_IN_MATCH = true -- Set to false to leave match respawning to your game.
local CHARACTER_ASSURANCE = 0.1
local MAP_CFRAME = CFrame.new(Vector3.new(50, 300, 0))
local BANANAS_COLLECTABLE_ATTRIBUTE = "BananasCollectable"
local MATCH_START_TIME_ATTRIBUTE = "BananasMatchStartedAt"
local MATCH_BANANAS_FOLDER = "MatchBananas"
local LEADER_CROWN_NAME = "MatchLeaderCrown"
local LEADER_HIGHLIGHT_NAME = "MatchLeaderHighlight"

local activeMap: Model?
local started = false
local phase = "Intermission"
local participatingPlayers: { [Player]: boolean } = {}
local matchLeader: Player?
local matchService = {}

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
		if player.Parent == players then
			moveCharacterToModel(player, model)
		end
	end
end

local function prepareMatchBananas(player: Player)
	local oldFolder = player:FindFirstChild(MATCH_BANANAS_FOLDER)
	if oldFolder then
		for _, instance in pairs(oldFolder:GetChildren()) do
			if instance:IsA("StringValue") then
				instance:Destroy()
			end
		end

		return
	end

	local matchBananas = Instance.new("Folder")
	matchBananas.Name = MATCH_BANANAS_FOLDER
	matchBananas.Parent = player
end

local function getMatchBananaPoints(player: Player): number
	local matchBananas = player:FindFirstChild(MATCH_BANANAS_FOLDER)
	if not matchBananas then
		return 0
	end

	local points = 0
	for _, entry in ipairs(matchBananas:GetChildren()) do
		points += tonumber((entry :: StringValue).Value) or 0
	end

	return points
end

local function settleMatchBananas(player: Player)
	local matchBananas = player:FindFirstChild(MATCH_BANANAS_FOLDER)
	if not matchBananas then
		return
	end

	local bananasAttribute = player:GetAttribute("Bananas")
	local currentBananas = if typeof(bananasAttribute) == "number" then bananasAttribute else 0
	player:SetAttribute("Bananas", currentBananas + getMatchBananaPoints(player))
	prepareMatchBananas(player)
end

local function removeLeaderVisuals(player: Player)
	local character = player.Character
	if not character then
		return
	end

	for _, name in ipairs({ LEADER_CROWN_NAME, LEADER_HIGHLIGHT_NAME }) do
		local visual = character:FindFirstChild(name)
		if visual then
			visual:Destroy()
		end
	end
end

local function addLeaderVisuals(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid then
		return
	end

	removeLeaderVisuals(player)
	local hatAttachment = character:FindFirstChild("HatAttachment", true)
	if
		hatAttachment
		and hatAttachment:IsA("Attachment")
		and not (hatAttachment.Parent and hatAttachment.Parent:IsA("BasePart"))
	then
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("Motor6D") and descendant.Name == "Head" and descendant.Part1 then
				hatAttachment.Parent = descendant.Part1
				break
			end
		end
	end

	local crown = crownTemplate:Clone()
	crown.Name = LEADER_CROWN_NAME
	local handle = crown:FindFirstChild("Handle") :: BasePart
	for _, descendant in ipairs(crown:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true

			if descendant ~= handle then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "CrownWeld"
				weld.Part0 = handle
				weld.Part1 = descendant
				weld.Parent = handle
			end
		end
	end

	humanoid:AddAccessory(crown)

	local highlight = Instance.new("Highlight")
	highlight.Name = LEADER_HIGHLIGHT_NAME
	highlight.Adornee = character
	highlight.FillColor = Color3.fromRGB(255, 221, 0)
	highlight.FillTransparency = 0.45
	highlight.OutlineColor = Color3.fromRGB(255, 255, 0)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character
end

local function setMatchLeader(player: Player?)
	if player == matchLeader then
		return
	end

	if matchLeader then
		removeLeaderVisuals(matchLeader)
	end

	matchLeader = player
	if player then
		addLeaderVisuals(player)
	end
end

local function updateMatchLeader()
	local leader = matchLeader
	local highestPoints = 0
	if leader and participatingPlayers[leader] and leader.Parent == players then
		highestPoints = getMatchBananaPoints(leader)
	else
		leader = nil
	end

	for player in pairs(participatingPlayers) do
		if player.Parent == players then
			local points = getMatchBananaPoints(player)
			if points > highestPoints then
				leader = player
				highestPoints = points
			end
		end
	end

	setMatchLeader(if highestPoints > 0 then leader else nil)
end

local function shouldRespawnInMatch(player: Player): boolean
	return RESPAWN_IN_MATCH
		and (phase == "MatchStarting" or phase == "Match")
		and participatingPlayers[player] == true
		and player.Parent == players
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

	local destination = if shouldRespawnInMatch(player) then activeMap else intermissionModel

	if destination then
		task.defer(moveCharacterToModel, player, destination)
	end

	if player == matchLeader then
		task.defer(addLeaderVisuals, player)
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
	selectedMap.Parent = workspace
	activeMap = selectedMap
	return selectedMap
end

local function runIntermission()
	phase = "Intermission"
	setMatchLeader(nil)
	table.clear(participatingPlayers)
	movePlayersToModel(players:GetPlayers(), intermissionModel)

	for seconds = INTERMISSION_DURATION, 0, -1 do
		sendCountdown("Intermission", seconds, nil)
		if seconds > 0 then
			task.wait(1)
		end
	end
end

local function runMatch()
	local playersForMatch = players:GetPlayers()
	if #playersForMatch <= 0 then
		setMatchLeader(nil)
		destroyActiveMap()
		phase = "Intermission"
		table.clear(participatingPlayers)

		return
	end

	destroyActiveMap()
	setMatchLeader(nil)
	local selectedMap = chooseMap()
	selectedMap:SetAttribute(BANANAS_COLLECTABLE_ATTRIBUTE, false)
	phase = "MatchStarting"
	table.clear(participatingPlayers)
	for _, player in ipairs(playersForMatch) do
		participatingPlayers[player] = true
		prepareMatchBananas(player)
	end

	-- Configure match characters here
	movePlayersToModel(playersForMatch, selectedMap)
	task.spawn(bananasSpawner.spawnBananasInMap, selectedMap, MATCH_DURATION)

	for seconds = MATCH_START_COUNTDOWN, 1, -1 do
		sendCountdown("MatchStarting", seconds, selectedMap)
		task.wait(1)
	end

	phase = "Match"
	selectedMap:SetAttribute(BANANAS_COLLECTABLE_ATTRIBUTE, true)
	selectedMap:SetAttribute(MATCH_START_TIME_ATTRIBUTE, workspace:GetServerTimeNow())
	for seconds = MATCH_DURATION, 0, -1 do
		updateMatchLeader()
		sendCountdown("Match", seconds, selectedMap)
		if seconds > 0 then
			task.wait(1)
		end
	end

	selectedMap:SetAttribute(BANANAS_COLLECTABLE_ATTRIBUTE, false)
	setMatchLeader(nil)
	for _, player in ipairs(playersForMatch) do
		if player.Parent == players then
			settleMatchBananas(player)
		end
	end
	destroyActiveMap()
	phase = "Intermission"
	table.clear(participatingPlayers)
end

function matchService.init()
	if started then
		return
	end
	started = true

	for _, player in ipairs(players:GetPlayers()) do
		connectPlayer(player)
	end
	players.PlayerAdded:Connect(connectPlayer)
	players.PlayerRemoving:Connect(function(player)
		if participatingPlayers[player] then
			settleMatchBananas(player)
			participatingPlayers[player] = nil
		end

		if player == matchLeader then
			setMatchLeader(nil)
			if phase == "Match" then
				updateMatchLeader()
			end
		end
	end)

	task.spawn(function()
		while true do
			runIntermission()
			runMatch()
		end
	end)
end

return matchService
