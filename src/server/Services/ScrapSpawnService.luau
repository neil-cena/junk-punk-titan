--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

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
	pile.Size = Vector3.new(1.8, 1.0, 1.8)
	pile.Material = Enum.Material.CorrodedMetal
	pile.Color = Color3.fromRGB(180, 160, 100)
	pile.Anchored = true
	pile.CanCollide = false
	pile.Position = Vector3.new(x, yPos, z)
	pile.Parent = Workspace
	table.insert(activeScrapPiles, pile)
end

function ScrapSpawnService.Init(): ()
	task.spawn(function()
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

	local MAGNET_TICK = 0.05
	local PULL_SPEED = 40
	local magnetAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		magnetAcc += dt
		if magnetAcc < MAGNET_TICK then
			return
		end
		magnetAcc = 0

		local magnetRadius = Constants.SCRAP_SPAWNS.MagnetRadius
		local alive: { BasePart } = {}

		for _, pile in activeScrapPiles do
			if pile.Parent == nil or pickedPiles[pile] then
				continue
			end

			local nearestRoot: BasePart? = nil
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
					nearestRoot = root
				end
			end

			if nearestRoot ~= nil and nearestDist <= magnetRadius then
				if nearestDist <= 1.5 then
					pickedPiles[pile] = true
					EconomyService.AddScrap(Constants.LOOT.JunkBlockValue)
					pile:Destroy()
				else
					local distRatio = nearestDist / magnetRadius
					local arcY = math.sin(distRatio * math.pi) * 1.5
					local targetPos = nearestRoot.Position + Vector3.new(0, arcY, 0)
					local dir = (targetPos - pile.Position).Unit
					local step = PULL_SPEED * MAGNET_TICK
					local newPos = pile.Position + dir * math.min(step, nearestDist)
					local spinAngle = os.clock() * 4
					pile.CFrame = CFrame.new(newPos) * CFrame.Angles(0, spinAngle, math.sin(spinAngle) * 0.3)
					table.insert(alive, pile)
				end
			else
				table.insert(alive, pile)
			end
		end

		activeScrapPiles = alive
	end)
end

return ScrapSpawnService
