--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local RemotesModule = require(Shared:WaitForChild("Remotes"))
local TheftComponent = require(Shared:WaitForChild("TheftComponent"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local BuildingService = require(script.Parent:WaitForChild("BuildingService"))
local ObjectiveService = require(script.Parent:WaitForChild("ObjectiveService"))
local PlayerTrackingService = require(script.Parent:WaitForChild("PlayerTrackingService"))
local RemoteGuard = require(script.Parent.Parent:WaitForChild("RemoteGuard"))

local EnemyService = {}

local remotes = RemotesModule.Get()
local currentWave = 0
local totalKills = 0
local gameActive = true
local finalStandActive = false
local swarmActive = false
local activeRats: { [Model]: true } = {}
local burrowPositions = {
	Vector3.new(-220, 0.2, -220),
	Vector3.new(220, 0.2, -220),
	Vector3.new(-220, 0.2, 220),
	Vector3.new(220, 0.2, 220),
}

type RatState = {
	state: string,
	stolenBuildingCost: number,
	despawning: boolean,
	targetBuilding: BasePart?,
}

local ratStates: { [Model]: RatState } = {}

local function publishNextWaveTimer(secondsRemaining: number)
	local remaining = math.max(0, math.floor(secondsRemaining + 0.5))
	local nextWaveTime = os.time() + remaining
	remotes.Folder:SetAttribute("NextWaveTime", nextWaveTime)
	remotes.UpdateWaveTimer:FireAllClients(remaining, nextWaveTime)
end

local function removeRatFromActive(ratModel: Model)
	activeRats[ratModel] = nil
end

local function despawnRat(ratModel: Model)
	local state = ratStates[ratModel]
	if state ~= nil then
		state.despawning = true
	end
	removeRatFromActive(ratModel)
	if ratModel.Parent ~= nil then
		ratModel:Destroy()
	end
	ratStates[ratModel] = nil
end

local function spawnCollectableBundle(atPosition: Vector3, scrapValue: number)
	local bundle = Instance.new("Part")
	bundle.Name = "ScrapBundle"
	bundle.Size = Vector3.new(1.5, 1.5, 1.5)
	bundle.Shape = Enum.PartType.Ball
	bundle.Material = Enum.Material.Metal
	bundle.Color = Color3.fromRGB(200, 180, 80)
	bundle.Anchored = false
	bundle.CanCollide = true
	bundle.Position = atPosition + Vector3.new(0, 2, 0)
	bundle.Parent = Workspace

	local picked = false
	bundle.Touched:Connect(function(hit: BasePart)
		if picked then
			return
		end
		local model = hit:FindFirstAncestorOfClass("Model")
		if model == nil then
			return
		end
		local player = Players:GetPlayerFromCharacter(model)
		if player == nil then
			return
		end
		picked = true
		EconomyService.AddScrap(scrapValue)
		bundle:Destroy()
	end)

	task.delay(Constants.COMBAT.ScrapBundleDespawnSeconds, function()
		if not picked and bundle.Parent ~= nil then
			bundle:Destroy()
		end
	end)
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

	if state.state == "fleeing" and state.stolenBuildingCost > 0 then
		local reward = math.random(Constants.COMBAT.StandardKillMinReward, Constants.COMBAT.StandardKillMaxReward)
		EconomyService.AddScrap(reward)
		local refund = math.floor(state.stolenBuildingCost * Constants.COMBAT.ThiefKillRefundPercent)
		if refund > 0 then
			spawnCollectableBundle(atPosition, refund)
		end
	else
		local reward = math.random(Constants.COMBAT.StandardKillMinReward, Constants.COMBAT.StandardKillMaxReward)
		EconomyService.AddScrap(reward)
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

local function createScrapRatModel(spawnPosition: Vector3, isElite: boolean?): Model
	local hp = Constants.COMBAT.RatBaseHealth
	local speed = 12

	if isElite then
		hp = math.floor(hp * Constants.TITAN.EliteRatHealthMult)
		speed = speed * Constants.TITAN.EliteRatSpeedMult
	end

	local rat = Instance.new("Model")
	rat.Name = "ScrapRat"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = false
	root.CanCollide = true
	root.Position = spawnPosition
	root.Parent = rat

	if isElite then
		root.Size = Vector3.new(2.5, 2.5, 2.5)
		root.Color = Color3.fromRGB(180, 50, 50)
		root.Material = Enum.Material.Metal
	else
		root.Size = Vector3.new(2, 2, 2)
	end

	local humanoid = Instance.new("Humanoid")
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
	TheftComponent.StartDismantle(targetBuilding, ratModel)
	remotes.ThreatDetected:FireAllClients(targetBuilding.Name, targetBuilding.Position)
end

local moveToWithShortTimeout: (Humanoid, Vector3, number) -> boolean

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

local function attachStolenScrapVisual(ratModel: Model): BasePart?
	local root = ratModel.PrimaryPart
	if root == nil then
		return nil
	end

	local visual = Instance.new("Part")
	visual.Name = "StolenScrapVisual"
	visual.Size = Vector3.new(0.7, 0.7, 0.7)
	visual.Shape = Enum.PartType.Ball
	visual.Material = Enum.Material.Metal
	visual.Color = Color3.fromRGB(170, 170, 170)
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
	hole.Material = Enum.Material.Slate
	hole.Color = Color3.fromRGB(25, 25, 25)
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
	humanoid.WalkSpeed = 12 * Constants.COMBAT.RatFleeSpeedMultiplier
	local holePosition = pickNearestBurrow(root.Position)
	local hole = ensureBurrowHole(holePosition)

	moveToWithShortTimeout(humanoid, holePosition, 4)

	despawnRat(ratModel)
	task.delay(1.2, function()
		if hole.Parent ~= nil then
			hole:Destroy()
		end
	end)
end

moveToWithShortTimeout = function(humanoid: Humanoid, targetPosition: Vector3, timeoutSeconds: number): boolean
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
		task.wait(0.05)
	end

	connection:Disconnect()
	return reached
end

local spawnRatToward: (BasePart, boolean?) -> ()

local function retargetRat(ratModel: Model)
	local state = ratStates[ratModel]
	if state == nil or state.despawning then
		return
	end
	local newTarget = getTargetBuilding() or ObjectiveService.GetTitanCore()
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
		local path = PathfindingService:CreatePath()
		local ok = pcall(function()
			path:ComputeAsync(root.Position, newTarget.Position)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			for _, waypoint in path:GetWaypoints() do
				if humanoid.Health <= 0 or newTarget.Parent == nil or activeRats[ratModel] == nil then
					if newTarget.Parent == nil and activeRats[ratModel] ~= nil then
						retargetRat(ratModel)
					end
					return
				end
				moveToWithShortTimeout(humanoid, waypoint.Position, 0.9)
			end
		else
			moveToWithShortTimeout(humanoid, newTarget.Position, 1.2)
		end
		if humanoid.Health <= 0 or activeRats[ratModel] == nil or ratModel.Parent == nil then
			return
		end
		if newTarget.Parent ~= nil then
			EnemyService.StartDismantle(newTarget, ratModel)
			task.spawn(function()
				while activeRats[ratModel] ~= nil and newTarget.Parent ~= nil do
					if humanoid.Health <= 0 then
						return
					end
					task.wait(0.2)
					local progressAttr = newTarget:GetAttribute("DismantleProgress")
					if typeof(progressAttr) == "number" and (progressAttr :: number) >= 100 then
						return
					end
				end
				if activeRats[ratModel] ~= nil and newTarget.Parent == nil then
					retargetRat(ratModel)
				end
			end)
		end
	end)
end

local function dismantleAndDestroyBuilding(dismantledPart: BasePart, ratModel: Model?)
	local finalPosition = dismantledPart.Position
	local buildingType = dismantledPart:GetAttribute("BuildingType")
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

	BuildingService.RegisterDestroyedSlot(finalPosition, buildingType)

	if ratModel ~= nil then
		local state = ratStates[ratModel]
		if state ~= nil then
			state.state = "fleeing"
			state.stolenBuildingCost = baseCost
		end
		fleeAndDespawnRat(ratModel)
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
	activeRats = {}
	ratStates = {}
end

spawnRatToward = function(targetBuilding: BasePart, isElite: boolean?)
	local radius = Constants.WAVES.SpawnRadius
	local minDist = math.min(Constants.WAVES.MinSpawnDistanceFromCenter, radius)
	local angle = math.random() * math.pi * 2
	local dist = minDist + (math.random() * (radius - minDist))
	local spawnPosition = Vector3.new(math.cos(angle) * dist, 3, math.sin(angle) * dist)
	local ratModel = createScrapRatModel(spawnPosition, isElite)
	activeRats[ratModel] = true

	local state = ratStates[ratModel]
	if state ~= nil then
		state.targetBuilding = targetBuilding
	end

	local humanoid = ratModel:FindFirstChildOfClass("Humanoid")
	local root = ratModel.PrimaryPart

	if humanoid == nil or root == nil then
		return
	end

	local path = PathfindingService:CreatePath()
	local ok = pcall(function()
		path:ComputeAsync(root.Position, targetBuilding.Position)
	end)

	if ok and path.Status == Enum.PathStatus.Success then
		for _, waypoint in path:GetWaypoints() do
			if humanoid.Health <= 0 or targetBuilding.Parent == nil or activeRats[ratModel] == nil then
				if targetBuilding.Parent == nil and activeRats[ratModel] ~= nil then
					retargetRat(ratModel)
				end
				return
			end
			moveToWithShortTimeout(humanoid, waypoint.Position, 0.9)
		end
	else
		moveToWithShortTimeout(humanoid, targetBuilding.Position, 1.2)
	end

	if humanoid.Health <= 0 or activeRats[ratModel] == nil or ratModel.Parent == nil then
		return
	end

	if targetBuilding.Parent ~= nil then
		EnemyService.StartDismantle(targetBuilding, ratModel)
		task.spawn(function()
			while activeRats[ratModel] ~= nil and targetBuilding.Parent ~= nil do
				if humanoid.Health <= 0 then
					return
				end
				task.wait(0.2)
				local progressAttr = targetBuilding:GetAttribute("DismantleProgress")
				if typeof(progressAttr) == "number" and (progressAttr :: number) >= 100 then
					dismantleAndDestroyBuilding(targetBuilding, ratModel)
					return
				end
			end

			if activeRats[ratModel] ~= nil and targetBuilding.Parent == nil then
				retargetRat(ratModel)
			end
		end)
	end
end

function EnemyService.SpawnScrapRat(targetBuilding: BasePart?, isElite: boolean?): ()
	if targetBuilding == nil then
		return
	end
	task.spawn(function()
		spawnRatToward(targetBuilding, isElite)
	end)
end

function EnemyService.SpawnWave(waveNumber: number): ()
	currentWave = waveNumber
	publishNextWaveTimer(0)
	remotes.WaveStarted:FireAllClients(currentWave)

	local baseCount = Constants.WAVES.BaseEnemyCount + (currentWave * Constants.WAVES.EnemiesPerWave)
	local difficultyMult = EnemyService.GetDifficultyMultiplier()
	local enemyCount = math.floor(baseCount * difficultyMult + 0.5)

	swarmActive = true
	for _ = 1, enemyCount do
		local targetBuilding = getTargetBuilding()
		if targetBuilding == nil then
			targetBuilding = ObjectiveService.GetTitanCore()
		end
		if targetBuilding ~= nil then
			EnemyService.SpawnScrapRat(targetBuilding)
		end
	end

	task.spawn(function()
		task.wait(Constants.WAVES.SwarmDurationSeconds)
		swarmActive = false
		remotes.SwarmEnded:FireAllClients()
		retreatAllRats()
	end)
end

function EnemyService.GetCurrentWave(): number
	return currentWave
end

function EnemyService.IsSwarmActive(): boolean
	return swarmActive
end

local function retreatAllRats()
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

function EnemyService.Init(): ()
	RemoteGuard.Register("HitEnemy", 5, 1)

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

	TheftComponent.ConnectCompleted(function(dismantledPart: BasePart, ratModel: Model?)
		dismantleAndDestroyBuilding(dismantledPart, ratModel)
	end)

	ObjectiveService.ConnectGameStateChanged(function(state: string)
		if state == "final_stand" then
			startFinalStandSpawning()
		elseif state == "victory" or state == "defeat" then
			EnemyService.StopAll()
		end
	end)

	task.spawn(function()
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
end

return EnemyService
