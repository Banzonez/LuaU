--!strict

local bananaConfig = {
	Chances = {
		Banana = 45,
		GoldBanana = 25,
	},

	TagsNames = {
		"Banana",
		"GoldBanana",
		"SmallBananaCrate",
		"BananaCrate",
	},

	MAX_BANANAS_SPAWNED = 50,
	MAX_CRATES = 4,
	MAX_SMALL_CRATES = 6,
	SPAWN_RATE = 1,
}

function bananaConfig.getName(index: number): string?
	return bananaConfig.TagsNames[index]
end

return bananaConfig
