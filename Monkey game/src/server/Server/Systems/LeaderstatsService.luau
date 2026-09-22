local players = game:GetService("Players")

local STATS: { [string]: number } = {
	Bananas = 0,
	Coins = 0,
}

local initialized = false
local leaderstatsService = {}

local function createLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	for name, defaultValue in pairs(STATS) do
		local value = player:GetAttribute(name)
		if typeof(value) ~= "number" then
			value = defaultValue
			player:SetAttribute(name, value)
		end

		local stat = Instance.new("IntValue")
		stat.Name = name
		stat.Value = value
		stat.Parent = folder

		player:GetAttributeChangedSignal(name):Connect(function()
			local updatedValue = player:GetAttribute(name)
			if typeof(updatedValue) == "number" then
				stat.Value = updatedValue
			end
		end)
	end

	folder.Parent = player
end

function leaderstatsService.init()
	if initialized then
		return
	end
	initialized = true

	for _, player in ipairs(players:GetPlayers()) do
		createLeaderstats(player)
	end

	players.PlayerAdded:Connect(createLeaderstats)
end

return leaderstatsService
