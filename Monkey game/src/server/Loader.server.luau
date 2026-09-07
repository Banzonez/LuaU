local Server = script.Parent.Server

local Systems = Server:FindFirstChild("Systems")
assert(Systems, "Server.Systems is missing.")
local RemotesSetupModule = Systems:FindFirstChild("RemotesSetup")
assert(RemotesSetupModule, "Server.Systems.RemotesSetup is missing.")
local RemotesSetup = require(RemotesSetupModule)

RemotesSetup.init()

for _, script in ipairs(Server:GetDescendants()) do
	if script:IsA("ModuleScript") then
		local mdl = require(script)
		if mdl.init then
			mdl.init()
		end
	end
end
