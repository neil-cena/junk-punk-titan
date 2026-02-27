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
local AssetPackResolver = require(Shared:WaitForChild("assetpacks"):WaitForChild("AssetPackResolver"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Utils = require(Shared:WaitForChild("Utils"))
local Platform = require(Shared:WaitForChild("Platform"))
local Animations = AssetPackResolver.GetAnimations()

type BuildingType = "Turret" | "Drill" | "Wall"
type ControllerMode = "Idle" | "Placing" | "Interacting"

local BlueprintController = {}

local remotes = Remotes.Get()
local mode: ControllerMode = "Idle"
local isInitialized = false
local currentType: BuildingType? = nil
local currentGhost: Part? = nil
local currentGroundMarker: Part? = nil
local renderConn: RBXScriptConnection? = nil
local placementPosition: Vector3? = nil
local placementValid = false
local currentRotation: number = 0
local useGridSnap = true

local holdTarget: BasePart? = nil
local holdStartTime: number = 0
local holdDuration: number = 0
local holdRenderConn: RBXScriptConnection? = nil
local buildProgressCallbacks: { (number) -> () } = {}
local activeHighlight: Highlight? = nil
local activeSelectionBox: SelectionBox? = nil
local highlightedBlueprint: BasePart? = nil
local highlightRenderConn: RBXScriptConnection? = nil
local BLUEPRINT_INTERACT_RANGE = 16
local HIGHLIGHT_PULSE_SPEED = 5
local HIGHLIGHT_FILL_BASE = 0.35
local HIGHLIGHT_FILL_AMPLITUDE = 0.12
local HIGHLIGHT_OUTLINE_BASE = 0
local HIGHLIGHT_OUTLINE_AMPLITUDE = 0.2
local SELECTION_LINE_BASE = 0.04
local SELECTION_LINE_AMPLITUDE = 0.03
local PLACEMENT_OVERLAP_XZ_PADDING = 0.1

local BUILD_ANIM_ID = Animations.Build
local cachedBuildTrack: AnimationTrack? = nil
local cachedBuildHumanoid: Humanoid? = nil
local slowedHumanoid: Humanoid? = nil
local originalWalkSpeed: number? = nil

local function getBuildTrack(humanoid: Humanoid): AnimationTrack?
	if cachedBuildTrack ~= nil and cachedBuildHumanoid == humanoid then
		return cachedBuildTrack
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = BUILD_ANIM_ID
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if not ok or track == nil then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	cachedBuildTrack = track
	cachedBuildHumanoid = humanoid
	return track
end

local function stopBuildAnim()
	if cachedBuildTrack ~= nil and cachedBuildTrack.IsPlaying then
		cachedBuildTrack:Stop(0.15)
	end
end

local function emitBuildProgress(progress: number)
	for _, callback in buildProgressCallbacks do
		callback(progress)
	end
end

local function setHighlightedBlueprint(target: BasePart?)
	if activeHighlight == nil then
		local highlight = Instance.new("Highlight")
		highlight.Name = "NearestBlueprintHighlight"
		highlight.FillColor = Color3.fromRGB(255, 205, 80)
		highlight.FillTransparency = HIGHLIGHT_FILL_BASE
		highlight.OutlineColor = Color3.fromRGB(255, 230, 120)
		highlight.OutlineTransparency = HIGHLIGHT_OUTLINE_BASE
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Enabled = false
		highlight.Parent = Workspace
		activeHighlight = highlight
	end
	if activeSelectionBox == nil then
		local selection = Instance.new("SelectionBox")
		selection.Name = "NearestBlueprintSelection"
		selection.Color3 = Color3.fromRGB(255, 225, 120)
		selection.SurfaceTransparency = 1
		selection.LineThickness = SELECTION_LINE_BASE
		selection.Visible = false
		selection.Parent = Workspace
		activeSelectionBox = selection
	end

	highlightedBlueprint = target
	if activeHighlight == nil or activeSelectionBox == nil then
		return
	end

	if target ~= nil and target.Parent ~= nil then
		activeHighlight.Adornee = target
		activeHighlight.Enabled = true
		activeSelectionBox.Adornee = target
		activeSelectionBox.Visible = true
	else
		activeHighlight.Adornee = nil
		activeHighlight.Enabled = false
		activeSelectionBox.Adornee = nil
		activeSelectionBox.Visible = false
	end
end

local function clearGhost()
	if renderConn ~= nil then
		renderConn:Disconnect()
		renderConn = nil
	end

	if currentGhost ~= nil then
		currentGhost:Destroy()
		currentGhost = nil
	end
	if currentGroundMarker ~= nil then
		currentGroundMarker:Destroy()
		currentGroundMarker = nil
	end

	placementPosition = nil
	placementValid = false
	currentType = nil
	-- currentRotation preserved for next placement session
	mode = "Idle"

	if slowedHumanoid ~= nil and slowedHumanoid.Parent ~= nil and originalWalkSpeed ~= nil then
		slowedHumanoid.WalkSpeed = originalWalkSpeed
	end
	slowedHumanoid = nil
	originalWalkSpeed = nil
end

local function getPlacementResult(): (boolean, Vector3?)
	local character = LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return false, nil
	end

	local placed: Vector3
	if Platform.IsMobile then
		local look = root.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		local flatLookMag = flatLook.Magnitude
		local forward = if flatLookMag > 0.001 then (flatLook / flatLookMag) else Vector3.new(0, 0, -1)
		local rawPos = root.Position + forward * 5
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { LocalPlayer.Character, currentGhost, currentGroundMarker }
		local groundOrigin = Vector3.new(rawPos.X, 300, rawPos.Z)
		local result = Workspace:Raycast(groundOrigin, Vector3.new(0, -800, 0), rayParams)
		local groundY = if result ~= nil then result.Position.Y else rawPos.Y - root.Size.Y * 0.5
		placed = Vector3.new(rawPos.X, groundY, rawPos.Z)
	else
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return false, nil
		end

		local unitRay = camera:ViewportPointToRay(Mouse.X, Mouse.Y)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { LocalPlayer.Character, currentGhost, currentGroundMarker }

		local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, rayParams)
		if result == nil then
			return false, nil
		end
		placed = result.Position
	end
	if useGridSnap then
		placed = Utils.SnapToGrid(placed, Constants.BUILDING.GridSize)
	end

	local maxDistance = Constants.BUILDING.PlacementMaxDistance
	if (root.Position - placed).Magnitude > maxDistance then
		return false, nil
	end
	local maxBuildRadius = Constants.BUILDING.MaxBuildRadiusFromCenter
	if Vector3.new(placed.X, 0, placed.Z).Magnitude > maxBuildRadius then
		return false, nil
	end

	local buildType = currentType
	if buildType == nil then
		return false, nil
	end

	local size = Constants.BUILDING.Sizes[buildType]
	local overlapSize = Vector3.new(
		math.max(0.05, size.X - PLACEMENT_OVERLAP_XZ_PADDING),
		size.Y,
		math.max(0.05, size.Z - PLACEMENT_OVERLAP_XZ_PADDING)
	)
	local center = placed + Vector3.new(0, size.Y * 0.5, 0)
	local rotatedCF = CFrame.new(center) * CFrame.Angles(0, math.rad(currentRotation), 0)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList: { Instance } = { LocalPlayer.Character, currentGhost }
	if currentGroundMarker ~= nil then
		table.insert(filterList, currentGroundMarker)
	end
	overlapParams.FilterDescendantsInstances = filterList
	local overlaps = Workspace:GetPartBoundsInBox(rotatedCF, overlapSize, overlapParams)
	for _, overlap in overlaps do
		if overlap:IsA("BasePart") then
			if CollectionService:HasTag(overlap, "TitanObjective") then
				return false, nil
			end
			-- Disallow stacking on blueprints or buildings (only block if overlap part itself is tagged, not child parts)
			if CollectionService:HasTag(overlap, "Blueprint") or CollectionService:HasTag(overlap, "DismantlableBuilding") then
				return false, nil
			end
		end
	end

	return true, placed
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
		if currentGroundMarker ~= nil then
			local markerY = pos.Y + (currentGroundMarker.Size.Y * 0.5)
			currentGroundMarker.CFrame = CFrame.new(pos.X, markerY, pos.Z) * CFrame.Angles(0, math.rad(currentRotation), 0)
		end
	end

	if valid then
		currentGhost.Color = VisualManifest.Tools.GhostValidColor
		if currentGroundMarker ~= nil then
			currentGroundMarker.Color = VisualManifest.Tools.GhostValidColor
		end
	else
		currentGhost.Color = VisualManifest.Tools.GhostInvalidColor
		if currentGroundMarker ~= nil then
			currentGroundMarker.Color = VisualManifest.Tools.GhostInvalidColor
		end
	end
end

function BlueprintController.StartPlacing(buildingType: BuildingType)
	clearGhost()

	mode = "Placing"
	currentType = buildingType
	setHighlightedBlueprint(nil)

	local character = LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid ~= nil then
		originalWalkSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = math.max(1, humanoid.WalkSpeed * 0.5)
		slowedHumanoid = humanoid
	end

	local ghost = Instance.new("Part")
	ghost.Name = "LocalPlacementGhost"
	ghost.Size = Constants.BUILDING.Sizes[buildingType]
	ghost.Transparency = if Platform.IsMobile then 0.15 else Constants.BUILDING.GhostTransparency
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.Material = VisualManifest.Buildings.GhostMaterial
	ghost.Color = VisualManifest.Buildings.BaseColors[buildingType]
	ghost.Parent = Workspace
	currentGhost = ghost

	local marker = Instance.new("Part")
	marker.Name = "LocalPlacementGroundMarker"
	marker.Size = Vector3.new(ghost.Size.X, 0.08, ghost.Size.Z)
	marker.Anchored = true
	marker.CanCollide = false
	marker.Material = Enum.Material.Neon
	marker.Transparency = 0.4
	marker.Color = VisualManifest.Tools.GhostValidColor
	marker.Parent = Workspace
	currentGroundMarker = marker

	renderConn = RunService.RenderStepped:Connect(updateGhostVisual)
end

local function placeCurrentBlueprint()
	if mode ~= "Placing" or currentType == nil or placementPosition == nil or not placementValid then
		return
	end

	remotes.PlaceBlueprint:FireServer(currentType, placementPosition, currentRotation)
	-- Stay in Placing mode so user can place more without reselecting; guard against rapid double-place
	placementPosition = nil
	placementValid = false
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

function BlueprintController.GetMode(): ControllerMode
	return mode
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

local function getTitanStage(): number
	for _, tagged in CollectionService:GetTagged("TitanObjective") do
		if tagged:IsA("Model") then
			local stageAttr = tagged:GetAttribute("TitanStage")
			if typeof(stageAttr) == "number" then
				return math.max(0, math.floor(stageAttr))
			end
		end
	end
	return 0
end

local function getCatchupBuildMultiplier(): number
	local folder = remotes.Folder
	if folder == nil then
		return 1
	end
	local untilAttr = folder:GetAttribute("CatchupUntil")
	if typeof(untilAttr) ~= "number" then
		return 1
	end
	if (untilAttr :: number) > os.clock() then
		local bonus = Constants.BUILDING.CatchupBuildSpeedBonus or 0.25
		return math.max(0.1, 1 - bonus)
	end
	return 1
end

local function getBuildTime(): number
	local base = Constants.BUILDING.BaseBuildTimeSeconds
	local role = LocalPlayer:GetAttribute("Role")
	local roleMult = if role == "Fixer" then 0.6 else 1.0

	local stage = getTitanStage()
	local bonusPerStage = Constants.TITAN.BuildSpeedBonusPerStage or 0.1
	local titanMult = math.max(Constants.TITAN.MinBuildTimeMultiplier or 0.25, 1 - (stage * bonusPerStage))

	local catchupMult = getCatchupBuildMultiplier()

	local result = base * roleMult * titanMult * catchupMult
	local minMult = Constants.TITAN.MinBuildTimeMultiplier or 0.25
	return math.max(base * minMult, result)
end

local function cancelHold()
	if holdRenderConn ~= nil then
		holdRenderConn:Disconnect()
		holdRenderConn = nil
	end
	holdTarget = nil
	stopBuildAnim()
	emitBuildProgress(0)
	if mode == "Interacting" then
		mode = "Idle"
	end
end

local function startHold(targetOverride: BasePart?)
	local target = targetOverride or getNearestBlueprint(BLUEPRINT_INTERACT_RANGE)
	if target == nil then
		return
	end
	local character = LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return
	end
	if (target.Position - root.Position).Magnitude > BLUEPRINT_INTERACT_RANGE + 0.5 then
		return
	end
	mode = "Interacting"
	holdTarget = target
	holdStartTime = os.clock()
	holdDuration = getBuildTime()

	local character = LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		local track = getBuildTrack(humanoid)
		if track ~= nil then
			track:Play(0.1, 1, 1.4)
		end
	end

	holdRenderConn = RunService.RenderStepped:Connect(function()
		if holdTarget == nil or holdTarget.Parent == nil then
			cancelHold()
			return
		end

		local elapsed = os.clock() - holdStartTime
		local progress = math.clamp(elapsed / holdDuration, 0, 1)

		emitBuildProgress(progress)

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
			if (root.Position - holdTarget.Position).Magnitude > BLUEPRINT_INTERACT_RANGE + 2 then
				cancelHold()
			end
		end
	end)
end

function BlueprintController.ConnectBuildProgress(callback: (number) -> ())
	table.insert(buildProgressCallbacks, callback)
	return function()
		for index, existing in buildProgressCallbacks do
			if existing == callback then
				table.remove(buildProgressCallbacks, index)
				break
			end
		end
	end
end

function BlueprintController.RotatePlacement(): boolean
	if mode ~= "Placing" then
		return false
	end
	currentRotation = (currentRotation + 90) % 360
	return true
end

function BlueprintController.PlaceCurrentBlueprint(): boolean
	if mode ~= "Placing" then
		return false
	end
	placeCurrentBlueprint()
	return true
end

function BlueprintController.SetGridSnap(enabled: boolean)
	useGridSnap = enabled
end

function BlueprintController.GetGridSnap(): boolean
	return useGridSnap
end

function BlueprintController.GetCurrentType(): BuildingType?
	return currentType
end

function BlueprintController.CancelPlacement(): boolean
	if mode ~= "Placing" then
		return false
	end
	clearGhost()
	return true
end

function BlueprintController.GetNearestBlueprint(range: number?): BasePart?
	local useRange = if typeof(range) == "number" then (range :: number) else BLUEPRINT_INTERACT_RANGE
	return getNearestBlueprint(useRange)
end

function BlueprintController.StartInteractHold(): boolean
	if mode == "Placing" then
		return false
	end
	if holdTarget == nil then
		startHold()
	end
	return holdTarget ~= nil
end

function BlueprintController.EndInteractHold()
	if holdTarget ~= nil then
		cancelHold()
	end
end

function BlueprintController.CancelNearestBlueprint(): boolean
	local nearest = getNearestBlueprint(BLUEPRINT_INTERACT_RANGE)
	if nearest == nil then
		return false
	end
	local bpId = nearest:GetAttribute("BlueprintId")
	if typeof(bpId) == "string" then
		remotes.CancelBlueprint:FireServer(bpId :: string)
		return true
	end
	return false
end

local function onInputBegan(input: InputObject, processed: boolean)
	if mode == "Placing" then
		if input.KeyCode == Enum.KeyCode.R then
			BlueprintController.RotatePlacement()
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			BlueprintController.CancelPlacement()
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			BlueprintController.CancelPlacement()
			return
		end
		if (input.UserInputType == Enum.UserInputType.MouseButton1 or (input.UserInputType == Enum.UserInputType.Touch and not Platform.IsMobile))
			and not processed then
			placeCurrentBlueprint()
			return
		end
	end

	-- Mobile building hold is driven by the on-screen BUILD button.

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
			BlueprintController.StartInteractHold()
		end
	elseif input.KeyCode == Enum.KeyCode.X then
		BlueprintController.CancelNearestBlueprint()
	end
end

local function onInputEnded(input: InputObject, _processed: boolean)
	if input.KeyCode == Enum.KeyCode.E and holdTarget ~= nil then
		cancelHold()
	elseif Platform.IsMobile and input.UserInputType == Enum.UserInputType.Touch and holdTarget ~= nil then
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

	highlightRenderConn = RunService.RenderStepped:Connect(function()
		if mode == "Placing" then
			if highlightedBlueprint ~= nil then
				setHighlightedBlueprint(nil)
			end
			return
		end

		if mode == "Interacting" then
			if holdTarget ~= nil and holdTarget.Parent ~= nil then
				if highlightedBlueprint ~= holdTarget then
					setHighlightedBlueprint(holdTarget)
				end
			elseif highlightedBlueprint ~= nil then
				setHighlightedBlueprint(nil)
			end
			return
		end

		local nearest = getNearestBlueprint(BLUEPRINT_INTERACT_RANGE)
		if nearest ~= highlightedBlueprint then
			setHighlightedBlueprint(nearest)
		end

		if activeHighlight ~= nil and activeHighlight.Enabled then
			local pulse = (math.sin(os.clock() * HIGHLIGHT_PULSE_SPEED) + 1) * 0.5
			activeHighlight.FillTransparency = math.clamp(
				HIGHLIGHT_FILL_BASE + pulse * HIGHLIGHT_FILL_AMPLITUDE,
				0,
				1
			)
			activeHighlight.OutlineTransparency = math.clamp(
				HIGHLIGHT_OUTLINE_BASE + pulse * HIGHLIGHT_OUTLINE_AMPLITUDE,
				0,
				1
			)
			if activeSelectionBox ~= nil and activeSelectionBox.Visible then
				activeSelectionBox.LineThickness = SELECTION_LINE_BASE + pulse * SELECTION_LINE_AMPLITUDE
			end
		end
	end)
end

return BlueprintController
