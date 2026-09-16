--!strict

local server = script.Parent.Server

local systems = server:FindFirstChild("Systems")
assert(systems, "Server.Systems is missing.")
local remotesSetupModule = systems:FindFirstChild("RemotesSetup")
assert(remotesSetupModule, "Server.Systems.RemotesSetup is missing.")
local remotesSetup = require(remotesSetupModule)

remotesSetup.init()

for _, descendant in ipairs(server:GetDescendants()) do
	if descendant:IsA("ModuleScript") then
		local module = require(descendant)
		if module.init then
			module.init()
		end
	end
end
