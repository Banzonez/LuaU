--!strict

local utils = {}

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local StateHandler = require(
	ServerScriptService:WaitForChild("Server")
		:WaitForChild("Modules")
		:WaitForChild("Systems")
		:WaitForChild("CombatStateHandler")
)

local debug = true

type ActiveAttack = {
	player: Player,
	character: Model,
	maxAngle: number,
	damage: number,
	stunTime: number,
	settings: Types.AttackSettings,
	remainingTime: number,
	hitHumanoids: { [Humanoid]: boolean },
	hitCount: number,
}

local attacks: { [Player]: { [number]: ActiveAttack } } = {}

local tracks: {
	[Player]: {
		Animator: Animator,
		Tracks: { [Animation]: AnimationTrack },
		PlayingTrack: AnimationTrack?,
	},
} = {}
local hitConnections: { [Player]: RBXScriptConnection } = {}
local stoppedConnections: { [Player]: RBXScriptConnection } = {}
local attackIds: { [Player]: number } = {}

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude

local function clearAttackConnections(player: Player): ()
	attacks[player] = nil
	attackIds[player] = (attackIds[player] or 0) + 1
	local hitConnection = hitConnections[player]
	if hitConnection then
		hitConnection:Disconnect()
		hitConnections[player] = nil
	end

	local stoppedConnection = stoppedConnections[player]
	if stoppedConnection then
		stoppedConnection:Disconnect()
		stoppedConnections[player] = nil
	end
end

local function clearTracks(player: Player): ()
	clearAttackConnections(player)

	local playerTracks = tracks[player]
	if not playerTracks then
		return
	end

	for _, track in pairs(playerTracks.Tracks) do
		track:Stop()
		track:Destroy()
	end

	tracks[player] = nil
end

local function getTargetData(part: BasePart): (Humanoid?, BasePart?)
	local current: Instance? = part

	while current do
		if current:IsA("Model") then
			local humanoid = current:FindFirstChildOfClass("Humanoid")
			local rootPart = current:FindFirstChild("HumanoidRootPart")

			if humanoid and rootPart and rootPart:IsA("BasePart") then
				return humanoid, rootPart
			end
		end

		current = current.Parent
	end

	return nil, nil
end

function utils.preloadAnimations(folder: Instance): ()
	local animations: { Animation } = {}

	for _, instance in ipairs(folder:GetDescendants()) do
		if instance:IsA("Animation") then
			table.insert(animations, instance)
		end
	end

	if #animations > 0 then
		ContentProvider:PreloadAsync(animations)
	end
end

function utils.getAnimationDuration(player: Player, animation: Animation): number?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end

	local cachedTracks = tracks[player]
	if cachedTracks and cachedTracks.Animator ~= animator then
		clearTracks(player)
	end

	local playerTracks: {
		Animator: Animator,
		Tracks: { [Animation]: AnimationTrack },
		PlayingTrack: AnimationTrack?,
	}
	if cachedTracks and cachedTracks.Animator == animator then
		playerTracks = cachedTracks
	else
		playerTracks = {
			Animator = animator,
			Tracks = {},
			PlayingTrack = nil,
		}
		tracks[player] = playerTracks
	end

	local cachedTrack = playerTracks.Tracks[animation]
	local track: AnimationTrack
	if cachedTrack then
		track = cachedTrack
	else
		track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action
		playerTracks.Tracks[animation] = track
	end

	local timeout = os.clock() + 2
	while track.Length <= 0 and os.clock() < timeout do
		task.wait()
	end

	if track.Length <= 0 then
		warn(
			"Could not load the duration of "
				.. animation.Name
				.. " for "
				.. player.Name
				.. ". Check its AnimationId and permissions."
		)
		return nil
	end

	return track.Length
end

function utils.hitboxDebug(center: Vector3, size: Vector3, parent: Instance): ()
	if not debug then
		return
	end

	local possibleHitbox = parent:FindFirstChild("HitboxDebug")
	if possibleHitbox and possibleHitbox:IsA("BasePart") then
		possibleHitbox.Position = center
		possibleHitbox.Transparency = 0.5
		task.wait(0.05)
		possibleHitbox.Transparency = 1
		return
	end

	local hitbox = Instance.new("Part")
	hitbox.Name = "HitboxDebug"
	hitbox.Size = size
	hitbox.Transparency = 0.5
	hitbox.Color = Color3.fromRGB(165, 13, 13)
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.Parent = parent

	utils.hitboxDebug(center, size, parent)
end

function utils.attack(attack: ActiveAttack): ()
	local player = attack.player
	local character = attack.character
	if player.Parent ~= Players or player.Character ~= character then
		return
	end

	local attackerHumanoid = character:FindFirstChildOfClass("Humanoid")
	local attackerRoot = character:FindFirstChild("HumanoidRootPart")
	if not attackerHumanoid or attackerHumanoid.Health <= 0 or not attackerRoot or not attackerRoot:IsA("BasePart") then
		return
	end

	local playerState = StateHandler:GetPlayerState(player)
	if playerState.State ~= "Attacking" then
		return
	end

	overlapParams.FilterDescendantsInstances = { character }

	local closestHumanoid: Humanoid? = nil
	local closestDistance = math.huge
	local cosThreshold = math.cos(math.rad(attack.maxAngle))
	local cf = attackerRoot.CFrame * attack.settings.hitboxOffset
	local center = cf.Position
	local hitboxSize = attack.settings.hitboxSize
	task.spawn(utils.hitboxDebug, center, hitboxSize, workspace)

	for _, part in ipairs(workspace:GetPartBoundsInBox(cf, hitboxSize, overlapParams)) do
		local targetHumanoid, targetRoot = getTargetData(part)
		if not targetHumanoid or not targetRoot or targetHumanoid == attackerHumanoid or targetHumanoid.Health <= 0 or attack.hitHumanoids[targetHumanoid] then
			continue
		end

		local offset = targetRoot.Position - attackerRoot.Position
		local distance = offset.Magnitude
		if distance > 0 and attackerRoot.CFrame.LookVector:Dot(offset / distance) < cosThreshold then
			continue
		end

		if distance < closestDistance then
			closestHumanoid = targetHumanoid
			closestDistance = distance
		end
	end

	if closestHumanoid and attack.hitCount < attack.settings.maxTargets then
		attack.hitHumanoids[closestHumanoid] = true
		attack.hitCount += 1
		closestHumanoid:TakeDamage(attack.damage)
		StateHandler:StunHumanoid(closestHumanoid, attack.stunTime)
	end
end

function utils.playClickAnimation(
	player: Player,
	animation: Animation,
	maxAngle: number,
	damage: number,
	stunTime: number,
	attackSettings: Types.AttackSettings
): boolean
	local playerTracks = tracks[player]
	if not playerTracks then
		return false
	end

	local track = playerTracks.Tracks[animation]
	if not track or track.IsPlaying then
		return false
	end

	local playingTrack = playerTracks.PlayingTrack
	if playingTrack and playingTrack.IsPlaying then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	clearAttackConnections(player)

	local attackId = (attackIds[player] or 0) + 1
	attackIds[player] = attackId
	playerTracks.PlayingTrack = track

	hitConnections[player] = track:GetMarkerReachedSignal("Hit"):Connect(function()
		if attackIds[player] ~= attackId or player.Parent ~= Players or player.Character ~= character then
			return
		end
		if StateHandler:GetPlayerState(player).State ~= "Attacking" then
			clearAttackConnections(player)
			return
		end

		local attack: ActiveAttack = {
			player = player, character = character,
			maxAngle = maxAngle, damage = damage, stunTime = stunTime,
			settings = table.clone(attackSettings),
			remainingTime = attackSettings.activeDuration,
			hitHumanoids = {}, hitCount = 0,
		}
		attacks[player] = attacks[player] or {}
		attacks[player][attackId] = attack
		utils.attack(attack)

		local hitConnection = hitConnections[player]
		if hitConnection then
			hitConnection:Disconnect()
			hitConnections[player] = nil
		end
	end)

	stoppedConnections[player] = track.Stopped:Connect(function()
		if attackIds[player] ~= attackId then
			return
		end

		clearAttackConnections(player)
		if playerTracks.PlayingTrack == track then
			playerTracks.PlayingTrack = nil
		end
	end)

	track:Play(0.1)
	return true
end

RunService.Heartbeat:Connect(function(delta: number)
	for player, playerAttacks in pairs(attacks) do
		for id, attack in pairs(playerAttacks) do
			local humanoid = attack.character:FindFirstChildOfClass("Humanoid")
			if player.Parent ~= Players or player.Character ~= attack.character or not humanoid or humanoid.Health <= 0
				or attackIds[player] ~= id or StateHandler:GetPlayerState(player).State ~= "Attacking" then
				playerAttacks[id] = nil
				continue
			end

			attack.remainingTime -= delta
			if attack.remainingTime <= 0 or attack.hitCount >= attack.settings.maxTargets then
				playerAttacks[id] = nil
				continue
			end
			utils.attack(attack)
		end
		if next(playerAttacks) == nil then
			attacks[player] = nil
		end
	end
end)

utils.init = function(): ()
	Players.PlayerRemoving:Connect(function(player)
		clearTracks(player)
		attackIds[player] = nil
	end)

	local function setupPlayer(player: Player): ()
		player.CharacterRemoving:Connect(function()
			clearTracks(player)
		end)
	end

	Players.PlayerAdded:Connect(setupPlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end
end

return utils
