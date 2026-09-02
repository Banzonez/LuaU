--!strict

local client = script.Parent
local systems = client:WaitForChild("Modules"):WaitForChild("Systems")

local CombatController = require(systems:WaitForChild("CombatController"))

CombatController.init()
