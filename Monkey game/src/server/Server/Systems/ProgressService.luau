local progressConfig = require(script.Parent.Parent.Configs.ProgressConfig)

export type RewardSource = "Winning" | "CollectingBananas" | "LandingPunches" | "CompletingQuests" | "PlayingMatches"

type Reward = {
	Coins: number,
	XP: number,
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

local function incrementAttribute(player: Player, dataName: "Bananas" | "Coins" | "XP", amount: number): boolean
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
	local xp = math.floor(reward.XP * multiplier)
	local coinsAdded = incrementAttribute(player, "Coins", coins)
	local xpAdded = incrementAttribute(player, "XP", xp)
	if coinsAdded and matchCoinsEarned[player] then
		matchCoinsEarned[player] += coins
	end
	return coinsAdded and xpAdded
end

function progressService.beginMatch(player: Player)
	matchCoinsEarned[player] = 0
end

function progressService.discardMatchCoins(player: Player): boolean
	local coins = matchCoinsEarned[player]
	if not coins or coins <= 0 then
		matchCoinsEarned[player] = nil
		return true
	end

	local success = incrementAttribute(player, "Coins", -coins)
	if success then
		matchCoinsEarned[player] = nil
	end
	return success
end

function progressService.finishMatch(player: Player)
	matchCoinsEarned[player] = nil
end

return progressService
