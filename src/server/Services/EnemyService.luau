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
local activeRats: { [Model]: true } = {}
local burrowPositions = {
	Vector3.new(-220, 0.2, -220),
	Vector3.new(220, 0.2, -220),
	Vector3.new(-220, 0.2, 220),
	Vector3.new(220, 0.2, 220),
}

local function publishNextWaveTimer(secondsRemaining: number)
	local remaining = math.max(0, math.floor(secondsRemaining + 0.5))
	local nextWaveTime = os.time() + remaining
	remotes.Folder:SetAttribute("NextWaveTime", nextWaveTime)
	remotes.UpdateWaveTimer:FireAllClients(remaining, nextWaveTime)
end

local function createScrapRatModel(spawnPosition: Vector3): Model
	local rat = Instance.new("Model")
	rat.Name = "ScrapRat"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 2)
	root.Anchored = false
	root.CanCollide = true
	root.Position = spawnPosition
	root.Parent = rat

	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = 12
	humanoid.Parent = rat

	rat.PrimaryPart = root
	CollectionService:AddTag(rat, "ScrapRatEnemy")
	rat.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			removeRatFromActive(rat)
		end
	end)
	rat.Parent = workspace
	return rat
end

local function spawnScrapBundle(atPosition: Vector3)
	local bundle = Instance.new("Part")
	bundle.Name = "ScrapBundle"
	bundle.Size = Vector3.new(1.5, 1.5, 1.5)
	bundle.Shape = Enum.PartType.Ball
	bundle.Material = Enum.Material.Metal
	bundle.Color = Color3.fromRGB(168, 168, 168)
	bundle.Anchored = false
	bundle.CanCollide = true
	bundle.Position = atPosition + Vector3.new(0, 2, 0)
	bundle.Parent = workspace
end

local function getBuildingTypeAndBaseCost(buildingPart: BasePart): (string?, number)
	for buildingType, baseCost in Constants.BASE_COSTS do
		if string.find(buildingPart.Name, buildingType) ~= nil then
			return buildingType, baseCost
		end
	end

	return nil, 0
end

local function getMostExpensiveBuilding(): BasePart?
	local best: BasePart? = nil
	local bestCost = -1
	local bestProgress = math.huge
	local tagged = CollectionService:GetTagged("DismantlableBuilding")
	for _, instance in tagged do
		if instance:IsA("BasePart") and instance.Parent ~= nil then
			local _, baseCost = getBuildingTypeAndBaseCost(instance)
			local progressAttr = instance:GetAttribute("DismantleProgress")
			local progress = if typeof(progressAttr) == "number" then progressAttr :: number else 0

			if baseCost > bestCost then
				best = instance
				bestCost = baseCost
				bestProgress = progress
			elseif baseCost == bestCost and progress < bestProgress then
				best = instance
				bestProgress = progress
			end
		end
	end

	return best
end

function EnemyService.GetDifficultyMultiplier(): number
	local playersInSession = PlayerTrackingService.GetCurrentPlayerCount()
	return math.max(1, playersInSession * Constants.SCALING.SwarmMultiplierPerPlayer)
end

function EnemyService.StartDismantle(targetBuilding: BasePart, ratModel: Model): ()
	TheftComponent.Attach(targetBuilding)
	TheftComponent.StartDismantle(targetBuilding, ratModel)
	remotes.ThreatDetected:FireAllClients(targetBuilding.Name, targetBuilding.Position)
end

local function removeRatFromActive(ratModel: Model)
	activeRats[ratModel] = nil
end

local function despawnRat(ratModel: Model)
	removeRatFromActive(ratModel)
	if ratModel.Parent ~= nil then
		ratModel:Destroy()
	end
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
	if root == nil or humanoid == nil then
		despawnRat(ratModel)
		return
	end

	local visual = attachStolenScrapVisual(ratModel)
	local holePosition = pickNearestBurrow(root.Position)
	local hole = ensureBurrowHole(holePosition)

	moveToWithShortTimeout(humanoid, holePosition, 2.5)
	if visual ~= nil and visual.Parent ~= nil then
		visual:Destroy()
	end

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
		task.wait(0.05)
	end

	connection:Disconnect()
	return reached
end

local function dismantleAndDestroyBuilding(dismantledPart: BasePart, ratModel: Model?)
	local finalPosition = dismantledPart.Position
	local buildingType = dismantledPart:GetAttribute("BuildingType")

	if dismantledPart.Parent ~= nil then
		remotes.BuildingDismantled:FireAllClients(dismantledPart.Name, finalPosition)
		dismantledPart:Destroy()
	end

	BuildingService.RegisterDestroyedSlot(finalPosition, buildingType)

	if ratModel ~= nil then
		fleeAndDespawnRat(ratModel)
	end
end

function EnemyService.KillRat(ratModel: Model): boolean
	if ratModel.Parent == nil or ratModel.Name ~= "ScrapRat" then
		return false
	end

	local root = ratModel.PrimaryPart
	local atPosition = if root ~= nil then root.Position else ratModel:GetPivot().Position

	despawnRat(ratModel)

	spawnScrapBundle(atPosition)
	EconomyService.AddScrap(Constants.COMBAT.RatKillScrapReward)
	remotes.EnemyKilled:FireAllClients(atPosition)
	return true
end

function EnemyService.SpawnScrapRat(targetBuilding: BasePart?): Model?
	if targetBuilding == nil then
		return nil
	end

	local radius = Constants.WAVES.SpawnRadius
	local spawnPosition = targetBuilding.Position + Vector3.new(math.random(-radius, radius), 3, math.random(-radius, radius))
	local ratModel = createScrapRatModel(spawnPosition)
	activeRats[ratModel] = true

	local humanoid = ratModel:FindFirstChildOfClass("Humanoid")
	local root = ratModel.PrimaryPart

	if humanoid == nil or root == nil then
		return ratModel
	end

	-- Basic movement skeleton: pathfinding attempt, fallback to direct move.
	local path = PathfindingService:CreatePath()
	local ok = pcall(function()
		path:ComputeAsync(root.Position, targetBuilding.Position)
	end)

	if ok and path.Status == Enum.PathStatus.Success then
		for _, waypoint in path:GetWaypoints() do
			if humanoid.Health <= 0 or targetBuilding.Parent == nil or activeRats[ratModel] == nil then
				if targetBuilding.Parent == nil then
					despawnRat(ratModel)
				end
				return ratModel
			end
			moveToWithShortTimeout(humanoid, waypoint.Position, 0.9)
		end
	else
		moveToWithShortTimeout(humanoid, targetBuilding.Position, 1.2)
	end

	if activeRats[ratModel] ~= nil and ratModel.Parent ~= nil and targetBuilding.Parent ~= nil then
		EnemyService.StartDismantle(targetBuilding, ratModel)
		task.spawn(function()
			while activeRats[ratModel] ~= nil and targetBuilding.Parent ~= nil do
				task.wait(0.2)
				local progressAttr = targetBuilding:GetAttribute("DismantleProgress")
				if typeof(progressAttr) == "number" and (progressAttr :: number) >= 100 then
					dismantleAndDestroyBuilding(targetBuilding, ratModel)
					return
				end
			end

			if activeRats[ratModel] ~= nil and targetBuilding.Parent == nil then
				despawnRat(ratModel)
			end
		end)
	end

	return ratModel
end

function EnemyService.SpawnWave(waveNumber: number): ()
	currentWave = waveNumber
	publishNextWaveTimer(0)
	remotes.WaveStarted:FireAllClients(currentWave)

	local enemyCount = Constants.WAVES.BaseEnemyCount + (currentWave * Constants.WAVES.EnemiesPerWave)

	for _ = 1, enemyCount do
		local targetBuilding = getMostExpensiveBuilding()
		if targetBuilding == nil then
			targetBuilding = ObjectiveService.GetTitanCore()
		end
		if targetBuilding ~= nil then
			task.spawn(function()
				EnemyService.SpawnScrapRat(targetBuilding)
			end)
		end
	end
end

function EnemyService.GetCurrentWave(): number
	return currentWave
end

function EnemyService.Init(): ()
	RemoteGuard.Register("HitEnemy", 5, 1)

	remotes.HitEnemy.OnServerEvent:Connect(function(player: Player, ratModelOrPart: Instance)
		if not RemoteGuard.Check("HitEnemy", player) then
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

		local root = ratModel.PrimaryPart
		local char = player.Character
		local playerRoot = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if root == nil or playerRoot == nil or not playerRoot:IsA("BasePart") then
			return
		end

		if (playerRoot.Position - root.Position).Magnitude > Constants.COMBAT.ShotgunRange then
			return
		end

		EnemyService.KillRat(ratModel)
	end)

	TheftComponent.ConnectCompleted(function(dismantledPart: BasePart, ratModel: Model?)
		dismantleAndDestroyBuilding(dismantledPart, ratModel)
	end)

	task.spawn(function()
		while true do
			local remaining = Constants.WAVES.IntervalSeconds
			while remaining > 0 do
				publishNextWaveTimer(remaining)
				task.wait(1)
				remaining -= 1
			end
			publishNextWaveTimer(0)
			local nextWave = currentWave + 1
			EnemyService.SpawnWave(nextWave)
		end
	end)
end

return EnemyService
