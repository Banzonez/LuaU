--!strict

local modules = script.Parent.Modules
local systems = modules.Systems

local CombatStateHandler = require(systems.CombatStateHandler)
local CombatSetup = require(systems.CombatSetup)
local CombatUtil = require(modules.Utils.CombatUtil)
local CombatService = require(systems.CombatService)
local CombatNpcHandler = require(systems.CombatNpcHandler)

CombatStateHandler.init()
CombatSetup.init()
CombatUtil.init()
CombatService.init()
CombatNpcHandler.init()
