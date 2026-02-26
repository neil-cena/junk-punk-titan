--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local VisualManifest = require(Shared:WaitForChild("VisualManifest"))
local RemotesModule = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local Utils = require(Shared:WaitForChild("Utils"))

local PlayerTrackingService = require(script.Parent:WaitForChild("PlayerTrackingService"))
local RemoteGuard = require(script.Parent.Parent:WaitForChild("RemoteGuard"))

type RoleName = Types.RoleName

local RoleService = {}

local remotes = RemotesModule.Get()
local playerRoles: { [number]: RoleName } = {}
local SHOTGUN_TOOL_NAME = "RustyShotgun"
local WRENCH_TOOL_NAME = "RustyWrench"

local function createRustyShotgunTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = SHOTGUN_TOOL_NAME
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.6, 0.35, 0.35)
	handle.Color = VisualManifest.Tools.WrenchHandleColor
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Parent = tool

	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(1.2, 0.2, 0.2)
	barrel.Color = VisualManifest.Tools.ShotgunBarrelColor
	barrel.Material = VisualManifest.Tools.ShotgunBarrelMaterial
	barrel.CanCollide = false
	barrel.Massless = true
	barrel.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = barrel
	weld.Parent = handle

	barrel.CFrame = handle.CFrame * CFrame.new(1, 0, 0)
	return tool
end

local function createWrenchTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = WRENCH_TOOL_NAME
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1.2, 0.25, 0.25)
	handle.Color = VisualManifest.Tools.WrenchHandleColor
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Parent = tool

	local head = Instance.new("Part")
	head.Name = "WrenchHead"
	head.Size = Vector3.new(0.4, 0.7, 0.2)
	head.Color = VisualManifest.Tools.WrenchHeadColor
	head.Material = VisualManifest.Tools.WrenchHeadMaterial
	head.CanCollide = false
	head.Massless = true
	head.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = handle

	head.CFrame = handle.CFrame * CFrame.new(0.45, 0.22, 0)
	return tool
end

local function removeShotgun(player: Player)
	Utils.RemoveToolByName(player, SHOTGUN_TOOL_NAME)
end

local function removeWrench(player: Player)
	Utils.RemoveToolByName(player, WRENCH_TOOL_NAME)
end

local function ensureShotgunForRole(player: Player, roleName: RoleName)
	if roleName ~= "Enforcer" then
		removeShotgun(player)
		return
	end

	local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack")
	local starterGear = player:FindFirstChild("StarterGear") or player:WaitForChild("StarterGear")

	local character = player.Character
	local hasEquipped = character ~= nil and character:FindFirstChild(SHOTGUN_TOOL_NAME) ~= nil

	if backpack:FindFirstChild(SHOTGUN_TOOL_NAME) == nil and not hasEquipped then
		createRustyShotgunTool().Parent = backpack
	end

	if starterGear:FindFirstChild(SHOTGUN_TOOL_NAME) == nil then
		createRustyShotgunTool().Parent = starterGear
	end
end

local function ensureWrenchForRole(player: Player, roleName: RoleName)
	if roleName ~= "Fixer" then
		removeWrench(player)
		return
	end

	local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack")
	local starterGear = player:FindFirstChild("StarterGear") or player:WaitForChild("StarterGear")

	local character = player.Character
	local hasEquipped = character ~= nil and character:FindFirstChild(WRENCH_TOOL_NAME) ~= nil

	if backpack:FindFirstChild(WRENCH_TOOL_NAME) == nil and not hasEquipped then
		createWrenchTool().Parent = backpack
	end

	if starterGear:FindFirstChild(WRENCH_TOOL_NAME) == nil then
		createWrenchTool().Parent = starterGear
	end
end

local function applyRoleAttributes(player: Player, roleName: RoleName)
	local roleDefinition = Constants.ROLE_DEFINITIONS[roleName]
	if roleDefinition == nil then
		return
	end

	player:SetAttribute("Role", roleName)
	player:SetAttribute("SpeedMult", roleDefinition.speedMult)
	player:SetAttribute("RepairMult", roleDefinition.repairMult)
	player:SetAttribute("DamageMult", roleDefinition.damageMult)
	player:SetAttribute("BuildCostMult", roleDefinition.buildCostMult or 1)
	player:SetAttribute("LootBonusMult", roleDefinition.lootBonusMult or 1)
	player:SetAttribute("LegacyScrapGatherMult", PlayerTrackingService.GetLegacyScrapMultiplier())
	player:SetAttribute("LegacyReloadSpeedMult", PlayerTrackingService.GetLegacyReloadMultiplier())

	local character = player.Character
	if character ~= nil then
		character:SetAttribute("Role", roleName)
		character:SetAttribute("SpeedMult", roleDefinition.speedMult)
		character:SetAttribute("RepairMult", roleDefinition.repairMult)
		character:SetAttribute("DamageMult", roleDefinition.damageMult)
		character:SetAttribute("BuildCostMult", roleDefinition.buildCostMult or 1)
		character:SetAttribute("LootBonusMult", roleDefinition.lootBonusMult or 1)
		character:SetAttribute("LegacyScrapGatherMult", PlayerTrackingService.GetLegacyScrapMultiplier())
		character:SetAttribute("LegacyReloadSpeedMult", PlayerTrackingService.GetLegacyReloadMultiplier())
	end

	ensureShotgunForRole(player, roleName)
	ensureWrenchForRole(player, roleName)
end

function RoleService.AssignRole(player: Player, roleName: string): boolean
	if Constants.ROLE_DEFINITIONS[roleName] == nil then
		return false
	end

	if playerRoles[player.UserId] ~= nil then
		return false
	end

	local typedRoleName = roleName :: RoleName
	playerRoles[player.UserId] = typedRoleName
	applyRoleAttributes(player, typedRoleName)
	return true
end

function RoleService.GetActiveBuffs(player: Player): {
	role: RoleName?,
	speedMult: number,
	repairMult: number,
	damageMult: number,
	scrapGatherMult: number,
	reloadSpeedMult: number,
}
	local roleName = playerRoles[player.UserId]
	local roleDefinition = if roleName ~= nil then Constants.ROLE_DEFINITIONS[roleName] else nil

	return {
		role = roleName,
		speedMult = if roleDefinition ~= nil then roleDefinition.speedMult else 1,
		repairMult = if roleDefinition ~= nil then roleDefinition.repairMult else 1,
		damageMult = if roleDefinition ~= nil then roleDefinition.damageMult else 1,
		scrapGatherMult = PlayerTrackingService.GetLegacyScrapMultiplier(),
		reloadSpeedMult = PlayerTrackingService.GetLegacyReloadMultiplier(),
	}
end

function RoleService.AllPlayersReady(): boolean
	local players = Players:GetPlayers()
	if #players == 0 then
		return false
	end
	for _, player in players do
		if playerRoles[player.UserId] == nil then
			return false
		end
	end
	return true
end

function RoleService.WaitForAllPlayersReady()
	while not RoleService.AllPlayersReady() do
		task.wait(0.5)
	end
end

function RoleService.Init(): ()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			local existingRole = playerRoles[player.UserId]
			if existingRole ~= nil then
				applyRoleAttributes(player, existingRole)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerRoles[player.UserId] = nil

		for _, survivor in Players:GetPlayers() do
			local roleName = playerRoles[survivor.UserId]
			if roleName ~= nil then
				applyRoleAttributes(survivor, roleName)
			end
		end
	end)

	RemoteGuard.Register("RoleSelected", 1, 5)

	remotes.RoleSelected.OnServerEvent:Connect(function(player: Player, roleName: string)
		if not RemoteGuard.Check("RoleSelected", player) then
			return
		end
		if typeof(roleName) ~= "string" then
			return
		end
		RoleService.AssignRole(player, roleName)
	end)
end

return RoleService
