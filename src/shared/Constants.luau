--!strict

local Constants = {
	GROWTH_RATE = 1.15,

	BASE_COSTS = {
		Turret = 100,
		Drill = 250,
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
		MaxBuildRadiusFromCenter = 50,
		RebuildCooldownSeconds = 15,
		TurretRange = 45,
		TurretFireInterval = 1.5,
		TurretDamage = 7.5,
		DrillScrapPerTick = 8,
		DrillTickInterval = 2,
		DefaultHP = 100,
		BaseBuildTimeSeconds = 3,
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
		DrillBaseOutput = 30,
		StabilityDegradationPercent = 0.35,
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
		FirstWaveDelaySeconds = 150,
		SwarmDurationSeconds = 30,
		BaseEnemyCount = 6,
		EnemiesPerWave = 3,
		MinSpawnDistanceFromCenter = 50,
		SpawnRadius = 60,
		RetreatBurrowDistance = 400,
		RetreatTimeoutMinSeconds = 6,
		RetreatTimeoutMaxSeconds = 16,
		RetreatTimeoutBufferSeconds = 1.25,
	},

	COMBAT = {
		ShotgunBaseDamage = 20,
		ShotgunRange = 30,
		ShotgunCooldown = 0.27,
		PunchDamage = 5,
		PunchRange = 8,
		PunchCooldown = 0.33,
		RatBaseHealth = 50,
		RatFleeSpeedMultiplier = 1.2,
		ScrapBundleDespawnSeconds = 30,
	},

	THIEF_RAT = {
		SpawnChance = 0.15,
		WalkSpeed = 14.4,
		HealthMultiplier = 0.85,
		DismantleProgressMultiplier = 0.7,
		BuildingBagCapacityMultiplier = 1.0,
		RetreatSpeedMultiplier = 1.1,
	},

	LOOT = {
		JunkBlockValue = 5,
		RatCacheValue = 2,
		RatCacheMinDrops = 2,
		RatCacheMaxDrops = 3,
		RatCacheBonusDivisor = 75,
		RatCacheBonusMax = 5,
	},

	ECONOMY = {
		InitialScrap = 200,
		DeathPenaltyPercent = 0.15,
		DeathPenaltyCooldownSeconds = 10,
	},

	STORM = {
		IntervalSeconds = 450,
		DurationSeconds = 20,
		WindDamagePerSecond = 2,
		TetherPadRadius = 6,
		TetherPadsRequired = 3,
		TetherPadsReducedOnLeave = 2,
		StormSteelDropCount = 5,
		SteelSpawnRadius = 120,
	},

	SCRAP_SPAWNS = {
		IntervalSeconds = 6,
		CountPerSpawn = 5,
		MinSpawnRadius = 30,
		MaxSpawnRadius = 180,
		RadiusRampCycles = 20,
		MaxActivePiles = 60,
		MagnetRadius = 7,
	},

	TITAN = {
		Stages = {
			[1] = { scrap = 300, steel = 0 },
			[2] = { scrap = 600, steel = 2 },
			[3] = { scrap = 900, steel = 5 },
			[4] = { scrap = 1200, steel = 10 },
		},
		IntegrityDrainPerSecond = 1.67,
		IntegrityRepairPerStage = 25,
		DepositRange = 12,
		FinalStandDurationSeconds = 240,
		EliteRatHealthMult = 2.0,
		EliteRatSpeedMult = 1.3,
		EliteSpawnIntervalSeconds = 3,
	},
}

return Constants
