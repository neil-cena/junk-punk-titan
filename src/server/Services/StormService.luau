--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local RemotesModule = require(Shared:WaitForChild("Remotes"))

local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local StormService = {}
StormService.__index = StormService

local remotes = RemotesModule.Get()
local peakPlayerCount = 0
local activeStorm = false
local tetherPads: { BasePart } = {}

local function updatePeakPlayers()
	peakPlayerCount = math.max(peakPlayerCount, #Players:GetPlayers())
end

local function createStormScrapBundle(atPosition: Vector3)
	local bundle = Instance.new("Part")
	bundle.Name = "StormScrapBundle"
	bundle.Size = Vector3.new(1.2, 1.2, 1.2)
	bundle.Shape = Enum.PartType.Ball
	bundle.Material = Enum.Material.Metal
	bundle.Color = Color3.fromRGB(120, 120, 120)
	bundle.Anchored = false
	bundle.CanCollide = true
	bundle.Position = atPosition + Vector3.new(0, 2, 0)
	bundle.Parent = Workspace
end

local function spawnTetherPads()
	local center = Vector3.new(0, 0.5, 0)
	local spacing = 16
	local offsets = {
		Vector3.new(-spacing, 0, -spacing),
		Vector3.new(spacing, 0, -spacing),
		Vector3.new(0, 0, spacing),
	}

	for index, offset in offsets do
		local pad = Instance.new("Part")
		pad.Name = ("TetherPad%d"):format(index)
		pad.Anchored = true
		pad.CanCollide = false
		pad.Material = Enum.Material.Neon
		pad.Color = Color3.fromRGB(255, 175, 70)
		pad.Size = Vector3.new(8, 0.6, 8)
		pad.Position = center + offset
		pad.Parent = Workspace
		CollectionService:AddTag(pad, "TetherPad")
		table.insert(tetherPads, pad)
	end
end

local function clearTetherPads()
	for _, pad in tetherPads do
		if pad.Parent ~= nil then
			pad:Destroy()
		end
	end
	tetherPads = {}
end

local function countAnchoredPads(): number
	local occupied = 0
	for _, pad in tetherPads do
		if pad.Parent ~= nil then
			local touchingPlayers = {}
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
				if root ~= nil and root:IsA("BasePart") then
					local distance = (root.Position - pad.Position).Magnitude
					if distance <= Constants.STORM.TetherPadRadius then
						touchingPlayers[player.UserId] = true
					end
				end
			end

			if next(touchingPlayers) ~= nil then
				occupied += 1
			end
		end
	end

	return occupied
end

local function requiredPadCount(): number
	local currentPlayers = #Players:GetPlayers()
	if currentPlayers < peakPlayerCount then
		return Constants.STORM.TetherPadsReducedOnLeave
	end

	return Constants.STORM.TetherPadsRequired
end

local function applyStormWindDamage()
	for _, instance in CollectionService:GetTagged("DismantlableBuilding") do
		if instance:IsA("BasePart") and instance.Parent ~= nil then
			local progressAttr = instance:GetAttribute("DismantleProgress")
			local currentProgress = if typeof(progressAttr) == "number" then (progressAttr :: number) else 0
			local nextProgress = math.clamp(currentProgress + Constants.STORM.WindDamagePerSecond, 0, 100)
			instance:SetAttribute("DismantleProgress", nextProgress)
			instance:SetAttribute("IsBeingDismantled", true)

			if nextProgress >= 100 then
				local destroyedPos = instance.Position
				instance.Parent = nil
				createStormScrapBundle(destroyedPos)
				EconomyService.AddScrap(Constants.SCRAP_BUNDLE_VALUE)
				remotes.BuildingDismantled:FireAllClients("StormDamage", destroyedPos)
			end
		end
	end
end

local function spawnStormSteelDrops()
	for _ = 1, Constants.STORM.StormSteelDropCount do
		local drop = Instance.new("Part")
		drop.Name = "StormHardenedSteel"
		drop.Shape = Enum.PartType.Ball
		drop.Material = Enum.Material.Metal
		drop.Color = Color3.fromRGB(100, 160, 200)
		drop.Size = Vector3.new(1.6, 1.6, 1.6)
		drop.Position = Vector3.new(math.random(-25, 25), 3, math.random(-25, 25))
		drop.Anchored = false
		drop.CanCollide = true
		drop.Parent = Workspace

		local picked = false
		drop.Touched:Connect(function(hit: BasePart)
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
			EconomyService.AddStormSteel(1)
			drop:Destroy()
		end)
	end
end

local function runStorm()
	activeStorm = true
	remotes.StormStarted:FireAllClients()
	spawnTetherPads()

	local elapsed = 0
	while activeStorm and elapsed < Constants.STORM.DurationSeconds do
		task.wait(1)
		elapsed += 1

		local occupiedPads = countAnchoredPads()
		local neededPads = requiredPadCount()
		remotes.TetherStatus:FireAllClients(occupiedPads, neededPads)

		if occupiedPads < neededPads then
			applyStormWindDamage()
		end
	end

	clearTetherPads()
	remotes.TetherStatus:FireAllClients(0, 0)
	spawnStormSteelDrops()
	activeStorm = false
	remotes.StormEnded:FireAllClients()
end

function StormService.TriggerStormNow(): boolean
	if activeStorm then
		return false
	end

	task.spawn(runStorm)
	return true
end

function StormService.Init(): ()
	updatePeakPlayers()
	Players.PlayerAdded:Connect(updatePeakPlayers)
	Players.PlayerRemoving:Connect(function()
		task.defer(updatePeakPlayers)
	end)

	task.spawn(function()
		while true do
			task.wait(Constants.STORM.IntervalSeconds)
			if not activeStorm then
				StormService.TriggerStormNow()
			end
		end
	end)
end

return StormService
