--!strict

local dataStoreService = game:GetService("DataStoreService")

local DATA_STORE_NAME = "PlayerData"
local MAX_REQUEST_ATTEMPTS = 4
local BASE_RETRY_DELAY = 1
local MAX_RETRY_DELAY = 8

export type PlayerData = { [string]: any }
export type DataKey = string | number
export type DataPath = { DataKey }

local standardStore = dataStoreService:GetDataStore(DATA_STORE_NAME)
local orderedStore = dataStoreService:GetOrderedDataStore(DATA_STORE_NAME)
local retryRandom = Random.new()
local dataUtil = {}

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isArray(value: { [any]: any }): boolean
	local length = #value
	local entries = 0

	for key in pairs(value) do
		if typeof(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > length then
			return false
		end
		entries += 1
	end

	return entries == length
end

local function copyValue(value: any, copies: { [any]: any }): any
	if typeof(value) ~= "table" then
		return value
	end

	local existingCopy = copies[value]
	if existingCopy then
		return existingCopy
	end

	local copy: { [any]: any } = {}
	copies[value] = copy
	for key, childValue in pairs(value) do
		copy[copyValue(key, copies)] = copyValue(childValue, copies)
	end

	return copy
end

local function isSerializableValue(value: any, visited: { [any]: boolean }): boolean
	local valueType = typeof(value)
	if valueType == "boolean" or valueType == "string" then
		return true
	end
	if valueType == "number" then
		return isFiniteNumber(value)
	end
	if valueType ~= "table" or visited[value] then
		return false
	end

	visited[value] = true
	for key, childValue in pairs(value) do
		local keyType = typeof(key)
		local validKey = keyType == "string" or (keyType == "number" and isFiniteNumber(key))
		if not validKey or not isSerializableValue(childValue, visited) then
			visited[value] = nil
			return false
		end
	end
	visited[value] = nil

	return true
end

local function matchesTemplate(value: any, template: any): boolean
	if typeof(template) ~= "table" then
		return typeof(value) == typeof(template) and isSerializableValue(value, {})
	end
	if typeof(value) ~= "table" or not isSerializableValue(value, {}) then
		return false
	end
	if next(template) == nil then
		return true
	end

	if isArray(template) then
		if not isArray(value) then
			return false
		end

		local itemTemplate = template[1]
		for _, item in ipairs(value) do
			if not matchesTemplate(item, itemTemplate) then
				return false
			end
		end
		return true
	end

	for key in pairs(value) do
		if template[key] == nil then
			return false
		end
	end
	for key, childTemplate in pairs(template) do
		if not matchesTemplate(value[key], childTemplate) then
			return false
		end
	end

	return true
end

local function reconcileValue(savedValue: any, defaultValue: any): any
	if typeof(defaultValue) ~= "table" then
		return if matchesTemplate(savedValue, defaultValue) then savedValue else copyValue(defaultValue, {})
	end
	if typeof(savedValue) ~= "table" then
		return copyValue(defaultValue, {})
	end
	if next(defaultValue) == nil then
		return if isSerializableValue(savedValue, {}) then copyValue(savedValue, {}) else {}
	end

	if isArray(defaultValue) then
		if not isArray(savedValue) then
			return copyValue(defaultValue, {})
		end

		local itemTemplate = defaultValue[1]
		local reconciledArray: { any } = {}
		for _, item in ipairs(savedValue) do
			if matchesTemplate(item, itemTemplate) then
				table.insert(reconciledArray, reconcileValue(item, itemTemplate))
			end
		end
		return reconciledArray
	end

	local reconciledTable: { [any]: any } = {}
	for key, childDefault in pairs(defaultValue) do
		reconciledTable[key] = reconcileValue(savedValue[key], childDefault)
	end
	return reconciledTable
end

local function request(callback: () -> any): (boolean, any)
	local lastError: any = nil

	for attempt = 1, MAX_REQUEST_ATTEMPTS do
		local success, result = pcall(callback)
		if success then
			return true, result
		end

		lastError = result
		if attempt < MAX_REQUEST_ATTEMPTS then
			local retryDelay = math.min(BASE_RETRY_DELAY * 2 ^ (attempt - 1), MAX_RETRY_DELAY)
			task.wait(retryDelay + retryRandom:NextNumber(0, 0.5))
		end
	end

	return false, lastError
end

function dataUtil.copy(value: any): any
	return copyValue(value, {})
end

function dataUtil.isSerializable(value: any): boolean
	return isSerializableValue(value, {})
end

function dataUtil.matchesTemplate(value: any, template: any): boolean
	return matchesTemplate(value, template)
end

function dataUtil.reconcile(savedData: any, defaultData: PlayerData): PlayerData
	return reconcileValue(savedData, defaultData)
end

function dataUtil.getValue(data: PlayerData, path: DataPath): any
	local current: any = data
	for _, key in ipairs(path) do
		if typeof(current) ~= "table" then
			return nil
		end
		current = current[key]
	end
	return current
end

function dataUtil.setValue(data: PlayerData, path: DataPath, value: any): boolean
	if #path == 0 or not dataUtil.isSerializable(value) then
		return false
	end

	local current: any = data
	for index = 1, #path - 1 do
		local key = path[index]
		local child = current[key]
		if typeof(child) ~= "table" then
			child = {}
			current[key] = child
		end
		current = child
	end

	current[path[#path]] = dataUtil.copy(value)
	return true
end

function dataUtil.getData(key: string): (boolean, any)
	return request(function()
		return standardStore:GetAsync(key)
	end)
end

function dataUtil.updateData(key: string, transform: (any) -> any): (boolean, any)
	return request(function()
		return standardStore:UpdateAsync(key, transform)
	end)
end

function dataUtil.removeData(key: string): (boolean, any)
	return request(function()
		return standardStore:RemoveAsync(key)
	end)
end

function dataUtil.getOrderedData(key: string): (boolean, any)
	return request(function()
		return orderedStore:GetAsync(key)
	end)
end

function dataUtil.setOrderedData(key: string, value: number): (boolean, any)
	if not isFiniteNumber(value) or value % 1 ~= 0 then
		return false, "Ordered data values must be finite integers."
	end

	return request(function()
		return orderedStore:SetAsync(key, value)
	end)
end

function dataUtil.incrementOrderedData(key: string, amount: number): (boolean, any)
	if not isFiniteNumber(amount) or amount % 1 ~= 0 then
		return false, "Ordered data increments must be finite integers."
	end

	return request(function()
		return orderedStore:IncrementAsync(key, amount)
	end)
end

function dataUtil.getSortedData(
	ascending: boolean,
	pageSize: number,
	minimumValue: number?,
	maximumValue: number?
): (boolean, any)
	return request(function()
		return orderedStore:GetSortedAsync(ascending, pageSize, minimumValue, maximumValue)
	end)
end

return dataUtil
