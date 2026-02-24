--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Remotes = require(Shared:WaitForChild("Remotes"))
local EconomyService = require(script:WaitForChild("Services"):WaitForChild("EconomyService"))
local BuildingService = require(script:WaitForChild("Services"):WaitForChild("BuildingService"))
local ResourceService = require(script:WaitForChild("Services"):WaitForChild("ResourceService"))
local EnemyService = require(script:WaitForChild("Services"):WaitForChild("EnemyService"))
local RoleService = require(script:WaitForChild("Services"):WaitForChild("RoleService"))
local StormService = require(script:WaitForChild("Services"):WaitForChild("StormService"))
local DebugService = require(script:WaitForChild("Services"):WaitForChild("DebugService"))

Remotes.Get()
EconomyService.Init(100)
BuildingService.Init()
ResourceService.Init()
RoleService.Init()
EnemyService.Init()
StormService.Init()
DebugService.Init()
