--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local RemotesModule = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))

type BuildingType = Types.BuildingType
type PurchaseResponse = Types.PurchaseResponse

local EconomyService = {}
EconomyService.__index = EconomyService

local teamScrap = 0
local stormSteel = 0
local remotes = RemotesModule.Get()

local function applyDeathPenalty()
	if teamScrap <= 0 then
		return
	end
	local loss = math.floor(teamScrap * 0.15 + 0.5)
	if loss <= 0 then
		return
	end
	teamScrap = math.max(0, teamScrap - loss)
	remotes.ScrapUpdated:FireAllClients(teamScrap)
end

local function bindDeathPenalty(player: Player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid")
		if humanoid == nil or not humanoid:IsA("Humanoid") then
			return
		end
		humanoid.Died:Connect(function()
			applyDeathPenalty()
		end)
	end)
end

function EconomyService.GetCost(baseCost: number, count: number): number
	local clampedCount = math.max(0, count)
	local rawCost = baseCost * (Constants.GROWTH_RATE ^ clampedCount)
	return math.floor(rawCost + 0.5)
end

function EconomyService.AddScrap(amount: number): number
	teamScrap += amount
	remotes.ScrapUpdated:FireAllClients(teamScrap)
	return teamScrap
end

function EconomyService.GetScrap(): number
	return teamScrap
end

function EconomyService.AddStormSteel(amount: number): number
	stormSteel += amount
	remotes.StormSteelUpdated:FireAllClients(stormSteel)
	return stormSteel
end

function EconomyService.GetStormSteel(): number
	return stormSteel
end

local function getBaseCost(buildingType: BuildingType): number?
	local baseCost = Constants.BASE_COSTS[buildingType]
	if typeof(baseCost) ~= "number" then
		return nil
	end
	return baseCost
end

local function validatePurchase(buildingType: BuildingType, currentCount: number): PurchaseResponse
	local baseCost = getBaseCost(buildingType)
	if baseCost == nil then
		return {
			success = false,
			cost = 0,
			remainingScrap = teamScrap,
			reason = "Unknown building type",
		}
	end

	local purchaseCost = EconomyService.GetCost(baseCost, currentCount)
	if teamScrap < purchaseCost then
		return {
			success = false,
			cost = purchaseCost,
			remainingScrap = teamScrap,
			reason = "Not enough scrap",
		}
	end

	teamScrap -= purchaseCost
	remotes.ScrapUpdated:FireAllClients(teamScrap)

	return {
		success = true,
		cost = purchaseCost,
		remainingScrap = teamScrap,
	}
end

function EconomyService.TryPurchase(buildingType: BuildingType, currentCount: number): PurchaseResponse
	return validatePurchase(buildingType, currentCount)
end

function EconomyService.Init(initialScrap: number?): ()
	if typeof(initialScrap) == "number" then
		teamScrap = math.max(0, initialScrap :: number)
	end

	remotes.RequestPurchase.OnServerInvoke = function(_player: Player, buildingType: BuildingType, currentCount: number)
		return EconomyService.TryPurchase(buildingType, currentCount)
	end
	remotes.RequestEconomyState.OnServerInvoke = function(_player: Player)
		return {
			scrap = teamScrap,
			stormSteel = stormSteel,
		}
	end

	remotes.ScrapUpdated:FireAllClients(teamScrap)
	remotes.StormSteelUpdated:FireAllClients(stormSteel)

	for _, player in Players:GetPlayers() do
		remotes.ScrapUpdated:FireClient(player, teamScrap)
		remotes.StormSteelUpdated:FireClient(player, stormSteel)
		bindDeathPenalty(player)
	end

	Players.PlayerAdded:Connect(function(player)
		bindDeathPenalty(player)
		task.defer(function()
			remotes.ScrapUpdated:FireClient(player, teamScrap)
			remotes.StormSteelUpdated:FireClient(player, stormSteel)
		end)
	end)
end

return EconomyService
