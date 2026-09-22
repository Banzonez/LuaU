local debris = game:GetService("Debris")
local lighting = game:GetService("Lighting")
local tweenService = game:GetService("TweenService")
local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local serverStorage = game:GetService("ServerStorage")
local workspace = game:GetService("Workspace")

local bananasSpawner = require(script.Parent.Parent.Utils.BananasSpawner)
local progressService = require(script.Parent.ProgressService)

local sharedFolder = replicatedStorage:FindFirstChild("Shared") :: Folder
local sharedUtilsFolder = sharedFolder:FindFirstChild("Utils") :: Folder
local soundUtils = require(sharedUtilsFolder:FindFirstChild("SoundUtils"))
local eventsFolder = sharedFolder:FindFirstChild("Events") :: Folder
local matchEvent = eventsFolder:FindFirstChild("MatchEvent") :: RemoteEvent

local assetsFolder = serverStorage:FindFirstChild("Assets") :: Folder
local mapsFolder = assetsFolder:FindFirstChild("Maps") :: Folder
local crownTemplate = assetsFolder:FindFirstChild("Crown") :: Accessory

local intermissionModel = workspace:FindFirstChild("Lobby") :: Model

local INTERMISSION_DURATION = 10 -- 30
local MATCH_DURATION = 5 * 60 -- 5 minutes
local MATCH_START_COUNTDOWN = 3
local RESPAWN_IN_MATCH = true -- Set to false to leave match respawning to your game.
local CHARACTER_GROUND_CLEARANCE = 0.1
local SPAWN_GROUND_RAY_HEIGHT = 4
local SPAWN_GROUND_RAY_DISTANCE = 12
local MINIMUM_SPAWN_GROUND_NORMAL_Y = 0.5
local MAP_CFRAME = CFrame.new(Vector3.new(50, 300, 0))
local BANANAS_COLLECTABLE_ATTRIBUTE = "BananasCollectable"
local MATCH_START_TIME_ATTRIBUTE = "BananasMatchStartedAt"
local MATCH_BANANAS_FOLDER = "MatchBananas"
local LEADER_CROWN_NAME = "MatchLeaderCrown"
local LEADER_HIGHLIGHT_NAME = "MatchLeaderHighlight"
local COUNTDOWN_HIGHLIGHT_NAME = "MatchCountdownTemporaryHighlight"

local activeMap: Model?
local started = false
local phase = "Intermission"
local participatingPlayers: { [Player]: boolean } = {}
local matchLeader: Player?
local matchService = {}

local function getSpawnCFrame(model: Model): (CFrame, BasePart?)
	local spawns = model:FindFirstChild("Spawns")
	if spawns then
		local validSpawns: { BasePart } = {}

		for _, descendant in ipairs(spawns:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(validSpawns, descendant)
			end
		end

		if #validSpawns > 0 then
			local selectedSpawn = validSpawns[math.random(1, #validSpawns)]
			return selectedSpawn.CFrame, selectedSpawn
		end
	end

	local spawn = model:FindFirstChild("Spawn")
	if spawn and spawn:IsA("BasePart") then
		return spawn.CFrame, spawn
	end

	return model:GetPivot(), nil
end

local function getCharacterStandingHeight(character: Model, humanoid: Humanoid, rootPart: BasePart): number
	local standingHeight = humanoid.HipHeight + rootPart.Size.Y / 2
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		local leftLeg = character:FindFirstChild("Left Leg")
		if leftLeg and leftLeg:IsA("BasePart") then
			standingHeight += leftLeg.Size.Y
		end
	end

	return standingHeight
end

local function getSpawnGroundY(
	character: Model,
	model: Model,
	spawnCFrame: CFrame,
	spawnPart: BasePart?
): number
	local excludedInstances: { Instance } = { character }
	local spawns = model:FindFirstChild("Spawns")
	if spawns then
		table.insert(excludedInstances, spawns)
	end
	if spawnPart and (not spawns or not spawnPart:IsDescendantOf(spawns)) then
		table.insert(excludedInstances, spawnPart)
	end

	for _, player in ipairs(players:GetPlayers()) do
		local otherCharacter = player.Character
		if otherCharacter and otherCharacter ~= character then
			table.insert(excludedInstances, otherCharacter)
		end
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excludedInstances
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true

	local rayOrigin = spawnCFrame.Position + Vector3.yAxis * SPAWN_GROUND_RAY_HEIGHT
	local rayDirection = -Vector3.yAxis * SPAWN_GROUND_RAY_DISTANCE
	local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if rayResult and rayResult.Normal.Y >= MINIMUM_SPAWN_GROUND_NORMAL_Y then
		return rayResult.Position.Y
	end

	return spawnCFrame.Position.Y
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

	local spawnCFrame, spawnPart = getSpawnCFrame(model)

	-- Keep the character upright even if a spawn part or model pivot is rotated.
	local lookVector = Vector3.new(spawnCFrame.LookVector.X, 0, spawnCFrame.LookVector.Z)

	if lookVector.Magnitude < 0.001 then
		lookVector = Vector3.zAxis
	else
		lookVector = lookVector.Unit
	end

	local groundY = getSpawnGroundY(character, model, spawnCFrame, spawnPart)
	local standingHeight = getCharacterStandingHeight(character, humanoid, rootPart)
	local position = Vector3.new(
		spawnCFrame.Position.X,
		groundY + standingHeight + CHARACTER_GROUND_CLEARANCE,
		spawnCFrame.Position.Z
	)

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

local function getParticipatingPlayers(): { Player }
	local currentParticipants: { Player } = {}

	for player in pairs(participatingPlayers) do
		if player.Parent == players then
			table.insert(currentParticipants, player)
		end
	end

	return currentParticipants
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

local function settleMatchBananas(player: Player): boolean
	local matchBananas = player:FindFirstChild(MATCH_BANANAS_FOLDER)
	if not matchBananas then
		return true
	end

	local collectedPoints = getMatchBananaPoints(player)
	if collectedPoints > 0 and not progressService.addBananas(player, collectedPoints) then
		warn(`Could not settle {collectedPoints} bananas for {player.Name}.`)
		return false
	end

	prepareMatchBananas(player)
	return true
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

local function sendCountdown(phase: string, seconds: number, map: Model?, soundName: string?)
	matchEvent:FireAllClients({
		phase = phase,
		seconds = seconds,
		map = map,
		soundName = soundName,
	})
end

local function sendSound(player: Player, soundName: string)
	matchEvent:FireClient(player, {
		action = "PlaySound",
		soundName = soundName,
	})
end

local function enrollPlayerInMatch(player: Player): boolean
	local selectedMap = activeMap
	if
		participatingPlayers[player]
		or player.Parent ~= players
		or not selectedMap
		or (phase ~= "MatchStarting" and phase ~= "Match")
	then
		return false
	end

	participatingPlayers[player] = true
	progressService.beginMatch(player)
	prepareMatchBananas(player)

	if player.Character then
		task.defer(moveCharacterToModel, player, selectedMap)
	end

	sendSound(player, soundUtils.names.teleportToMatch)
	return true
end

local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.TintColor = Color3.fromRGB(0, 0, 0)
colorCorrection.Enabled = false
colorCorrection.Saturation = -1
colorCorrection.Parent = lighting
local colorCorrectionTween: Tween?

local function colorCorrectionEffect(duration: number)
	if colorCorrectionTween and colorCorrectionTween.PlaybackState == Enum.PlaybackState.Playing then
		return
	end

	colorCorrection.TintColor = Color3.fromRGB(0, 0, 0)
	colorCorrection.Saturation = -1
	colorCorrection.Enabled = true

	local tween = colorCorrectionTween
	if not tween then
		tween = tweenService:Create(colorCorrection
		,TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
		,{ TintColor = Color3.fromRGB(255, 255, 255), Saturation = 0 })

		colorCorrectionTween = tween
	end

	tween:Play()
	tween.Completed:Wait()

	colorCorrection.Enabled = false
end

local countdownHighlight = Instance.new("Highlight")
countdownHighlight.Name = COUNTDOWN_HIGHLIGHT_NAME
countdownHighlight.FillColor = Color3.fromRGB(255, 255, 255)
local function prepareHighlight(playersForHighlight: { Player }, lifetime: number)
	for _, player in ipairs(playersForHighlight) do
		local char = player.Character
		if not char then
			continue
		end

		local newLight = countdownHighlight:Clone()
		newLight.Parent = char
		debris:AddItem(newLight, lifetime)
	end
end

local function destroyActiveMap()
	if activeMap then
		activeMap:Destroy()
		activeMap = nil
	end
end

local function chooseMap(): Model
	local maps: { Model } = {}
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
		progressService.beginMatch(player)
		prepareMatchBananas(player)
	end

	-- Configure match characters here
	movePlayersToModel(playersForMatch, selectedMap)
	for _, player in ipairs(playersForMatch) do
		if player.Parent == players then
			sendSound(player, soundUtils.names.teleportToMatch)
		end
	end
	task.spawn(bananasSpawner.spawnBananasInMap, selectedMap, MATCH_DURATION)
	task.spawn(colorCorrectionEffect, 3)
	task.spawn(prepareHighlight, playersForMatch, 4)

	for seconds = MATCH_START_COUNTDOWN, 1, -1 do
		sendCountdown("MatchStarting", seconds, selectedMap, soundUtils.names.matchCountdown)
		task.wait(1)
	end
	sendCountdown("MatchStarting", 0, selectedMap, soundUtils.names.matchGo)
	task.wait(1)

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
	phase = "MatchEnding"
	local playersAtEnd = getParticipatingPlayers()
	local winner = matchLeader
	setMatchLeader(nil)
	for _, player in ipairs(playersAtEnd) do
		if player.Parent == players then
			settleMatchBananas(player)
			progressService.award(player, "PlayingMatches")
			if player == winner then
				progressService.award(player, "Winning")
			end
			progressService.finishMatch(player)
		end
	end
	destroyActiveMap()
	phase = "Intermission"
	movePlayersToModel(playersAtEnd, intermissionModel)
	for _, player in ipairs(playersAtEnd) do
		if player.Parent == players then
			local soundName = if player == winner then soundUtils.names.matchVictory else soundUtils.names.matchDefeat
			sendSound(player, soundName)
		end
	end
	table.clear(participatingPlayers)
end

function matchService.isActivePlayer(player: Player): boolean
	return phase == "Match" and participatingPlayers[player] == true
end

function matchService.init()
	if started then
		return
	end
	started = true

	local function onPlayerAdded(player: Player)
		enrollPlayerInMatch(player)
		connectPlayer(player)
	end

	for _, player in ipairs(players:GetPlayers()) do
		onPlayerAdded(player)
	end
	players.PlayerAdded:Connect(onPlayerAdded)
	players.PlayerRemoving:Connect(function(player)
		if participatingPlayers[player] then
			progressService.discardMatchCoins(player)
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
