--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local BlueprintController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("BlueprintController"))

type BuildingType = "Turret" | "Drill" | "Wall"

local MainHUD = {}

local remotes = Remotes.Get()
local isInitialized = false
local currentScrap = 0
local scrapLabel: TextLabel? = nil
local dismantleBars: { [BasePart]: BillboardGui } = {}
local roleScreen: ScreenGui? = nil

local function getCostPreview(buildingType: BuildingType): number
	local base = Constants.BASE_COSTS[buildingType]
	return math.floor(base + 0.5)
end

local function animateScrapPop(label: TextLabel)
	local grow = TweenService:Create(label, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextSize = 28,
	})
	local shrink = TweenService:Create(label, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextSize = 24,
	})
	grow:Play()
	grow.Completed:Connect(function()
		shrink:Play()
	end)
end

local function showScrapDelta(delta: number)
	local gui = PlayerGui:FindFirstChild("MainHUDGui")
	if gui == nil or not gui:IsA("ScreenGui") then
		return
	end

	local deltaLabel = Instance.new("TextLabel")
	deltaLabel.Name = "ScrapDelta"
	deltaLabel.BackgroundTransparency = 1
	deltaLabel.Size = UDim2.fromOffset(120, 28)
	deltaLabel.Position = UDim2.new(0.5, -60, 0.07, 0)
	deltaLabel.TextScaled = true
	deltaLabel.Font = Enum.Font.GothamBold
	deltaLabel.TextStrokeTransparency = 0.35
	deltaLabel.Text = (delta >= 0 and "+" or "") .. tostring(delta)
	deltaLabel.TextColor3 = if delta >= 0 then Color3.fromRGB(120, 255, 120) else Color3.fromRGB(255, 120, 120)
	deltaLabel.Parent = gui

	local tween = TweenService:Create(deltaLabel, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, -60, 0.03, 0),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		deltaLabel:Destroy()
	end)
end

local function updateScrap(newScrap: number)
	local previous = currentScrap
	currentScrap = newScrap

	if scrapLabel ~= nil then
		scrapLabel.Text = ("Scrap: %d"):format(currentScrap)
		animateScrapPop(scrapLabel)
	end

	local delta = newScrap - previous
	if delta ~= 0 then
		showScrapDelta(delta)
	end
end

local function ensureBar(part: BasePart): BillboardGui
	local existing = dismantleBars[part]
	if existing ~= nil then
		return existing
	end

	local bar = Instance.new("BillboardGui")
	bar.Name = "DismantleBar"
	bar.Size = UDim2.fromOffset(140, 30)
	bar.StudsOffset = Vector3.new(0, part.Size.Y * 0.8, 0)
	bar.AlwaysOnTop = true
	bar.Enabled = false
	bar.Parent = part

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(120, 25, 25)
	bg.BorderSizePixel = 0
	bg.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local text = Instance.new("TextLabel")
	text.Name = "Label"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextStrokeTransparency = 0.4
	text.Text = "0%"
	text.Parent = bg

	dismantleBars[part] = bar
	return bar
end

local function updateDismantleBars()
	local role = LocalPlayer:GetAttribute("Role")
	local isFixer = role == "Fixer"

	for _, tagged in CollectionService:GetTagged("DismantlableBuilding") do
		if tagged:IsA("BasePart") and tagged.Parent ~= nil then
			local progressAttr = tagged:GetAttribute("DismantleProgress")
			local progress = if typeof(progressAttr) == "number" then math.clamp(progressAttr :: number, 0, 100) else 0
			local bar = ensureBar(tagged)
			local bg = bar:FindFirstChild("Background")
			if bg and bg:IsA("Frame") then
				local fill = bg:FindFirstChild("Fill")
				local text = bg:FindFirstChild("Label")

				if fill and fill:IsA("Frame") then
					fill.Size = UDim2.fromScale(progress / 100, 1)
				end
				if text and text:IsA("TextLabel") then
					text.Text = ("%d%%"):format(math.floor(progress + 0.5))
				end

				if isFixer then
					bg.BorderSizePixel = 2
					bg.BorderColor3 = Color3.fromRGB(255, 215, 85)
				else
					bg.BorderSizePixel = 0
				end
			end

			bar.Enabled = progress > 0
		end
	end

	for part, bar in dismantleBars do
		if part.Parent == nil then
			bar:Destroy()
			dismantleBars[part] = nil
		end
	end
end

local function makeRoleButton(parent: Instance, roleName: string, xScale: number)
	local roleDef = Constants.ROLE_DEFINITIONS[roleName]

	local button = Instance.new("TextButton")
	button.Name = roleName .. "Button"
	button.Size = UDim2.new(0.25, 0, 0.42, 0)
	button.Position = UDim2.new(xScale, 0, 0.3, 0)
	button.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = true
	button.Font = Enum.Font.GothamBold
	button.Text = string.format(
		"%s\nSPD x%.1f\nRPR x%.1f\nDMG x%.1f",
		roleName,
		roleDef.speedMult,
		roleDef.repairMult,
		roleDef.damageMult
	)
	button.Parent = parent

	button.MouseButton1Click:Connect(function()
		remotes.RoleSelected:FireServer(roleName)
		if roleScreen ~= nil then
			local overlay = roleScreen:FindFirstChild("Overlay")
			if overlay and overlay:IsA("Frame") then
				local fade = TweenService:Create(overlay, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					BackgroundTransparency = 1,
				})
				fade:Play()
				fade.Completed:Connect(function()
					roleScreen.Enabled = false
				end)
			else
				roleScreen.Enabled = false
			end
		end
	end)
end

local function createRoleSelection()
	if LocalPlayer:GetAttribute("Role") ~= nil then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "RoleSelectionGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = PlayerGui
	roleScreen = screen

	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(10, 10, 15)
	overlay.BackgroundTransparency = 0.2
	overlay.Parent = screen

	makeRoleButton(overlay, "Scrapper", 0.08)
	makeRoleButton(overlay, "Fixer", 0.375)
	makeRoleButton(overlay, "Enforcer", 0.67)
end

local function createToolbar(parent: Instance)
	local frame = Instance.new("Frame")
	frame.Name = "BuildToolbar"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 0.97, 0)
	frame.Size = UDim2.fromOffset(460, 88)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	frame.BackgroundTransparency = 0.2
	frame.Parent = parent

	local slots: { { name: BuildingType, key: string } } = {
		{ name = "Turret", key = "1" },
		{ name = "Drill", key = "2" },
		{ name = "Wall", key = "3" },
	}

	for index, info in slots do
		local slot = Instance.new("TextButton")
		slot.Name = info.name .. "Slot"
		slot.Size = UDim2.new(0, 140, 0, 72)
		slot.Position = UDim2.new(0, 10 + (index - 1) * 150, 0, 8)
		slot.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
		slot.TextColor3 = Color3.fromRGB(255, 255, 255)
		slot.TextScaled = true
		slot.Font = Enum.Font.GothamBold
		slot.Text = string.format("%s\n$%d\n[%s]", info.name, getCostPreview(info.name), info.key)
		slot.Parent = frame

		local colorSwatch = Instance.new("Frame")
		colorSwatch.Name = "Swatch"
		colorSwatch.Size = UDim2.fromOffset(16, 16)
		colorSwatch.Position = UDim2.fromOffset(6, 6)
		colorSwatch.BackgroundColor3 = Constants.BUILDING.Colors[info.name]
		colorSwatch.BorderSizePixel = 0
		colorSwatch.Parent = slot

		slot.MouseButton1Click:Connect(function()
			BlueprintController.StartPlacing(info.name)
		end)
	end
end

local function createMainHUD()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MainHUDGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = PlayerGui

	local scrapFrame = Instance.new("Frame")
	scrapFrame.Name = "ScrapFrame"
	scrapFrame.AnchorPoint = Vector2.new(0.5, 0)
	scrapFrame.Position = UDim2.new(0.5, 0, 0.02, 0)
	scrapFrame.Size = UDim2.fromOffset(240, 52)
	scrapFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	scrapFrame.BackgroundTransparency = 0.15
	scrapFrame.Parent = gui

	local label = Instance.new("TextLabel")
	label.Name = "ScrapLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 236, 117)
	label.TextScaled = false
	label.TextSize = 24
	label.Font = Enum.Font.GothamBold
	label.Text = "Scrap: 0"
	label.Parent = scrapFrame
	scrapLabel = label

	createToolbar(gui)
end

function MainHUD.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	createMainHUD()
	createRoleSelection()

	remotes.ScrapUpdated.OnClientEvent:Connect(function(newScrap: number)
		updateScrap(newScrap)
	end)

	RunService.Heartbeat:Connect(updateDismantleBars)
end

return MainHUD
