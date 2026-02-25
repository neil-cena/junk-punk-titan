--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local ScrapSpawnService = {}

local activeScrapPiles: { BasePart } = {}

local function spawnScrapPile()
	local radius = Constants.SCRAP_SPAWNS.SpawnRadius
	local x = math.random(-radius, radius)
	local z = math.random(-radius, radius)

	local rayOrigin = Vector3.new(x, 200, z)
	local result = Workspace:Raycast(rayOrigin, Vector3.new(0, -400, 0))
	local yPos = if result then result.Position.Y + 0.8 else 0.8

	local pile = Instance.new("Part")
	pile.Name = "LooseScrapPile"
	pile.Size = Vector3.new(1.8, 1.0, 1.8)
	pile.Material = Enum.Material.CorrodedMetal
	pile.Color = Color3.fromRGB(180, 160, 100)
	pile.Anchored = true
	pile.CanCollide = false
	pile.Position = Vector3.new(x, yPos, z)
	pile.Parent = Workspace
	table.insert(activeScrapPiles, pile)

	local picked = false
	pile.Touched:Connect(function(hit: BasePart)
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
		EconomyService.AddScrap(Constants.SCRAP_SPAWNS.ValuePerPile)
		pile:Destroy()
	end)

	task.delay(Constants.SCRAP_SPAWNS.DespawnSeconds, function()
		if not picked and pile.Parent ~= nil then
			pile:Destroy()
		end
	end)
end

function ScrapSpawnService.Init(): ()
	task.spawn(function()
		while true do
			task.wait(Constants.SCRAP_SPAWNS.IntervalSeconds)
			for _ = 1, Constants.SCRAP_SPAWNS.CountPerSpawn do
				spawnScrapPile()
			end
		end
	end)
end

return ScrapSpawnService
