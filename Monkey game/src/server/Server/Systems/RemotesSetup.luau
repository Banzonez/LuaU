--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemotesConfig = require(script.Parent.Parent.Configs.RemotesConfig)

local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
assert(sharedFolder, "ReplicatedStorage.Shared is missing.")

local RemotesSetup = {}

local function load(names: { string }, className: string, parent: Instance)
	for _, name in ipairs(names) do
		if parent:FindFirstChild(name) then
			continue
		end

		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = parent
	end
end

function RemotesSetup.init()
	local events = sharedFolder:FindFirstChild("Events")
	if not events then
		events = Instance.new("Folder")
		events.Name = "Events"
		events.Parent = sharedFolder
	end

	local functions = sharedFolder:FindFirstChild("Functions")
	if not functions then
		functions = Instance.new("Folder")
		functions.Name = "Functions"
		functions.Parent = sharedFolder
	end

	load(RemotesConfig.Events, "RemoteEvent", events)
	load(RemotesConfig.Functions, "RemoteFunction", functions)
end

return RemotesSetup
