local httpService = game:GetService("HttpService")
local players = game:GetService("Players")
local runService = game:GetService("RunService")

local defaultData = require(script.Parent.Parent.Configs.DataConfig) :: { [string]: any }
local dataUtil = require(script.Parent.Parent.Utils.DataUtil)

local DATA_LOADED_ATTRIBUTE = "DataLoaded"
local SESSION_LOCK_TIMEOUT = 180
local SHUTDOWN_SAVE_TIMEOUT = 25
local SESSION_ID = if game.JobId ~= "" then game.JobId else `Studio_{httpService:GenerateGUID(false)}`

local NESTED_DATA_ATTRIBUTES = {
	EquippedGlove = { "Inventory", "Gloves", "EquippedGlove" },
	EquippedGloveFolder = { "Inventory", "Gloves", "EquippedFolder" },
	EquippedMonkeyColor = { "Inventory", "MonkeyColors", "EquippedColor" },
	EquippedMonkeyFolder = { "Inventory", "MonkeyColors", "EquippedFolder" },
}

type PlayerData = { [string]: any }
type DataPath = { string | number }
type SessionData = {
	Id: string,
	UpdatedAt: number,
}
type StoredProfile = {
	PlayerData: PlayerData,
	Session: SessionData?,
}
type PlayerState = {
	data: PlayerData,
	persistent: boolean,
	version: number,
	savedVersion: number,
	saving: boolean,
}

local initialized = false
local closing = false
local states: { [Player]: PlayerState } = {}
local loadingPlayers: { [Player]: boolean } = {}
local dataHandler = {}

local function getKey(player: Player): string
	return tostring(player.UserId)
end

local function isSessionActive(session: SessionData?): boolean
	return session ~= nil and session.Id ~= SESSION_ID and os.time() - session.UpdatedAt < SESSION_LOCK_TIMEOUT
end

local function unpackProfile(storedValue: any): (any, SessionData?)
	if typeof(storedValue) == "table" and typeof(storedValue.PlayerData) == "table" then
		local session = storedValue.Session
		if typeof(session) == "table" and typeof(session.Id) == "string" and typeof(session.UpdatedAt) == "number" then
			return storedValue.PlayerData, session
		end

		return storedValue.PlayerData, nil
	end

	return storedValue, nil
end

local function createStoredProfile(data: PlayerData, releaseSession: boolean): StoredProfile
	return {
		PlayerData = data,
		Session = if releaseSession
			then nil
			else {
				Id = SESSION_ID,
				UpdatedAt = os.time(),
			},
	}
end

local function isAttributeValue(value: any): boolean
	local valueType = typeof(value)
	return valueType == "boolean" or valueType == "number" or valueType == "string"
end

local function setConfiguredAttribute(player: Player, name: string, value: any)
	player:SetAttribute(name, value)
end

local function syncTopLevelAttribute(player: Player, path: DataPath, value: any)
	local attributeName = path[1]
	if #path == 1 and typeof(attributeName) == "string" and isAttributeValue(value) then
		setConfiguredAttribute(player, attributeName, value)
	end
end

local function pathsMatch(first: DataPath, second: DataPath): boolean
	if #first ~= #second then
		return false
	end

	for index, value in ipairs(first) do
		if second[index] ~= value then
			return false
		end
	end

	return true
end

local function syncNestedAttribute(player: Player, path: DataPath, value: any)
	if not isAttributeValue(value) then
		return
	end

	for attributeName, attributePath in pairs(NESTED_DATA_ATTRIBUTES) do
		if pathsMatch(path, attributePath) then
			setConfiguredAttribute(player, attributeName, value)
			return
		end
	end
end

local function captureRuntimeAttributes(player: Player, state: PlayerState)
	for name, template in pairs(defaultData) do
		local value = player:GetAttribute(name)
		if isAttributeValue(template) and dataUtil.matchesTemplate(value, template) then
			dataUtil.setValue(state.data, { name }, value)
		end
	end

	for attributeName, path in pairs(NESTED_DATA_ATTRIBUTES) do
		local value = player:GetAttribute(attributeName)
		local template = dataUtil.getValue(defaultData, path)
		if template ~= nil and dataUtil.matchesTemplate(value, template) then
			dataUtil.setValue(state.data, path, value)
		end
	end

	state.version += 1
end

local function setValue(player: Player, path: DataPath, value: any): boolean
	local state = states[player]
	local template = dataUtil.getValue(defaultData, path)
	if not state or template == nil or not dataUtil.matchesTemplate(value, template) then
		return false
	end

	if not dataUtil.setValue(state.data, path, value) then
		return false
	end

	state.version += 1
	syncTopLevelAttribute(player, path, value)
	syncNestedAttribute(player, path, value)
	return true
end

local function connectAttributes(player: Player, state: PlayerState)
	for name, template in pairs(defaultData) do
		local value = state.data[name]
		if isAttributeValue(template) and isAttributeValue(value) then
			player:SetAttribute(name, value)
		end
	end

	for attributeName, path in pairs(NESTED_DATA_ATTRIBUTES) do
		local value = dataUtil.getValue(state.data, path)
		if isAttributeValue(value) then
			player:SetAttribute(attributeName, value)
		end
	end
end

local function loadPlayerData(player: Player): (PlayerData?, boolean)
	local loadedData: PlayerData? = nil
	local acquiredSession = false
	local success, result = dataUtil.updateData(getKey(player), function(storedValue: any)
		local savedData, session = unpackProfile(storedValue)
		if isSessionActive(session) then
			return nil
		end

		loadedData = dataUtil.reconcile(savedData, defaultData)
		acquiredSession = true
		return createStoredProfile(loadedData :: PlayerData, false)
	end)

	if success and acquiredSession then
		return loadedData, true
	end
	if success then
		warn(`Data for {player.Name} is active in another server.`)
		return nil, false
	end

	warn(`Could not load data for {player.Name}: {tostring(result)}`)
	if runService:IsStudio() then
		return dataUtil.copy(defaultData), false
	end

	return nil, false
end

local function savePlayerState(player: Player, state: PlayerState, releaseSession: boolean): boolean
	if not state.persistent then
		return true
	end
	if not releaseSession and (closing or states[player] ~= state or player.Parent ~= players) then
		return false
	end
	if state.saving then
		return false
	end
	if releaseSession then
		captureRuntimeAttributes(player, state)
	end

	state.saving = true
	local savedVersion = state.version
	local snapshot = dataUtil.copy(state.data)
	local ownsSession = true
	local success, result = dataUtil.updateData(getKey(player), function(storedValue: any)
		local _, session = unpackProfile(storedValue)
		if isSessionActive(session) then
			ownsSession = false
			return nil
		end

		return createStoredProfile(snapshot, releaseSession)
	end)
	state.saving = false

	if success and ownsSession then
		state.savedVersion = savedVersion
		return true
	end

	warn(`Could not save data for {player.Name}: {tostring(result)}`)
	return false
end

local function releasePlayer(player: Player)
	local state = states[player]
	if not state then
		return
	end

	local deadline = os.clock() + SHUTDOWN_SAVE_TIMEOUT
	while state.saving and os.clock() < deadline do
		task.wait(0.1)
	end
	savePlayerState(player, state, true)
	states[player] = nil
end

local function loadPlayer(player: Player)
	if loadingPlayers[player] or states[player] then
		return
	end

	loadingPlayers[player] = true
	player:SetAttribute(DATA_LOADED_ATTRIBUTE, false)
	local data, persistent = loadPlayerData(player)
	loadingPlayers[player] = nil

	if not data then
		if player.Parent == players then
			player:Kick("Your data is already loaded or could not be loaded. Please rejoin.")
		end
		return
	end

	local state: PlayerState = {
		data = data,
		persistent = persistent,
		version = 0,
		savedVersion = 0,
		saving = false,
	}
	states[player] = state

	if player.Parent ~= players then
		releasePlayer(player)
		return
	end

	connectAttributes(player, state)
	player:SetAttribute(DATA_LOADED_ATTRIBUTE, true)
end

function dataHandler.get(player: Player): PlayerData?
	local state = states[player]
	return if state then dataUtil.copy(state.data) else nil
end

function dataHandler.getValue(player: Player, path: DataPath): any
	local state = states[player]
	return if state then dataUtil.copy(dataUtil.getValue(state.data, path)) else nil
end

function dataHandler.setValue(player: Player, path: DataPath, value: any): boolean
	return setValue(player, path, value)
end

function dataHandler.updateValue(player: Player, path: DataPath, transform: (any) -> any): (boolean, any)
	local currentValue = dataHandler.getValue(player, path)
	local updatedValue = transform(currentValue)
	local changed = setValue(player, path, updatedValue)
	local returnedValue = if changed then dataUtil.copy(updatedValue) else currentValue
	return changed, returnedValue
end

function dataHandler.incrementValue(player: Player, path: DataPath, amount: number): (boolean, number?)
	local currentValue = dataHandler.getValue(player, path)
	if typeof(currentValue) ~= "number" then
		return false, nil
	end

	local updatedValue = currentValue + amount
	return setValue(player, path, updatedValue), updatedValue
end

function dataHandler.save(player: Player): boolean
	local state = states[player]
	return if state then savePlayerState(player, state, false) else false
end

function dataHandler.init()
	if initialized then
		return
	end
	initialized = true

	for _, player in ipairs(players:GetPlayers()) do
		task.spawn(loadPlayer, player)
	end
	players.PlayerAdded:Connect(function(player)
		task.spawn(loadPlayer, player)
	end)
	players.PlayerRemoving:Connect(function(player)
		task.defer(releasePlayer, player)
	end)

	game:BindToClose(function()
		closing = true
		local pendingSaves = 0
		for player in pairs(states) do
			pendingSaves += 1
			task.spawn(function()
				releasePlayer(player)
				pendingSaves -= 1
			end)
		end

		local deadline = os.clock() + SHUTDOWN_SAVE_TIMEOUT
		while pendingSaves > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return dataHandler
