local Client = script.Parent.Client

for _, script in ipairs(Client:GetDescendants()) do
	if script:IsA("ModuleScript") then
		local mdl = require(script)
		if mdl.init then
			mdl.init()
		end
	end
end
