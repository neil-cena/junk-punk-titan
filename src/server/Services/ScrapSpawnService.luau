--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local VisualManifest = require(Shared:WaitForChild("VisualManifest"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local RoleService = require(script.Parent:WaitForChild("RoleService"))

local ScrapSpawnService = {}

local activeScrapPiles: { BasePart } = {}
local pickedPiles: { [BasePart]: boolean } = {}
local elapsedCycles = 0

local function getActivePileCount(): number
	local alive: { BasePart } = {}
	for _, pile in activeScrapPiles do
		if pile.Parent ~= nil and not pickedPiles[pile] then
			table.insert(alive, pile)
		end
	end
	activeScrapPiles = alive
	return #activeScrapPiles
end

local function getCurrentRadius(): number
	local cfg = Constants.SCRAP_SPAWNS
	local t = math.clamp(elapsedCycles / cfg.RadiusRampCycles, 0, 1)
	return cfg.MinSpawnRadius + (cfg.MaxSpawnRadius - cfg.MinSpawnRadius) * t
end

local function spawnScrapPile()
	local radius = getCurrentRadius()
	local angle = math.random() * math.pi * 2
	local dist = math.random() * radius
	local x = math.floor(math.cos(angle) * dist)
	local z = math.floor(math.sin(angle) * dist)

	local rayOrigin = Vector3.new(x, 200, z)
	local result = Workspace:Raycast(rayOrigin, Vector3.new(0, -400, 0))
	local yPos = if result then result.Position.Y + 0.8 else 0.8

	local pile = Instance.new("Part")
	pile.Name = "JunkBlock"
	pile.Size = Vector3.new(1.7, 1.0, 1.7)
	pile.Material = VisualManifest.Loot.JunkBlock.material
	pile.Color = VisualManifest.Loot.JunkBlock.color
	pile.Anchored = true
	pile.CanCollide = false
	pile.Position = Vector3.new(x, yPos, z)
	pile.Parent = Workspace

	table.insert(activeScrapPiles, pile)
end

function ScrapSpawnService.Init(): ()
	task.spawn(function()
		RoleService.WaitForAllPlayersReady()
		while true do
			task.wait(Constants.SCRAP_SPAWNS.IntervalSeconds)
			local activeCount = getActivePileCount()
			local budget = math.max(0, Constants.SCRAP_SPAWNS.MaxActivePiles - activeCount)
			local spawnCount = math.min(Constants.SCRAP_SPAWNS.CountPerSpawn, budget)
			for _ = 1, spawnCount do
				spawnScrapPile()
			end
			elapsedCycles += 1
		end
	end)

	local MAGNET_TICK = 0.15
	local MAX_COLLECTS_PER_TICK = 5
	local magnetAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		magnetAcc += dt
		if magnetAcc < MAGNET_TICK then
			return
		end
		magnetAcc = 0

		local magnetRadius = Constants.SCRAP_SPAWNS.MagnetRadius
		local alive: { BasePart } = {}
		local collectedThisTick = 0

		for _, pile in activeScrapPiles do
			if pile.Parent == nil or pickedPiles[pile] then
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
				local pDist = (root.Position - pile.Position).Magnitude
				if pDist < nearestDist then
					nearestDist = pDist
					nearestPlayer = player
				end
			end

			if nearestPlayer ~= nil and nearestDist <= magnetRadius then
				if collectedThisTick >= MAX_COLLECTS_PER_TICK then
					table.insert(alive, pile)
					continue
				end
				collectedThisTick += 1
				pickedPiles[pile] = true
				local isInstant = nearestDist <= Constants.SCRAP_SPAWNS.InstantPickupRadius
				pile:SetAttribute("MagnetTarget", nearestPlayer.Name)
				if isInstant then
					pile:SetAttribute("InstantPickup", true)
				end
				local scrapValue = Constants.LOOT.JunkBlockValue
				if math.random() < Constants.LOOT.CriticalHarvestChance then
					scrapValue = scrapValue * Constants.LOOT.CriticalHarvestMultiplier
					pile:SetAttribute("CriticalHarvest", true)
				end
				EconomyService.AddScrap(scrapValue)
				if isInstant then
					task.defer(function()
						if pile.Parent ~= nil then
							pile:Destroy()
						end
					end)
				else
					task.delay(0.5, function()
						if pile.Parent ~= nil then
							pile:Destroy()
						end
					end)
				end
			else
				if pile:GetAttribute("MagnetTarget") ~= nil then
					pile:SetAttribute("MagnetTarget", nil)
				end
				table.insert(alive, pile)
			end
		end

		activeScrapPiles = alive
	end)
end

return ScrapSpawnService
