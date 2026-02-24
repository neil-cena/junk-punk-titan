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

	BUILDING = {
		GridSize = 4,
		GhostTransparency = 0.6,
		PlacementMaxDistance = 50,
		RebuildCooldownSeconds = 15,
		TurretRange = 45,
		TurretFireInterval = 0.5,
		DrillScrapPerTick = 4,
		DrillTickInterval = 2.5,
		Sizes = {
			Turret = Vector3.new(4, 4, 4),
			Drill = Vector3.new(4, 6, 4),
			Wall = Vector3.new(8, 8, 2),
		},
		Colors = {
			Turret = Color3.fromRGB(200, 180, 60),
			Drill = Color3.fromRGB(120, 120, 120),
			Wall = Color3.fromRGB(90, 80, 70),
		},
	},

	SCALING = {
		OptimalPlayers = 3,
		PlayerDeltaEnemyFactor = 0.5,
		SwarmMultiplierPerPlayer = 1.5,
		LegacyScrapGatherBuff = 0.25,
		LegacyReloadSpeedBuff = 0.15,
	},

	MAINTENANCE = {
		ResourceTickSeconds = 10,
		DrillBaseOutput = 10,
		StabilityDegradationPercent = 1,
		StabilityDegradationInterval = 2,
		WrenchSuccessRestore = 40,
		OverclockDurationSeconds = 30,
		OverclockMultiplier = 1.2,
		ClogDurationSeconds = 5,
		MinigameBarSpeed = 1.4,
		MinigameSuccessZoneWidth = 0.18,
	},

	WAVES = {
		IntervalSeconds = 120,
		BaseEnemyCount = 5,
		EnemiesPerWave = 2,
		SpawnRadius = 60,
	},

	COMBAT = {
		ShotgunDamage = 100,
		ShotgunRange = 80,
		ShotgunCooldown = 0.8,
		RatKillScrapReward = 15,
	},

	STORM = {
		IntervalSeconds = 600,
		DurationSeconds = 60,
		WindDamagePerSecond = 2,
		TetherPadRadius = 6,
		TetherPadsRequired = 3,
		TetherPadsReducedOnLeave = 2,
		StormSteelDropCount = 3,
	},

	SCRAP_BUNDLE_VALUE = 20,
}

return Constants
