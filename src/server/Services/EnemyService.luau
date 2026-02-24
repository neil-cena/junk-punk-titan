--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local RemotesModule = require(Shared:WaitForChild("Remotes"))
local TheftComponent = require(Shared:WaitForChild("TheftComponent"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local EnemyService = {}
EnemyService.__index = EnemyService

local remotes = RemotesModule.Get()
local peakPlayerCount = 0
local currentWave = 0
local activeRats: { Model } = {}

local function updatePeakPlayerCount()
	peakPlayerCount = math.max(peakPlayerCount, #Players:GetPlayers())
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

local function getTargetBuilding(): BasePart?
	local tagged = CollectionService:GetTagged("DismantlableBuilding")
	for _, instance in tagged do
		if instance:IsA("BasePart") and instance.Parent ~= nil then
			return instance
		end
	end
	return nil
end

function EnemyService.GetDifficultyMultiplier(): number
	local playersInSession = #Players:GetPlayers()
	return math.max(1, playersInSession * Constants.SCALING.SwarmMultiplierPerPlayer)
end

function EnemyService.GetLegacyMultiplier(): { scrapMult: number, reloadMult: number }
	local currentPlayers = #Players:GetPlayers()
	local didLosePlayer = peakPlayerCount > 0 and currentPlayers < peakPlayerCount

	if didLosePlayer then
		return {
			scrapMult = 1 + Constants.SCALING.LegacyScrapGatherBuff,
			reloadMult = 1 + Constants.SCALING.LegacyReloadSpeedBuff,
		}
	end

	return {
		scrapMult = 1,
		reloadMult = 1,
	}
end

function EnemyService.StartDismantle(targetBuilding: BasePart, ratModel: Model): ()
	TheftComponent.Attach(targetBuilding)
	TheftComponent.StartDismantle(targetBuilding, ratModel)
end

function EnemyService.SpawnScrapRat(targetBuilding: BasePart?): Model?
	if targetBuilding == nil then
		return nil
	end

	local spawnPosition = targetBuilding.Position + Vector3.new(math.random(-15, 15), 3, math.random(-15, 15))
	local ratModel = createScrapRatModel(spawnPosition)
	table.insert(activeRats, ratModel)

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
			if humanoid.Health <= 0 or targetBuilding.Parent == nil then
				return ratModel
			end
			humanoid:MoveTo(waypoint.Position)
			humanoid.MoveToFinished:Wait()
		end
	else
		humanoid:MoveTo(targetBuilding.Position)
		humanoid.MoveToFinished:Wait()
	end

	if ratModel.Parent ~= nil and targetBuilding.Parent ~= nil then
		EnemyService.StartDismantle(targetBuilding, ratModel)
	end

	return ratModel
end

function EnemyService.SpawnWave(waveNumber: number): ()
	currentWave = waveNumber
	remotes.WaveStarted:FireAllClients(currentWave)

	local baseCount = Constants.SCALING.OptimalPlayers
	local enemyCount = math.max(1, math.floor(baseCount * EnemyService.GetDifficultyMultiplier()))

	for _ = 1, enemyCount do
		local targetBuilding = getTargetBuilding()
		if targetBuilding ~= nil then
			task.spawn(function()
				EnemyService.SpawnScrapRat(targetBuilding)
			end)
		end
	end
end

function EnemyService.Init(): ()
	updatePeakPlayerCount()
	Players.PlayerAdded:Connect(updatePeakPlayerCount)
	Players.PlayerRemoving:Connect(function()
		task.defer(updatePeakPlayerCount)
	end)

	TheftComponent.ConnectCompleted(function(dismantledPart: BasePart, ratModel: Model?)
		local finalPosition = dismantledPart.Position

		if dismantledPart.Parent ~= nil then
			dismantledPart.Parent = nil
		end

		spawnScrapBundle(finalPosition)
		EconomyService.AddScrap(Constants.SCRAP_BUNDLE_VALUE)
		remotes.BuildingDismantled:FireAllClients(dismantledPart.Name, finalPosition)

		if ratModel ~= nil and ratModel.Parent ~= nil then
			ratModel:Destroy()
		end
	end)
end

return EnemyService
