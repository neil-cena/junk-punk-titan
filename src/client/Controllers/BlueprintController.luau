--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local VisualManifest = require(Shared:WaitForChild("VisualManifest"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Utils = require(Shared:WaitForChild("Utils"))

type BuildingType = "Turret" | "Drill" | "Wall"
type ControllerMode = "Idle" | "Placing" | "Interacting"

local BlueprintController = {}

local remotes = Remotes.Get()
local mode: ControllerMode = "Idle"
local isInitialized = false
local currentType: BuildingType? = nil
local currentGhost: Part? = nil
local renderConn: RBXScriptConnection? = nil
local placementPosition: Vector3? = nil
local placementValid = false
local currentRotation: number = 0

local holdTarget: BasePart? = nil
local holdStartTime: number = 0
local holdDuration: number = 0
local holdRenderConn: RBXScriptConnection? = nil
local buildProgressCallback: ((number) -> ())? = nil

local function clearGhost()
	if renderConn ~= nil then
		renderConn:Disconnect()
		renderConn = nil
	end

	if currentGhost ~= nil then
		currentGhost:Destroy()
		currentGhost = nil
	end

	placementPosition = nil
	placementValid = false
	currentType = nil
	currentRotation = 0
	mode = "Idle"
end

local function getPlacementResult(): (boolean, Vector3?)
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return false, nil
	end

	local unitRay = camera:ViewportPointToRay(Mouse.X, Mouse.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { LocalPlayer.Character, currentGhost }

	local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, rayParams)
	if result == nil then
		return false, nil
	end

	local snapped = Utils.SnapToGrid(result.Position, Constants.BUILDING.GridSize)
	local character = LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return false, nil
	end

	local maxDistance = Constants.BUILDING.PlacementMaxDistance
	if (root.Position - snapped).Magnitude > maxDistance then
		return false, nil
	end
	local maxBuildRadius = Constants.BUILDING.MaxBuildRadiusFromCenter
	if Vector3.new(snapped.X, 0, snapped.Z).Magnitude > maxBuildRadius then
		return false, nil
	end

	local buildType = currentType
	if buildType == nil then
		return false, nil
	end

	local size = Constants.BUILDING.Sizes[buildType]
	local center = snapped + Vector3.new(0, size.Y * 0.5, 0)
	local rotatedCF = CFrame.new(center) * CFrame.Angles(0, math.rad(currentRotation), 0)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { LocalPlayer.Character, currentGhost }
	local overlaps = Workspace:GetPartBoundsInBox(rotatedCF, size, overlapParams)
	for _, overlap in overlaps do
		if overlap:IsA("BasePart") and CollectionService:HasTag(overlap, "TitanObjective") then
			return false, nil
		end
	end

	return true, snapped
end

local function updateGhostVisual()
	if currentGhost == nil or currentType == nil then
		return
	end

	local valid, pos = getPlacementResult()
	placementValid = valid
	placementPosition = pos

	if pos ~= nil then
		local y = currentGhost.Size.Y * 0.5
		currentGhost.CFrame = CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, math.rad(currentRotation), 0)
	end

	if valid then
		currentGhost.Color = VisualManifest.Tools.GhostValidColor
	else
		currentGhost.Color = VisualManifest.Tools.GhostInvalidColor
	end
end

function BlueprintController.StartPlacing(buildingType: BuildingType)
	clearGhost()

	mode = "Placing"
	currentType = buildingType

	local ghost = Instance.new("Part")
	ghost.Name = "LocalPlacementGhost"
	ghost.Size = Constants.BUILDING.Sizes[buildingType]
	ghost.Transparency = Constants.BUILDING.GhostTransparency
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.Material = VisualManifest.Buildings.GhostMaterial
	ghost.Color = VisualManifest.Buildings.BaseColors[buildingType]
	ghost.Parent = Workspace
	currentGhost = ghost

	renderConn = RunService.RenderStepped:Connect(updateGhostVisual)
end

local function placeCurrentBlueprint()
	if mode ~= "Placing" or currentType == nil or placementPosition == nil or not placementValid then
		return
	end

	remotes.PlaceBlueprint:FireServer(currentType, placementPosition, currentRotation)
	clearGhost()
end

function BlueprintController.FinishBlueprint(blueprintId: string)
	local response = remotes.FinishBlueprint:InvokeServer(blueprintId)
	if not response.success then
		warn(("[Blueprint] Finish failed: %s"):format(response.reason or "Unknown"))
	end
	return response
end

function BlueprintController.IsPlacing(): boolean
	return mode == "Placing"
end

local function getNearestBlueprint(range: number): BasePart?
	local character = LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return nil
	end

	local nearest: BasePart? = nil
	local nearestDistance = range
	for _, instance in CollectionService:GetTagged("Blueprint") do
		if instance:IsA("BasePart") and instance.Parent ~= nil then
			local dist = (instance.Position - root.Position).Magnitude
			if dist <= nearestDistance then
				nearestDistance = dist
				nearest = instance
			end
		end
	end

	return nearest
end

local function getBuildTime(): number
	local base = Constants.BUILDING.BaseBuildTimeSeconds
	local role = LocalPlayer:GetAttribute("Role")
	if role == "Fixer" then
		return base * 0.6
	end
	return base
end

local function cancelHold()
	if holdRenderConn ~= nil then
		holdRenderConn:Disconnect()
		holdRenderConn = nil
	end
	holdTarget = nil
	if buildProgressCallback ~= nil then
		buildProgressCallback(0)
	end
	if mode == "Interacting" then
		mode = "Idle"
	end
end

local function startHold()
	local nearest = getNearestBlueprint(12)
	if nearest == nil then
		return
	end
	mode = "Interacting"
	holdTarget = nearest
	holdStartTime = os.clock()
	holdDuration = getBuildTime()

	holdRenderConn = RunService.RenderStepped:Connect(function()
		if holdTarget == nil or holdTarget.Parent == nil then
			cancelHold()
			return
		end

		local elapsed = os.clock() - holdStartTime
		local progress = math.clamp(elapsed / holdDuration, 0, 1)

		if buildProgressCallback ~= nil then
			buildProgressCallback(progress)
		end

		if progress >= 1 then
			local bpId = holdTarget:GetAttribute("BlueprintId")
			cancelHold()
			if typeof(bpId) == "string" then
				BlueprintController.FinishBlueprint(bpId :: string)
			end
			return
		end

		local character = LocalPlayer.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root ~= nil and root:IsA("BasePart") then
			if (root.Position - holdTarget.Position).Magnitude > 14 then
				cancelHold()
			end
		end
	end)
end

function BlueprintController.ConnectBuildProgress(callback: (number) -> ())
	buildProgressCallback = callback
end

local function onInputBegan(input: InputObject, processed: boolean)
	if mode == "Placing" then
		if input.KeyCode == Enum.KeyCode.R then
			currentRotation = (currentRotation + 90) % 360
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			clearGhost()
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			clearGhost()
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
			placeCurrentBlueprint()
			return
		end
	end

	if processed then
		return
	end

	if input.KeyCode == Enum.KeyCode.One then
		BlueprintController.StartPlacing("Turret")
	elseif input.KeyCode == Enum.KeyCode.Two then
		BlueprintController.StartPlacing("Drill")
	elseif input.KeyCode == Enum.KeyCode.Three then
		BlueprintController.StartPlacing("Wall")
	elseif input.KeyCode == Enum.KeyCode.E then
		if holdTarget == nil then
			startHold()
		end
	elseif input.KeyCode == Enum.KeyCode.X then
		local nearest = getNearestBlueprint(12)
		if nearest ~= nil then
			local bpId = nearest:GetAttribute("BlueprintId")
			if typeof(bpId) == "string" then
				remotes.CancelBlueprint:FireServer(bpId :: string)
			end
		end
	end
end

local function onInputEnded(input: InputObject, _processed: boolean)
	if input.KeyCode == Enum.KeyCode.E and holdTarget ~= nil then
		cancelHold()
	end
end

function BlueprintController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
end

return BlueprintController
