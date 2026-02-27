--!strict

local Constants = {
	GROWTH_RATE = 1.15,

	BASE_COSTS = {
		Turret = 80,
		Drill = 120,
		Wall = 8,
	},

	ROLE_DEFINITIONS = {
		Scrapper = {
			speedMult = 1.4,
			repairMult = 0.8,
			damageMult = 0.9,
			buildCostMult = 1.0,
			lootBonusMult = 1.3,
		},
		Fixer = {
			speedMult = 0.9,
			repairMult = 1.5,
			damageMult = 0.8,
			buildCostMult = 0.7,
			lootBonusMult = 1.0,
		},
		Enforcer = {
			speedMult = 1.0,
			repairMult = 0.9,
			damageMult = 1.3,
			buildCostMult = 1.0,
			lootBonusMult = 1.0,
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
		DrillScrapPerTick = 12,
		DrillTickInterval = 1.5,
		DefaultHP = 100,
		BaseBuildTimeSeconds = 2.4,
		MaxLevel = 4,
		-- Pacing: catch-up boost after destructive events
		CatchupBoostSeconds = 28,
		CatchupBuildSpeedBonus = 0.25,
		CatchupUpgradeSpeedBonus = 0.25,
		CatchupCooldownSeconds = 18,
		UpgradeSpeedMultiplier = 0.8,
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
			[1] = { scrapPerTick = 12, tickInterval = 1.5, hp = 100, cost = 0 },
			[2] = { scrapPerTick = 20, tickInterval = 1.5, hp = 140, cost = 80 },
			[3] = { scrapPerTick = 32, tickInterval = 1.3, hp = 190, cost = 150 },
			[4] = { scrapPerTick = 48, tickInterval = 1.0, hp = 250, cost = 240 },
		},
		Wall = {
			[1] = { hp = 150, cost = 0 },
			[2] = { hp = 300, cost = 15 },
			[3] = { hp = 500, cost = 30 },
			[4] = { hp = 750, cost = 55 },
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
		IntervalSeconds = 55,
		FirstWaveDelaySeconds = 90,
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
		SpawnBatchIntervalSeconds = 2,
		InitialBatchFraction = 0.15,
		BatchGrowthRate = 1.4,
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

	ENEMY_TYPES = {
		WallEater = {
			speed = 18,
			health = 14,
			-- Dismantle multiplier per building type (Wall > Drill > Turret > Titan)
			dismantleMultByType = { Wall = 1.8, Drill = 1.2, Turret = 0.7, Titan = 0.4 },
			canSteal = false,
			minCacheDrops = 3,
			maxCacheDrops = 5,
		},
		Juggernaut = {
			speed = 5,
			health = 120,
			dismantleMult = 2.5,
			targetsTurretOnly = true,
			canSteal = false,
			minCacheDrops = 6,
			maxCacheDrops = 8,
		},
		Decoy = {
			speed = 16,
			health = 65,
			dismantleMult = 0,
			canSteal = false,
			minCacheDrops = 1,
			maxCacheDrops = 2,
		},
		ScrapCarrier = {
			speed = 7,
			health = 30,
			dismantleMult = 0.3,
			canSteal = false,
			minCacheDrops = 10,
			maxCacheDrops = 18,
		},
	},

	GAME_PHASES = {
		{ endMinute = 3, intervalSeconds = 70, intensityMult = 0.35, lootVacuumWeight = 1, standardChance = 1, thiefChance = 0, wallEaterChance = 0, juggernautChance = 0, decoyChance = 0, scrapCarrierChance = 0, scrapCarrierLastBatchOnly = false },
		{ endMinute = 5, intervalSeconds = 50, intensityMult = 0.8, lootVacuumWeight = 1, standardChance = 0.85, thiefChance = 0.15, wallEaterChance = 0, juggernautChance = 0, decoyChance = 0, scrapCarrierChance = 0, scrapCarrierLastBatchOnly = false },
		{ endMinute = 10, intervalSeconds = 65, intensityMult = 0.45, lootVacuumWeight = 2, standardChance = 0.85, thiefChance = 0.15, wallEaterChance = 0, juggernautChance = 0, decoyChance = 0, scrapCarrierChance = 0, scrapCarrierLastBatchOnly = false },
		{ endMinute = 13, intervalSeconds = 50, intensityMult = 1.0, lootVacuumWeight = 2, standardChance = 0.7, thiefChance = 0.1, wallEaterChance = 0.2, juggernautChance = 0, decoyChance = 0, scrapCarrierChance = 0, scrapCarrierLastBatchOnly = false },
		{ endMinute = 15, intervalSeconds = 38, intensityMult = 1.7, lootVacuumWeight = 3, standardChance = 0.55, thiefChance = 0.1, wallEaterChance = 0.15, juggernautChance = 0.08, decoyChance = 0.12, scrapCarrierChance = 0.25, scrapCarrierLastBatchOnly = true, maxJuggernautPerWave = 3 },
		{ endMinute = 18, intervalSeconds = 60, intensityMult = 0.5, lootVacuumWeight = 3, standardChance = 0.85, thiefChance = 0.15, wallEaterChance = 0, juggernautChance = 0, decoyChance = 0, scrapCarrierChance = 0, scrapCarrierLastBatchOnly = false },
		{ endMinute = 20, intervalSeconds = 80, intensityMult = 0.25, lootVacuumWeight = 4, standardChance = 0.6, thiefChance = 0.1, wallEaterChance = 0, juggernautChance = 0, decoyChance = 0, scrapCarrierChance = 0.3, scrapCarrierLastBatchOnly = false },
		{ endMinute = 23, intervalSeconds = 42, intensityMult = 1.3, lootVacuumWeight = 4, standardChance = 0.5, thiefChance = 0.1, wallEaterChance = 0.15, juggernautChance = 0.1, decoyChance = 0.15, scrapCarrierChance = 0, scrapCarrierLastBatchOnly = false, maxJuggernautPerWave = 3 },
		{ endMinute = 25, intervalSeconds = 28, intensityMult = 2.5, lootVacuumWeight = 4, standardChance = 0.5, thiefChance = 0, wallEaterChance = 0.2, juggernautChance = 0.1, decoyChance = 0.2, scrapCarrierChance = 0, scrapCarrierLastBatchOnly = false, maxJuggernautPerWave = 3 },
	},

	LOOT = {
		JunkBlockValue = 5,
		RatCacheValue = 3,
		RatCacheMinDrops = 3,
		RatCacheMaxDrops = 4,
		RatCacheBonusDivisor = 75,
		RatCacheBonusMax = 5,
		CriticalHarvestChance = 0.12,
		CriticalHarvestMultiplier = 3,
		-- Time after spawn before dropped loot (rat/driller) can be picked up; prevents instant grant when player is on top of spawn.
		LootPickupArmDelaySeconds = 0.8,
		-- If true, scrap is only awarded after player touch or newly entering pickup radius (no passive auto-credit for already-nearby players).
		LootPickupRequireIntent = true,
		MaxActiveBeforeAutoCollect = 500,
		AutoCollectFraction = 0.5,
		MaxActiveCaches = 1500,
	},

	DRILL_SWARM_BONUS = {
		MinBlocks = 20,
		MaxBlocks = 40,
		CountMultiplier = 2,
		BlockValue = 1,
		-- Higher launch: vertical velocity and spawn offset (shoot scraps higher).
		VelocityYMin = 52,
		VelocityYMax = 76,
		SpawnOffsetYMin = 6,
		SpawnOffsetYMax = 12,
	},

	POWERUPS = {
		DropChance = 0.08,
		Types = { "Lightning", "Shockwave", "RepairAura", "TitanPush", "WeakLootVacuum", "StrongLootVacuum", "ActivateAll", "RatStun" },
		Lightning = { kills = { 5, 10 } },
		Shockwave = { radius = 20, damagePercent = 0.5 },
		RepairAura = { radius = 25, healAmount = 40 },
		TitanPush = { radius = 30, pushDistance = 10 },
		WeakLootVacuum = { radius = 20 },
		StrongLootVacuum = { radius = 15, useBaseRadius = true },
		ActivateAll = {},
		RatStun = { duration = 2 },
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
		SteelSpawnMinRadius = 50,
		SteelSpawnMaxRadius = 58,
	},

	SCRAP_SPAWNS = {
		IntervalSeconds = 3,
		CountPerSpawn = 9,
		MinSpawnRadius = 20,
		MaxSpawnRadius = 180,
		RadiusRampCycles = 20,
		MaxActivePiles = 80,
		MagnetRadius = 7,
		InstantPickupRadius = 2,
	},

	TITAN = {
		Stages = {
			[1] = { scrap = 225, steel = 0 },
			[2] = { scrap = 525, steel = 2 },
			[3] = { scrap = 900, steel = 5 },
			[4] = { scrap = 1350, steel = 9 },
		},
		IntegrityDrainPerSecond = 1.67,
		IntegrityRepairPerStage = 25,
		DepositRange = 12,
		FinalStandDurationSeconds = 120,
		PostGameDelaySeconds = 10,
		EliteRatHealthMult = 2.0,
		EliteRatSpeedMult = 1.3,
		EliteSpawnIntervalSeconds = 3,
		-- Pacing: build/upgrade speed scales with titan stage
		BuildSpeedBonusPerStage = 0.1,
		UpgradeSpeedBonusPerStage = 0.1,
		MinBuildTimeMultiplier = 0.25,
		MinUpgradeHoldDuration = 0.35,
	},
}

return Constants
