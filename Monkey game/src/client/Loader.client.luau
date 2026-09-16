--!strict

local client = script.Parent.Client

for _, descendant in ipairs(client:GetDescendants()) do
	if descendant:IsA("ModuleScript") then
		local module = require(descendant)
		if module.init then
			module.init()
		end
	end
end
