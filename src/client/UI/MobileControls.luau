--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Platform = require(Shared:WaitForChild("Platform"))

local BlueprintController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("BlueprintController"))
local ToolController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("ToolController"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local MobileControls = {}

local isInitialized = false
local rootGui: ScreenGui? = nil
local rootFrame: Frame? = nil
local buildMenuOpen = false

local rotateButton: TextButton? = nil
local cancelButton: TextButton? = nil
local holdButton: TextButton? = nil
local removeButton: TextButton? = nil
local optionFrame: Frame? = nil
local toolButton: TextButton? = nil
local holdPointerDown = false

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

local function updateToolButton()
	if toolButton == nil then
		return
	end
	local toolName = ToolController.GetCurrentToolName()
	if toolName == nil then
		toolButton.Visible = false
		return
	end
	toolButton.Visible = true
	toolButton.Text = if toolName == "RustyShotgun" then "SHOT" else "WRENCH"
	toolButton.BackgroundColor3 = if ToolController.IsCurrentToolEquipped()
		then Theme.Colors.ToolEquipped
		else Theme.Colors.ToolUnequipped
end

local function createUI(parentGui: ScreenGui)
	rootFrame = Instance.new("Frame")
	rootFrame.Name = "MobileControls"
	rootFrame.Size = UDim2.fromScale(1, 1)
	rootFrame.BackgroundTransparency = 1
	rootFrame.ZIndex = 20
	rootFrame.Parent = parentGui

	local buildButton = makeButton(
		rootFrame,
		"BuildMenuButton",
		"BUILD",
		UDim2.fromOffset(92, 52),
		UDim2.new(0.5, -46, 1, -102),
		Theme.Colors.Accent
	)
	buildButton.TextColor3 = Theme.Colors.Panel

	optionFrame = Instance.new("Frame")
	optionFrame.Name = "BuildOptions"
	optionFrame.Size = UDim2.fromOffset(228, 52)
	optionFrame.Position = UDim2.new(0.5, -114, 1, -160)
	optionFrame.BackgroundTransparency = 1
	optionFrame.Visible = false
	optionFrame.Parent = rootFrame

	local optionLayout = Instance.new("UIListLayout")
	optionLayout.FillDirection = Enum.FillDirection.Horizontal
	optionLayout.Padding = UDim.new(0, 8)
	optionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	optionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	optionLayout.Parent = optionFrame

	local turret = makeButton(optionFrame, "TurretButton", "T", UDim2.fromOffset(68, 52), UDim2.fromOffset(0, 0))
	turret.MouseButton1Click:Connect(function()
		BlueprintController.StartPlacing("Turret")
		buildMenuOpen = false
		if optionFrame then
			optionFrame.Visible = false
		end
	end)

	local drill = makeButton(optionFrame, "DrillButton", "D", UDim2.fromOffset(68, 52), UDim2.fromOffset(0, 0))
	drill.MouseButton1Click:Connect(function()
		BlueprintController.StartPlacing("Drill")
		buildMenuOpen = false
		if optionFrame then
			optionFrame.Visible = false
		end
	end)

	local wall = makeButton(optionFrame, "WallButton", "W", UDim2.fromOffset(68, 52), UDim2.fromOffset(0, 0))
	wall.MouseButton1Click:Connect(function()
		BlueprintController.StartPlacing("Wall")
		buildMenuOpen = false
		if optionFrame then
			optionFrame.Visible = false
		end
	end)

	buildButton.MouseButton1Click:Connect(function()
		buildMenuOpen = not buildMenuOpen
		if optionFrame then
			optionFrame.Visible = buildMenuOpen
		end
	end)

	rotateButton = makeButton(rootFrame, "RotateButton", "ROTATE", UDim2.fromOffset(94, 50), UDim2.new(1, -206, 1, -162))
	rotateButton.MouseButton1Click:Connect(function()
		BlueprintController.RotatePlacement()
	end)

	cancelButton = makeButton(rootFrame, "CancelButton", "CANCEL", UDim2.fromOffset(94, 50), UDim2.new(1, -106, 1, -162))
	cancelButton.MouseButton1Click:Connect(function()
		BlueprintController.CancelPlacement()
	end)

	holdButton = makeButton(
		rootFrame,
		"BuildHoldButton",
		"HOLD\nBUILD",
		UDim2.fromOffset(100, 64),
		UDim2.new(1, -112, 1, -242),
		Theme.Colors.Good
	)
	holdButton.TextColor3 = Theme.Colors.Panel
	holdButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holdPointerDown = true
			BlueprintController.StartInteractHold()
		end
	end)
	holdButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holdPointerDown = false
			BlueprintController.EndInteractHold()
		end
	end)

	removeButton = makeButton(rootFrame, "RemoveButton", "REMOVE", UDim2.fromOffset(94, 50), UDim2.new(1, -106, 1, -106))
	removeButton.MouseButton1Click:Connect(function()
		BlueprintController.CancelNearestBlueprint()
	end)

	toolButton = makeButton(rootFrame, "ToolButton", "TOOL", UDim2.fromOffset(94, 50), UDim2.new(1, -106, 1, -52))
	toolButton.MouseButton1Click:Connect(function()
		if ToolController.IsCurrentToolEquipped() then
			ToolController.UnequipCurrentTool()
		else
			ToolController.EquipCurrentTool()
		end
		updateToolButton()
	end)

	updateToolButton()
end

function MobileControls.Init()
	if isInitialized or not Platform.IsMobile then
		return
	end
	isInitialized = true

	local playerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	rootGui = playerGui:WaitForChild("MainHUDGui") :: ScreenGui
	createUI(rootGui)

	RunService.RenderStepped:Connect(function()
		if rootFrame == nil then
			return
		end

		local mode = BlueprintController.GetMode()
		local placing = mode == "Placing"
		local hasNearbyBlueprint = BlueprintController.GetNearestBlueprint(16) ~= nil

		if optionFrame ~= nil and not buildMenuOpen then
			optionFrame.Visible = false
		end

		if rotateButton ~= nil then
			rotateButton.Visible = placing
		end
		if cancelButton ~= nil then
			cancelButton.Visible = placing
		end

		if holdButton ~= nil then
			holdButton.Visible = not placing and hasNearbyBlueprint
			if not holdButton.Visible and holdPointerDown then
				holdPointerDown = false
				BlueprintController.EndInteractHold()
			end
		end
		if removeButton ~= nil then
			removeButton.Visible = not placing and hasNearbyBlueprint
		end

		updateToolButton()
	end)
end

return MobileControls
