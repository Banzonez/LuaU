local progressConfig = require(script.Parent.Parent.Configs.ProgressConfig)

export type RewardSource = "Winning" | "CollectingBananas" | "LandingPunches" | "CompletingQuests" | "PlayingMatches"

type Reward = {
	Coins: number,
}

type ProgressService = {
	addBananas: (player: Player, amount: number) -> boolean,
	award: (player: Player, source: RewardSource, quantity: number?) -> boolean,
	beginMatch: (player: Player) -> (),
	discardMatchCoins: (player: Player) -> boolean,
	finishMatch: (player: Player) -> (),
}

local progressService: ProgressService = {} :: ProgressService
local matchCoinsEarned: { [Player]: number } = {}

local function isValidAmount(amount: number): boolean
	return amount == amount and amount > 0 and amount < math.huge
end

local function incrementAttribute(player: Player, dataName: "Bananas" | "Coins", amount: number): boolean
	if amount == 0 then
		return true
	end

	local currentValue = player:GetAttribute(dataName)
	if typeof(currentValue) ~= "number" then
		return false
	end

	player:SetAttribute(dataName, currentValue + amount)
	return true
end

function progressService.addBananas(player: Player, amount: number): boolean
	if not isValidAmount(amount) then
		return false
	end

	return incrementAttribute(player, "Bananas", math.floor(amount))
end

function progressService.award(player: Player, source: RewardSource, quantity: number?): boolean
	local multiplier = quantity or 1
	local reward = progressConfig.Rewards[source] :: Reward?
	if not reward or not isValidAmount(multiplier) then
		return false
	end

	local coins = math.floor(reward.Coins * multiplier)
	if matchCoinsEarned[player] ~= nil then
		matchCoinsEarned[player] += coins
		return true
	end

	return incrementAttribute(player, "Coins", coins)
end

function progressService.beginMatch(player: Player)
	matchCoinsEarned[player] = 0
end

function progressService.discardMatchCoins(player: Player): boolean
	matchCoinsEarned[player] = nil
	return true
end

function progressService.finishMatch(player: Player)
	local coins = matchCoinsEarned[player]
	if coins and coins > 0 then
		incrementAttribute(player, "Coins", coins)
	end
	matchCoinsEarned[player] = nil
end

return progressService
