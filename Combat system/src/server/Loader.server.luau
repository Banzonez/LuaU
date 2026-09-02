--!strict

-- Initialize dependencies before the service that uses them.
local server = script.Parent
local modules = server:WaitForChild("Modules")
local systems = modules:WaitForChild("Systems")
local utils = modules:WaitForChild("Utils")

local CombatStateHandler = require(systems:WaitForChild("CombatStateHandler"))
local CombatSetup = require(systems:WaitForChild("CombatSetup"))
local CombatUtil = require(utils:WaitForChild("CombatUtil"))
local CombatService = require(systems:WaitForChild("CombatService"))

CombatStateHandler.init()
CombatSetup.init()
CombatUtil.init()
CombatService.init()
