--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local remotes = Remotes.Get()

remotes.ScrapUpdated.OnClientEvent:Connect(function(currentScrap: number)
	print(("[Economy] Team Scrap updated: %d"):format(currentScrap))
end)

remotes.BuildingDismantled.OnClientEvent:Connect(function(buildingName: string, position: Vector3)
	print(("[Theft] %s dismantled at %.1f, %.1f, %.1f"):format(buildingName, position.X, position.Y, position.Z))
end)

remotes.WaveStarted.OnClientEvent:Connect(function(waveNumber: number)
	print(("[Wave] Started wave %d"):format(waveNumber))
end)

local function requestPurchase(buildingType: "Turret" | "Drill" | "Wall", currentCount: number)
	local response = remotes.RequestPurchase:InvokeServer(buildingType, currentCount)
	if response.success then
		print(("[Build] Purchased %s for %d scrap"):format(buildingType, response.cost))
	else
		warn(("[Build] Purchase failed (%s): %s"):format(buildingType, response.reason or "Unknown"))
	end
end

task.delay(1, function()
	requestPurchase("Wall", 0)
end)

print(("[Client] Junk-Punk initialized (growth rate: %.2f)"):format(Constants.GROWTH_RATE))
