--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local RemotesModule = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))

type RoleName = Types.RoleName

local RoleService = {}
RoleService.__index = RoleService

local remotes = RemotesModule.Get()
local playerRoles: { [number]: RoleName } = {}
local peakPlayerCount = 0
local legacyBuff = {
	scrapGatherMult = 1,
	reloadSpeedMult = 1,
}

local function updateLegacyBuff()
	local currentPlayers = #Players:GetPlayers()
	peakPlayerCount = math.max(peakPlayerCount, currentPlayers)

	if peakPlayerCount > 0 and currentPlayers < peakPlayerCount then
		legacyBuff = {
			scrapGatherMult = 1 + Constants.SCALING.LegacyScrapGatherBuff,
			reloadSpeedMult = 1 + Constants.SCALING.LegacyReloadSpeedBuff,
		}
	else
		legacyBuff = {
			scrapGatherMult = 1,
			reloadSpeedMult = 1,
		}
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
	player:SetAttribute("LegacyScrapGatherMult", legacyBuff.scrapGatherMult)
	player:SetAttribute("LegacyReloadSpeedMult", legacyBuff.reloadSpeedMult)

	local character = player.Character
	if character ~= nil then
		character:SetAttribute("Role", roleName)
		character:SetAttribute("SpeedMult", roleDefinition.speedMult)
		character:SetAttribute("RepairMult", roleDefinition.repairMult)
		character:SetAttribute("DamageMult", roleDefinition.damageMult)
		character:SetAttribute("LegacyScrapGatherMult", legacyBuff.scrapGatherMult)
		character:SetAttribute("LegacyReloadSpeedMult", legacyBuff.reloadSpeedMult)
	end
end

function RoleService.AssignRole(player: Player, roleName: string): boolean
	if Constants.ROLE_DEFINITIONS[roleName] == nil then
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
		scrapGatherMult = legacyBuff.scrapGatherMult,
		reloadSpeedMult = legacyBuff.reloadSpeedMult,
	}
end

function RoleService.Init(): ()
	updateLegacyBuff()

	Players.PlayerAdded:Connect(function(player)
		updateLegacyBuff()
		player.CharacterAdded:Connect(function()
			local existingRole = playerRoles[player.UserId]
			if existingRole ~= nil then
				applyRoleAttributes(player, existingRole)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerRoles[player.UserId] = nil
		updateLegacyBuff()

		for _, survivor in Players:GetPlayers() do
			local roleName = playerRoles[survivor.UserId]
			if roleName ~= nil then
				applyRoleAttributes(survivor, roleName)
			end
		end
	end)

	remotes.RoleSelected.OnServerEvent:Connect(function(player: Player, roleName: string)
		RoleService.AssignRole(player, roleName)
	end)
end

return RoleService
