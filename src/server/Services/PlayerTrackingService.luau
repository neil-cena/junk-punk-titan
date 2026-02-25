--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))

local PlayerTrackingService = {}

local peakPlayerCount = 0

local function updatePeakPlayerCount()
	peakPlayerCount = math.max(peakPlayerCount, #Players:GetPlayers())
end

function PlayerTrackingService.GetPeakPlayerCount(): number
	return peakPlayerCount
end

function PlayerTrackingService.GetCurrentPlayerCount(): number
	return #Players:GetPlayers()
end

function PlayerTrackingService.HasLostPlayers(): boolean
	return peakPlayerCount > 0 and #Players:GetPlayers() < peakPlayerCount
end

function PlayerTrackingService.GetLegacyScrapMultiplier(): number
	if PlayerTrackingService.HasLostPlayers() then
		return 1 + Constants.SCALING.LegacyScrapGatherBuff
	end
	return 1
end

function PlayerTrackingService.GetLegacyReloadMultiplier(): number
	if PlayerTrackingService.HasLostPlayers() then
		return 1 + Constants.SCALING.LegacyReloadSpeedBuff
	end
	return 1
end

function PlayerTrackingService.Init(): ()
	updatePeakPlayerCount()
	Players.PlayerAdded:Connect(updatePeakPlayerCount)
	Players.PlayerRemoving:Connect(function()
		task.defer(updatePeakPlayerCount)
	end)
end

return PlayerTrackingService
