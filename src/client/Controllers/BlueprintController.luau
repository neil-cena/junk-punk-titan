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

	local buildType = currentType
	if buildType == nil then
		return false, nil
	end

	local size = Constants.BUILDING.Sizes[buildType]
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { LocalPlayer.Character, currentGhost }
	local center = snapped + Vector3.new(0, size.Y * 0.5, 0)
	local overlaps = Workspace:GetPartBoundsInBox(CFrame.new(center), size, overlapParams)
	for _, overlap in overlaps do
		if overlap:IsA("BasePart") and not CollectionService:HasTag(overlap, "Blueprint") and overlap.Name ~= "Baseplate" then
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
		currentGhost.CFrame = CFrame.new(pos + Vector3.new(0, y, 0))
	end

	if valid then
		currentGhost.Color = Color3.fromRGB(90, 220, 90)
	else
		currentGhost.Color = Color3.fromRGB(220, 80, 80)
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
	ghost.Material = Enum.Material.ForceField
	ghost.Color = Constants.BUILDING.Colors[buildingType]
	ghost.Parent = Workspace
	currentGhost = ghost

	renderConn = RunService.RenderStepped:Connect(updateGhostVisual)
end

local function placeCurrentBlueprint()
	if mode ~= "Placing" or currentType == nil or placementPosition == nil or not placementValid then
		return
	end

	remotes.PlaceBlueprint:FireServer(currentType, placementPosition)
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

local function onInputBegan(input: InputObject, processed: boolean)
	if processed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 and mode == "Placing" then
		placeCurrentBlueprint()
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton2 and mode == "Placing" then
		clearGhost()
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape and mode == "Placing" then
		clearGhost()
		return
	end

	if input.KeyCode == Enum.KeyCode.One then
		BlueprintController.StartPlacing("Turret")
	elseif input.KeyCode == Enum.KeyCode.Two then
		BlueprintController.StartPlacing("Drill")
	elseif input.KeyCode == Enum.KeyCode.Three then
		BlueprintController.StartPlacing("Wall")
	elseif input.KeyCode == Enum.KeyCode.E then
		mode = "Interacting"
		local nearest = getNearestBlueprint(12)
		if nearest ~= nil then
			local blueprintId = nearest:GetAttribute("BlueprintId")
			if typeof(blueprintId) == "string" then
				BlueprintController.FinishBlueprint(blueprintId :: string)
			end
		end
		mode = "Idle"
	end
end

function BlueprintController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	UserInputService.InputBegan:Connect(onInputBegan)
end

return BlueprintController
