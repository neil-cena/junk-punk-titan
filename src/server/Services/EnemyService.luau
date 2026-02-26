--!strict

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local COLLISION_GROUP_PLAYERS = "Players"
local COLLISION_GROUP_LOOT_DROPS = "LootDrops"

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local VisualManifest = require(Shared:WaitForChild("VisualManifest"))
local RemotesModule = require(Shared:WaitForChild("Remotes"))
local TheftComponent = require(Shared:WaitForChild("TheftComponent"))
local SpatialGrid = require(Shared:WaitForChild("SpatialGrid"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local BuildingService = require(script.Parent:WaitForChild("BuildingService"))
local ObjectiveService = require(script.Parent:WaitForChild("ObjectiveService"))
local PlayerTrackingService = require(script.Parent:WaitForChild("PlayerTrackingService"))
local RoleService = require(script.Parent:WaitForChild("RoleService"))
local RemoteGuard = require(script.Parent.Parent:WaitForChild("RemoteGuard"))

local EnemyService = {}

local remotes = RemotesModule.Get()
local currentWave = 0
local totalKills = 0
local gameActive = true
local finalStandActive = false
local swarmActive = false
local activeRats: { [Model]: true } = {}
local ratGrid = SpatialGrid.new(16)
local retreatBurrowDistance = Constants.WAVES.RetreatBurrowDistance
local burrowPositions = {
	Vector3.new(-retreatBurrowDistance, 0.2, -retreatBurrowDistance),
	Vector3.new(retreatBurrowDistance, 0.2, -retreatBurrowDistance),
	Vector3.new(-retreatBurrowDistance, 0.2, retreatBurrowDistance),
	Vector3.new(retreatBurrowDistance, 0.2, retreatBurrowDistance),
}

type RatState = {
	state: string,
	stolenBuildingCost: number,
	despawning: boolean,
	targetBuilding: BasePart?,
	isThief: boolean,
	carriedScrap: number,
	bagCapacity: number,
}

local ratStates: { [Model]: RatState } = {}
local activeRatCaches: { BasePart } = {}
local pickedRatCaches: { [BasePart]: boolean } = {}
local ratCacheValues: { [BasePart]: number } = {}
-- Intent-based pickup: only award scrap after touch or radius-entry when LootPickupRequireIntent is true.
local bundleHasIntent: { [BasePart]: boolean } = {}
local playersInRadiusLastTick: { [BasePart]: { [Player]: true } } = {}
local bundleTouchConnections: { [BasePart]: RBXScriptConnection } = {}
type PowerUpType = "Lightning" | "Shockwave" | "RepairAura" | "TitanPush" | "LootVacuum"
local activePowerUps: { BasePart } = {}
local pickedPowerUps: { [BasePart]: boolean } = {}
local powerUpTypeByOrb: { [BasePart]: PowerUpType } = {}

local function getLootBonusMultiplier(player: Player): number
	local multAttr = player:GetAttribute("LootBonusMult")
	if typeof(multAttr) == "number" then
		return math.max(1, multAttr :: number)
	end
	return 1
end

local ratPool: { Model } = {}
local RAT_POOL_INITIAL = 30
local ratCachePool: { BasePart } = {}
local RAT_CACHE_POOL_INITIAL = 50
local POOL_HIDE_POS = Vector3.new(0, -500, 0)

local function initCollisionGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_PLAYERS)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(COLLISION_GROUP_LOOT_DROPS)
	end)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP_PLAYERS, COLLISION_GROUP_LOOT_DROPS, false)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP_LOOT_DROPS, "Default", true)
end

local function publishNextWaveTimer(secondsRemaining: number)
	local remaining = math.max(0, math.floor(secondsRemaining + 0.5))
	local nextWaveTime = os.time() + remaining
	remotes.Folder:SetAttribute("NextWaveTime", nextWaveTime)
	remotes.UpdateWaveTimer:FireAllClients(remaining, nextWaveTime)
end

local function removeRatFromActive(ratModel: Model)
	activeRats[ratModel] = nil
	ratGrid:Remove(ratModel)
end

local function returnRatToPool(ratModel: Model)
	CollectionService:RemoveTag(ratModel, "ScrapRatEnemy")
	local humanoid = ratModel:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.Health = 0
	end
	ratModel.Parent = nil
	for _, child in ratModel:GetChildren() do
		if child.Name == "StolenScrapVisual" or child.Name == "AggroTarget" then
			child:Destroy()
		end
	end
	table.insert(ratPool, ratModel)
end

local function despawnRat(ratModel: Model)
	local state = ratStates[ratModel]
	if state ~= nil then
		state.despawning = true
	end
	removeRatFromActive(ratModel)
	if ratModel.Parent ~= nil then
		returnRatToPool(ratModel)
	end
	ratStates[ratModel] = nil
end

local function createRatCachePart(): BasePart
	local bundle = Instance.new("Part")
	bundle.Name = "RatCache"
	bundle.Size = Vector3.new(1.1, 1.1, 1.1)
	bundle.Shape = Enum.PartType.Block
	bundle.Material = VisualManifest.Loot.RatCache.material
	bundle.Color = VisualManifest.Loot.RatCache.color
	bundle.Anchored = true
	bundle.CanCollide = true
	bundle.CollisionGroup = COLLISION_GROUP_LOOT_DROPS
	bundle.CFrame = CFrame.new(POOL_HIDE_POS)

	local cogA = Instance.new("Part")
	cogA.Name = "CogA"
	cogA.Size = Vector3.new(0.25, 1.5, 0.55)
	cogA.Material = VisualManifest.Loot.RatCache.cogMaterial
	cogA.Color = VisualManifest.Loot.RatCache.cogColor
	cogA.Anchored = false
	cogA.CanCollide = false
	cogA.CFrame = bundle.CFrame
	cogA.Parent = bundle
	local weldA = Instance.new("WeldConstraint")
	weldA.Part0 = bundle
	weldA.Part1 = cogA
	weldA.Parent = bundle

	local cogB = cogA:Clone()
	cogB.Name = "CogB"
	cogB.Size = Vector3.new(0.55, 1.5, 0.25)
	cogB.Parent = bundle
	local weldB = Instance.new("WeldConstraint")
	weldB.Part0 = bundle
	weldB.Part1 = cogB
	weldB.Parent = bundle

	return bundle
end

local function acquireRatCache(): BasePart
	if #ratCachePool > 0 then
		local bundle = ratCachePool[#ratCachePool]
		table.remove(ratCachePool, #ratCachePool)
		return bundle
	end
	return createRatCachePart()
end

local function returnRatCacheToPool(cachePart: BasePart)
	cachePart.Anchored = true
	if cachePart:GetAttribute("MagnetTarget") ~= nil then
		cachePart:SetAttribute("MagnetTarget", nil)
	end
	local conn = bundleTouchConnections[cachePart]
	if conn ~= nil then
		conn:Disconnect()
		bundleTouchConnections[cachePart] = nil
	end
	bundleHasIntent[cachePart] = nil
	playersInRadiusLastTick[cachePart] = nil
	cachePart.Parent = nil
	table.insert(ratCachePool, cachePart)
end

local function isBundleArmed(cache: BasePart): boolean
	local spawnedAt = cache:GetAttribute("SpawnedAt")
	if typeof(spawnedAt) ~= "number" then
		return true
	end
	return (os.clock() - (spawnedAt :: number)) >= Constants.LOOT.LootPickupArmDelaySeconds
end

local function getPlayerFromTouch(other: BasePart): Player?
	local character = other:FindFirstAncestorOfClass("Model")
	if character == nil or not character:IsA("Model") then
		return nil
	end
	if character:FindFirstChildOfClass("Humanoid") == nil then
		return nil
	end
	for _, player in Players:GetPlayers() do
		if player.Character == character then
			return player
		end
	end
	return nil
end

local function spawnCollectableBundle(atPosition: Vector3, scrapValue: number): BasePart
	local bundle = acquireRatCache()
	bundle.Anchored = false
	bundle.CanCollide = true
	bundle.CFrame = CFrame.new(atPosition + Vector3.new(0, 2, 0))
	bundle:SetAttribute("MagnetTarget", nil)
	bundle:SetAttribute("InstantPickup", nil)
	bundle:SetAttribute("CriticalHarvest", nil)
	bundle:SetAttribute("SpawnedAt", os.clock())
	bundle.Parent = Workspace

	bundleHasIntent[bundle] = false
	playersInRadiusLastTick[bundle] = {}
	local conn = bundle.Touched:Connect(function(other: BasePart)
		if bundle.Parent == nil or pickedRatCaches[bundle] then
			return
		end
		local player = getPlayerFromTouch(other)
		if player ~= nil then
			bundleHasIntent[bundle] = true
		end
	end)
	bundleTouchConnections[bundle] = conn

	table.insert(activeRatCaches, bundle)
	ratCacheValues[bundle] = scrapValue

	task.delay(Constants.COMBAT.ScrapBundleDespawnSeconds, function()
		if not pickedRatCaches[bundle] and bundle.Parent ~= nil then
			returnRatCacheToPool(bundle)
		end
		pickedRatCaches[bundle] = nil
		ratCacheValues[bundle] = nil
		bundleHasIntent[bundle] = nil
		playersInRadiusLastTick[bundle] = nil
		local conn = bundleTouchConnections[bundle]
		if conn ~= nil then
			conn:Disconnect()
			bundleTouchConnections[bundle] = nil
		end
	end)

	return bundle
end

local function spawnRatCacheDrops(atPosition: Vector3, dropCount: number, scrapPerDrop: number)
	local clampedCount = math.clamp(dropCount, 1, 10)
	for i = 1, clampedCount do
		local offset = Vector3.new(math.random(-3, 3), math.random(1, 3), math.random(-3, 3))
		task.delay((i - 1) * 0.03, function()
			spawnCollectableBundle(atPosition + offset, scrapPerDrop)
		end)
	end
end

local function triggerDrillBonusShower()
	local cfg = Constants.DRILL_SWARM_BONUS
	local mult = typeof(cfg.CountMultiplier) == "number" and (cfg.CountMultiplier :: number) or 2
	local velYMin = typeof(cfg.VelocityYMin) == "number" and (cfg.VelocityYMin :: number) or 52
	local velYMax = typeof(cfg.VelocityYMax) == "number" and (cfg.VelocityYMax :: number) or 76
	local offYMin = typeof(cfg.SpawnOffsetYMin) == "number" and (cfg.SpawnOffsetYMin :: number) or 6
	local offYMax = typeof(cfg.SpawnOffsetYMax) == "number" and (cfg.SpawnOffsetYMax :: number) or 12

	local drillPositions: { Vector3 } = {}
	for _, instance in CollectionService:GetTagged("Drill") do
		if not instance:IsA("BasePart") or instance.Parent == nil then
			continue
		end
		table.insert(drillPositions, instance.Position)

		local baseCount = math.random(cfg.MinBlocks, cfg.MaxBlocks)
		local dropCount = math.max(1, math.floor(baseCount * mult))
		for i = 1, dropCount do
			task.delay((i - 1) * 0.02, function()
				if instance.Parent == nil then
					return
				end
				local offset = Vector3.new(math.random(-4, 4), math.random(offYMin, offYMax), math.random(-4, 4))
				local bundle = spawnCollectableBundle(instance.Position + offset, cfg.BlockValue)
				bundle.AssemblyLinearVelocity = Vector3.new(
					math.random(-20, 20),
					math.random(velYMin, velYMax),
					math.random(-20, 20)
				)
			end)
		end
	end
	if #drillPositions > 0 then
		remotes.DrillBonusShower:FireAllClients(drillPositions)
	end
end

local function getPowerUpColor(powerUpType: PowerUpType): Color3
	local colors = VisualManifest.Loot.PowerUps
	if powerUpType == "Lightning" then
		return colors.Lightning
	elseif powerUpType == "RepairAura" then
		return colors.RepairAura
	elseif powerUpType == "TitanPush" then
		return colors.TitanPush
	elseif powerUpType == "LootVacuum" then
		return colors.LootVacuum
	end
	return colors.Shockwave
end

local function createPowerUpOrb(atPosition: Vector3, powerUpType: PowerUpType): BasePart
	local orb = Instance.new("Part")
	orb.Name = "PowerUpOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Constants.POWERUPS.OrbSize
	orb.Material = Enum.Material.Neon
	orb.Color = getPowerUpColor(powerUpType)
	orb.Anchored = true
	orb.CanCollide = false
	orb.Position = atPosition + Vector3.new(0, 1.7, 0)
	orb.Parent = Workspace
	orb:SetAttribute("PowerUpType", powerUpType)
	CollectionService:AddTag(orb, "PowerUpOrb")
	return orb
end

local function spawnPowerUpOrb(atPosition: Vector3)
	local availableTypes = Constants.POWERUPS.Types
	local idx = math.random(1, #availableTypes)
	local powerUpType = availableTypes[idx] :: PowerUpType
	local orb = createPowerUpOrb(atPosition, powerUpType)
	powerUpTypeByOrb[orb] = powerUpType
	table.insert(activePowerUps, orb)
	remotes.PowerUpSpawned:FireAllClients(orb, powerUpType)

	task.delay(Constants.POWERUPS.DespawnSeconds, function()
		if pickedPowerUps[orb] then
			pickedPowerUps[orb] = nil
			powerUpTypeByOrb[orb] = nil
			return
		end
		if orb.Parent ~= nil then
			CollectionService:RemoveTag(orb, "PowerUpOrb")
			orb:Destroy()
		end
		pickedPowerUps[orb] = nil
		powerUpTypeByOrb[orb] = nil
	end)
end

local function getAliveRatRoots(): { BasePart }
	local roots: { BasePart } = {}
	for rat in activeRats do
		local humanoid = rat:FindFirstChildOfClass("Humanoid")
		local root = rat.PrimaryPart
		if humanoid ~= nil and humanoid.Health > 0 and root ~= nil and rat.Parent ~= nil then
			table.insert(roots, root)
		end
	end
	return roots
end

local collectRatCache: ((BasePart) -> ())?
local function executePowerUp(player: Player, powerUpType: PowerUpType): { Vector3 }
	local character = player.Character
	local playerRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if playerRoot == nil or not playerRoot:IsA("BasePart") then
		return {}
	end

	local hitPositions: { Vector3 } = {}
	if powerUpType == "Lightning" then
		local minKills = Constants.POWERUPS.Lightning.kills[1]
		local maxKills = Constants.POWERUPS.Lightning.kills[2]
		local wantedKills = math.random(minKills, maxKills)
		local ranked: { { root: BasePart, dist: number } } = {}
		for _, root in getAliveRatRoots() do
			table.insert(ranked, { root = root, dist = (root.Position - playerRoot.Position).Magnitude })
		end
		table.sort(ranked, function(a, b)
			return a.dist < b.dist
		end)
		local killCount = math.min(wantedKills, #ranked)
		for i = 1, killCount do
			local root = ranked[i].root
			local rat = root.Parent
			if rat ~= nil and rat:IsA("Model") then
				local humanoid = rat:FindFirstChildOfClass("Humanoid")
				if humanoid ~= nil and humanoid.Health > 0 then
					table.insert(hitPositions, root.Position)
					humanoid.Health = 0
				end
			end
		end
	elseif powerUpType == "Shockwave" then
		local radius = Constants.POWERUPS.Shockwave.radius
		local damagePercent = Constants.POWERUPS.Shockwave.damagePercent
		local origin = playerRoot.Position
		for rat in activeRats do
			local humanoid = rat:FindFirstChildOfClass("Humanoid")
			local root = rat.PrimaryPart
			if humanoid == nil or humanoid.Health <= 0 or root == nil then
				continue
			end
			if (root.Position - origin).Magnitude <= radius then
				table.insert(hitPositions, root.Position)
				local damage = math.max(1, humanoid.MaxHealth * damagePercent)
				humanoid:TakeDamage(damage)
			end
		end
	elseif powerUpType == "RepairAura" then
		local radius = Constants.POWERUPS.RepairAura.radius
		local healAmount = Constants.POWERUPS.RepairAura.healAmount
		for _, instance in CollectionService:GetTagged("DismantlableBuilding") do
			if not instance:IsA("BasePart") or instance.Parent == nil then
				continue
			end
			if (instance.Position - playerRoot.Position).Magnitude > radius then
				continue
			end
			local maxHP = getBuildingMaxHP(instance)
			local hpAttr = instance:GetAttribute("BuildingHP")
			local currentHP = if typeof(hpAttr) == "number" then (hpAttr :: number) else maxHP
			local healedHP = math.clamp(currentHP + healAmount, 0, maxHP)
			if healedHP > currentHP then
				instance:SetAttribute("BuildingHP", healedHP)
				table.insert(hitPositions, instance.Position)
			end
		end
	elseif powerUpType == "TitanPush" then
		local radius = Constants.POWERUPS.TitanPush.radius
		local pushDistance = Constants.POWERUPS.TitanPush.pushDistance
		local titanCore = ObjectiveService.GetTitanCore()
		local titanOrigin = if titanCore ~= nil then titanCore.Position else playerRoot.Position
		for rat in activeRats do
			local humanoid = rat:FindFirstChildOfClass("Humanoid")
			local root = rat.PrimaryPart
			if humanoid == nil or humanoid.Health <= 0 or root == nil or rat.Parent == nil then
				continue
			end
			local fromTitan = root.Position - titanOrigin
			if fromTitan.Magnitude > radius then
				continue
			end
			local dir = Vector3.new(fromTitan.X, 0, fromTitan.Z)
			if dir.Magnitude < 0.01 then
				dir = Vector3.new(0, 0, 1)
			end
			local unitDir = dir.Unit
			local currentPos = root.Position
			local targetPos = currentPos + unitDir * pushDistance
			root.CFrame = CFrame.lookAt(targetPos, targetPos + root.CFrame.LookVector)
			humanoid:MoveTo(targetPos)
			table.insert(hitPositions, currentPos)
		end
	elseif powerUpType == "LootVacuum" then
		local radius = Constants.POWERUPS.LootVacuum.radius
		local origin = playerRoot.Position
		for _, cache in activeRatCaches do
			if cache.Parent == nil or pickedRatCaches[cache] then
				continue
			end
			if not isBundleArmed(cache) then
				continue
			end
			if (cache.Position - origin).Magnitude <= radius then
				cache:SetAttribute("MagnetTarget", player.Name)
				if collectRatCache ~= nil then
					collectRatCache(cache)
				end
				table.insert(hitPositions, cache.Position)
			end
		end

		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = { character }
		for _, part in Workspace:GetPartBoundsInRadius(origin, radius, overlapParams) do
			if not part:IsA("BasePart") or part.Parent == nil then
				continue
			end
			if part:GetAttribute("CollectedByLootVacuum") == true then
				continue
			end
			if part.Name == "JunkBlock" then
				part:SetAttribute("CollectedByLootVacuum", true)
				part:SetAttribute("MagnetTarget", player.Name)
				part:SetAttribute("InstantPickup", true)
				local scrapValue = Constants.LOOT.JunkBlockValue
				if math.random() < Constants.LOOT.CriticalHarvestChance then
					scrapValue = scrapValue * Constants.LOOT.CriticalHarvestMultiplier
					part:SetAttribute("CriticalHarvest", true)
				end
				EconomyService.AddScrap(scrapValue)
				table.insert(hitPositions, part.Position)
				part:Destroy()
			elseif part.Name == "StormHardenedSteel" then
				part:SetAttribute("CollectedByLootVacuum", true)
				part:SetAttribute("MagnetTarget", player.Name)
				part:SetAttribute("InstantPickup", true)
				EconomyService.AddStormSteel(1)
				table.insert(hitPositions, part.Position)
				part:Destroy()
			end
		end
	end

	return hitPositions
end

local function collectPowerUp(orb: BasePart, player: Player)
	if pickedPowerUps[orb] then
		return
	end
	local powerUpType = powerUpTypeByOrb[orb]
	if powerUpType == nil then
		return
	end
	pickedPowerUps[orb] = true
	orb:SetAttribute("MagnetTarget", player.Name)
	local origin = orb.Position
	local hitPositions = executePowerUp(player, powerUpType)
	remotes.PowerUpCollected:FireAllClients(player, powerUpType, origin, hitPositions)
	if orb.Parent ~= nil then
		CollectionService:RemoveTag(orb, "PowerUpOrb")
		task.delay(0.15, function()
			if orb.Parent ~= nil then
				orb:Destroy()
			end
		end)
	end
	powerUpTypeByOrb[orb] = nil
end

local function handleRatDeath(ratModel: Model)
	local state = ratStates[ratModel]
	if state == nil or state.despawning then
		ratStates[ratModel] = nil
		return
	end

	totalKills += 1

	local root = ratModel.PrimaryPart
	local atPosition = if root ~= nil then root.Position else ratModel:GetPivot().Position

	local dropCount = math.random(Constants.LOOT.RatCacheMinDrops, Constants.LOOT.RatCacheMaxDrops)
	local stolenValue = math.max(state.stolenBuildingCost, state.carriedScrap)
	if stolenValue > 0 then
		local bonusDrops = math.clamp(
			math.floor(stolenValue / Constants.LOOT.RatCacheBonusDivisor),
			1,
			if state.isThief then (Constants.LOOT.RatCacheBonusMax * 2) else Constants.LOOT.RatCacheBonusMax
		)
		dropCount = dropCount + bonusDrops
	end
	spawnRatCacheDrops(atPosition, dropCount, Constants.LOOT.RatCacheValue)
	if math.random() < Constants.POWERUPS.DropChance then
		spawnPowerUpOrb(atPosition)
	end

	remotes.EnemyKilled:FireAllClients(atPosition)
	ratStates[ratModel] = nil
	removeRatFromActive(ratModel)

	task.defer(function()
		if ratModel.Parent ~= nil then
			ratModel:Destroy()
		end
	end)
end

local function createScrapRatModel(spawnPosition: Vector3, isElite: boolean?, isThief: boolean?): Model
	local hp = Constants.COMBAT.RatBaseHealth
	local speed = 12

	if isElite then
		hp = math.floor(hp * Constants.TITAN.EliteRatHealthMult)
		speed = speed * Constants.TITAN.EliteRatSpeedMult
	elseif isThief then
		hp = math.floor(hp * Constants.THIEF_RAT.HealthMultiplier)
		speed = Constants.THIEF_RAT.WalkSpeed
	end

	local rat = Instance.new("Model")
	rat.Name = "ScrapRat"
	rat:SetAttribute("RatType", if isElite then "Elite" elseif isThief then "Thief" else "Standard")

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = false
	root.CanCollide = true
	root.Position = spawnPosition
	root.Parent = rat

	root.Size = VisualManifest.Rats.Standard.bodySize
	root.Color = VisualManifest.Rats.Standard.bodyColor
	root.Material = VisualManifest.Rats.Standard.bodyMaterial
	if isElite then
		root.Size = VisualManifest.Rats.Elite.bodySize
		root.Color = VisualManifest.Rats.Elite.bodyColor
		root.Material = VisualManifest.Rats.Elite.bodyMaterial
	elseif isThief then
		root.Size = VisualManifest.Rats.Thief.bodySize
		root.Color = VisualManifest.Rats.Thief.bodyColor
		root.Material = VisualManifest.Rats.Thief.bodyMaterial
	end

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(root.Size.X * 0.6, root.Size.Y * 0.7, root.Size.Z * 0.5)
	head.Material = root.Material
	head.Color = root.Color
	head.CanCollide = false
	head.Massless = true
	head.CFrame = root.CFrame * CFrame.new(0, root.Size.Y * 0.18, -root.Size.Z * 0.45)
	head.Parent = rat

	local tail = Instance.new("Part")
	tail.Name = "Tail"
	tail.Shape = Enum.PartType.Cylinder
	tail.Size = Vector3.new(1.4, 0.25, 0.25)
	tail.Material = VisualManifest.Rats.TailMaterial
	tail.Color = VisualManifest.Rats.TailColor
	tail.CanCollide = false
	tail.Massless = true
	tail.CFrame = root.CFrame * CFrame.new(0, -root.Size.Y * 0.1, root.Size.Z * 0.58) * CFrame.Angles(0, 0, math.rad(90))
	tail.Parent = rat

	local eyeL = Instance.new("Part")
	eyeL.Name = "EyeL"
	eyeL.Size = Vector3.new(0.14, 0.14, 0.14)
	eyeL.Material = VisualManifest.Rats.EyeMaterial
	eyeL.Color = if isElite then VisualManifest.Rats.EliteEyeColor else VisualManifest.Rats.EyeColor
	eyeL.CanCollide = false
	eyeL.Massless = true
	eyeL.CFrame = head.CFrame * CFrame.new(-0.15, 0.02, -head.Size.Z * 0.42)
	eyeL.Parent = rat

	local eyeR = eyeL:Clone()
	eyeR.Name = "EyeR"
	eyeR.CFrame = head.CFrame * CFrame.new(0.15, 0.02, -head.Size.Z * 0.42)
	eyeR.Parent = rat

	local weldHead = Instance.new("WeldConstraint")
	weldHead.Part0 = root
	weldHead.Part1 = head
	weldHead.Parent = root

	local weldTail = Instance.new("WeldConstraint")
	weldTail.Part0 = root
	weldTail.Part1 = tail
	weldTail.Parent = root

	local weldEyeL = Instance.new("WeldConstraint")
	weldEyeL.Part0 = head
	weldEyeL.Part1 = eyeL
	weldEyeL.Parent = head

	local weldEyeR = Instance.new("WeldConstraint")
	weldEyeR.Part0 = head
	weldEyeR.Part1 = eyeR
	weldEyeR.Parent = head

	if isThief then
		local bag = Instance.new("Part")
		bag.Name = "LootBag"
		bag.Shape = Enum.PartType.Ball
		bag.Size = Vector3.new(0.9, 1.1, 0.9)
		bag.Material = VisualManifest.Rats.Thief.bagMaterial
		bag.Color = VisualManifest.Rats.Thief.bagColor
		bag.CanCollide = false
		bag.Massless = true
		bag.CFrame = root.CFrame * CFrame.new(0, root.Size.Y * 0.35, root.Size.Z * 0.2)
		bag.Parent = rat

		local weldBag = Instance.new("WeldConstraint")
		weldBag.Part0 = root
		weldBag.Part1 = bag
		weldBag.Parent = root
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.MaxHealth = hp
	humanoid.Health = hp
	humanoid.WalkSpeed = speed
	humanoid.Parent = rat

	rat.PrimaryPart = root
	CollectionService:AddTag(rat, "ScrapRatEnemy")

	humanoid.Died:Connect(function()
		handleRatDeath(rat)
	end)

	rat.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			removeRatFromActive(rat)
			ratStates[rat] = nil
		end
	end)

	ratStates[rat] = {
		state = "approaching",
		stolenBuildingCost = 0,
		despawning = false,
		targetBuilding = nil,
		isThief = isThief == true,
		carriedScrap = 0,
		bagCapacity = 0,
	}

	rat.Parent = Workspace
	return rat
end

local function getBuildingBaseCost(buildingPart: BasePart): number
	for buildingType, baseCost in Constants.BASE_COSTS do
		if string.find(buildingPart.Name, buildingType) ~= nil then
			return baseCost
		end
	end
	return 0
end

local function getBuildingType(buildingPart: BasePart): string?
	local attrType = buildingPart:GetAttribute("BuildingType")
	if typeof(attrType) == "string" then
		return attrType :: string
	end
	for buildingType, _ in Constants.BASE_COSTS do
		if string.find(buildingPart.Name, buildingType) ~= nil then
			return buildingType
		end
	end
	return nil
end

local function getBuildingMaxHP(buildingPart: BasePart): number
	local buildingType = getBuildingType(buildingPart)
	if buildingType == nil then
		return Constants.BUILDING.DefaultHP
	end
	local levelAttr = buildingPart:GetAttribute("BuildingLevel")
	local level = if typeof(levelAttr) == "number" then math.floor(levelAttr :: number) else 1
	local typeUpgrades = Constants.BUILDING_UPGRADES[buildingType]
	if typeUpgrades == nil then
		return Constants.BUILDING.DefaultHP
	end
	local levelStats = typeUpgrades[level] or typeUpgrades[1]
	if levelStats == nil then
		return Constants.BUILDING.DefaultHP
	end
	local hp = levelStats.hp
	return if typeof(hp) == "number" then (hp :: number) else Constants.BUILDING.DefaultHP
end

local function getTargetBuilding(): BasePart?
	local buildings: { { part: BasePart, score: number } } = {}

	for _, instance in CollectionService:GetTagged("DismantlableBuilding") do
		if instance:IsA("BasePart") and instance.Parent ~= nil then
			local baseCost = getBuildingBaseCost(instance)
			local hpAttr = instance:GetAttribute("BuildingHP")
			local hp = if typeof(hpAttr) == "number" then (hpAttr :: number) else Constants.BUILDING.DefaultHP
			local score = baseCost * (hp / Constants.BUILDING.DefaultHP)
			table.insert(buildings, { part = instance, score = score })
		end
	end

	if #buildings == 0 then
		return nil
	end

	table.sort(buildings, function(a, b) return a.score > b.score end)
	local poolSize = math.min(3, #buildings)
	return buildings[math.random(1, poolSize)].part
end

function EnemyService.GetDifficultyMultiplier(): number
	local playerCount = PlayerTrackingService.GetCurrentPlayerCount()
	if playerCount <= 3 then
		return 1
	elseif playerCount == 4 then
		return 1.5
	else
		return 2
	end
end

function EnemyService.StartDismantle(targetBuilding: BasePart, ratModel: Model): ()
	local state = ratStates[ratModel]
	if state ~= nil then
		state.state = "dismantling"
	end
	TheftComponent.Attach(targetBuilding)
	local speedMult = if state ~= nil and state.isThief then Constants.THIEF_RAT.DismantleProgressMultiplier else 1
	TheftComponent.StartDismantle(targetBuilding, ratModel, speedMult)
	remotes.ThreatDetected:FireAllClients(targetBuilding.Name, targetBuilding.Position)
end

local moveToWithShortTimeout: (Humanoid, Vector3, number, Model?) -> boolean

local function pickNearestBurrow(position: Vector3): Vector3
	local nearest = burrowPositions[1]
	local nearestDistance = (nearest - position).Magnitude
	for index = 2, #burrowPositions do
		local candidate = burrowPositions[index]
		local candidateDistance = (candidate - position).Magnitude
		if candidateDistance < nearestDistance then
			nearest = candidate
			nearestDistance = candidateDistance
		end
	end
	return nearest
end

local function isRatRetreating(ratModel: Model): boolean
	local state = ratStates[ratModel]
	return state ~= nil and (state.despawning or state.state == "fleeing")
end

local function attachStolenScrapVisual(ratModel: Model): BasePart?
	local root = ratModel.PrimaryPart
	if root == nil then
		return nil
	end

	local visual = Instance.new("Part")
	visual.Name = "StolenScrapVisual"
	visual.Size = Vector3.new(0.7, 0.7, 0.7)
	visual.Shape = Enum.PartType.Ball
	visual.Material = VisualManifest.Rats.StolenScrapVisualMaterial
	visual.Color = VisualManifest.Rats.StolenScrapVisualColor
	visual.CanCollide = false
	visual.Massless = true
	visual.CFrame = root.CFrame * CFrame.new(0, 0.8, -0.7)
	visual.Parent = ratModel

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = visual
	weld.Parent = root

	return visual
end

local function ensureBurrowHole(position: Vector3): BasePart
	local hole = Instance.new("Part")
	hole.Name = "ScrapRatHole"
	hole.Anchored = true
	hole.CanCollide = false
	hole.Material = VisualManifest.Rats.BurrowHoleMaterial
	hole.Color = VisualManifest.Rats.BurrowHoleColor
	hole.Transparency = 0.15
	hole.Size = Vector3.new(5, 0.2, 5)
	hole.Position = position
	hole.Parent = Workspace
	return hole
end

local function fleeAndDespawnRat(ratModel: Model)
	if ratModel.Parent == nil then
		despawnRat(ratModel)
		return
	end

	local root = ratModel.PrimaryPart
	local humanoid = ratModel:FindFirstChildOfClass("Humanoid")
	if root == nil or humanoid == nil or humanoid.Health <= 0 then
		despawnRat(ratModel)
		return
	end

	attachStolenScrapVisual(ratModel)
	local state = ratStates[ratModel]
	local fleeMult = Constants.COMBAT.RatFleeSpeedMultiplier
	if state ~= nil and state.isThief then
		fleeMult = fleeMult * Constants.THIEF_RAT.RetreatSpeedMultiplier
	end
	local fleeSpeed = 12 * fleeMult
	humanoid.WalkSpeed = fleeSpeed
	local holePosition = pickNearestBurrow(root.Position)
	local hole = ensureBurrowHole(holePosition)

	local distance = (holePosition - root.Position).Magnitude
	local timeout = math.clamp(
		(distance / math.max(1, fleeSpeed)) + Constants.WAVES.RetreatTimeoutBufferSeconds,
		Constants.WAVES.RetreatTimeoutMinSeconds,
		Constants.WAVES.RetreatTimeoutMaxSeconds
	)
	moveToWithShortTimeout(humanoid, holePosition, timeout)

	despawnRat(ratModel)
	task.delay(1.2, function()
		if hole.Parent ~= nil then
			hole:Destroy()
		end
	end)
end

moveToWithShortTimeout = function(humanoid: Humanoid, targetPosition: Vector3, timeoutSeconds: number, ratModel: Model?): boolean
	local completed = false
	local reached = false
	local connection = humanoid.MoveToFinished:Connect(function(success: boolean)
		completed = true
		reached = success
	end)

	humanoid:MoveTo(targetPosition)
	local deadline = os.clock() + timeoutSeconds
	while not completed and os.clock() < deadline do
		if humanoid.Health <= 0 then
			break
		end
		if ratModel ~= nil and isRatRetreating(ratModel) then
			break
		end
		task.wait(0.15)
	end

	connection:Disconnect()
	return reached
end

local spawnRatToward: (BasePart, boolean?, boolean?) -> ()
local dismantleAndDestroyBuilding: (BasePart, Model?) -> ()
local retreatAllRats: (() -> ())?

local PATH_ZONE_SIZE = 16
local pathCache: { [string]: { waypoints: { PathWaypoint }, time: number } } = {}
local PATH_CACHE_TTL = 3
local pathComputeThisFrame = 0
local MAX_PATHS_PER_FRAME = 3
local lastPathFrameTime = 0

local losRayParams = RaycastParams.new()
losRayParams.FilterType = Enum.RaycastFilterType.Include
losRayParams.FilterDescendantsInstances = {}

local function refreshLosFilter()
	local walls: { Instance } = {}
	for _, inst in CollectionService:GetTagged("DismantlableBuilding") do
		if inst:IsA("BasePart") and inst.Parent ~= nil then
			table.insert(walls, inst)
		end
	end
	losRayParams.FilterDescendantsInstances = walls
end

local function hasLineOfSight(from: Vector3, to: Vector3): boolean
	local dir = to - from
	if dir.Magnitude < 0.5 then
		return true
	end
	local result = Workspace:Raycast(from, dir, losRayParams)
	return result == nil
end

local function zoneKey(pos: Vector3): string
	local zx = math.floor(pos.X / PATH_ZONE_SIZE)
	local zz = math.floor(pos.Z / PATH_ZONE_SIZE)
	return ("%d,%d"):format(zx, zz)
end

local function getCachedPath(from: Vector3, to: Vector3): { PathWaypoint }?
	local key = zoneKey(from) .. ">" .. zoneKey(to)
	local cached = pathCache[key]
	if cached ~= nil and (os.clock() - cached.time) < PATH_CACHE_TTL then
		return cached.waypoints
	end
	return nil
end

local function storeCachedPath(from: Vector3, to: Vector3, waypoints: { PathWaypoint })
	local key = zoneKey(from) .. ">" .. zoneKey(to)
	pathCache[key] = { waypoints = waypoints, time = os.clock() }
end

local function computePathStaggered(from: Vector3, to: Vector3): { PathWaypoint }?
	local now = os.clock()
	if now ~= lastPathFrameTime then
		lastPathFrameTime = now
		pathComputeThisFrame = 0
	end
	if pathComputeThisFrame >= MAX_PATHS_PER_FRAME then
		task.wait()
		lastPathFrameTime = os.clock()
		pathComputeThisFrame = 0
	end
	pathComputeThisFrame += 1

	local cached = getCachedPath(from, to)
	if cached ~= nil then
		return cached
	end

	local path = PathfindingService:CreatePath()
	local ok = pcall(function()
		path:ComputeAsync(from, to)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		local waypoints = path:GetWaypoints()
		storeCachedPath(from, to, waypoints)
		return waypoints
	end
	return nil
end

local function invalidatePathCache()
	table.clear(pathCache)
	refreshLosFilter()
end

local function getAggroTarget(ratModel: Model): BasePart?
	local aggroVal = ratModel:FindFirstChild("AggroTarget")
	if aggroVal ~= nil and aggroVal:IsA("ObjectValue") then
		local target = aggroVal.Value
		if target ~= nil and target:IsA("BasePart") and target.Parent ~= nil then
			aggroVal:Destroy()
			return target
		end
		aggroVal:Destroy()
	end
	return nil
end

local function pickNextTarget(): BasePart?
	return getTargetBuilding() or ObjectiveService.GetTitanCore()
end

local function findBlockingBuilding(fromPos: Vector3, toPos: Vector3, currentTarget: BasePart, ratModel: Model): BasePart?
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { ratModel }
	local result = Workspace:Raycast(fromPos, toPos - fromPos, rayParams)
	if result ~= nil and result.Instance:IsA("BasePart") then
		local hitPart = result.Instance
		if hitPart ~= currentTarget and CollectionService:HasTag(hitPart, "DismantlableBuilding") then
			return hitPart
		end
	end

	-- Fallback: pick a nearby building close to the direct line to target.
	local direction = toPos - fromPos
	local len = direction.Magnitude
	if len <= 0.001 then
		return nil
	end
	local dir = direction / len
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, candidate in CollectionService:GetTagged("DismantlableBuilding") do
		if candidate:IsA("BasePart") and candidate.Parent ~= nil and candidate ~= currentTarget then
			local rel = candidate.Position - fromPos
			local t = math.clamp(rel:Dot(dir), 0, len)
			local closest = fromPos + dir * t
			local lineDist = (candidate.Position - closest).Magnitude
			local ratDist = (candidate.Position - fromPos).Magnitude
			if lineDist <= 4 and ratDist <= 14 and ratDist < bestDist then
				best = candidate
				bestDist = ratDist
			end
		end
	end
	return best
end

local function moveRatBehavior(ratModel: Model, humanoid: Humanoid, root: BasePart, initialTarget: BasePart)
	local currentTarget = initialTarget
	local state = ratStates[ratModel]

	while currentTarget ~= nil
		and currentTarget.Parent ~= nil
		and humanoid.Health > 0
		and activeRats[ratModel] ~= nil
		and not isRatRetreating(ratModel) do
		if state ~= nil then
			state.state = "approaching"
			state.targetBuilding = currentTarget
			if state.isThief and state.bagCapacity <= 0 then
				state.bagCapacity = math.max(
					1,
					math.floor(getBuildingBaseCost(currentTarget) * Constants.THIEF_RAT.BuildingBagCapacityMultiplier + 0.5)
				)
			end
		end

		local redirected = false

		if hasLineOfSight(root.Position, currentTarget.Position) then
			local reached = moveToWithShortTimeout(humanoid, currentTarget.Position, 1.2, ratModel)
			if not reached then
				local blocker = findBlockingBuilding(root.Position, currentTarget.Position, currentTarget, ratModel)
				if blocker ~= nil then
					currentTarget = blocker
					redirected = true
				end
			end
		else
			local waypoints = computePathStaggered(root.Position, currentTarget.Position)
			if waypoints ~= nil then
				for _, waypoint in waypoints do
					if humanoid.Health <= 0 or activeRats[ratModel] == nil or isRatRetreating(ratModel) then
						return
					end
					local aggroTarget = getAggroTarget(ratModel)
					if aggroTarget ~= nil and aggroTarget ~= currentTarget then
						currentTarget = aggroTarget
						redirected = true
						break
					end
					if currentTarget.Parent == nil then
						local nextTgt = pickNextTarget()
						if nextTgt == nil then
							despawnRat(ratModel)
							return
						end
						currentTarget = nextTgt
						redirected = true
						break
					end
					local reached = moveToWithShortTimeout(humanoid, waypoint.Position, 0.9, ratModel)
					if not reached then
						local blocker = findBlockingBuilding(root.Position, currentTarget.Position, currentTarget, ratModel)
						if blocker ~= nil then
							currentTarget = blocker
							redirected = true
							break
						end
					end
				end
			else
				local reached = moveToWithShortTimeout(humanoid, currentTarget.Position, 1.2, ratModel)
				if not reached then
					local blocker = findBlockingBuilding(root.Position, currentTarget.Position, currentTarget, ratModel)
					if blocker ~= nil then
						currentTarget = blocker
						redirected = true
					end
				end
			end
		end

		if redirected then
			continue
		end
		if humanoid.Health <= 0 or activeRats[ratModel] == nil or ratModel.Parent == nil or isRatRetreating(ratModel) then
			return
		end
		if currentTarget.Parent == nil then
			local nextTgt = pickNextTarget()
			if nextTgt == nil then
				despawnRat(ratModel)
				return
			end
			currentTarget = nextTgt
			continue
		end

		EnemyService.StartDismantle(currentTarget, ratModel)
		local dismantleRedirected = false
		while activeRats[ratModel] ~= nil and currentTarget.Parent ~= nil and not isRatRetreating(ratModel) do
			if humanoid.Health <= 0 then
				return
			end
			task.wait(0.2)
			local aggroTarget = getAggroTarget(ratModel)
			if aggroTarget ~= nil and aggroTarget ~= currentTarget then
				currentTarget = aggroTarget
				dismantleRedirected = true
				break
			end
			local progressAttr = currentTarget:GetAttribute("DismantleProgress")
			if typeof(progressAttr) == "number" and (progressAttr :: number) >= 100 then
				dismantleAndDestroyBuilding(currentTarget, ratModel)
				return
			end
		end

		if isRatRetreating(ratModel) then
			TheftComponent.StopDismantle(currentTarget, true)
			return
		end

		if dismantleRedirected then
			continue
		end
		if currentTarget.Parent == nil then
			local nextTgt = pickNextTarget()
			if nextTgt == nil then
				despawnRat(ratModel)
				return
			end
			currentTarget = nextTgt
			continue
		end
	end
end

local function retargetRat(ratModel: Model)
	local state = ratStates[ratModel]
	if state == nil or state.despawning or state.state == "fleeing" then
		return
	end
	local newTarget = pickNextTarget()
	if newTarget == nil then
		despawnRat(ratModel)
		return
	end
	state.state = "approaching"
	state.targetBuilding = newTarget
	task.spawn(function()
		local humanoid = ratModel:FindFirstChildOfClass("Humanoid")
		local root = ratModel.PrimaryPart
		if humanoid == nil or root == nil or humanoid.Health <= 0 then
			return
		end
		moveRatBehavior(ratModel, humanoid, root, newTarget)
	end)
end

dismantleAndDestroyBuilding = function(dismantledPart: BasePart, ratModel: Model?)
	local finalPosition = dismantledPart.Position - Vector3.new(0, dismantledPart.Size.Y * 0.5, 0)
	local buildingType = dismantledPart:GetAttribute("BuildingType")
	local rotationAttr = dismantledPart:GetAttribute("BuildingRotation")
	local buildingRotation = if typeof(rotationAttr) == "number"
		then (rotationAttr :: number)
		else math.deg(select(2, dismantledPart.CFrame:ToEulerAnglesYXZ()))
	local baseCost = if typeof(buildingType) == "string" then (Constants.BASE_COSTS[buildingType] or 0) else 0

	local affectedRats: { Model } = {}
	for rat, state in ratStates do
		if rat ~= ratModel and state.targetBuilding == dismantledPart and not state.despawning and activeRats[rat] ~= nil then
			table.insert(affectedRats, rat)
		end
	end

	if dismantledPart.Parent ~= nil then
		remotes.BuildingDismantled:FireAllClients(dismantledPart.Name, finalPosition)
		dismantledPart:Destroy()
	end

	invalidatePathCache()
	BuildingService.RegisterDestroyedSlot(finalPosition, buildingType)
	BuildingService.PlaceRuinGhost(finalPosition, buildingType, buildingRotation)

	if ratModel ~= nil then
		local state = ratStates[ratModel]
		if state ~= nil then
			if state.isThief then
				state.carriedScrap += baseCost
				if state.bagCapacity <= 0 then
					state.bagCapacity = math.max(
						1,
						math.floor(baseCost * Constants.THIEF_RAT.BuildingBagCapacityMultiplier + 0.5)
					)
				end
				state.stolenBuildingCost = state.carriedScrap
				if state.carriedScrap >= state.bagCapacity then
					state.state = "fleeing"
				else
					state.state = "approaching"
				end
			else
				state.state = "fleeing"
				state.stolenBuildingCost = baseCost
			end
		end
		if state ~= nil and state.state == "fleeing" then
			fleeAndDespawnRat(ratModel)
		else
			task.spawn(function()
				retargetRat(ratModel)
			end)
		end
	end

	local fleeCount = math.ceil(baseCost / 30)
	for i, rat in affectedRats do
		if i <= fleeCount then
			local state = ratStates[rat]
			if state ~= nil then
				state.state = "fleeing"
				state.stolenBuildingCost = math.random(1, 2)
			end
			task.spawn(function()
				fleeAndDespawnRat(rat)
			end)
		else
			task.spawn(function()
				retargetRat(rat)
			end)
		end
	end
end

function EnemyService.KillRat(ratModel: Model): boolean
	if ratModel.Parent == nil or ratModel.Name ~= "ScrapRat" then
		return false
	end

	local humanoid = ratModel:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil and humanoid.Health > 0 then
		humanoid.Health = 0
		return true
	end

	despawnRat(ratModel)
	return true
end

function EnemyService.GetTotalKills(): number
	return totalKills
end

function EnemyService.StopAll(): ()
	gameActive = false
	finalStandActive = false
	swarmActive = false
	for rat in activeRats do
		if rat.Parent ~= nil then
			local state = ratStates[rat]
			if state ~= nil then
				state.despawning = true
			end
			rat:Destroy()
		end
	end
	for _, orb in activePowerUps do
		if orb.Parent ~= nil then
			CollectionService:RemoveTag(orb, "PowerUpOrb")
			orb:Destroy()
		end
	end
	activeRats = {}
	ratStates = {}
	activePowerUps = {}
	pickedPowerUps = {}
	powerUpTypeByOrb = {}
end

spawnRatToward = function(targetBuilding: BasePart, isElite: boolean?, isThief: boolean?)
	local radius = Constants.WAVES.SpawnRadius
	local minDist = math.min(Constants.WAVES.MinSpawnDistanceFromCenter, radius)
	local angle = math.random() * math.pi * 2
	local dist = minDist + (math.random() * (radius - minDist))
	local spawnPosition = Vector3.new(math.cos(angle) * dist, 3, math.sin(angle) * dist)
	local ratModel = createScrapRatModel(spawnPosition, isElite, isThief)
	activeRats[ratModel] = true
	ratGrid:Insert(ratModel, spawnPosition)

	local state = ratStates[ratModel]
	if state ~= nil then
		state.targetBuilding = targetBuilding
	end

	local humanoid = ratModel:FindFirstChildOfClass("Humanoid")
	local root = ratModel.PrimaryPart

	if humanoid == nil or root == nil then
		return
	end

	moveRatBehavior(ratModel, humanoid, root, targetBuilding)
end

function EnemyService.SpawnScrapRat(targetBuilding: BasePart?, isElite: boolean?, isThief: boolean?): ()
	if targetBuilding == nil then
		return
	end
	task.spawn(function()
		spawnRatToward(targetBuilding, isElite, isThief)
	end)
end

function EnemyService.SpawnWave(waveNumber: number): ()
	currentWave = waveNumber
	publishNextWaveTimer(0)
	local pattern = Constants.WAVES.IntensityPattern
	local patternIdx = ((waveNumber - 1) % #pattern) + 1
	local seasonMult = pattern[patternIdx]
	remotes.WaveStarted:FireAllClients(currentWave, patternIdx)

	local baseCount = Constants.WAVES.BaseEnemyCount + (currentWave * Constants.WAVES.EnemiesPerWave)
	local difficultyMult = EnemyService.GetDifficultyMultiplier()
	local randomMult = 0.8 + (math.random() * 0.7)
	local enemyCount = math.max(1, math.floor(baseCount * difficultyMult * randomMult * seasonMult + 0.5))

	swarmActive = true
	local titanCore = ObjectiveService.GetTitanCore()
	for _ = 1, enemyCount do
		local target = titanCore or getTargetBuilding()
		if target ~= nil then
			local spawnThief = (not finalStandActive) and (math.random() < Constants.THIEF_RAT.SpawnChance)
			EnemyService.SpawnScrapRat(target, false, spawnThief)
		end
	end

	task.spawn(function()
		local remaining = Constants.WAVES.SwarmDurationSeconds
		while remaining > 0 and swarmActive and gameActive do
			publishNextWaveTimer(-remaining)
			task.wait(1)
			remaining -= 1
		end
		if swarmActive then
			swarmActive = false
			remotes.SwarmEnded:FireAllClients()
			if retreatAllRats ~= nil then
				retreatAllRats()
			else
				warn("[EnemyService] retreatAllRats missing at swarm end")
			end
			triggerDrillBonusShower()
		end
	end)
end

function EnemyService.GetCurrentWave(): number
	return currentWave
end

function EnemyService.IsSwarmActive(): boolean
	return swarmActive
end

retreatAllRats = function()
	local ratsToRetreat: { Model } = {}
	for rat in activeRats do
		local state = ratStates[rat]
		if state ~= nil and not state.despawning and state.state ~= "fleeing" then
			table.insert(ratsToRetreat, rat)
		end
	end
	for _, rat in ratsToRetreat do
		local state = ratStates[rat]
		if state ~= nil then
			if state.targetBuilding ~= nil and state.targetBuilding.Parent ~= nil then
				TheftComponent.StopDismantle(state.targetBuilding, true)
			end
			state.state = "fleeing"
			state.stolenBuildingCost = 0
		end
		task.spawn(function()
			fleeAndDespawnRat(rat)
		end)
	end
end

local function startFinalStandSpawning()
	finalStandActive = true
	task.spawn(function()
		while finalStandActive and gameActive do
			local target = getTargetBuilding() or ObjectiveService.GetTitanCore()
			if target ~= nil then
				EnemyService.SpawnScrapRat(target, true)
			end
			task.wait(Constants.TITAN.EliteSpawnIntervalSeconds)
		end
	end)
end

local function resolveRatModel(ratModelOrPart: Instance): Model?
	local ratModel: Model? = nil
	if ratModelOrPart:IsA("Model") then
		ratModel = ratModelOrPart
	elseif ratModelOrPart:IsA("BasePart") then
		local ancestor = ratModelOrPart:FindFirstAncestorOfClass("Model")
		if ancestor ~= nil then
			ratModel = ancestor
		end
	end
	if ratModel == nil or ratModel.Name ~= "ScrapRat" then
		return nil
	end
	return ratModel
end

local function findNearestPunchTarget(player: Player): Model?
	local character = player.Character
	local playerRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if playerRoot == nil or not playerRoot:IsA("BasePart") then
		return nil
	end

	local nearest: Model? = nil
	local maxRange = Constants.COMBAT.PunchRange + 2
	local nearestDistance = maxRange
	for _, instance in CollectionService:GetTagged("ScrapRatEnemy") do
		if instance:IsA("Model") and instance.Parent ~= nil then
			local humanoid = instance:FindFirstChildOfClass("Humanoid")
			local root = instance.PrimaryPart
			if humanoid ~= nil and humanoid.Health > 0 and root ~= nil then
				local dist = (playerRoot.Position - root.Position).Magnitude
				if dist < nearestDistance then
					nearestDistance = dist
					nearest = instance
				end
			end
		end
	end
	return nearest
end

collectRatCache = function(cachePart: BasePart)
	if pickedRatCaches[cachePart] then
		return
	end
	pickedRatCaches[cachePart] = true
	local scrapValue = ratCacheValues[cachePart] or Constants.LOOT.RatCacheValue
	ratCacheValues[cachePart] = nil
	if math.random() < Constants.LOOT.CriticalHarvestChance then
		scrapValue = scrapValue * Constants.LOOT.CriticalHarvestMultiplier
		cachePart:SetAttribute("CriticalHarvest", true)
	end
	EconomyService.AddScrap(scrapValue)
	if cachePart.Parent ~= nil then
		returnRatCacheToPool(cachePart)
	end
end

local function assignCharacterToPlayersGroup(character: Model)
	for _, desc in character:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.CollisionGroup = COLLISION_GROUP_PLAYERS
		end
	end
	character.DescendantAdded:Connect(function(desc)
		if desc:IsA("BasePart") then
			desc.CollisionGroup = COLLISION_GROUP_PLAYERS
		end
	end)
end

function EnemyService.Init(): ()
	initCollisionGroups()

	local function wirePlayerCollisionGroup(player: Player)
		if player.Character then
			assignCharacterToPlayersGroup(player.Character)
		end
		player.CharacterAdded:Connect(function(character)
			assignCharacterToPlayersGroup(character)
		end)
	end

	for _, player in Players:GetPlayers() do
		wirePlayerCollisionGroup(player)
	end
	Players.PlayerAdded:Connect(wirePlayerCollisionGroup)

	for _ = 1, RAT_CACHE_POOL_INITIAL do
		table.insert(ratCachePool, createRatCachePart())
	end

	refreshLosFilter()
	CollectionService:GetInstanceAddedSignal("DismantlableBuilding"):Connect(function()
		invalidatePathCache()
	end)
	CollectionService:GetInstanceRemovedSignal("DismantlableBuilding"):Connect(function()
		invalidatePathCache()
	end)

	RemoteGuard.Register("HitEnemy", 5, 1)
	RemoteGuard.Register("PunchEnemy", 20, 1)
	RemoteGuard.Register("PowerUpPickup", 20, 1)

	remotes.HitEnemy.OnServerEvent:Connect(function(player: Player, ratModelOrPart: Instance)
		if not gameActive then
			return
		end
		if not RemoteGuard.Check("HitEnemy", player) then
			return
		end

		if player:GetAttribute("Role") ~= "Enforcer" then
			return
		end

		local ratModel = resolveRatModel(ratModelOrPart)
		if ratModel == nil then
			return
		end

		local humanoid = ratModel:FindFirstChildOfClass("Humanoid")
		if humanoid == nil or humanoid.Health <= 0 then
			return
		end

		local root = ratModel.PrimaryPart
		local char = player.Character
		local playerRoot = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if root == nil or playerRoot == nil or not playerRoot:IsA("BasePart") then
			return
		end

		if (playerRoot.Position - root.Position).Magnitude > Constants.COMBAT.ShotgunRange then
			return
		end

		local damageMultAttr = player:GetAttribute("DamageMult")
		local damageMult = if typeof(damageMultAttr) == "number" then (damageMultAttr :: number) else 1
		local damage = Constants.COMBAT.ShotgunBaseDamage * damageMult
		humanoid:TakeDamage(damage)
	end)

	remotes.PunchEnemy.OnServerEvent:Connect(function(player: Player, ...)
		local args = { ... }
		local ratModelOrPart: Instance? = if #args > 0 and typeof(args[1]) == "Instance" then args[1] else nil

		if not gameActive then
			warn("[PunchEnemy] rejected: game not active")
			return
		end
		if not RemoteGuard.Check("PunchEnemy", player) then
			warn("[PunchEnemy] rejected: rate limited for", player.Name)
			return
		end

		local char = player.Character
		local playerRoot = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if playerRoot == nil or not playerRoot:IsA("BasePart") then
			warn("[PunchEnemy] rejected: no player root for", player.Name)
			return
		end

		local ratModel: Model? = nil
		if ratModelOrPart ~= nil then
			ratModel = resolveRatModel(ratModelOrPart)
		end
		if ratModel == nil then
			ratModel = findNearestPunchTarget(player)
		end
		if ratModel == nil then
			warn("[PunchEnemy] rejected: no rat found near", player.Name)
			return
		end

		local humanoid = ratModel:FindFirstChildOfClass("Humanoid")
		if humanoid == nil or humanoid.Health <= 0 then
			return
		end

		local ratRoot = ratModel.PrimaryPart
		if ratRoot == nil then
			return
		end
		if (playerRoot.Position - ratRoot.Position).Magnitude > Constants.COMBAT.PunchRange + 2 then
			return
		end

		local damageMultAttr = player:GetAttribute("DamageMult")
		local damageMult = if typeof(damageMultAttr) == "number" then (damageMultAttr :: number) else 1
		local damage = math.max(1, Constants.COMBAT.PunchDamage * damageMult)
		humanoid.Health = math.max(0, humanoid.Health - damage)
	end)

	remotes.PowerUpPickup.OnServerEvent:Connect(function(player: Player, orbPart: Instance)
		if not gameActive then
			return
		end
		if not RemoteGuard.Check("PowerUpPickup", player) then
			return
		end
		if not orbPart:IsA("BasePart") then
			return
		end
		if powerUpTypeByOrb[orbPart] == nil then
			return
		end
		local char = player.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if root == nil or not root:IsA("BasePart") then
			return
		end
		local maxPickupRange = Constants.SCRAP_SPAWNS.MagnetRadius + 8
		if (root.Position - orbPart.Position).Magnitude > maxPickupRange then
			return
		end
		collectPowerUp(orbPart, player)
	end)

	TheftComponent.ConnectCompleted(function(dismantledPart: BasePart, ratModel: Model?)
		dismantleAndDestroyBuilding(dismantledPart, ratModel)
	end)

	ObjectiveService.ConnectGameStateChanged(function(state: string)
		if state == "final_stand" then
			startFinalStandSpawning()
		elseif state == "victory" or state == "defeat" or state == "sandbox" then
			EnemyService.StopAll()
		end
	end)

	task.spawn(function()
		RoleService.WaitForAllPlayersReady()
		local firstDelay = Constants.WAVES.FirstWaveDelaySeconds
		local remaining = firstDelay
		while remaining > 0 and gameActive do
			publishNextWaveTimer(remaining)
			task.wait(1)
			remaining -= 1
		end

		while gameActive do
			if not gameActive then
				break
			end
			publishNextWaveTimer(0)
			local nextWave = currentWave + 1
			EnemyService.SpawnWave(nextWave)

			while swarmActive and gameActive do
				task.wait(0.5)
			end
			if not gameActive then
				break
			end

			remaining = Constants.WAVES.IntervalSeconds
			while remaining > 0 and gameActive do
				publishNextWaveTimer(remaining)
				task.wait(1)
				remaining -= 1
			end
		end
	end)

	local gridUpdateAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		gridUpdateAcc += dt
		if gridUpdateAcc < 0.5 then
			return
		end
		gridUpdateAcc = 0
		for ratModel in activeRats do
			local root = ratModel.PrimaryPart
			if root ~= nil then
				ratGrid:Update(ratModel, root.Position)
			end
		end
	end)

	local RATCACHE_MAGNET_TICK = 0.15
	local RATCACHE_MAX_COLLECTS_PER_TICK = 5
	local ratCacheMagnetAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		ratCacheMagnetAcc += dt
		if ratCacheMagnetAcc < RATCACHE_MAGNET_TICK then
			return
		end
		ratCacheMagnetAcc = 0

		local magnetRadius = Constants.SCRAP_SPAWNS.MagnetRadius
		local alive: { BasePart } = {}
		local collectedThisTick = 0

		local requireIntent = (typeof(Constants.LOOT.LootPickupRequireIntent) == "boolean" and Constants.LOOT.LootPickupRequireIntent) or false

		for _, cache in activeRatCaches do
			if cache.Parent == nil or pickedRatCaches[cache] then
				pickedRatCaches[cache] = nil
				ratCacheValues[cache] = nil
				bundleHasIntent[cache] = nil
				playersInRadiusLastTick[cache] = nil
				continue
			end
			if not isBundleArmed(cache) then
				table.insert(alive, cache)
				continue
			end

			local nearestPlayer: Player? = nil
			local nearestDist = magnetRadius + 1
			local playersInRadiusNow: { [Player]: true } = {}

			for _, player in Players:GetPlayers() do
				local character = player.Character
				if character == nil then
					continue
				end
				local root = character:FindFirstChild("HumanoidRootPart")
				if root == nil or not root:IsA("BasePart") then
					continue
				end
				local pDist = (root.Position - cache.Position).Magnitude
				if pDist <= magnetRadius then
					playersInRadiusNow[player] = true
				end
				if pDist < nearestDist then
					nearestDist = pDist
					nearestPlayer = player
				end
			end

			-- Radius-entry: if requireIntent, set intent when a player enters radius (was not in radius last tick).
			if requireIntent then
				local lastTick = playersInRadiusLastTick[cache] or {}
				for player, _ in playersInRadiusNow do
					if lastTick[player] ~= true then
						bundleHasIntent[cache] = true
						break
					end
				end
			end
			playersInRadiusLastTick[cache] = playersInRadiusNow

			local mayCollect = (nearestPlayer ~= nil and nearestDist <= magnetRadius)
				and (not requireIntent or bundleHasIntent[cache] == true)

			if mayCollect then
				if collectedThisTick >= RATCACHE_MAX_COLLECTS_PER_TICK then
					table.insert(alive, cache)
					continue
				end
				collectedThisTick += 1
				pickedRatCaches[cache] = true
				local isInstant = nearestDist <= Constants.SCRAP_SPAWNS.InstantPickupRadius
				cache:SetAttribute("MagnetTarget", nearestPlayer.Name)
				if isInstant then
					cache:SetAttribute("InstantPickup", true)
				end
				local scrapValue = ratCacheValues[cache] or Constants.LOOT.RatCacheValue
				ratCacheValues[cache] = nil
				if math.random() < Constants.LOOT.CriticalHarvestChance then
					scrapValue = scrapValue * Constants.LOOT.CriticalHarvestMultiplier
					cache:SetAttribute("CriticalHarvest", true)
				end
				scrapValue = math.max(1, math.floor((scrapValue * getLootBonusMultiplier(nearestPlayer)) + 0.5))
				EconomyService.AddScrap(scrapValue)
				if isInstant then
					task.defer(function()
						if cache.Parent ~= nil then
							returnRatCacheToPool(cache)
						end
						pickedRatCaches[cache] = nil
					end)
				else
					task.delay(0.5, function()
						if cache.Parent ~= nil then
							returnRatCacheToPool(cache)
						end
						pickedRatCaches[cache] = nil
					end)
				end
			else
				if cache:GetAttribute("MagnetTarget") ~= nil then
					cache:SetAttribute("MagnetTarget", nil)
				end
				table.insert(alive, cache)
			end
		end

		activeRatCaches = alive
	end)

	local POWERUP_MAGNET_TICK = 0.12
	local powerUpMagnetAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		powerUpMagnetAcc += dt
		if powerUpMagnetAcc < POWERUP_MAGNET_TICK then
			return
		end
		powerUpMagnetAcc = 0

		local magnetRadius = Constants.SCRAP_SPAWNS.MagnetRadius
		local alive: { BasePart } = {}

		for _, orb in activePowerUps do
			if orb.Parent == nil or pickedPowerUps[orb] then
				pickedPowerUps[orb] = nil
				powerUpTypeByOrb[orb] = nil
				continue
			end

			local nearestPlayer: Player? = nil
			local nearestDist = magnetRadius + 1

			for _, player in Players:GetPlayers() do
				local character = player.Character
				if character == nil then
					continue
				end
				local root = character:FindFirstChild("HumanoidRootPart")
				if root == nil or not root:IsA("BasePart") then
					continue
				end
				local pDist = (root.Position - orb.Position).Magnitude
				if pDist < nearestDist then
					nearestDist = pDist
					nearestPlayer = player
				end
			end

			if nearestPlayer ~= nil and nearestDist <= magnetRadius then
				collectPowerUp(orb, nearestPlayer)
			else
				if orb:GetAttribute("MagnetTarget") ~= nil then
					orb:SetAttribute("MagnetTarget", nil)
				end
				table.insert(alive, orb)
			end
		end

		activePowerUps = alive
	end)
end

function EnemyService.GetNearestRatInRadius(position: Vector3, radius: number): Model?
	local model, _ = ratGrid:GetNearestInRadius(position, radius)
	if model ~= nil then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid ~= nil and humanoid.Health > 0 and model.Parent ~= nil then
			return model
		end
	end
	return nil
end

return EnemyService
