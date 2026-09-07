local BananaConfig = {
	Chances = {
		Banana = 45,
		GoldBanana = 25,
		SmallBananaCrate = 15,
		BananaCrate = 5,
	},

	TagsNames = {
		"Banana",
		"GoldBanana",
		"SmallBananaCrate",
		"BananaCrate",
	},

	MAX_BANANAS_SPAWNED = 50,
	SPAWN_RATE = 1,
}

function BananaConfig.getName(index: number): string?
	return BananaConfig.TagsNames[index]
end

return BananaConfig
