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
local blockedSlots: { [string]: number } = {}
local activeBuildingTasks: { [BasePart]: thread } = {}
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
	if buildingType == "Drill" then
		CollectionService:AddTag(part, "Drill")
	end
	TheftComponent.Attach(part)
	return part
end

local function killRatFromBuilding(targetRat: Model)
	local root = targetRat.PrimaryPart
	local atPosition = if root ~= nil then root.Position else targetRat:GetPivot().Position
	if targetRat.Parent ~= nil then
		targetRat:Destroy()
	end

	local bundle = Instance.new("Part")
	bundle.Name = "ScrapBundle"
	bundle.Size = Vector3.new(1.2, 1.2, 1.2)
	bundle.Shape = Enum.PartType.Ball
	bundle.Material = Enum.Material.Metal
	bundle.Color = Color3.fromRGB(168, 168, 168)
	bundle.Anchored = false
	bundle.CanCollide = true
	bundle.Position = atPosition + Vector3.new(0, 1.5, 0)
	bundle.Parent = Workspace

	EconomyService.AddScrap(Constants.COMBAT.RatKillScrapReward)
	remotes.EnemyKilled:FireAllClients(atPosition)
end

local function playTurretMuzzleFlash(turretPart: BasePart, targetPosition: Vector3)
	local direction = (targetPosition - turretPart.Position)
	if direction.Magnitude < 0.01 then
		direction = Vector3.new(0, 0, -1)
	end

	local flash = Instance.new("Part")
	flash.Name = "TurretMuzzleFlash"
	flash.Anchored = true
	flash.CanCollide = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 186, 92)
	flash.Size = Vector3.new(0.25, 0.25, 0.25)
	flash.CFrame = CFrame.lookAt(turretPart.Position + Vector3.new(0, turretPart.Size.Y * 0.35, 0), targetPosition) * CFrame.new(0, 0, -1.8)
	flash.Parent = Workspace

	task.delay(0.06, function()
		if flash.Parent ~= nil then
			flash:Destroy()
		end
	end)
end

local function ensureDrillFx(drillPart: BasePart): Attachment
	local attachment = drillPart:FindFirstChild("DrillFxAttachment")
	if attachment and attachment:IsA("Attachment") then
		return attachment
	end

	local newAttachment = Instance.new("Attachment")
	newAttachment.Name = "DrillFxAttachment"
	newAttachment.Position = Vector3.new(0, -drillPart.Size.Y * 0.5 + 0.15, 0)
	newAttachment.Parent = drillPart

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DrillSparks"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 188, 103), Color3.fromRGB(173, 119, 78))
	emitter.Lifetime = NumberRange.new(0.12, 0.22)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.Rate = 10
	emitter.SpreadAngle = Vector2.new(30, 30)
	emitter.Size = NumberSequence.new(0.08, 0.02)
	emitter.Parent = newAttachment

	return newAttachment
end

local function getNearestRat(position: Vector3, maxRange: number): Model?
	local nearest: Model? = nil
	local nearestDist = maxRange
	for _, instance in CollectionService:GetTagged("ScrapRatEnemy") do
		if instance:IsA("Model") and instance.Parent ~= nil then
			local root = instance.PrimaryPart
			if root ~= nil then
				local distance = (root.Position - position).Magnitude
				if distance <= nearestDist then
					nearestDist = distance
					nearest = instance
				end
			end
		end
	end
	return nearest
end

local function activateBuildingBehavior(part: BasePart, buildingType: BuildingType)
	local existing = activeBuildingTasks[part]
	if existing ~= nil then
		return
	end

	if buildingType == "Turret" then
		activeBuildingTasks[part] = task.spawn(function()
			while part.Parent ~= nil do
				task.wait(Constants.BUILDING.TurretFireInterval)
				local targetRat = getNearestRat(part.Position, Constants.BUILDING.TurretRange)
				if targetRat ~= nil then
					local root = targetRat.PrimaryPart
					if root ~= nil then
						playTurretMuzzleFlash(part, root.Position)
					end
					killRatFromBuilding(targetRat)
				end
			end
			activeBuildingTasks[part] = nil
		end)
	elseif buildingType == "Drill" then
		activeBuildingTasks[part] = task.spawn(function()
			local drillAttachment = ensureDrillFx(part)
			local emitter = drillAttachment:FindFirstChild("DrillSparks")
			while part.Parent ~= nil do
				task.wait(Constants.BUILDING.DrillTickInterval)
				part.CFrame = part.CFrame * CFrame.Angles(0, math.rad(20), 0)
				if emitter and emitter:IsA("ParticleEmitter") then
					emitter:Emit(18)
				end
			end
			activeBuildingTasks[part] = nil
		end)
	end

	part.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			activeBuildingTasks[part] = nil
		end
	end)
end

local function positionSlotKey(position: Vector3): string
	local snapped = snapToGrid(position)
	return ("%d:%d:%d"):format(math.round(snapped.X), math.round(snapped.Y), math.round(snapped.Z))
end

local function getRemainingSlotCooldown(position: Vector3): number
	local key = positionSlotKey(position)
	local blockedUntil = blockedSlots[key]
	if blockedUntil == nil then
		return 0
	end

	local remaining = blockedUntil - os.clock()
	if remaining <= 0 then
		blockedSlots[key] = nil
		return 0
	end

	return remaining
end

local function placeBlueprint(player: Player, buildingType: BuildingType, requestedPosition: Vector3): ()
	if Constants.BUILDING.Sizes[buildingType] == nil then
		return
	end

	local ok, snappedPos = isPositionValid(player, requestedPosition)
	if not ok or snappedPos == nil then
		return
	end

	if getRemainingSlotCooldown(snappedPos) > 0 then
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

	local builtPart = createFinalBuilding(blueprint.buildingType, blueprint.position)
	activateBuildingBehavior(builtPart, blueprint.buildingType)
	builtCounts[blueprint.buildingType] = countForType + 1
	blueprints[blueprintId] = nil
	remotes.BlueprintFinished:FireAllClients(blueprintId, blueprint.position)

	return response
end

local function getNextBuildCosts(): { [BuildingType]: number }
	return {
		Turret = EconomyService.GetCost(Constants.BASE_COSTS.Turret, builtCounts.Turret),
		Drill = EconomyService.GetCost(Constants.BASE_COSTS.Drill, builtCounts.Drill),
		Wall = EconomyService.GetCost(Constants.BASE_COSTS.Wall, builtCounts.Wall),
	}
end

function BuildingService.RegisterDestroyedSlot(position: Vector3)
	local key = positionSlotKey(position)
	blockedSlots[key] = os.clock() + Constants.BUILDING.RebuildCooldownSeconds
end

function BuildingService.Init(): ()
	remotes.PlaceBlueprint.OnServerEvent:Connect(function(player: Player, buildingType: BuildingType, position: Vector3)
		placeBlueprint(player, buildingType, position)
	end)

	remotes.FinishBlueprint.OnServerInvoke = function(player: Player, blueprintId: string)
		return finishBlueprint(player, blueprintId)
	end
	remotes.RequestBuildCosts.OnServerInvoke = function(_player: Player)
		return getNextBuildCosts()
	end
end

return BuildingService
