--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemotesModule = require(Shared:WaitForChild("Remotes"))

local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local EnemyService = require(script.Parent:WaitForChild("EnemyService"))
local StormService = require(script.Parent:WaitForChild("StormService"))

local DebugService = {}

local remotes = RemotesModule.Get()

function DebugService.Init(): ()
	remotes.DebugCommand.OnServerEvent:Connect(function(_player: Player, command: string, payload: any)
		if not RunService:IsStudio() then
			return
		end

		if command == "SpawnWave" then
			local wave = EnemyService.GetCurrentWave() + 1
			EnemyService.SpawnWave(wave)
		elseif command == "StartStorm" then
			StormService.TriggerStormNow()
		elseif command == "AddScrap" then
			local amount = if typeof(payload) == "number" then payload :: number else 100
			EconomyService.AddScrap(math.max(1, math.floor(amount)))
		end
	end)
end

return DebugService
