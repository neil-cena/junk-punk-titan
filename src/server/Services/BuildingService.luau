--!strict

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local VisualManifest = require(Shared:WaitForChild("VisualManifest"))
local RemotesModule = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))
local TheftComponent = require(Shared:WaitForChild("TheftComponent"))
local Utils = require(Shared:WaitForChild("Utils"))

local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local RemoteGuard = require(script.Parent.Parent:WaitForChild("RemoteGuard"))

local EnemyServiceRef: any = nil
local function getEnemyService()
	if EnemyServiceRef == nil then
		EnemyServiceRef = require(script.Parent:WaitForChild("EnemyService"))
	end
	return EnemyServiceRef
end

local ObjectiveServiceRef: any = nil
local function getObjectiveService()
	if ObjectiveServiceRef == nil then
		ObjectiveServiceRef = require(script.Parent:WaitForChild("ObjectiveService"))
	end
	return ObjectiveServiceRef
end

type BuildingType = Types.BuildingType
type BlueprintData = Types.BlueprintData
type PurchaseResponse = Types.PurchaseResponse

type InternalBlueprintData = BlueprintData & {
	ghostPart: BasePart,
}

local BLUEPRINT_TAG = "Blueprint"
local DISMANTLABLE_TAG = "DismantlableBuilding"
local PLACEMENT_OVERLAP_XZ_PADDING = 0.1

local BuildingService = {}

local remotes = RemotesModule.Get()
local blueprints: { [string]: InternalBlueprintData } = {}
local blockedSlots: { [string]: number } = {}
local activeBuildingTasks: { [BasePart]: thread } = {}
local builtCounts: { [BuildingType]: number } = {
	Turret = 0,
	Drill = 0,
	Wall = 0,
}
local buildingsLostCount = 0
local finishedBuildings: { [BasePart]: true } = {}
local REQUEST_UPGRADE_MAX_DISTANCE = 14

local catchupUntil = 0
local lastCatchupTrigger = 0

local upgradeBuilding: (player: Player, part: BasePart) -> ()

local function getMaxUnlockedLevel(): number
	local ok, stage = pcall(function()
		return getObjectiveService().GetCurrentStage()
	end)
	if not ok or typeof(stage) ~= "number" then
		return 1
	end
	return math.clamp(stage + 1, 1, Constants.BUILDING.MaxLevel)
end

local function getUpgradeStats(buildingType: string, level: number): { [string]: number }?
	local tiers = Constants.BUILDING_UPGRADES[buildingType]
	if tiers == nil then
		return nil
	end
	return tiers[level]
end

local function getCumulativeUpgradeCost(buildingType: string, fromLevel: number, toLevel: number, buildCostMult: number): number
	local total = 0
	for lv = fromLevel + 1, toLevel do
		local stats = getUpgradeStats(buildingType, lv)
		if stats ~= nil and typeof(stats.cost) == "number" and stats.cost > 0 then
			total += math.max(1, math.floor((stats.cost * buildCostMult) + 0.5))
		end
	end
	return total
end

local function getPlayerBuildCostMult(player: Player): number
	local multAttr = player:GetAttribute("BuildCostMult")
	if typeof(multAttr) == "number" then
		return math.max(0.1, multAttr :: number)
	end
	return 1
end

function BuildingService.TriggerCatchupBoost(_reason: string?)
	local now = os.clock()
	local cooldown = Constants.BUILDING.CatchupCooldownSeconds or 18
	if lastCatchupTrigger > 0 and (now - lastCatchupTrigger) < cooldown then
		return
	end
	lastCatchupTrigger = now
	local boostSec = Constants.BUILDING.CatchupBoostSeconds or 28
	catchupUntil = now + boostSec
	syncCatchupAttribute()
	BuildingService.RefreshAllUpgradePrompts()
end

local function syncCatchupAttribute()
	local folder = remotes.Folder
	if folder == nil then
		return
	end
	if catchupUntil > os.clock() then
		folder:SetAttribute("CatchupUntil", catchupUntil)
	else
		folder:SetAttribute("CatchupUntil", nil)
	end
end

local function getCatchupUpgradeMultiplier(): number
	if catchupUntil <= os.clock() then
		return 1
	end
	local bonus = Constants.BUILDING.CatchupUpgradeSpeedBonus or 0.25
	return math.max(0.1, 1 - bonus)
end

local function getUpgradeHoldDuration(): number
	local baseHold = 1.0
	local stage = 0
	local ok, s = pcall(function()
		return getObjectiveService().GetCurrentStage()
	end)
	if ok and typeof(s) == "number" then
		stage = math.max(0, math.floor(s :: number))
	end
	local bonusPerStage = Constants.TITAN.UpgradeSpeedBonusPerStage or 0.1
	local titanMult = math.max(Constants.TITAN.MinUpgradeHoldDuration or 0.35, 1 - (stage * bonusPerStage))
	local catchupMult = getCatchupUpgradeMultiplier()
	local speedMult = Constants.BUILDING.UpgradeSpeedMultiplier or 1
	local result = baseHold * titanMult * catchupMult * speedMult
	return math.max(Constants.TITAN.MinUpgradeHoldDuration or 0.35, result)
end

local function refreshUpgradePrompt(part: BasePart)
	local buildingType = part:GetAttribute("BuildingType")
	local level = part:GetAttribute("BuildingLevel") or 1
	if typeof(buildingType) ~= "string" then
		return
	end

	local maxLevel = getMaxUnlockedLevel()
	local nextLevel = level + 1
	local prompt = part:FindFirstChild("UpgradePrompt") :: ProximityPrompt?

	if nextLevel > maxLevel or nextLevel > Constants.BUILDING.MaxLevel then
		if prompt ~= nil then
			prompt.Enabled = false
		end
		return
	end

	local stats = getUpgradeStats(buildingType, nextLevel)
	if stats == nil then
		return
	end

	if prompt == nil then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "UpgradePrompt"
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = part

		prompt.Triggered:Connect(function(player: Player)
			upgradeBuilding(player, part)
		end)
	end

	prompt.HoldDuration = getUpgradeHoldDuration()
	prompt.ObjectText = ("%s Lv.%d"):format(buildingType, level)
	prompt.ActionText = ("Upgrade to Lv.%d ($%d)"):format(nextLevel, stats.cost)
	prompt.Enabled = true
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

	local snapped = Utils.SnapToGrid(result.Position, Constants.BUILDING.GridSize)
	local maxDist = Constants.BUILDING.PlacementMaxDistance
	if (root.Position - snapped).Magnitude > maxDist then
		return false, nil
	end
	local maxBuildRadius = Constants.BUILDING.MaxBuildRadiusFromCenter
	if Vector3.new(snapped.X, 0, snapped.Z).Magnitude > maxBuildRadius then
		return false, nil
	end

	return true, snapped
end

local function isOverlapping(position: Vector3, buildingType: BuildingType, rotation: number): boolean
	local size = Constants.BUILDING.Sizes[buildingType]
	local overlapSize = Vector3.new(
		math.max(0.05, size.X - PLACEMENT_OVERLAP_XZ_PADDING),
		size.Y,
		math.max(0.05, size.Z - PLACEMENT_OVERLAP_XZ_PADDING)
	)
	local center = position + Vector3.new(0, size.Y * 0.5, 0)
	local rotatedCF = CFrame.new(center) * CFrame.Angles(0, math.rad(rotation), 0)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {}

	local overlaps = Workspace:GetPartBoundsInBox(rotatedCF, overlapSize, overlapParams)
	for _, overlap in overlaps do
		if overlap:IsA("BasePart") then
			if CollectionService:HasTag(overlap, "TitanObjective") then
				return true
			end
			-- Disallow stacking on blueprints or buildings (only block if overlap part itself is tagged, not child parts)
			if CollectionService:HasTag(overlap, BLUEPRINT_TAG) or CollectionService:HasTag(overlap, DISMANTLABLE_TAG) then
				return true
			end
		end
	end

	return false
end

local function createBlueprintGhost(buildingType: BuildingType, position: Vector3, rotation: number): BasePart
	local ghost = Instance.new("Part")
	ghost.Name = string.format("%sBlueprintGhost", buildingType)
	ghost.Size = Constants.BUILDING.Sizes[buildingType]
	ghost.Color = VisualManifest.Buildings.BaseColors[buildingType]
	ghost.Material = VisualManifest.Buildings.GhostMaterial
	ghost.Transparency = Constants.BUILDING.GhostTransparency
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CFrame = CFrame.new(position + Vector3.new(0, ghost.Size.Y * 0.5, 0)) * CFrame.Angles(0, math.rad(rotation), 0)

	local labelGui = Instance.new("BillboardGui")
	labelGui.Name = "BlueprintLabel"
	labelGui.Size = UDim2.fromOffset(80, 16)
	labelGui.StudsOffset = Vector3.new(0, ghost.Size.Y * 0.7 + 1.2, 0)
	labelGui.AlwaysOnTop = true
	labelGui.MaxDistance = 60
	labelGui.Parent = ghost

	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextStrokeTransparency = 0.45
	label.TextColor3 = Color3.fromRGB(240, 225, 160)
	label.Text = string.upper(buildingType)
	label.Parent = labelGui

	ghost.Parent = Workspace
	CollectionService:AddTag(ghost, BLUEPRINT_TAG)
	return ghost
end

local function createFinalBuilding(buildingType: BuildingType, position: Vector3, rotation: number, level: number?): BasePart
	local targetLevel = if typeof(level) == "number" and level >= 1 and level <= Constants.BUILDING.MaxLevel then level else 1
	local stats = getUpgradeStats(buildingType, targetLevel)
	local hp = if stats ~= nil and typeof(stats.hp) == "number" then stats.hp else Constants.BUILDING.DefaultHP

	local part = Instance.new("Part")
	part.Name = string.format("%sBuilding", buildingType)
	part.Size = Constants.BUILDING.Sizes[buildingType]
	part.Color = VisualManifest.Buildings.BaseColors[buildingType]
	part.Material = VisualManifest.Buildings.MainMaterial
	part.Transparency = 0
	part.Anchored = true
	part.CanCollide = true
	part.CFrame = CFrame.new(position + Vector3.new(0, part.Size.Y * 0.5, 0)) * CFrame.Angles(0, math.rad(rotation), 0)
	part:SetAttribute("BuildingType", buildingType)
	part:SetAttribute("BuildingRotation", rotation)
	part:SetAttribute("BuildingLevel", targetLevel)
	part:SetAttribute("BuildingHP", hp)
	part.Parent = Workspace
	finishedBuildings[part] = true
	CollectionService:AddTag(part, DISMANTLABLE_TAG)
	if buildingType == "Drill" then
		CollectionService:AddTag(part, "Drill")
	end
	TheftComponent.Attach(part)
	if buildingType == "Turret" then
		local basePlate = Instance.new("Part")
		basePlate.Name = "TurretPlate"
		basePlate.Size = Vector3.new(3.2, 0.6, 3.2)
		basePlate.Anchored = true
		basePlate.CanCollide = false
		basePlate.Material = VisualManifest.Buildings.TurretPlate.material
		basePlate.Color = VisualManifest.Buildings.TurretPlate.color
		basePlate.CFrame = part.CFrame * CFrame.new(0, part.Size.Y * 0.35, 0)
		basePlate.Parent = part

		local barrel = Instance.new("Part")
		barrel.Name = "TurretBarrel"
		barrel.Size = Vector3.new(0.7, 0.7, 3.4)
		barrel.Anchored = true
		barrel.CanCollide = false
		barrel.Material = VisualManifest.Buildings.TurretBarrel.material
		barrel.Color = VisualManifest.Buildings.TurretBarrel.color
		barrel.CFrame = part.CFrame * CFrame.new(0, part.Size.Y * 0.1, -1.4)
		barrel.Parent = part
	elseif buildingType == "Drill" then
		local tripodA = Instance.new("Part")
		tripodA.Name = "DrillLegA"
		tripodA.Size = Vector3.new(0.45, 4, 0.45)
		tripodA.Anchored = true
		tripodA.CanCollide = false
		tripodA.Material = VisualManifest.Buildings.DrillLeg.material
		tripodA.Color = VisualManifest.Buildings.DrillLeg.color
		tripodA.CFrame = part.CFrame * CFrame.new(1.4, -0.7, 1.2)
		tripodA.Parent = part

		local tripodB = tripodA:Clone()
		tripodB.Name = "DrillLegB"
		tripodB.CFrame = part.CFrame * CFrame.new(-1.4, -0.7, 1.2)
		tripodB.Parent = part

		local bit = Instance.new("Part")
		bit.Name = "DrillBit"
		bit.Shape = Enum.PartType.Cylinder
		bit.Size = Vector3.new(3.2, 0.8, 0.8)
		bit.Anchored = true
		bit.CanCollide = false
		bit.Material = VisualManifest.Buildings.DrillBit.material
		bit.Color = VisualManifest.Buildings.DrillBit.color
		bit.CFrame = part.CFrame * CFrame.new(0, -part.Size.Y * 0.42, 0) * CFrame.Angles(0, 0, math.rad(90))
		bit.Parent = part
	elseif buildingType == "Wall" then
		local panel = Instance.new("Part")
		panel.Name = "WallPlate"
		panel.Size = Vector3.new(part.Size.X * 0.9, part.Size.Y * 0.75, 0.35)
		panel.Anchored = true
		panel.CanCollide = false
		panel.Material = VisualManifest.Buildings.WallPlate.material
		panel.Color = VisualManifest.Buildings.WallPlate.color
		panel.CFrame = part.CFrame * CFrame.new(0, 0.5, 0)
		panel.Parent = part

		local lip = Instance.new("Part")
		lip.Name = "WallTopLip"
		lip.Size = Vector3.new(part.Size.X * 0.95, 0.35, 0.6)
		lip.Anchored = true
		lip.CanCollide = false
		lip.Material = VisualManifest.Buildings.WallTopLip.material
		lip.Color = VisualManifest.Buildings.WallTopLip.color
		lip.CFrame = part.CFrame * CFrame.new(0, part.Size.Y * 0.5 - 0.4, 0)
		lip.Parent = part
	end

	task.defer(function()
		refreshUpgradePrompt(part)
	end)

	part.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			finishedBuildings[part] = nil
		end
	end)

	return part
end

local function signalTurretFire(turretPart: BasePart, targetPosition: Vector3)
	turretPart:SetAttribute("LastFireTarget", targetPosition)
end

local function getNearestRat(position: Vector3, maxRange: number): Model?
	local ok, result = pcall(function()
		return getEnemyService().GetNearestRatInRadius(position, maxRange)
	end)
	if ok and result ~= nil then
		return result
	end

	local nearest: Model? = nil
	local nearestDist = maxRange
	for _, instance in CollectionService:GetTagged("ScrapRatEnemy") do
		if instance:IsA("Model") and instance.Parent ~= nil then
			local humanoid = instance:FindFirstChildOfClass("Humanoid")
			if humanoid ~= nil and humanoid.Health > 0 then
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
	end
	return nearest
end

local function getTurretStatsForPart(part: BasePart): (number, number, number)
	local level = part:GetAttribute("BuildingLevel") or 1
	local stats = getUpgradeStats("Turret", level)
	if stats ~= nil then
		return stats.damage, stats.range, stats.fireInterval
	end
	return Constants.BUILDING.TurretDamage, Constants.BUILDING.TurretRange, Constants.BUILDING.TurretFireInterval
end

local function activateBuildingBehavior(part: BasePart, buildingType: BuildingType)
	local existing = activeBuildingTasks[part]
	if existing ~= nil then
		task.cancel(existing)
		activeBuildingTasks[part] = nil
	end

	if buildingType == "Turret" then
		activeBuildingTasks[part] = task.spawn(function()
			while part.Parent ~= nil do
				local damage, range, fireInterval = getTurretStatsForPart(part)
				task.wait(fireInterval)
				local targetRat = getNearestRat(part.Position, range)
				if targetRat ~= nil then
					local humanoid = targetRat:FindFirstChildOfClass("Humanoid")
					local root = targetRat.PrimaryPart
					if humanoid ~= nil and root ~= nil and humanoid.Health > 0 then
						signalTurretFire(part, root.Position)
						humanoid:TakeDamage(damage)
						local aggroVal = targetRat:FindFirstChild("AggroTarget")
						if aggroVal == nil then
							aggroVal = Instance.new("ObjectValue")
							aggroVal.Name = "AggroTarget"
							aggroVal.Parent = targetRat
						end
						if aggroVal:IsA("ObjectValue") then
							(aggroVal :: ObjectValue).Value = part
						end
					end
				end
			end
			activeBuildingTasks[part] = nil
		end)
	elseif buildingType == "Drill" then
		activeBuildingTasks[part] = task.spawn(function()
			while part.Parent ~= nil do
				task.wait(Constants.BUILDING.DrillTickInterval)
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

upgradeBuilding = function(player: Player, part: BasePart)
	if part.Parent == nil then
		return
	end

	local buildingType = part:GetAttribute("BuildingType")
	local currentLevel = part:GetAttribute("BuildingLevel") or 1
	if typeof(buildingType) ~= "string" then
		return
	end

	local nextLevel = currentLevel + 1
	local maxLevel = getMaxUnlockedLevel()
	if nextLevel > maxLevel or nextLevel > Constants.BUILDING.MaxLevel then
		return
	end

	local stats = getUpgradeStats(buildingType, nextLevel)
	if stats == nil then
		return
	end

	local buildCostMult = getPlayerBuildCostMult(player)
	local adjustedUpgradeCost = math.max(1, math.floor((stats.cost * buildCostMult) + 0.5))
	if not EconomyService.DeductScrap(adjustedUpgradeCost) then
		return
	end

	part:SetAttribute("BuildingLevel", nextLevel)
	part:SetAttribute("BuildingHP", stats.hp)

	if buildingType == "Turret" then
		activateBuildingBehavior(part, "Turret")
	end

	refreshUpgradePrompt(part)
	remotes.BuildingUpgraded:FireAllClients(part, nextLevel, buildingType)
end

local function positionSlotKey(position: Vector3): string
	local snapped = Utils.SnapToGrid(position, Constants.BUILDING.GridSize)
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

local VALID_ROTATIONS = { [0] = true, [90] = true, [180] = true, [270] = true }

local function placeBlueprint(player: Player, buildingType: BuildingType, requestedPosition: Vector3, requestedRotation: number?): ()
	if Constants.BUILDING.Sizes[buildingType] == nil then
		return
	end

	if typeof(requestedPosition) ~= "Vector3" then
		return
	end

	local rotation = 0
	if typeof(requestedRotation) == "number" then
		rotation = math.floor(requestedRotation :: number) % 360
		if not VALID_ROTATIONS[rotation] then
			rotation = 0
		end
	end

	local ok, snappedPos = isPositionValid(player, requestedPosition)
	if not ok or snappedPos == nil then
		return
	end

	if getRemainingSlotCooldown(snappedPos) > 0 then
		return
	end

	if isOverlapping(snappedPos, buildingType, rotation) then
		return
	end

	local blueprintId = HttpService:GenerateGUID(false)
	local ghost = createBlueprintGhost(buildingType, snappedPos, rotation)
	ghost:SetAttribute("BlueprintId", blueprintId)
	ghost:SetAttribute("BlueprintBuildingType", buildingType)

	blueprints[blueprintId] = {
		id = blueprintId,
		buildingType = buildingType,
		position = snappedPos,
		rotation = rotation,
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

local function finishBlueprint(player: Player, blueprintId: string): PurchaseResponse
	if typeof(blueprintId) ~= "string" then
		return failResponse("Invalid blueprint ID")
	end

	local blueprint = blueprints[blueprintId]
	if blueprint == nil then
		return failResponse("Blueprint not found")
	end

	if blueprint.isFinished then
		return failResponse("Blueprint already finished")
	end

	local countForType = builtCounts[blueprint.buildingType]
	local buildCostMult = getPlayerBuildCostMult(player)
	local targetLevel = getMaxUnlockedLevel()

	local rawBaseCost = Constants.BASE_COSTS[blueprint.buildingType]
	if typeof(rawBaseCost) ~= "number" then
		return failResponse("Unknown building type")
	end
	local baseCost = EconomyService.GetCost(rawBaseCost :: number, countForType)
	baseCost = math.max(1, math.floor((baseCost * buildCostMult) + 0.5))
	local upgradeSurcharge = getCumulativeUpgradeCost(blueprint.buildingType, 1, targetLevel, buildCostMult)
	local totalCost = baseCost + upgradeSurcharge

	if EconomyService.GetScrap() < totalCost then
		return {
			success = false,
			cost = totalCost,
			remainingScrap = EconomyService.GetScrap(),
			reason = "Not enough scrap",
		}
	end

	if not EconomyService.DeductScrap(totalCost) then
		return failResponse("Not enough scrap")
	end

	blueprint.isFinished = true

	if blueprint.ghostPart.Parent ~= nil then
		blueprint.ghostPart:Destroy()
	end

	local builtPart = createFinalBuilding(blueprint.buildingType, blueprint.position, blueprint.rotation or 0, targetLevel)
	activateBuildingBehavior(builtPart, blueprint.buildingType)
	builtCounts[blueprint.buildingType] = countForType + 1
	blueprints[blueprintId] = nil
	remotes.BlueprintFinished:FireAllClients(blueprintId, blueprint.position)

	return {
		success = true,
		cost = totalCost,
		remainingScrap = EconomyService.GetScrap(),
	}
end

local function getNextBuildCosts(player: Player?): { [BuildingType]: number }
	local buildCostMult = 1
	if player ~= nil then
		buildCostMult = getPlayerBuildCostMult(player)
	end

	local targetLevel = getMaxUnlockedLevel()

	local function totalCost(buildingType: BuildingType): number
		local rawBase = Constants.BASE_COSTS[buildingType]
		if typeof(rawBase) ~= "number" then
			return 0
		end
		local base = EconomyService.GetCost(rawBase :: number, builtCounts[buildingType])
		base = math.max(1, math.floor((base * buildCostMult) + 0.5))
		local surcharge = getCumulativeUpgradeCost(buildingType, 1, targetLevel, buildCostMult)
		return base + surcharge
	end

	return {
		Turret = totalCost("Turret"),
		Drill = totalCost("Drill"),
		Wall = totalCost("Wall"),
	}
end

local function cleanupPlayerBlueprints(player: Player)
	for id, data in blueprints do
		if data.ownerUserId == player.UserId and not data.isFinished then
			if data.ghostPart.Parent ~= nil then
				data.ghostPart:Destroy()
			end
			blueprints[id] = nil
		end
	end
end

function BuildingService.RegisterDestroyedSlot(position: Vector3, buildingType: string?)
	local key = positionSlotKey(position)
	blockedSlots[key] = os.clock() + Constants.BUILDING.RebuildCooldownSeconds
	buildingsLostCount += 1

	if buildingType ~= nil and builtCounts[buildingType] ~= nil then
		builtCounts[buildingType] = math.max(0, builtCounts[buildingType] - 1)
	end
end

local function snapRotationToQuarterTurn(rotation: number): number
	local snapped = (math.floor((rotation / 90) + 0.5) * 90) % 360
	if snapped < 0 then
		snapped += 360
	end
	if not VALID_ROTATIONS[snapped] then
		return 0
	end
	return snapped
end

function BuildingService.PlaceRuinGhost(position: Vector3, buildingType: string?, rotation: number?)
	if typeof(position) ~= "Vector3" or typeof(buildingType) ~= "string" then
		return
	end
	if Constants.BUILDING.Sizes[buildingType] == nil then
		return
	end

	local typedBuildingType = buildingType :: BuildingType
	local snappedPos = Utils.SnapToGrid(position, Constants.BUILDING.GridSize)
	local snappedRotation = 0
	if typeof(rotation) == "number" then
		snappedRotation = snapRotationToQuarterTurn(rotation :: number)
	end

	local slotKey = positionSlotKey(snappedPos)
	blockedSlots[slotKey] = nil

	for id, data in blueprints do
		if not data.isFinished and positionSlotKey(data.position) == slotKey then
			if data.ghostPart.Parent ~= nil then
				data.ghostPart:Destroy()
			end
			blueprints[id] = nil
		end
	end

	local blueprintId = HttpService:GenerateGUID(false)
	local ghost = createBlueprintGhost(typedBuildingType, snappedPos, snappedRotation)
	ghost.Transparency = math.clamp(Constants.BUILDING.GhostTransparency + 0.12, 0, 0.95)
	ghost:SetAttribute("BlueprintId", blueprintId)
	ghost:SetAttribute("BlueprintBuildingType", typedBuildingType)
	ghost:SetAttribute("IsRuin", true)

	blueprints[blueprintId] = {
		id = blueprintId,
		buildingType = typedBuildingType,
		position = snappedPos,
		rotation = snappedRotation,
		ownerUserId = 0,
		isFinished = false,
		ghostPart = ghost,
	}

	remotes.BlueprintPlaced:FireAllClients(blueprintId, typedBuildingType, snappedPos)
end

function BuildingService.GetBuildingsLost(): number
	return buildingsLostCount
end

function BuildingService.RefreshAllUpgradePrompts()
	for part in finishedBuildings do
		if part.Parent ~= nil then
			refreshUpgradePrompt(part)
		end
	end
end

local function cancelBlueprint(player: Player, blueprintId: string)
	if typeof(blueprintId) ~= "string" then
		return
	end
	local blueprint = blueprints[blueprintId]
	if blueprint == nil then
		return
	end
	if blueprint.ownerUserId ~= player.UserId then
		return
	end
	if blueprint.isFinished then
		return
	end
	if blueprint.ghostPart.Parent ~= nil then
		blueprint.ghostPart:Destroy()
	end
	blueprints[blueprintId] = nil
end

function BuildingService.Init(): ()
	RemoteGuard.Register("PlaceBlueprint", 5, 1)
	RemoteGuard.Register("FinishBlueprint", 3, 1)
	RemoteGuard.Register("CancelBlueprint", 5, 1)
	RemoteGuard.Register("RequestUpgrade", 5, 1)

	RunService.Heartbeat:Connect(function()
		if catchupUntil > 0 and catchupUntil <= os.clock() then
			catchupUntil = 0
			syncCatchupAttribute()
			BuildingService.RefreshAllUpgradePrompts()
		end
	end)

	remotes.PlaceBlueprint.OnServerEvent:Connect(function(player: Player, buildingType: BuildingType, position: Vector3, rotation: number?)
		if not RemoteGuard.Check("PlaceBlueprint", player) then
			return
		end
		placeBlueprint(player, buildingType, position, rotation)
	end)

	remotes.FinishBlueprint.OnServerInvoke = function(player: Player, blueprintId: string)
		if not RemoteGuard.Check("FinishBlueprint", player) then
			return failResponse("Too many requests")
		end
		return finishBlueprint(player, blueprintId)
	end
	remotes.RequestBuildCosts.OnServerInvoke = function(player: Player)
		return getNextBuildCosts(player)
	end

	remotes.CancelBlueprint.OnServerEvent:Connect(function(player: Player, blueprintId: string)
		if not RemoteGuard.Check("CancelBlueprint", player) then
			return
		end
		cancelBlueprint(player, blueprintId)
	end)

	remotes.RequestUpgrade.OnServerEvent:Connect(function(player: Player, part: Instance)
		if not RemoteGuard.Check("RequestUpgrade", player) then
			return
		end
		if not part:IsA("BasePart") or part.Parent == nil then
			return
		end
		if finishedBuildings[part] ~= true then
			return
		end

		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root == nil or not root:IsA("BasePart") then
			return
		end
		if (root.Position - part.Position).Magnitude > REQUEST_UPGRADE_MAX_DISTANCE then
			return
		end

		upgradeBuilding(player, part)
	end)

	Players.PlayerRemoving:Connect(cleanupPlayerBlueprints)
end

return BuildingService
