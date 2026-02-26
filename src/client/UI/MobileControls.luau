--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Platform = require(Shared:WaitForChild("Platform"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local BlueprintController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("BlueprintController"))
local ToolController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("ToolController"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local MobileControls = {}
local remotes = Remotes.Get()
local userGameSettings = UserSettings():GetService("UserGameSettings")

local isInitialized = false
local rootGui: ScreenGui? = nil
local rootFrame: Frame? = nil
local hotbarFrame: Frame? = nil
local actionFrame: Frame? = nil

local slotButtons: { [string]: TextButton } = {}
local slotStrokes: { [string]: UIStroke } = {}

local placeButton: TextButton? = nil
local rotateButton: TextButton? = nil
local cancelButton: TextButton? = nil
local buildButton: TextButton? = nil
local removeButton: TextButton? = nil
local upgradeButton: TextButton? = nil
local gridModeButton: TextButton? = nil
local shiftLockButton: ImageButton? = nil
local activeSlotName: string? = nil
local SLOT_BASE_SIZE = UDim2.fromOffset(44, 44)
local SLOT_ACTIVE_SIZE = UDim2.fromOffset(48, 48)
local SHIFT_LOCK_OFF_ICON = "rbxasset://textures/ui/mouseLock_off@2x.png"
local SHIFT_LOCK_ON_ICON = "rbxasset://textures/ui/mouseLock_on@2x.png"
local trackedPromptParts: { [BasePart]: true } = {}

local function makeButton(
	parent: Instance,
	name: string,
	text: string,
	size: UDim2,
	position: UDim2,
	bgColor: Color3?
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = bgColor or Theme.Colors.PanelAlt
	button.BackgroundTransparency = 0.1
	button.TextColor3 = Theme.Colors.TextPrimary
	button.Font = Enum.Font.GothamBold
	button.TextScaled = true
	button.Text = text
	button.AutoButtonColor = true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button

	return button
end

local function getRootPart(): BasePart?
	local character = LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function getNearestUpgradePrompt(range: number): (ProximityPrompt?, number)
	local root = getRootPart()
	if root == nil then
		return nil, math.huge
	end
	local nearestPrompt: ProximityPrompt? = nil
	local nearestDist = range
	for _, tagged in CollectionService:GetTagged("DismantlableBuilding") do
		if tagged:IsA("BasePart") and tagged.Parent ~= nil then
			local dist = (tagged.Position - root.Position).Magnitude
			if dist <= nearestDist then
				local prompt = tagged:FindFirstChild("UpgradePrompt")
				if prompt ~= nil and prompt:IsA("ProximityPrompt") and prompt.Enabled then
					nearestDist = dist
					nearestPrompt = prompt
				end
			end
		end
	end
	if nearestPrompt == nil then
		return nil, math.huge
	end
	return nearestPrompt, nearestDist
end

local function getNearestBlueprintDistance(range: number): (BasePart?, number)
	local root = getRootPart()
	if root == nil then
		return nil, math.huge
	end
	local nearest = BlueprintController.GetNearestBlueprint(range)
	if nearest == nil then
		return nil, math.huge
	end
	return nearest, (nearest.Position - root.Position).Magnitude
end

local function updateShiftLockButtonVisual()
	if shiftLockButton == nil then
		return
	end
	local rotationType = userGameSettings.RotationType
	local enabled = rotationType == Enum.RotationType.CameraRelative
	shiftLockButton.Image = if enabled then SHIFT_LOCK_ON_ICON else SHIFT_LOCK_OFF_ICON
end

local function updateGridModeText()
	if gridModeButton == nil then
		return
	end
	local usingGrid = BlueprintController.GetGridSnap()
	gridModeButton.Text = if usingGrid then "[x] GRID" else "[ ] FREE"
end

local function updateToolSlot()
	local toolButton = slotButtons.Tool
	if toolButton == nil then
		return
	end

	local toolName = ToolController.GetCurrentToolName()
	if toolName == nil then
		toolButton.Visible = false
		return
	end
	toolButton.Visible = true
	toolButton.Text = if toolName == "RustyShotgun" then "GUN" else "WR"
end

local function setSlotActive(slotName: string, isActive: boolean)
	local button = slotButtons[slotName]
	local stroke = slotStrokes[slotName]
	if button == nil or stroke == nil then
		return
	end

	stroke.Transparency = if isActive then 0 else 0.75
	stroke.Thickness = if isActive then 2 else 1
	stroke.Color = if isActive then Theme.Colors.Accent else Theme.Colors.TextMuted
	button.BackgroundColor3 = if isActive then Theme.Colors.ToolEquipped else Theme.Colors.PanelAlt
	button.Size = if isActive then SLOT_ACTIVE_SIZE else SLOT_BASE_SIZE
end

local function pulseSlot(button: TextButton)
	local grow = TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = SLOT_ACTIVE_SIZE,
	})
	local shrink = TweenService:Create(button, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = SLOT_BASE_SIZE,
	})
	grow:Play()
	grow.Completed:Connect(function()
		shrink:Play()
	end)
end

local function syncActiveSlot()
	local mode = BlueprintController.GetMode()
	local desiredSlot: string? = nil
	if mode == "Placing" then
		local currentType = BlueprintController.GetCurrentType()
		if currentType == "Turret" then
			desiredSlot = "Turret"
		elseif currentType == "Drill" then
			desiredSlot = "Drill"
		elseif currentType == "Wall" then
			desiredSlot = "Wall"
		end
	elseif ToolController.IsCurrentToolEquipped() then
		local toolName = ToolController.GetCurrentToolName()
		if toolName ~= nil then
			desiredSlot = "Tool"
		end
	end
	activeSlotName = desiredSlot

	for slotName, _ in slotButtons do
		setSlotActive(slotName, slotName == activeSlotName)
	end
end

local function selectBuildSlot(buildType: "Turret" | "Drill" | "Wall")
	local mode = BlueprintController.GetMode()
	local currentType = BlueprintController.GetCurrentType()
	if mode == "Placing" and currentType == buildType then
		BlueprintController.CancelPlacement()
		return
	end

	if ToolController.IsCurrentToolEquipped() then
		ToolController.UnequipCurrentTool()
	end

	BlueprintController.StartPlacing(buildType)
	local slotButton = slotButtons[buildType]
	if slotButton ~= nil then
		pulseSlot(slotButton)
	end
end

local function toggleToolSlot()
	if BlueprintController.GetMode() == "Placing" then
		BlueprintController.CancelPlacement()
	end

	if ToolController.IsCurrentToolEquipped() then
		ToolController.UnequipCurrentTool()
		return
	end
	ToolController.EquipCurrentTool()
	local slotButton = slotButtons.Tool
	if slotButton ~= nil then
		pulseSlot(slotButton)
	end
end

local function createSlotButton(parent: Instance, slotName: string, text: string): TextButton
	local button = makeButton(parent, slotName .. "Slot", text, SLOT_BASE_SIZE, UDim2.fromOffset(0, 0))
	button.TextScaled = false
	button.TextSize = 14
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.TextMuted
	stroke.Transparency = 0.75
	stroke.Thickness = 1
	stroke.Parent = button
	slotButtons[slotName] = button
	slotStrokes[slotName] = stroke
	return button
end

local function createUI(parentGui: ScreenGui)
	rootFrame = Instance.new("Frame")
	rootFrame.Name = "MobileControls"
	rootFrame.Size = UDim2.fromScale(1, 1)
	rootFrame.BackgroundTransparency = 1
	rootFrame.ZIndex = 20
	rootFrame.Parent = parentGui

	hotbarFrame = Instance.new("Frame")
	hotbarFrame.Name = "Hotbar"
	hotbarFrame.AnchorPoint = Vector2.new(0.5, 1)
	hotbarFrame.Position = UDim2.new(0.5, 0, 1, -8)
	hotbarFrame.Size = UDim2.fromOffset(236, 56)
	hotbarFrame.BackgroundColor3 = Theme.Colors.Panel
	hotbarFrame.BackgroundTransparency = 0.2
	hotbarFrame.Parent = rootFrame
	Theme.StylePanel(hotbarFrame, 8)

	local hotbarLayout = Instance.new("UIListLayout")
	hotbarLayout.FillDirection = Enum.FillDirection.Horizontal
	hotbarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	hotbarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	hotbarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	hotbarLayout.Padding = UDim.new(0, 6)
	hotbarLayout.Parent = hotbarFrame

	local turretSlot = createSlotButton(hotbarFrame, "Turret", "T")
	turretSlot.LayoutOrder = 1
	turretSlot.MouseButton1Click:Connect(function()
		selectBuildSlot("Turret")
	end)

	local drillSlot = createSlotButton(hotbarFrame, "Drill", "D")
	drillSlot.LayoutOrder = 2
	drillSlot.MouseButton1Click:Connect(function()
		selectBuildSlot("Drill")
	end)

	local wallSlot = createSlotButton(hotbarFrame, "Wall", "W")
	wallSlot.LayoutOrder = 3
	wallSlot.MouseButton1Click:Connect(function()
		selectBuildSlot("Wall")
	end)

	local spacer = Instance.new("Frame")
	spacer.Name = "Spacer"
	spacer.Size = UDim2.fromOffset(16, 44)
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = 4
	spacer.Parent = hotbarFrame

	local toolSlot = createSlotButton(hotbarFrame, "Tool", "TOOL")
	toolSlot.LayoutOrder = 5
	toolSlot.MouseButton1Click:Connect(function()
		toggleToolSlot()
	end)

	actionFrame = Instance.new("Frame")
	actionFrame.Name = "ActionStack"
	actionFrame.AnchorPoint = Vector2.new(1, 1)
	actionFrame.Position = UDim2.new(1, -10, 1, -90)
	actionFrame.Size = UDim2.fromOffset(84, 220)
	actionFrame.BackgroundTransparency = 1
	actionFrame.Parent = rootFrame

	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Vertical
	actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	actionLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	actionLayout.Padding = UDim.new(0, 6)
	actionLayout.Parent = actionFrame

	placeButton = makeButton(actionFrame, "PlaceButton", "PLACE", UDim2.fromOffset(40, 40), UDim2.fromOffset(0, 0), Theme.Colors.Good)
	placeButton.TextColor3 = Theme.Colors.Panel
	placeButton.TextScaled = false
	placeButton.TextSize = 10
	placeButton.MouseButton1Click:Connect(function()
		BlueprintController.PlaceCurrentBlueprint()
	end)

	rotateButton = makeButton(actionFrame, "RotateButton", "ROT", UDim2.fromOffset(40, 40), UDim2.fromOffset(0, 0))
	rotateButton.TextScaled = false
	rotateButton.TextSize = 10
	rotateButton.MouseButton1Click:Connect(function()
		BlueprintController.RotatePlacement()
	end)

	cancelButton = makeButton(actionFrame, "CancelButton", "X", UDim2.fromOffset(40, 40), UDim2.fromOffset(0, 0), Theme.Colors.Bad)
	cancelButton.TextColor3 = Theme.Colors.Panel
	cancelButton.TextScaled = false
	cancelButton.TextSize = 14
	cancelButton.MouseButton1Click:Connect(function()
		BlueprintController.CancelPlacement()
	end)

	buildButton = makeButton(actionFrame, "BuildButton", "BUILD", UDim2.fromOffset(80, 40), UDim2.fromOffset(0, 0), Theme.Colors.Good)
	buildButton.TextColor3 = Theme.Colors.Panel
	buildButton.TextScaled = false
	buildButton.TextSize = 12
	buildButton.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			BlueprintController.StartInteractHold()
		end
	end)
	buildButton.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			BlueprintController.EndInteractHold()
		end
	end)

	removeButton = makeButton(actionFrame, "RemoveButton", "DEL", UDim2.fromOffset(40, 40), UDim2.fromOffset(0, 0))
	removeButton.TextScaled = false
	removeButton.TextSize = 11
	removeButton.MouseButton1Click:Connect(function()
		BlueprintController.CancelNearestBlueprint()
	end)

	upgradeButton = makeButton(actionFrame, "UpgradeButton", "UP", UDim2.fromOffset(40, 40), UDim2.fromOffset(0, 0))
	upgradeButton.TextScaled = false
	upgradeButton.TextSize = 12
	upgradeButton.MouseButton1Click:Connect(function()
		local prompt = getNearestUpgradePrompt(14)
		if prompt == nil then
			return
		end
		local buildingPart = prompt.Parent
		if buildingPart ~= nil and buildingPart:IsA("BasePart") then
			remotes.RequestUpgrade:FireServer(buildingPart)
		end
	end)

	gridModeButton = makeButton(actionFrame, "GridModeButton", "[x] GRID", UDim2.fromOffset(40, 40), UDim2.fromOffset(0, 0))
	gridModeButton.TextScaled = false
	gridModeButton.TextSize = 8
	gridModeButton.MouseButton1Click:Connect(function()
		BlueprintController.SetGridSnap(not BlueprintController.GetGridSnap())
		updateGridModeText()
	end)

	shiftLockButton = Instance.new("ImageButton")
	shiftLockButton.Name = "ShiftLockButton"
	shiftLockButton.AnchorPoint = Vector2.new(1, 1)
	shiftLockButton.Position = UDim2.new(1, -60, 1, -12)
	shiftLockButton.Size = UDim2.fromOffset(36, 36)
	shiftLockButton.BackgroundColor3 = Theme.Colors.PanelAlt
	shiftLockButton.BackgroundTransparency = 0.1
	shiftLockButton.ImageColor3 = Theme.Colors.TextPrimary
	shiftLockButton.Parent = rootFrame
	local shiftCorner = Instance.new("UICorner")
	shiftCorner.CornerRadius = UDim.new(0, 8)
	shiftCorner.Parent = shiftLockButton
	local shiftStroke = Instance.new("UIStroke")
	shiftStroke.Color = Theme.Colors.PanelStroke
	shiftStroke.Thickness = 1
	shiftStroke.Transparency = 0.3
	shiftStroke.Parent = shiftLockButton
	shiftLockButton.Activated:Connect(function()
		local nextType = if userGameSettings.RotationType == Enum.RotationType.CameraRelative
			then Enum.RotationType.MovementRelative
			else Enum.RotationType.CameraRelative
		userGameSettings.RotationType = nextType
		updateShiftLockButtonVisual()
	end)
	updateShiftLockButtonVisual()

	updateGridModeText()
	updateToolSlot()
	syncActiveSlot()
end

local function suppressUpgradePromptOnPart(part: BasePart)
	local function applyPromptStyle(child: Instance)
		if child:IsA("ProximityPrompt") and child.Name == "UpgradePrompt" then
			child.Style = Enum.ProximityPromptStyle.Custom
		end
	end
	for _, child in part:GetChildren() do
		applyPromptStyle(child)
	end
	part.ChildAdded:Connect(function(child)
		applyPromptStyle(child)
	end)
end

function MobileControls.Init()
	if isInitialized or not Platform.IsMobile then
		return
	end
	isInitialized = true

	local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	rootGui = playerGui:WaitForChild("MainHUDGui") :: ScreenGui
	createUI(rootGui)

	for _, tagged in CollectionService:GetTagged("DismantlableBuilding") do
		if tagged:IsA("BasePart") and trackedPromptParts[tagged] ~= true then
			trackedPromptParts[tagged] = true
			suppressUpgradePromptOnPart(tagged)
		end
	end
	CollectionService:GetInstanceAddedSignal("DismantlableBuilding"):Connect(function(instance)
		if instance:IsA("BasePart") and trackedPromptParts[instance] ~= true then
			trackedPromptParts[instance] = true
			suppressUpgradePromptOnPart(instance)
		end
	end)

	RunService.RenderStepped:Connect(function()
		if rootFrame == nil then
			return
		end

		local mode = BlueprintController.GetMode()
		local placing = mode == "Placing"
		local nearestBlueprint, nearestBlueprintDist = getNearestBlueprintDistance(16)
		local nearestUpgradePrompt, nearestUpgradeDist = getNearestUpgradePrompt(14)
		local showBuildActions = not placing and nearestBlueprint ~= nil and nearestBlueprintDist <= nearestUpgradeDist
		local showUpgradeAction = not placing and nearestUpgradePrompt ~= nil and not showBuildActions

		if placeButton ~= nil then
			placeButton.Visible = placing
		end
		if rotateButton ~= nil then
			rotateButton.Visible = placing
		end
		if cancelButton ~= nil then
			cancelButton.Visible = placing
		end
		if buildButton ~= nil then
			buildButton.Visible = showBuildActions
		end
		if removeButton ~= nil then
			removeButton.Visible = showBuildActions
		end
		if upgradeButton ~= nil then
			upgradeButton.Visible = showUpgradeAction
		end
		if gridModeButton ~= nil then
			gridModeButton.Visible = placing
		end

		updateGridModeText()
		updateShiftLockButtonVisual()
		updateToolSlot()
		syncActiveSlot()
	end)
end

return MobileControls
