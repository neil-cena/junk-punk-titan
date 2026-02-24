--!strict

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
local remotes = RemotesModule.Get()

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

function EconomyService.Init(initialScrap: number?): ()
	if typeof(initialScrap) == "number" then
		teamScrap = math.max(0, initialScrap :: number)
	end

	remotes.RequestPurchase.OnServerInvoke = function(_player: Player, buildingType: BuildingType, currentCount: number)
		return validatePurchase(buildingType, currentCount)
	end

	remotes.ScrapUpdated:FireAllClients(teamScrap)
end

return EconomyService
