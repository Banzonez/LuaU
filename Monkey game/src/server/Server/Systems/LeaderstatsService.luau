local module = {}

local Players = game:GetService("Players")

local STATS = {
	Bananas = 0,
}

local function createLeaderstats(player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	for name, value in pairs(STATS) do
		local stat = Instance.new("IntValue")
		stat.Name = name
		stat.Value = value
		stat.Parent = folder
	end

	folder.Parent = player
end

function module.init()
	Players.PlayerAdded:Connect(function(player: Player)
		createLeaderstats(player)

		player.AttributeChanged:Connect(function(attribute: string)
			if STATS[attribute] then
				local leaderstats = player:WaitForChild("leaderstats", 5)
				if not leaderstats then
					return
				end

				local stat = leaderstats[attribute]
				if not stat then
					return
				end

				stat.Value = player:GetAttribute(attribute)
			end
		end)
	end)
end

return module
