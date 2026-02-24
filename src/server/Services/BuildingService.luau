--!strict

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local RemotesModule = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local TheftComponent = require(Shared:WaitForChild("TheftComponent"))

local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

type BuildingType = Types.BuildingType
type BlueprintData = Types.BlueprintData
type PurchaseResponse = Types.PurchaseResponse

type InternalBlueprintData = BlueprintData & {
	ghostPart: BasePart,
}

local BLUEPRINT_TAG = "Blueprint"
local DISMANTLABLE_TAG = "DismantlableBuilding"

local BuildingService = {}
BuildingService.__index = BuildingService

local remotes = RemotesModule.Get()
local blueprints: { [string]: InternalBlueprintData } = {}
local builtCounts: { [BuildingType]: number } = {
	Turret = 0,
	Drill = 0,
	Wall = 0,
}

local function snapToGrid(position: Vector3): Vector3
	local grid = Constants.BUILDING.GridSize
	return Vector3.new(
		math.round(position.X / grid) * grid,
		position.Y,
		math.round(position.Z / grid) * grid
	)
end

local function isPositionValid(player: Player, requestedPosition: Vector3): (boolean, Vector3?)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return false, nil
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local rayOrigin = requestedPosition + Vector3.new(0, 30, 0)
	local rayDirection = Vector3.new(0, -120, 0)
	local result = Workspace:Raycast(rayOrigin, rayDirection, rayParams)
	if result == nil then
		return false, nil
	end

	local snapped = snapToGrid(result.Position)
	local maxDist = Constants.BUILDING.PlacementMaxDistance
	if (root.Position - snapped).Magnitude > maxDist then
		return false, nil
	end

	return true, snapped
end

local function createBlueprintGhost(buildingType: BuildingType, position: Vector3): BasePart
	local ghost = Instance.new("Part")
	ghost.Name = string.format("%sBlueprintGhost", buildingType)
	ghost.Size = Constants.BUILDING.Sizes[buildingType]
	ghost.Color = Constants.BUILDING.Colors[buildingType]
	ghost.Material = Enum.Material.ForceField
	ghost.Transparency = Constants.BUILDING.GhostTransparency
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CFrame = CFrame.new(position + Vector3.new(0, ghost.Size.Y * 0.5, 0))
	ghost.Parent = Workspace
	CollectionService:AddTag(ghost, BLUEPRINT_TAG)
	return ghost
end

local function createFinalBuilding(buildingType: BuildingType, position: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = string.format("%sBuilding", buildingType)
	part.Size = Constants.BUILDING.Sizes[buildingType]
	part.Color = Constants.BUILDING.Colors[buildingType]
	part.Material = Enum.Material.Metal
	part.Transparency = 0
	part.Anchored = true
	part.CanCollide = true
	part.CFrame = CFrame.new(position + Vector3.new(0, part.Size.Y * 0.5, 0))
	part.Parent = Workspace
	CollectionService:AddTag(part, DISMANTLABLE_TAG)
	TheftComponent.Attach(part)
	return part
end

local function placeBlueprint(player: Player, buildingType: BuildingType, requestedPosition: Vector3): ()
	if Constants.BUILDING.Sizes[buildingType] == nil then
		return
	end

	local ok, snappedPos = isPositionValid(player, requestedPosition)
	if not ok or snappedPos == nil then
		return
	end

	local blueprintId = HttpService:GenerateGUID(false)
	local ghost = createBlueprintGhost(buildingType, snappedPos)
	ghost:SetAttribute("BlueprintId", blueprintId)
	ghost:SetAttribute("BlueprintBuildingType", buildingType)

	blueprints[blueprintId] = {
		id = blueprintId,
		buildingType = buildingType,
		position = snappedPos,
		ownerUserId = player.UserId,
		isFinished = false,
		ghostPart = ghost,
	}

	remotes.BlueprintPlaced:FireAllClients(blueprintId, buildingType, snappedPos)
end

local function failResponse(reason: string): PurchaseResponse
	return {
		success = false,
		cost = 0,
		remainingScrap = EconomyService.GetScrap(),
		reason = reason,
	}
end

local function finishBlueprint(_player: Player, blueprintId: string): PurchaseResponse
	local blueprint = blueprints[blueprintId]
	if blueprint == nil then
		return failResponse("Blueprint not found")
	end

	if blueprint.isFinished then
		return failResponse("Blueprint already finished")
	end

	local countForType = builtCounts[blueprint.buildingType]
	local response = EconomyService.TryPurchase(blueprint.buildingType, countForType)
	if not response.success then
		return response
	end

	blueprint.isFinished = true

	if blueprint.ghostPart.Parent ~= nil then
		blueprint.ghostPart:Destroy()
	end

	createFinalBuilding(blueprint.buildingType, blueprint.position)
	builtCounts[blueprint.buildingType] = countForType + 1
	blueprints[blueprintId] = nil
	remotes.BlueprintFinished:FireAllClients(blueprintId, blueprint.position)

	return response
end

function BuildingService.Init(): ()
	remotes.PlaceBlueprint.OnServerEvent:Connect(function(player: Player, buildingType: BuildingType, position: Vector3)
		placeBlueprint(player, buildingType, position)
	end)

	remotes.FinishBlueprint.OnServerInvoke = function(player: Player, blueprintId: string)
		return finishBlueprint(player, blueprintId)
	end
end

return BuildingService
