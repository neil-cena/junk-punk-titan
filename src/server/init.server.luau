--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Remotes = require(Shared:WaitForChild("Remotes"))
local EconomyService = require(script:WaitForChild("Services"):WaitForChild("EconomyService"))
local EnemyService = require(script:WaitForChild("Services"):WaitForChild("EnemyService"))
local RoleService = require(script:WaitForChild("Services"):WaitForChild("RoleService"))

Remotes.Get()
EconomyService.Init(100)
RoleService.Init()
EnemyService.Init()
