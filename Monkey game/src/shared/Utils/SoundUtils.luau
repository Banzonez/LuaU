--!strict

local debris = game:GetService("Debris")
local soundService = game:GetService("SoundService")

local DEFAULT_LIFETIME = 10
local SPATIAL_ROLL_OFF_MAX_DISTANCE = 60
local SPATIAL_ROLL_OFF_MIN_DISTANCE = 15

export type SoundData = {
	soundId: string,
	volume: number,
	playbackSpeed: number,
}

local soundUtils = {}

soundUtils.Names = table.freeze({
	MatchCountdown = "Match Countdown",
	SlapSwing = "Slap Swing",
	SlapHit = "Slap Hit",
	SlapBlocked = "Slap Blocked",
	TeleportToMatch = "Teleport To Match",
	MatchVictory = "Match Victory",
	MatchDefeat = "Match Defeat",
})

local function scheduleCleanup(sound: Sound)
	sound.Ended:Once(function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	debris:AddItem(sound, math.max(sound.TimeLength + 1, DEFAULT_LIFETIME))
end

function soundUtils.playTemplate(template: Sound, parent: Instance?): Sound
	local sound = template:Clone()
	sound.PlayOnRemove = false
	sound.Parent = parent or soundService
	sound:Play()
	scheduleCleanup(sound)
	return sound
end

function soundUtils.playNamed(folder: Instance, soundName: string, parent: Instance?): Sound?
	local template = folder:FindFirstChild(soundName)
	if not template or not template:IsA("Sound") then
		return nil
	end

	return soundUtils.playTemplate(template, parent)
end

function soundUtils.getNamedData(folder: Instance, soundName: string): SoundData?
	local template = folder:FindFirstChild(soundName)
	if not template or not template:IsA("Sound") then
		return nil
	end

	return {
		soundId = template.SoundId,
		volume = template.Volume,
		playbackSpeed = template.PlaybackSpeed,
	}
end

function soundUtils.playData(data: SoundData, parent: Instance?): Sound?
	if data.soundId == "" then
		return nil
	end

	local sound = Instance.new("Sound")
	sound.SoundId = data.soundId
	sound.Volume = data.volume
	sound.PlaybackSpeed = data.playbackSpeed
	sound.PlayOnRemove = false
	sound.Parent = parent or soundService
	sound:Play()
	scheduleCleanup(sound)
	return sound
end

function soundUtils.playSpatialData(data: SoundData, position: Vector3): Sound?
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

	local sound = soundUtils.playData(data, source)
	if not sound then
		source:Destroy()
		return nil
	end

	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = SPATIAL_ROLL_OFF_MIN_DISTANCE
	sound.RollOffMaxDistance = SPATIAL_ROLL_OFF_MAX_DISTANCE
	sound.Ended:Once(function()
		if source.Parent then
			source:Destroy()
		end
	end)
	debris:AddItem(source, math.max(sound.TimeLength + 1, DEFAULT_LIFETIME))
	return sound
end

return soundUtils
