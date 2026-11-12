--!strict

local client = script.Parent
local systems = client.Modules.Systems

local CombatController = require(systems.CombatController)

CombatController.init()
