--!strict

local setup = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Types"))
local utilsFolder = ServerScriptService:WaitForChild("Server"):WaitForChild("Modules"):WaitForChild("Utils")
local combatStyles = utilsFolder:WaitForChild("CombatStyles")
local StateHandler = require(script.Parent:WaitForChild("CombatStateHandler"))

local playerObjs: { [Player]: Types.CombatObject } = {}

local function createStyle(player: Player, styleName: string, settings: Types.StyleSettings?): Types.CombatStyle?
	local styleModule = combatStyles:FindFirstChild(styleName)
	if not styleModule or not styleModule:IsA("ModuleScript") then
		warn("Combat style not found: " .. styleName .. ".")
		return nil
	end

	local styleFactory = require(styleModule) :: Types.CombatStyleModule
	return styleFactory.new(player, settings)
end

function setup.SetStyle(
	self: Types.CombatObject,
	player: Player,
	styleName: string,
	settings: Types.StyleSettings?
): boolean
	local newStyle = createStyle(player, styleName, settings)
	if not newStyle then
		return false
	end

	self.Style = newStyle
	self.Settings = newStyle.Settings
	self.State = StateHandler:GetPlayerState(player)
	return true
end

function setup:CreateObj(player: Player, settings: Types.StyleSettings?): Types.CombatObject
	local style = createStyle(player, "MuayThai", settings)
	assert(style, "Could not create the default combat style.")

	local combat: Types.CombatObject = {
		Style = style,
		Settings = style.Settings,
		State = StateHandler:GetPlayerState(player),
		SetStyle = setup.SetStyle,
	}

	playerObjs[player] = combat
	return combat
end

function setup:GetPlayerObj(player: Player): Types.CombatObject?
	return playerObjs[player]
end

setup.init = function(): ()
	Players.PlayerRemoving:Connect(function(player)
		playerObjs[player] = nil
	end)
end

return setup
