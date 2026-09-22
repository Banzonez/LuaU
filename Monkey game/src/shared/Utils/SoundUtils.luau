--!strict

local contentProvider = game:GetService("ContentProvider")
local debris = game:GetService("Debris")
local replicatedStorage = game:GetService("ReplicatedStorage")
local soundService = game:GetService("SoundService")

local DEFAULT_LIFETIME = 10
local SPATIAL_ROLL_OFF_MAX_DISTANCE = 60
local SPATIAL_ROLL_OFF_MIN_DISTANCE = 15

local soundTemplatesByName: { [string]: Sound } = {}
local soundTemplatesById: { [string]: Sound } = {}
local missingSoundWarnings: { [string]: boolean } = {}
local cacheReady = false
local preloadComplete = false

local soundUtils = {}

soundUtils.names = table.freeze({
	matchCountdown = "CountdownSound",
	matchGo = "GoSound",
	slapSwing = "Slap Swing",
	slapHit = "Slap Hit",
	slapBlocked = "Slap Blocked",
	teleportToMatch = "Teleport To Match",
	matchVictory = "Match Victory",
	matchDefeat = "Match Defeat",
})

local function getSoundIdKey(soundId: string): string
	return string.match(soundId, "%d+") or soundId
end

local function buildCache(): { Instance }
	if cacheReady then
		local cachedSounds: { Instance } = {}
		for _, sound in pairs(soundTemplatesById) do
			table.insert(cachedSounds, sound)
		end
		return cachedSounds
	end

	local soundsFolder = replicatedStorage:FindFirstChild("Sounds")
	if not soundsFolder then
		return {}
	end

	local sounds: { Instance } = {}
	for _, descendant in ipairs(soundsFolder:GetDescendants()) do
		if not descendant:IsA("Sound") then
			continue
		end

		if soundTemplatesByName[descendant.Name] then
			warn(`Duplicate sound name "{descendant.Name}" in ReplicatedStorage.Sounds; names must be unique.`)
		else
			soundTemplatesByName[descendant.Name] = descendant
		end

		local soundIdKey = getSoundIdKey(descendant.SoundId)
		if descendant.SoundId ~= "" and not soundTemplatesById[soundIdKey] then
			soundTemplatesById[soundIdKey] = descendant
			table.insert(sounds, descendant)
		end
	end

	cacheReady = true
	return sounds
end

local function getTemplate(soundName: string): Sound?
	if not cacheReady then
		buildCache()
	end

	local template = soundTemplatesByName[soundName]
	if template and template.SoundId ~= "" then
		return template
	end

	if not missingSoundWarnings[soundName] then
		missingSoundWarnings[soundName] = true
		warn(`Sound "{soundName}" is missing or has no SoundId in ReplicatedStorage.Sounds.`)
	end
	return nil
end

local function getAssetTemplate(soundId: string): Sound?
	if not cacheReady then
		buildCache()
	end

	local template = soundTemplatesById[getSoundIdKey(soundId)]
	if template then
		return template
	end

	if not missingSoundWarnings[soundId] then
		missingSoundWarnings[soundId] = true
		warn(`SoundId "{soundId}" is missing from ReplicatedStorage.Sounds.`)
	end
	return nil
end

local function scheduleCleanup(sound: Sound)
	sound.Ended:Once(function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	debris:AddItem(sound, math.max(sound.TimeLength + 1, DEFAULT_LIFETIME))
end

local function playTemplate(template: Sound, parent: Instance): Sound
	local sound = template:Clone()
	sound.PlayOnRemove = false
	sound.Parent = parent
	sound:Play()
	scheduleCleanup(sound)
	return sound
end

function soundUtils.preload(): boolean
	if preloadComplete then
		return true
	end

	local soundsFolder = replicatedStorage:WaitForChild("Sounds", 10)
	if not soundsFolder then
		warn("ReplicatedStorage.Sounds was not available for preloading.")
		return false
	end

	local sounds = buildCache()
	if #sounds == 0 then
		warn("ReplicatedStorage.Sounds has no sounds to preload.")
		return false
	end

	local success, message = pcall(function()
		contentProvider:PreloadAsync(sounds)
	end)
	if not success then
		warn(`Could not preload sounds: {tostring(message)}`)
		return false
	end

	preloadComplete = true
	return true
end

function soundUtils.play(soundName: string, parent: Instance?): Sound?
	local template = getTemplate(soundName)
	if not template then
		return nil
	end

	return playTemplate(template, parent or soundService)
end

function soundUtils.createAsset(soundId: string, parent: Instance?): Sound?
	local template = getAssetTemplate(soundId)
	if not template then
		return nil
	end

	local sound = template:Clone()
	sound.PlayOnRemove = false
	sound.Parent = parent or soundService
	return sound
end

function soundUtils.playAsset(soundId: string, parent: Instance?): Sound?
	local template = getAssetTemplate(soundId)
	if not template then
		return nil
	end

	return playTemplate(template, parent or soundService)
end

function soundUtils.playSpatial(soundName: string, position: Vector3): Sound?
	local template = getTemplate(soundName)
	if not template then
		return nil
	end

	local source = Instance.new("Part")
	source.Name = "SpatialSoundSource"
	source.Anchored = true
	source.CanCollide = false
	source.CanQuery = false
	source.CanTouch = false
	source.Transparency = 1
	source.Size = Vector3.one * 0.1
	source.Position = position
	source.Parent = workspace

	local sound = template:Clone()
	sound.PlayOnRemove = false
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = SPATIAL_ROLL_OFF_MIN_DISTANCE
	sound.RollOffMaxDistance = SPATIAL_ROLL_OFF_MAX_DISTANCE
	sound.Parent = source
	sound:Play()
	scheduleCleanup(sound)

	sound.Ended:Once(function()
		if source.Parent then
			source:Destroy()
		end
	end)
	debris:AddItem(source, math.max(sound.TimeLength + 1, DEFAULT_LIFETIME))
	return sound
end

return soundUtils
