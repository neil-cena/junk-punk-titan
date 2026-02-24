--!strict

local Constants = {
	GROWTH_RATE = 1.15,

	BASE_COSTS = {
		Turret = 50,
		Drill = 75,
		Wall = 30,
	},

	ROLE_DEFINITIONS = {
		Scrapper = {
			speedMult = 1.4,
			repairMult = 0.8,
			damageMult = 0.9,
		},
		Fixer = {
			speedMult = 0.9,
			repairMult = 1.5,
			damageMult = 0.8,
		},
		Enforcer = {
			speedMult = 1.0,
			repairMult = 0.9,
			damageMult = 1.5,
		},
	},

	THEFT_SETTINGS = {
		DismantleDuration = 8,
		ProgressPerSecond = 12.5,
	},

	SCALING = {
		OptimalPlayers = 3,
		PlayerDeltaEnemyFactor = 0.5,
		SwarmMultiplierPerPlayer = 1.5,
		LegacyScrapGatherBuff = 0.25,
		LegacyReloadSpeedBuff = 0.15,
	},

	SCRAP_BUNDLE_VALUE = 20,
}

return Constants
