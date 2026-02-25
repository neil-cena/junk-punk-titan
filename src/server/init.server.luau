--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Remotes = require(Shared:WaitForChild("Remotes"))
local PlayerTrackingService = require(script:WaitForChild("Services"):WaitForChild("PlayerTrackingService"))
local EconomyService = require(script:WaitForChild("Services"):WaitForChild("EconomyService"))
local BuildingService = require(script:WaitForChild("Services"):WaitForChild("BuildingService"))
local ResourceService = require(script:WaitForChild("Services"):WaitForChild("ResourceService"))
local ObjectiveService = require(script:WaitForChild("Services"):WaitForChild("ObjectiveService"))
local EnemyService = require(script:WaitForChild("Services"):WaitForChild("EnemyService"))
local RoleService = require(script:WaitForChild("Services"):WaitForChild("RoleService"))
local StormService = require(script:WaitForChild("Services"):WaitForChild("StormService"))
local DebugService = require(script:WaitForChild("Services"):WaitForChild("DebugService"))

Remotes.Get()

local initOrder: { { name: string, fn: () -> () } } = {
	{ name = "PlayerTrackingService", fn = function() PlayerTrackingService.Init() end },
	{ name = "EconomyService", fn = function() EconomyService.Init(100) end },
	{ name = "BuildingService", fn = function() BuildingService.Init() end },
	{ name = "ResourceService", fn = function() ResourceService.Init() end },
	{ name = "ObjectiveService", fn = function() ObjectiveService.Init() end },
	{ name = "RoleService", fn = function() RoleService.Init() end },
	{ name = "EnemyService", fn = function() EnemyService.Init() end },
	{ name = "StormService", fn = function() StormService.Init() end },
	{ name = "DebugService", fn = function() DebugService.Init() end },
}

for _, entry in initOrder do
	local ok, err = pcall(entry.fn)
	if not ok then
		warn(("[ServerInit] %s.Init() FAILED: %s"):format(entry.name, tostring(err)))
	end
end
