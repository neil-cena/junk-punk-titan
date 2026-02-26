--!strict

local Constants = {
	GROWTH_RATE = 1.15,

	BASE_COSTS = {
		Turret = 80,
		Drill = 180,
		Wall = 25,
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
		GhostTransparency = 0.45,
		PlacementMaxDistance = 50,
		MaxBuildRadiusFromCenter = 50,
		RebuildCooldownSeconds = 15,
		TurretRange = 45,
		TurretFireInterval = 0.9,
		TurretDamage = 5,
		DrillScrapPerTick = 8,
		DrillTickInterval = 2,
		DefaultHP = 100,
		BaseBuildTimeSeconds = 3,
		MaxLevel = 4,
		Sizes = {
			Turret = Vector3.new(4, 4, 4),
			Drill = Vector3.new(4, 6, 4),
			Wall = Vector3.new(8, 8, 2),
		},
	},

	BUILDING_UPGRADES = {
		Turret = {
			[1] = { damage = 5, range = 45, fireInterval = 0.9, hp = 100, cost = 0 },
			[2] = { damage = 8, range = 48, fireInterval = 0.75, hp = 140, cost = 75 },
			[3] = { damage = 13, range = 52, fireInterval = 0.6, hp = 190, cost = 140 },
			[4] = { damage = 18, range = 56, fireInterval = 0.45, hp = 250, cost = 220 },
		},
		Drill = {
			[1] = { scrapPerTick = 8, tickInterval = 2, hp = 100, cost = 0 },
			[2] = { scrapPerTick = 14, tickInterval = 2, hp = 140, cost = 100 },
			[3] = { scrapPerTick = 22, tickInterval = 1.8, hp = 190, cost = 180 },
			[4] = { scrapPerTick = 32, tickInterval = 1.5, hp = 250, cost = 280 },
		},
		Wall = {
			[1] = { hp = 100, cost = 0 },
			[2] = { hp = 180, cost = 20 },
			[3] = { hp = 300, cost = 45 },
			[4] = { hp = 450, cost = 80 },
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
		IntervalSeconds = 75,
		FirstWaveDelaySeconds = 60,
		SwarmDurationSeconds = 25,
		BaseEnemyCount = 16,
		EnemiesPerWave = 18,
		IntensityPattern = { 0.6, 1.0, 1.8 },
		MinSpawnDistanceFromCenter = 50,
		SpawnRadius = 60,
		RetreatBurrowDistance = 400,
		RetreatTimeoutMinSeconds = 6,
		RetreatTimeoutMaxSeconds = 16,
		RetreatTimeoutBufferSeconds = 1.25,
	},

	COMBAT = {
		ShotgunBaseDamage = 18,
		ShotgunRange = 30,
		ShotgunCooldown = 0.15,
		PunchDamage = 7,
		PunchRange = 6,
		PunchCooldown = 0.33,
		RatBaseHealth = 18,
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
		CriticalHarvestChance = 0.12,
		CriticalHarvestMultiplier = 3,
	},

	POWERUPS = {
		DropChance = 0.06,
		Types = { "Lightning", "Fireball", "Shockwave" },
		Lightning = { kills = { 5, 10 } },
		Fireball = { width = 6, length = 60, damage = 100 },
		Shockwave = { radius = 20, damagePercent = 0.5 },
		DespawnSeconds = 20,
		OrbSize = Vector3.new(1.8, 1.8, 1.8),
	},

	ECONOMY = {
		InitialScrap = 250,
		DeathPenaltyPercent = 0.15,
		DeathPenaltyCooldownSeconds = 10,
	},

	STORM = {
		IntervalSeconds = 420,
		DurationSeconds = 20,
		WindDamagePerSecond = 2,
		TetherPadRadius = 6,
		TetherPadsRequired = 3,
		TetherPadsReducedOnLeave = 2,
		StormSteelDropCount = 5,
		SteelSpawnRadius = 120,
	},

	SCRAP_SPAWNS = {
		IntervalSeconds = 4,
		CountPerSpawn = 7,
		MinSpawnRadius = 30,
		MaxSpawnRadius = 180,
		RadiusRampCycles = 20,
		MaxActivePiles = 60,
		MagnetRadius = 7,
		InstantPickupRadius = 2,
	},

	TITAN = {
		Stages = {
			[1] = { scrap = 150, steel = 0 },
			[2] = { scrap = 350, steel = 1 },
			[3] = { scrap = 600, steel = 3 },
			[4] = { scrap = 900, steel = 6 },
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
