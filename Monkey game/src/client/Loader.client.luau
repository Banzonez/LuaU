--!strict

local replicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = replicatedStorage:WaitForChild("Shared")
local soundUtils = require(sharedFolder:WaitForChild("Utils"):WaitForChild("SoundUtils"))
local client = script.Parent.Client

soundUtils.preload()

for _, descendant in ipairs(client:GetDescendants()) do
	if descendant:IsA("ModuleScript") then
		local module = require(descendant)
		if module.init then
			module.init()
		end
	end
end
