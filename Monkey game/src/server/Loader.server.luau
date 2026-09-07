local Server = script.Parent.Server

local RemotesSetup = require(Server.Systems:WaitForChild("RemotesSetup"))

RemotesSetup.init()

for _, script in pairs(Server:GetDescendants()) do
	if script:IsA("ModuleScript") then
		local mdl = require(script)
		if mdl.init then
			mdl.init()
		end
	end
end
