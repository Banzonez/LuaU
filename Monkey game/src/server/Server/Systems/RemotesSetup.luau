local replicatedStorage = game:GetService("ReplicatedStorage")

local remotesConfig = require(script.Parent.Parent.Configs.RemotesConfig)

local sharedFolder = replicatedStorage:FindFirstChild("Shared")
assert(sharedFolder, "ReplicatedStorage.Shared is missing.")

local remotesSetup = {}

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

function remotesSetup.init()
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

	load(remotesConfig.Events, "RemoteEvent", events)
	load(remotesConfig.Functions, "RemoteFunction", functions)
end

return remotesSetup
