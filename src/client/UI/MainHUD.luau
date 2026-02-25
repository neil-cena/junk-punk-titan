--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local AudioManifest = require(Shared:WaitForChild("AudioManifest"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local BlueprintController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("BlueprintController"))

type BuildingType = "Turret" | "Drill" | "Wall"

local MainHUD = {}

local remotes = Remotes.Get()
local isInitialized = false
local currentScrap = 0
local currentStormSteel = 0
local lastWaveSeconds = -1
local scrapLabel: TextLabel? = nil
local stormSteelLabel: TextLabel? = nil
local waveTimerLabel: TextLabel? = nil
local dismantleBars: { [BasePart]: BillboardGui } = {}
local buildCostButtons: { [BuildingType]: TextButton } = {}
local roleScreen: ScreenGui? = nil
local threatLabel: TextLabel? = nil
local stormBannerLabel: TextLabel? = nil
local tetherStatusLabel: TextLabel? = nil
local activeRepairMinigame: Frame? = nil
local repairRenderConnection: RBXScriptConnection? = nil
local repairInputConnection: RBXScriptConnection? = nil
local wavePulseTween: Tween? = nil
local wavePulseBackTween: Tween? = nil
local waveTimerSignal = Instance.new("BindableEvent")
local gameOverGui: Frame? = nil
local victoryGui: Frame? = nil
local titanStageLabel: TextLabel? = nil
local titanIntegrityFill: Frame? = nil
local titanIntegrityBar: Frame? = nil
local titanRequirementLabel: TextLabel? = nil
local finalStandBanner: TextLabel? = nil

local function playUISound(soundId: string, volume: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.3
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		if sound.Parent ~= nil then
			sound:Destroy()
		end
	end)
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

local function updateStormSteel(newStormSteel: number)
	currentStormSteel = newStormSteel
	if stormSteelLabel == nil then
		return
	end

	stormSteelLabel.Text = ("Storm Steel: %d"):format(currentStormSteel)
	stormSteelLabel.Visible = currentStormSteel > 0
end

local function formatTimer(secondsRemaining: number): string
	local seconds = math.max(0, math.floor(secondsRemaining + 0.5))
	local mins = math.floor(seconds / 60)
	local secs = seconds % 60
	return ("NEXT SWARM: %02d:%02d"):format(mins, secs)
end

local function pulseWaveTimer()
	if waveTimerLabel == nil then
		return
	end

	local baseSize = 20
	waveTimerLabel.TextSize = baseSize
	wavePulseTween = TweenService:Create(waveTimerLabel, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextSize = 24,
	})
	wavePulseBackTween = TweenService:Create(waveTimerLabel, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextSize = baseSize,
	})
	wavePulseTween:Play()
	wavePulseTween.Completed:Connect(function()
		if wavePulseBackTween ~= nil then
			wavePulseBackTween:Play()
		end
	end)
end

local function updateWaveTimer(secondsRemaining: number)
	local seconds = math.max(0, math.floor(secondsRemaining + 0.5))
	if waveTimerLabel == nil then
		lastWaveSeconds = seconds
		return
	end

	waveTimerLabel.Text = formatTimer(seconds)
	if seconds > 10 then
		waveTimerLabel.TextColor3 = Color3.fromRGB(255, 193, 64)
	else
		waveTimerLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
	end

	if seconds <= 5 and seconds ~= lastWaveSeconds then
		pulseWaveTimer()
	end

	if seconds == 0 and lastWaveSeconds ~= 0 then
		waveTimerSignal:Fire()
	end
	lastWaveSeconds = seconds
end

local function showGameOver()
	if gameOverGui ~= nil then
		return
	end

	local rootGui = PlayerGui:FindFirstChild("MainHUDGui")
	if rootGui == nil or not rootGui:IsA("ScreenGui") then
		return
	end

	local overlay = Instance.new("Frame")
	overlay.Name = "GameOverOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(10, 5, 5)
	overlay.BackgroundTransparency = 0.2
	overlay.Parent = rootGui
	gameOverGui = overlay

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.2)
	title.Position = UDim2.new(0, 0, 0.35, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 70, 70)
	title.TextStrokeTransparency = 0.4
	title.Text = "THE TITAN HAS COLLAPSED"
	title.Parent = overlay

	local statsLabel = Instance.new("TextLabel")
	statsLabel.Size = UDim2.new(0.5, 0, 0.25, 0)
	statsLabel.Position = UDim2.new(0.25, 0, 0.5, 0)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Font = Enum.Font.GothamSemibold
	statsLabel.TextColor3 = Color3.fromRGB(220, 200, 200)
	statsLabel.TextScaled = true
	statsLabel.TextWrapped = true
	statsLabel.Text = buildStatsText()
	statsLabel.Parent = overlay

	task.delay(5, function()
		local ok = pcall(function()
			TeleportService:Teleport(game.PlaceId, LocalPlayer)
		end)
		if not ok then
			LocalPlayer:Kick("Titan collapsed. Session reset.")
		end
	end)
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
					local displayProgress = if progress >= 100 then 100 else math.floor(progress)
					text.Text = ("%d%%"):format(displayProgress)
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
		playUISound(AudioManifest.UIClick, 0.4)
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
		slot.Text = string.format("%s\n$%d\n[%s]", info.name, Constants.BASE_COSTS[info.name], info.key)
		slot.Parent = frame
		buildCostButtons[info.name] = slot

		local colorSwatch = Instance.new("Frame")
		colorSwatch.Name = "Swatch"
		colorSwatch.Size = UDim2.fromOffset(16, 16)
		colorSwatch.Position = UDim2.fromOffset(6, 6)
		colorSwatch.BackgroundColor3 = Constants.BUILDING.Colors[info.name]
		colorSwatch.BorderSizePixel = 0
		colorSwatch.Parent = slot

		slot.MouseButton1Click:Connect(function()
			playUISound(AudioManifest.UIClick)
			BlueprintController.StartPlacing(info.name)
		end)
	end
end

local function refreshBuildCosts()
	local ok, response = pcall(function()
		return remotes.RequestBuildCosts:InvokeServer()
	end)
	if not ok or type(response) ~= "table" then
		return
	end

	local keys: { { name: BuildingType, key: string } } = {
		{ name = "Turret", key = "1" },
		{ name = "Drill", key = "2" },
		{ name = "Wall", key = "3" },
	}

	for _, info in keys do
		local button = buildCostButtons[info.name]
		local costValue = response[info.name]
		if button ~= nil and type(costValue) == "number" then
			local newText = string.format("%s\n$%d\n[%s]", info.name, math.floor(costValue + 0.5), info.key)
			local changed = button.Text ~= newText
			button.Text = newText

			if changed then
				local originalSize = button.Size
				local pulseUp = TweenService:Create(button, TweenInfo.new(0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = UDim2.new(originalSize.X.Scale, originalSize.X.Offset + 8, originalSize.Y.Scale, originalSize.Y.Offset + 6),
				})
				local pulseDown = TweenService:Create(button, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Size = originalSize,
				})
				pulseUp:Play()
				pulseUp.Completed:Connect(function()
					pulseDown:Play()
				end)
			end
		end
	end
end

local function createDebugPanel(parent: Instance)
	if not RunService:IsStudio() then
		return
	end

	local panel = Instance.new("Frame")
	panel.Name = "DebugPanel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 10, 1, -10)
	panel.Size = UDim2.fromOffset(230, 140)
	panel.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	panel.BackgroundTransparency = 0.15
	panel.Parent = parent

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromOffset(220, 26)
	title.Position = UDim2.fromOffset(6, 4)
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextScaled = true
	title.Text = "Debug Controls"
	title.Parent = panel

	local function addButton(label: string, y: number, callback: () -> ())
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromOffset(210, 30)
		button.Position = UDim2.fromOffset(10, y)
		button.BackgroundColor3 = Color3.fromRGB(48, 48, 60)
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.Font = Enum.Font.GothamSemibold
		button.TextScaled = true
		button.Text = label
		button.Parent = panel
		button.MouseButton1Click:Connect(callback)
	end

	addButton("Spawn Next Wave", 34, function()
		remotes.DebugCommand:FireServer("SpawnWave")
	end)
	addButton("Start Storm Now", 70, function()
		remotes.DebugCommand:FireServer("StartStorm")
	end)
	addButton("Add +100 Scrap", 106, function()
		remotes.DebugCommand:FireServer("AddScrap", 100)
	end)
end

local function createTitanProgressPanel(parent: Instance)
	local frame = Instance.new("Frame")
	frame.Name = "TitanProgress"
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -10, 0, 10)
	frame.Size = UDim2.fromOffset(210, 110)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	frame.BackgroundTransparency = 0.15
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -10, 0, 22)
	titleLabel.Position = UDim2.fromOffset(5, 4)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextColor3 = Color3.fromRGB(200, 210, 230)
	titleLabel.TextScaled = true
	titleLabel.Text = "TITAN - STAGE 0/4"
	titleLabel.Parent = frame
	titanStageLabel = titleLabel

	local barBg = Instance.new("Frame")
	barBg.Name = "IntegrityBarBg"
	barBg.Size = UDim2.new(1, -20, 0, 16)
	barBg.Position = UDim2.new(0, 10, 0, 30)
	barBg.BackgroundColor3 = Color3.fromRGB(60, 20, 20)
	barBg.BorderSizePixel = 0
	barBg.Parent = frame
	titanIntegrityBar = barBg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 200, 100)
	fill.BorderSizePixel = 0
	fill.Parent = barBg
	titanIntegrityFill = fill

	local intLabel = Instance.new("TextLabel")
	intLabel.Name = "IntLabel"
	intLabel.Size = UDim2.fromScale(1, 1)
	intLabel.BackgroundTransparency = 1
	intLabel.Font = Enum.Font.GothamBold
	intLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	intLabel.TextScaled = true
	intLabel.TextStrokeTransparency = 0.3
	intLabel.Text = "100%"
	intLabel.Parent = barBg

	local reqLabel = Instance.new("TextLabel")
	reqLabel.Name = "Requirements"
	reqLabel.Size = UDim2.new(1, -10, 0, 44)
	reqLabel.Position = UDim2.new(0, 5, 0, 52)
	reqLabel.BackgroundTransparency = 1
	reqLabel.Font = Enum.Font.GothamSemibold
	reqLabel.TextColor3 = Color3.fromRGB(200, 200, 180)
	reqLabel.TextScaled = true
	reqLabel.TextWrapped = true
	reqLabel.Text = "Next: 200 Scrap"
	reqLabel.Parent = frame
	titanRequirementLabel = reqLabel
end

local function updateTitanProgress(titanModelInstance: Model)
	local stageAttr = titanModelInstance:GetAttribute("TitanStage")
	local integrityAttr = titanModelInstance:GetAttribute("TitanIntegrity")
	local stage = if typeof(stageAttr) == "number" then math.floor(stageAttr :: number) else 0
	local intVal = if typeof(integrityAttr) == "number" then (integrityAttr :: number) else 100

	if titanStageLabel then
		titanStageLabel.Text = ("TITAN - STAGE %d/4"):format(stage)
	end
	if titanIntegrityFill then
		titanIntegrityFill.Size = UDim2.fromScale(math.clamp(intVal / 100, 0, 1), 1)
		if intVal > 60 then
			titanIntegrityFill.BackgroundColor3 = Color3.fromRGB(80, 200, 100)
		elseif intVal > 30 then
			titanIntegrityFill.BackgroundColor3 = Color3.fromRGB(255, 180, 50)
		else
			titanIntegrityFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
		end
	end
	if titanIntegrityBar then
		local intLabel = titanIntegrityBar:FindFirstChild("IntLabel")
		if intLabel and intLabel:IsA("TextLabel") then
			intLabel.Text = ("%d%%"):format(math.floor(intVal))
		end
	end
	if titanRequirementLabel then
		local nextStage = stage + 1
		if nextStage > 4 then
			titanRequirementLabel.Text = "All stages complete!"
		else
			local req = Constants.TITAN.Stages[nextStage]
			if req.steel > 0 then
				titanRequirementLabel.Text = ("Next: %d Scrap, %d Steel"):format(req.scrap, req.steel)
			else
				titanRequirementLabel.Text = ("Next: %d Scrap"):format(req.scrap)
			end
		end
	end
end

local function watchTitanAttributes()
	local titanModelInstance: Model? = nil
	for _, tagged in CollectionService:GetTagged("TitanObjective") do
		if tagged:IsA("Model") then
			titanModelInstance = tagged
			break
		end
	end
	if titanModelInstance == nil then
		task.delay(1, watchTitanAttributes)
		return
	end

	updateTitanProgress(titanModelInstance)
	local model = titanModelInstance :: Model
	model:GetAttributeChangedSignal("TitanStage"):Connect(function()
		updateTitanProgress(model)
	end)
	model:GetAttributeChangedSignal("TitanIntegrity"):Connect(function()
		updateTitanProgress(model)
	end)
end

local function showFinalStandBanner()
	local rootGui = PlayerGui:FindFirstChild("MainHUDGui")
	if rootGui == nil or not rootGui:IsA("ScreenGui") then
		return
	end

	if finalStandBanner ~= nil then
		return
	end

	local banner = Instance.new("TextLabel")
	banner.Name = "FinalStandBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0.13, 0)
	banner.Size = UDim2.fromOffset(480, 40)
	banner.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
	banner.BackgroundTransparency = 0.15
	banner.Font = Enum.Font.GothamBlack
	banner.TextColor3 = Color3.fromRGB(255, 230, 100)
	banner.TextScaled = true
	banner.Text = "FINAL STAND - DEFEND THE TITAN"
	banner.Parent = rootGui
	finalStandBanner = banner

	task.spawn(function()
		while finalStandBanner ~= nil and finalStandBanner.Parent ~= nil do
			TweenService:Create(finalStandBanner, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				TextColor3 = Color3.fromRGB(255, 100, 100),
			}):Play()
			task.wait(0.6)
			if finalStandBanner == nil then
				break
			end
			TweenService:Create(finalStandBanner, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				TextColor3 = Color3.fromRGB(255, 230, 100),
			}):Play()
			task.wait(0.6)
		end
	end)
end

local function buildStatsText(): string
	local ok, stats = pcall(function()
		return remotes.RequestSessionStats:InvokeServer()
	end)
	if not ok or type(stats) ~= "table" then
		return ""
	end

	local elapsed = stats.timeElapsed or 0
	local mins = math.floor(elapsed / 60)
	local secs = math.floor(elapsed % 60)
	return string.format(
		"Scrap Gathered: %d\nRats Eliminated: %d\nBuildings Lost: %d\nWaves Survived: %d\nTime: %02d:%02d",
		stats.scrapGathered or 0,
		stats.ratsKilled or 0,
		stats.buildingsLost or 0,
		stats.wavesCompleted or 0,
		mins, secs
	)
end

local function showVictory()
	if victoryGui ~= nil then
		return
	end

	local rootGui = PlayerGui:FindFirstChild("MainHUDGui")
	if rootGui == nil or not rootGui:IsA("ScreenGui") then
		return
	end

	if finalStandBanner ~= nil then
		finalStandBanner:Destroy()
		finalStandBanner = nil
	end

	local overlay = Instance.new("Frame")
	overlay.Name = "VictoryOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(5, 5, 15)
	overlay.BackgroundTransparency = 0.15
	overlay.Parent = rootGui
	victoryGui = overlay

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.8, 0.15)
	title.Position = UDim2.new(0.1, 0, 0.18, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 230, 80)
	title.TextStrokeTransparency = 0.3
	title.Text = "VICTORY"
	title.Parent = overlay

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.fromScale(0.6, 0.06)
	subtitle.Position = UDim2.new(0.2, 0, 0.34, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromRGB(200, 220, 180)
	subtitle.Text = "The Titan stands."
	subtitle.Parent = overlay

	local statsLabel = Instance.new("TextLabel")
	statsLabel.Size = UDim2.new(0.5, 0, 0.3, 0)
	statsLabel.Position = UDim2.new(0.25, 0, 0.44, 0)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Font = Enum.Font.GothamSemibold
	statsLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	statsLabel.TextScaled = true
	statsLabel.TextWrapped = true
	statsLabel.Text = buildStatsText()
	statsLabel.Parent = overlay

	task.delay(6, function()
		local teleOk = pcall(function()
			TeleportService:Teleport(game.PlaceId, LocalPlayer)
		end)
		if not teleOk then
			LocalPlayer:Kick("Victory! Session complete.")
		end
	end)
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

	local steelLabel = Instance.new("TextLabel")
	steelLabel.Name = "StormSteelLabel"
	steelLabel.AnchorPoint = Vector2.new(1, 0)
	steelLabel.Position = UDim2.new(1, -8, 0, 56)
	steelLabel.Size = UDim2.fromOffset(200, 34)
	steelLabel.BackgroundTransparency = 1
	steelLabel.TextColor3 = Color3.fromRGB(110, 190, 255)
	steelLabel.Font = Enum.Font.GothamBold
	steelLabel.TextScaled = true
	steelLabel.Text = "Storm Steel: 0"
	steelLabel.Visible = false
	steelLabel.Parent = scrapFrame
	stormSteelLabel = steelLabel

	local waveLabel = Instance.new("TextLabel")
	waveLabel.Name = "WaveTimer"
	waveLabel.AnchorPoint = Vector2.new(0.5, 0)
	waveLabel.Position = UDim2.new(0.5, 0, 0.095, 0)
	waveLabel.Size = UDim2.fromOffset(300, 28)
	waveLabel.BackgroundTransparency = 1
	waveLabel.TextColor3 = Color3.fromRGB(255, 193, 64)
	waveLabel.Font = Enum.Font.RobotoMono
	waveLabel.TextScaled = false
	waveLabel.TextSize = 20
	waveLabel.Text = "NEXT SWARM: 00:00"
	waveLabel.Parent = gui
	waveTimerLabel = waveLabel

	local threat = Instance.new("TextLabel")
	threat.Name = "ThreatBanner"
	threat.AnchorPoint = Vector2.new(0.5, 0)
	threat.Position = UDim2.new(0.5, 0, 0.1, 0)
	threat.Size = UDim2.fromOffset(520, 46)
	threat.BackgroundColor3 = Color3.fromRGB(172, 35, 35)
	threat.BackgroundTransparency = 1
	threat.TextTransparency = 1
	threat.TextColor3 = Color3.fromRGB(255, 255, 255)
	threat.TextScaled = true
	threat.Font = Enum.Font.GothamBlack
	threat.Text = ""
	threat.Parent = gui
	threatLabel = threat

	local stormBanner = Instance.new("TextLabel")
	stormBanner.Name = "StormBanner"
	stormBanner.AnchorPoint = Vector2.new(0.5, 0)
	stormBanner.Position = UDim2.new(0.5, 0, 0.17, 0)
	stormBanner.Size = UDim2.fromOffset(560, 44)
	stormBanner.BackgroundColor3 = Color3.fromRGB(120, 80, 40)
	stormBanner.BackgroundTransparency = 1
	stormBanner.TextTransparency = 1
	stormBanner.TextColor3 = Color3.fromRGB(255, 230, 190)
	stormBanner.Font = Enum.Font.GothamBlack
	stormBanner.TextScaled = true
	stormBanner.Text = "SCRAP STORM INCOMING"
	stormBanner.Parent = gui
	stormBannerLabel = stormBanner

	local tetherLabel = Instance.new("TextLabel")
	tetherLabel.Name = "TetherStatus"
	tetherLabel.AnchorPoint = Vector2.new(0.5, 0)
	tetherLabel.Position = UDim2.new(0.5, 0, 0.23, 0)
	tetherLabel.Size = UDim2.fromOffset(360, 34)
	tetherLabel.BackgroundTransparency = 1
	tetherLabel.TextColor3 = Color3.fromRGB(255, 230, 180)
	tetherLabel.TextTransparency = 1
	tetherLabel.Font = Enum.Font.GothamBold
	tetherLabel.TextScaled = true
	tetherLabel.Text = "Tethers: 0/0 ACTIVE"
	tetherLabel.Parent = gui
	tetherStatusLabel = tetherLabel

	createToolbar(gui)
	createTitanProgressPanel(gui)
	createDebugPanel(gui)
end

local function showThreatBanner(buildingName: string)
	if threatLabel == nil then
		return
	end

	threatLabel.Text = ("THREAT DETECTED - %s"):format(buildingName)
	local fadeIn = TweenService:Create(threatLabel, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.2,
		TextTransparency = 0,
	})
	fadeIn:Play()

	task.delay(2, function()
		if threatLabel == nil then
			return
		end
		local fadeOut = TweenService:Create(threatLabel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
			TextTransparency = 1,
		})
		fadeOut:Play()
	end)
end

local function showStormBanner()
	if stormBannerLabel == nil then
		return
	end

	TweenService:Create(stormBannerLabel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.2,
		TextTransparency = 0,
	}):Play()
end

local function hideStormBanner()
	if stormBannerLabel == nil then
		return
	end

	TweenService:Create(stormBannerLabel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = 1,
		TextTransparency = 1,
	}):Play()
end

local function updateTetherStatus(activePads: number, requiredPads: number)
	if tetherStatusLabel == nil then
		return
	end

	if requiredPads <= 0 then
		tetherStatusLabel.Text = ""
		TweenService:Create(tetherStatusLabel, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { TextTransparency = 1 }):Play()
		return
	end

	tetherStatusLabel.Text = ("Tethers: %d/%d ACTIVE"):format(activePads, requiredPads)
	TweenService:Create(tetherStatusLabel, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { TextTransparency = 0 }):Play()
end

local function clearRepairMinigame()
	if repairRenderConnection ~= nil then
		repairRenderConnection:Disconnect()
		repairRenderConnection = nil
	end
	if repairInputConnection ~= nil then
		repairInputConnection:Disconnect()
		repairInputConnection = nil
	end
	if activeRepairMinigame ~= nil then
		activeRepairMinigame:Destroy()
		activeRepairMinigame = nil
	end
end

function MainHUD.ShowRepairMinigame(drillPart: BasePart)
	if not isInitialized then
		return
	end

	local rootGui = PlayerGui:FindFirstChild("MainHUDGui")
	if rootGui == nil or not rootGui:IsA("ScreenGui") then
		return
	end

	clearRepairMinigame()

	local frame = Instance.new("Frame")
	frame.Name = "RepairMinigame"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 0.86, 0)
	frame.Size = UDim2.fromOffset(360, 92)
	frame.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	frame.BackgroundTransparency = 0.15
	frame.Parent = rootGui
	activeRepairMinigame = frame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -10, 0, 28)
	title.Position = UDim2.fromOffset(5, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(220, 240, 255)
	title.TextScaled = true
	title.Text = "Pressure Hiss - Click / Press E"
	title.Parent = frame

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBackground"
	barBg.AnchorPoint = Vector2.new(0.5, 0)
	barBg.Position = UDim2.new(0.5, 0, 0, 42)
	barBg.Size = UDim2.fromOffset(320, 28)
	barBg.BackgroundColor3 = Color3.fromRGB(70, 70, 75)
	barBg.BorderSizePixel = 0
	barBg.Parent = frame

	local successWidth = math.clamp(Constants.MAINTENANCE.MinigameSuccessZoneWidth, 0.08, 0.45)
	local successStart = math.random() * (1 - successWidth)

	local successZone = Instance.new("Frame")
	successZone.Name = "SuccessZone"
	successZone.Size = UDim2.new(successWidth, 0, 1, 0)
	successZone.Position = UDim2.new(successStart, 0, 0, 0)
	successZone.BackgroundColor3 = Color3.fromRGB(90, 205, 115)
	successZone.BorderSizePixel = 0
	successZone.Parent = barBg

	local needleWidth = 0.02
	local needle = Instance.new("Frame")
	needle.Name = "Needle"
	needle.AnchorPoint = Vector2.new(0.5, 0)
	needle.Size = UDim2.new(needleWidth, 0, 1, 0)
	needle.Position = UDim2.new(0, 0, 0, 0)
	needle.BackgroundColor3 = Color3.fromRGB(255, 210, 70)
	needle.BorderSizePixel = 0
	needle.Parent = barBg

	local feedback = Instance.new("TextLabel")
	feedback.Name = "Feedback"
	feedback.Size = UDim2.new(1, -10, 0, 22)
	feedback.Position = UDim2.new(0, 5, 1, -25)
	feedback.BackgroundTransparency = 1
	feedback.Font = Enum.Font.GothamBold
	feedback.TextScaled = true
	feedback.Text = ""
	feedback.Parent = frame

	local progress = 0
	local resolved = false
	local minigameSpeed = math.max(0.5, Constants.MAINTENANCE.MinigameBarSpeed)
	local successEnd = successStart + successWidth

	local function finish(success: boolean)
		if resolved then
			return
		end
		resolved = true

		if repairRenderConnection ~= nil then
			repairRenderConnection:Disconnect()
			repairRenderConnection = nil
		end
		if repairInputConnection ~= nil then
			repairInputConnection:Disconnect()
			repairInputConnection = nil
		end

		remotes.RepairMinigameResult:FireServer(drillPart, success)
		if success then
			feedback.Text = ("+%d Stability!"):format(Constants.MAINTENANCE.WrenchSuccessRestore)
			feedback.TextColor3 = Color3.fromRGB(120, 245, 120)
			playUISound(AudioManifest.MinigameSuccess, 0.4)
		else
			feedback.Text = "CLOGGED!"
			feedback.TextColor3 = Color3.fromRGB(255, 110, 110)
			playUISound(AudioManifest.MinigameFail, 0.35)
		end

		local fadeTween = TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		})
		local titleTween = TweenService:Create(title, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
		})
		local feedbackTween = TweenService:Create(feedback, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
		})
		fadeTween:Play()
		titleTween:Play()
		feedbackTween:Play()
		task.delay(0.5, function()
			if activeRepairMinigame == frame then
				clearRepairMinigame()
			end
		end)
	end

	local function submitAttempt()
		local hitPoint = progress
		if hitPoint >= successStart and hitPoint <= successEnd then
			finish(true)
		else
			finish(false)
		end
	end

	repairInputConnection = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or resolved then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.E then
			submitAttempt()
		end
	end)

	repairRenderConnection = RunService.RenderStepped:Connect(function(dt: number)
		if resolved then
			return
		end

		progress += dt * minigameSpeed
		needle.Position = UDim2.new(math.clamp(progress, 0, 1), 0, 0, 0)

		if progress >= 1 then
			finish(false)
		end
	end)
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
	remotes.StormSteelUpdated.OnClientEvent:Connect(function(newStormSteel: number)
		updateStormSteel(newStormSteel)
	end)
	remotes.ThreatDetected.OnClientEvent:Connect(function(buildingName: string, _position: Vector3)
		showThreatBanner(buildingName)
	end)
	remotes.StormStarted.OnClientEvent:Connect(function()
		showStormBanner()
	end)
	remotes.StormEnded.OnClientEvent:Connect(function()
		hideStormBanner()
		updateTetherStatus(0, 0)
	end)
	remotes.TetherStatus.OnClientEvent:Connect(function(activePads: number, requiredPads: number)
		updateTetherStatus(activePads, requiredPads)
	end)
	remotes.BlueprintFinished.OnClientEvent:Connect(function(_blueprintId: string, _position: Vector3)
		refreshBuildCosts()
	end)
	remotes.UpdateWaveTimer.OnClientEvent:Connect(function(secondsRemaining: number, _nextWaveTime: number)
		updateWaveTimer(secondsRemaining)
	end)
	remotes.GlobalGameOver.OnClientEvent:Connect(function()
		showGameOver()
	end)
	remotes.GlobalVictory.OnClientEvent:Connect(function()
		showVictory()
	end)
	remotes.FinalStandStarted.OnClientEvent:Connect(function()
		showFinalStandBanner()
	end)
	remotes.TitanStageCompleted.OnClientEvent:Connect(function(_stage: number)
		playUISound(AudioManifest.StageComplete, 0.5)
		if titanStageLabel ~= nil then
			local original = titanStageLabel.TextColor3
			TweenService:Create(titanStageLabel, TweenInfo.new(0.15), { TextColor3 = Color3.fromRGB(255, 255, 100) }):Play()
			task.delay(0.3, function()
				if titanStageLabel ~= nil then
					TweenService:Create(titanStageLabel, TweenInfo.new(0.3), { TextColor3 = original }):Play()
				end
			end)
		end
	end)

	local ok, snapshot = pcall(function()
		return remotes.RequestEconomyState:InvokeServer()
	end)
	if ok and type(snapshot) == "table" then
		local scrapValue = snapshot.scrap
		if type(scrapValue) == "number" then
			updateScrap(scrapValue)
		end

		local stormSteelValue = snapshot.stormSteel
		if type(stormSteelValue) == "number" then
			updateStormSteel(stormSteelValue)
		end
	end

	refreshBuildCosts()

	local nextWaveTimeAttr = remotes.Folder:GetAttribute("NextWaveTime")
	if typeof(nextWaveTimeAttr) == "number" then
		local remaining = math.max(0, (nextWaveTimeAttr :: number) - os.time())
		updateWaveTimer(remaining)
	end

	RunService.Heartbeat:Connect(updateDismantleBars)

	task.spawn(watchTitanAttributes)
end

function MainHUD.ConnectWaveTimerZero(callback: () -> ()): RBXScriptConnection
	return waveTimerSignal.Event:Connect(callback)
end

return MainHUD
