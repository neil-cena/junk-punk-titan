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
local VisualManifest = require(Shared:WaitForChild("VisualManifest"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Platform = require(Shared:WaitForChild("Platform"))
local BlueprintController = require(script.Parent.Parent:WaitForChild("Controllers"):WaitForChild("BlueprintController"))
local RepairMinigameUI = require(script.Parent:WaitForChild("RepairMinigameUI"))
local EndScreenUI = require(script.Parent:WaitForChild("EndScreenUI"))
local Theme = require(script.Parent:WaitForChild("Theme"))

type BuildingType = "Turret" | "Drill" | "Wall"

local MainHUD = {}

local remotes = Remotes.Get()
local isMobile = Platform.IsMobile
local isInitialized = false
local currentScrap = 0
local currentStormSteel = 0
local lastWaveSeconds = -1
local pickupHistory: { { t: number, v: number } } = {}
local pickupAccumulator = 0
local lastScrapUpdateAt = os.clock()
local scrapLabel: TextLabel? = nil
local stormSteelLabel: TextLabel? = nil
local waveTimerLabel: TextLabel? = nil
local stormTimerLabel: TextLabel? = nil
local waveSeasonLabel: TextLabel? = nil
local dismantleBars: { [BasePart]: BillboardGui } = {}
local buildCostButtons: { [BuildingType]: TextButton } = {}
local roleScreen: ScreenGui? = nil
local threatLabel: TextLabel? = nil
local stormBannerLabel: TextLabel? = nil
local tetherStatusLabel: TextLabel? = nil
local wavePulseTween: Tween? = nil
local wavePulseBackTween: Tween? = nil
local waveTimerSignal = Instance.new("BindableEvent")
local titanStageLabel: TextLabel? = nil
local titanIntegrityFill: Frame? = nil
local titanIntegrityBar: Frame? = nil
local titanRequirementLabel: TextLabel? = nil
local titanDistanceLabel: TextLabel? = nil
local buildProgressFrame: Frame? = nil
local buildProgressFill: Frame? = nil
local buildProgressLabel: TextLabel? = nil
local toolPanelFrame: Frame? = nil
local toolPanelButton: TextButton? = nil
local hudWatchdogStarted = false
local upgradeBanner: TextLabel? = nil
local sandboxMode = false
local currentMaxBuildLevel = 1
local currentWaveNumber = 0

local function updateWaveSeasonLabel(waveNumber: number, _patternIdx: number)
	currentWaveNumber = waveNumber
	if waveSeasonLabel == nil then
		return
	end
	waveSeasonLabel.Text = ""
end

local SHOTGUN_TOOL_NAME = "RustyShotgun"
local WRENCH_TOOL_NAME = "RustyWrench"

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

local function showUpgradeBanner(stage: number)
	local gui = PlayerGui:FindFirstChild("MainHUDGui")
	if gui == nil or not gui:IsA("ScreenGui") then
		return
	end

	local maxLevel = math.clamp(stage + 1, 1, Constants.BUILDING.MaxLevel)
	currentMaxBuildLevel = maxLevel

	if maxLevel <= 1 then
		return
	end

	local banner = Instance.new("TextLabel")
	banner.Name = "UpgradeBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.new(0.5, 0, 0.35, 0)
	banner.Size = UDim2.new(0.5, 0, 0, 44)
	banner.BackgroundColor3 = Theme.Colors.Accent
	banner.BackgroundTransparency = 0.15
	banner.Font = Enum.Font.GothamBold
	banner.TextScaled = true
	banner.TextColor3 = Theme.Colors.TextPrimary
	banner.Text = ("BUILDING UPGRADES Lv.%d UNLOCKED!"):format(maxLevel)
	banner.TextStrokeTransparency = 0.4
	banner.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = banner

	local fadeIn = TweenService:Create(banner, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.55, 0, 0, 50),
	})
	fadeIn:Play()

	task.delay(3.5, function()
		if banner.Parent ~= nil then
			local fadeOut = TweenService:Create(banner, TweenInfo.new(0.5), {
				BackgroundTransparency = 1,
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			})
			fadeOut:Play()
			task.delay(0.55, function()
				if banner.Parent ~= nil then
					banner:Destroy()
				end
			end)
		end
	end)
end

local function enterSandboxMode()
	sandboxMode = true
	if waveTimerLabel ~= nil then
		waveTimerLabel.Text = "FREE ROAM"
		waveTimerLabel.TextColor3 = Theme.Colors.Accent
	end
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
	deltaLabel.TextColor3 = if delta >= 0 then Theme.Colors.ScrapDeltaPositive else Theme.Colors.ScrapDeltaNegative
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

local function computeDrillRate(): number
	local total = 0
	local baseRate = Constants.MAINTENANCE.DrillBaseOutput / Constants.MAINTENANCE.ResourceTickSeconds
	local lv1Stats = Constants.BUILDING_UPGRADES.Drill[1]
	for _, drill in CollectionService:GetTagged("Drill") do
		if drill:IsA("BasePart") and drill.Parent ~= nil then
			local isClogged = drill:GetAttribute("IsClogged")
			if isClogged == true then
				continue
			end

			local stabilityAttr = drill:GetAttribute("Stability")
			local stability = if typeof(stabilityAttr) == "number" then math.clamp(stabilityAttr :: number, 0, 100) else 100
			local efficiency = if stability >= 80 then 1 elseif stability >= 20 then 0.5 else 0
			if efficiency <= 0 then
				continue
			end

			local overclockMult = if drill:GetAttribute("IsOverclocked") == true
				then Constants.MAINTENANCE.OverclockMultiplier
				else 1

			local drillLevelAttr = drill:GetAttribute("BuildingLevel")
			local drillLevel = if typeof(drillLevelAttr) == "number" then math.floor(drillLevelAttr :: number) else 1
			local levelStats = Constants.BUILDING_UPGRADES.Drill[drillLevel]
			local levelMult = 1
			if levelStats ~= nil and lv1Stats ~= nil then
				local currentRate = levelStats.scrapPerTick / levelStats.tickInterval
				local lv1Rate = lv1Stats.scrapPerTick / lv1Stats.tickInterval
				if lv1Rate > 0 then
					levelMult = currentRate / lv1Rate
				end
			end

			total += baseRate * levelMult * efficiency * overclockMult
		end
	end

	return total
end

local function getPickupRate(): number
	local now = os.clock()
	local cutoff = now - 10
	local pruned: { { t: number, v: number } } = {}
	for _, entry in pickupHistory do
		if entry.t >= cutoff then
			table.insert(pruned, entry)
		end
	end
	pickupHistory = pruned
	if #pickupHistory < 2 then
		return 0
	end
	local oldest = pickupHistory[1]
	local newest = pickupHistory[#pickupHistory]
	local elapsed = newest.t - oldest.t
	if elapsed < 0.5 then
		return 0
	end
	return (newest.v - oldest.v) / elapsed
end

local function refreshScrapLabel()
	if scrapLabel == nil then
		return
	end

	local pickupRate = getPickupRate()
	local drillRate = computeDrillRate()
	local totalRate = math.max(0, pickupRate + drillRate)
	scrapLabel.Text = ("Scrap: %d (+%.1f/s)"):format(currentScrap, totalRate)
end

local function updateScrap(newScrap: number)
	local previous = currentScrap
	local now = os.clock()
	local elapsed = math.max(0, now - lastScrapUpdateAt)
	lastScrapUpdateAt = now

	local predictedDrillGain = computeDrillRate() * elapsed
	currentScrap = newScrap
	local delta = newScrap - previous
	local pickupDelta = 0
	if delta > 0 then
		pickupDelta = math.max(0, delta - predictedDrillGain)
	end
	pickupAccumulator += pickupDelta
	table.insert(pickupHistory, { t = now, v = pickupAccumulator })

	if scrapLabel ~= nil then
		refreshScrapLabel()
		animateScrapPop(scrapLabel)
	end

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
	local abs = math.abs(secondsRemaining)
	local seconds = math.max(0, math.floor(abs + 0.5))
	local mins = math.floor(seconds / 60)
	local secs = seconds % 60
	if secondsRemaining < 0 then
		return ("SWARM ENDS: %02d:%02d"):format(mins, secs)
	end
	return ("NEXT SWARM: %02d:%02d"):format(mins, secs)
end

local function formatStormCountdown(remainingSeconds: number): string
	local mins = math.floor(remainingSeconds / 60)
	local secs = math.floor(remainingSeconds % 60 + 0.5)
	return ("NEXT STORM: %02d:%02d"):format(mins, secs)
end

local function updateStormTimer()
	if sandboxMode or stormTimerLabel == nil then
		return
	end
	local nextStormAttr = remotes.Folder:GetAttribute("NextStormTime")
	if typeof(nextStormAttr) ~= "number" then
		stormTimerLabel.Text = ""
		stormTimerLabel.Visible = false
		return
	end
	local nextStorm = nextStormAttr :: number
	if nextStorm <= 0 then
		stormTimerLabel.Text = "STORM ACTIVE"
		stormTimerLabel.TextColor3 = Theme.Colors.WaveTimerActive
		stormTimerLabel.Visible = true
		return
	end
	local remaining = math.max(0, nextStorm - os.time())
	stormTimerLabel.Text = formatStormCountdown(remaining)
	stormTimerLabel.TextColor3 = if remaining <= 60 then Theme.Colors.WaveTimerUrgent else Theme.Colors.TextMuted
	stormTimerLabel.Visible = true
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
	if sandboxMode then
		return
	end
	local abs = math.abs(secondsRemaining)
	local seconds = math.max(0, math.floor(abs + 0.5))
	local isSwarmActive = secondsRemaining < 0
	if waveTimerLabel == nil then
		lastWaveSeconds = seconds
		return
	end

	waveTimerLabel.Text = formatTimer(secondsRemaining)
	if isSwarmActive then
		waveTimerLabel.TextColor3 = Theme.Colors.WaveTimerActive
	elseif seconds > 10 then
		waveTimerLabel.TextColor3 = Theme.Colors.WaveTimerNormal
	else
		waveTimerLabel.TextColor3 = Theme.Colors.WaveTimerUrgent
	end

	if not isSwarmActive and seconds <= 5 and seconds ~= lastWaveSeconds then
		pulseWaveTimer()
	end

	if seconds == 0 and lastWaveSeconds ~= 0 and not isSwarmActive then
		waveTimerSignal:Fire()
	end
	lastWaveSeconds = seconds
end

local function showGameOver()
	local rootGui = PlayerGui:FindFirstChild("MainHUDGui")
	if rootGui == nil or not rootGui:IsA("ScreenGui") then
		return
	end
	EndScreenUI.ShowGameOver(rootGui, remotes)
end

local function ensureBar(part: BasePart): BillboardGui
	local existing = dismantleBars[part]
	if existing ~= nil then
		return existing
	end

	local bar = Instance.new("BillboardGui")
	bar.Name = "DismantleBar"
	bar.Size = UDim2.fromOffset(80, 14)
	bar.StudsOffset = Vector3.new(0, part.Size.Y * 0.8, 0)
	bar.AlwaysOnTop = true
	bar.Enabled = false
	bar.Parent = part

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Theme.Colors.DismantleBarBg
	bg.BorderSizePixel = 0
	bg.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Theme.Colors.DismantleBarFill
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local text = Instance.new("TextLabel")
	text.Name = "Label"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Theme.Colors.DismantleBarText
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

			if isFixer and progress > 0 then
				bg.BorderSizePixel = 2
				local pulse = (math.sin(os.clock() * 6) + 1) * 0.5
				bg.BorderColor3 = Color3.new(
					(math.floor(255 * pulse + 180 * (1 - pulse))) / 255,
					(math.floor(215 * pulse + 100 * (1 - pulse))) / 255,
					(math.floor(85 * pulse + 30 * (1 - pulse))) / 255
				)
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

local ROLE_DESCRIPTIONS = {
	Scrapper = "Fastest runner. Gains bonus scrap\nfrom loot pickups across the map.",
	Fixer = "Repair specialist. Buildings and upgrades\ncost less for the whole base setup.",
	Enforcer = "Combat expert. Strongest direct damage\nfor holding wave pressure at the base.",
}

local ROLE_COLORS = Theme.Colors.RoleColors

local function makeRoleButton(parent: Instance, roleName: string, xScale: number)
	local roleDef = Constants.ROLE_DEFINITIONS[roleName]

	local card = Instance.new("Frame")
	card.Name = roleName .. "Card"
	card.Size = UDim2.new(0.25, 0, 0.5, 0)
	card.Position = UDim2.new(xScale, 0, 0.25, 0)
	card.BackgroundColor3 = Theme.Colors.RoleCardBg
	card.BackgroundTransparency = 0.1
	card.Parent = parent

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 8)
	cardCorner.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "RoleName"
	nameLabel.Size = UDim2.new(1, 0, 0, 36)
	nameLabel.Position = UDim2.fromOffset(0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = ROLE_COLORS[roleName] or Theme.Colors.TextPrimary
	nameLabel.Text = string.upper(roleName)
	nameLabel.Parent = card

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Description"
	descLabel.Size = UDim2.new(1, -16, 0, 50)
	descLabel.Position = UDim2.new(0, 8, 0, 48)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextScaled = true
	descLabel.TextWrapped = true
	descLabel.TextColor3 = Theme.Colors.TextPrimary
	descLabel.Text = ROLE_DESCRIPTIONS[roleName] or ""
	descLabel.Parent = card

	local statsLabel = Instance.new("TextLabel")
	statsLabel.Name = "Stats"
	statsLabel.Size = UDim2.new(1, -16, 0, 40)
	statsLabel.Position = UDim2.new(0, 8, 0, 102)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Font = Enum.Font.GothamSemibold
	statsLabel.TextScaled = true
	statsLabel.TextColor3 = Theme.Colors.TextMuted
	if roleName == "Fixer" then
		local buildDiscount = math.max(0, (1 - (roleDef.buildCostMult or 1)) * 100)
		statsLabel.Text = string.format("BUILD -%.0f%%  RPR x%.1f", buildDiscount, roleDef.repairMult)
	elseif roleName == "Scrapper" then
		statsLabel.Text = string.format("SPD x%.1f  LOOT x%.1f", roleDef.speedMult, roleDef.lootBonusMult or 1)
	else
		statsLabel.Text = string.format("DMG x%.1f  SPD x%.1f", roleDef.damageMult, roleDef.speedMult)
	end
	statsLabel.Parent = card

	local button = Instance.new("TextButton")
	button.Name = roleName .. "Button"
	button.Size = if isMobile then UDim2.new(0.85, 0, 0, 52) else UDim2.new(0.8, 0, 0, 36)
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position = if isMobile then UDim2.new(0.5, 0, 1, -62) else UDim2.new(0.5, 0, 1, -48)
	button.BackgroundColor3 = ROLE_COLORS[roleName] or Theme.Colors.PanelStroke
	button.TextColor3 = Theme.Colors.Panel
	button.TextScaled = true
	button.Font = Enum.Font.GothamBold
	button.Text = "SELECT"
	button.Parent = card

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = button

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
	overlay.BackgroundColor3 = Theme.Colors.RoleOverlay
	overlay.BackgroundTransparency = 0.2
	overlay.Parent = screen

	local chooseTitle = Instance.new("TextLabel")
	chooseTitle.Name = "ChooseTitle"
	chooseTitle.Size = UDim2.new(1, 0, 0.12, 0)
	chooseTitle.Position = UDim2.new(0, 0, 0.08, 0)
	chooseTitle.BackgroundTransparency = 1
	chooseTitle.Font = Enum.Font.GothamBlack
	chooseTitle.TextScaled = true
	chooseTitle.TextColor3 = Theme.Colors.RoleTitle
	chooseTitle.TextStrokeTransparency = 0.5
	chooseTitle.Text = "CHOOSE YOUR ROLE"
	chooseTitle.Parent = overlay

	makeRoleButton(overlay, "Scrapper", 0.04)
	makeRoleButton(overlay, "Fixer", 0.36)
	makeRoleButton(overlay, "Enforcer", 0.68)
end

local function createToolbar(parent: Instance)
	local frame = Instance.new("Frame")
	frame.Name = "BuildToolbar"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = if isMobile then UDim2.new(0.5, 0, 0.84, 0) else UDim2.new(0.5, 0, 0.97, 0)
	frame.Size = if isMobile then UDim2.new(0.46, 0, 0, 100) else UDim2.new(0.3, 0, 0, 88)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BackgroundTransparency = 0.2
	frame.Visible = not isMobile
	frame.Parent = parent
	Theme.StylePanel(frame, 8)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame

	local slots: { { name: BuildingType, key: string } } = {
		{ name = "Turret", key = "1" },
		{ name = "Drill", key = "2" },
		{ name = "Wall", key = "3" },
	}

	for _, info in slots do
		local slot = Instance.new("TextButton")
		slot.Name = info.name .. "Slot"
		slot.Size = if isMobile then UDim2.new(0.3, 0, 0, 82) else UDim2.new(0.3, 0, 0, 72)
		slot.BackgroundColor3 = Theme.Colors.PanelAlt
		slot.TextColor3 = Theme.Colors.TextPrimary
		slot.TextScaled = true
		slot.Font = Enum.Font.GothamBold
		slot.Text = if isMobile
			then string.format("%s\n$%d", info.name, Constants.BASE_COSTS[info.name])
			else string.format("%s\n$%d\n[%s]", info.name, Constants.BASE_COSTS[info.name], info.key)
		slot.Parent = frame
		buildCostButtons[info.name] = slot

		Theme.StyleButton(slot)

		local colorSwatch = Instance.new("Frame")
		colorSwatch.Name = "Swatch"
		colorSwatch.Size = UDim2.fromOffset(12, 12)
		colorSwatch.Position = UDim2.fromOffset(4, 4)
		colorSwatch.BackgroundColor3 = VisualManifest.Buildings.BaseColors[info.name]
		colorSwatch.BorderSizePixel = 0
		colorSwatch.Parent = slot

		slot.MouseButton1Click:Connect(function()
			playUISound(AudioManifest.UIClick)
			BlueprintController.StartPlacing(info.name)
		end)

		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "Icon"
		viewport.Size = UDim2.fromOffset(24, 24)
		viewport.Position = UDim2.fromOffset(4, 22)
		viewport.BackgroundTransparency = 1
		viewport.Parent = slot

		local iconCamera = Instance.new("Camera")
		iconCamera.Parent = viewport
		viewport.CurrentCamera = iconCamera

		local iconModel = Instance.new("Model")
		iconModel.Name = "IconModel"
		iconModel.Parent = viewport

		local iconPart = Instance.new("Part")
		iconPart.Size = Vector3.new(1.6, if info.name == "Wall" then 2 else 1.2, if info.name == "Drill" then 0.9 else 1.4)
		iconPart.Material = Enum.Material.Metal
		iconPart.Color = VisualManifest.Buildings.BaseColors[info.name]
		iconPart.Anchored = true
		iconPart.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(-10), math.rad(35), 0)
		iconPart.Parent = iconModel
		iconCamera.CFrame = CFrame.new(Vector3.new(2.8, 2.3, 2.8), Vector3.zero)
	end

	local hintLabel = Instance.new("TextLabel")
	hintLabel.Name = "RotateHint"
	hintLabel.AnchorPoint = Vector2.new(0.5, 0)
	hintLabel.Position = UDim2.new(0.5, 0, 0.975, 0)
	hintLabel.Size = UDim2.new(0.22, 0, 0, 16)
	hintLabel.BackgroundTransparency = 1
	hintLabel.Font = Enum.Font.Gotham
	hintLabel.TextScaled = true
	hintLabel.TextColor3 = Theme.Colors.TextMuted
	hintLabel.Visible = not isMobile
	hintLabel.Text = if isMobile then "" else "[R] Rotate  |  [RMB/Esc] Cancel  |  [X] Remove"
	hintLabel.Parent = parent
end

local function getRoleToolName(): string?
	local role = LocalPlayer:GetAttribute("Role")
	if role == "Enforcer" then
		return SHOTGUN_TOOL_NAME
	elseif role == "Fixer" then
		return WRENCH_TOOL_NAME
	end
	return nil
end

local function isRoleToolEquipped(toolName: string): boolean
	local character = LocalPlayer.Character
	return character ~= nil and character:FindFirstChild(toolName) ~= nil
end

local function updateToolPanelVisual()
	if toolPanelFrame == nil or toolPanelButton == nil then
		return
	end
	if isMobile then
		toolPanelFrame.Visible = false
		return
	end

	local toolName = getRoleToolName()
	if toolName == nil then
		toolPanelFrame.Visible = false
		return
	end

	toolPanelFrame.Visible = true
	if toolName == SHOTGUN_TOOL_NAME then
		toolPanelButton.Text = "SHOTGUN"
	else
		toolPanelButton.Text = "WRENCH"
	end

	if isRoleToolEquipped(toolName) then
		toolPanelButton.BackgroundColor3 = Theme.Colors.ToolEquipped
	else
		toolPanelButton.BackgroundColor3 = Theme.Colors.ToolUnequipped
	end
end

local function toggleRoleTool()
	local toolName = getRoleToolName()
	if toolName == nil then
		return
	end

	local character = LocalPlayer.Character
	if character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end

	if isRoleToolEquipped(toolName) then
		humanoid:UnequipTools()
		updateToolPanelVisual()
		return
	end

	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if backpack == nil then
		return
	end
	local tool = backpack:FindFirstChild(toolName)
	if tool ~= nil and tool:IsA("Tool") then
		humanoid:EquipTool(tool)
		task.defer(updateToolPanelVisual)
	end
end

local function createToolPanel(parent: Instance)
	local panel = Instance.new("Frame")
	panel.Name = "ToolPanel"
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Position = if isMobile then UDim2.new(1, -10, 0.72, 0) else UDim2.new(1, -6, 0.56, 0)
	panel.Size = if isMobile then UDim2.fromOffset(72, 80) else UDim2.fromOffset(56, 64)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BackgroundTransparency = 0.15
	panel.Visible = false
	panel.Parent = parent
	Theme.StylePanel(panel, 8)

	local button = Instance.new("TextButton")
	button.Name = "ToolToggle"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = if isMobile then UDim2.fromOffset(62, 68) else UDim2.fromOffset(46, 50)
	button.BackgroundColor3 = Theme.Colors.PanelAlt
	button.TextColor3 = Theme.Colors.TextPrimary
	button.TextScaled = true
	button.Font = Enum.Font.GothamBold
	button.Text = "TOOL"
	button.Parent = panel
	button.MouseButton1Click:Connect(function()
		playUISound(AudioManifest.UIClick)
		toggleRoleTool()
	end)
	Theme.StyleButton(button)

	toolPanelFrame = panel
	toolPanelButton = button
	updateToolPanelVisual()

	LocalPlayer:GetAttributeChangedSignal("Role"):Connect(function()
		updateToolPanelVisual()
	end)

	LocalPlayer.CharacterAdded:Connect(function(character)
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				updateToolPanelVisual()
			end
		end)
		character.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				updateToolPanelVisual()
			end
		end)
		task.defer(updateToolPanelVisual)
	end)

	task.spawn(function()
		while toolPanelFrame ~= nil and toolPanelFrame.Parent ~= nil do
			updateToolPanelVisual()
			task.wait(0.25)
		end
	end)
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
			local newText = if isMobile
				then string.format("%s\n$%d", info.name, math.floor(costValue + 0.5))
				else string.format("%s\n$%d\n[%s]", info.name, math.floor(costValue + 0.5), info.key)
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

local function createSettingsPanel(parent: Instance)
	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "SettingsToggle"
	toggleBtn.AnchorPoint = if isMobile then Vector2.new(1, 0) else Vector2.new(1, 1)
	toggleBtn.Position = if isMobile then UDim2.new(1, -2, 0, 10) else UDim2.new(1, -10, 1, -10)
	toggleBtn.Size = if isMobile then UDim2.fromOffset(24, 24) else UDim2.fromOffset(36, 36)
	toggleBtn.BackgroundColor3 = Theme.Colors.PanelAlt
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.TextScaled = true
	toggleBtn.TextColor3 = Theme.Colors.TextPrimary
	toggleBtn.Text = "S"
	toggleBtn.Parent = parent

	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 6)
	toggleCorner.Parent = toggleBtn

	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.AnchorPoint = if isMobile then Vector2.new(1, 0) else Vector2.new(1, 1)
	panel.Position = if isMobile then UDim2.new(1, -2, 0, 38) else UDim2.new(1, -10, 1, -52)
	panel.Size = if isMobile then UDim2.new(0.35, 0, 0, 260) else UDim2.new(0.16, 0, 0, 190)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BackgroundTransparency = 0.1
	panel.Visible = false
	panel.Parent = parent

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = panel

	local panelTitle = Instance.new("TextLabel")
	panelTitle.Size = UDim2.new(1, -10, 0, 24)
	panelTitle.Position = UDim2.fromOffset(5, 4)
	panelTitle.BackgroundTransparency = 1
	panelTitle.Font = Enum.Font.GothamBold
	panelTitle.TextScaled = true
	panelTitle.TextColor3 = Theme.Colors.TextPrimary
	panelTitle.Text = "Settings"
	panelTitle.Parent = panel

	local function createSlider(label: string, yPos: number, initial: number, onChange: (number) -> ())
		local sliderLabel = Instance.new("TextLabel")
		sliderLabel.Size = UDim2.new(1, -16, 0, 16)
		sliderLabel.Position = UDim2.new(0, 8, 0, yPos)
		sliderLabel.BackgroundTransparency = 1
		sliderLabel.Font = Enum.Font.Gotham
		sliderLabel.TextScaled = true
		sliderLabel.TextXAlignment = Enum.TextXAlignment.Left
		sliderLabel.TextColor3 = Theme.Colors.TextMuted
		sliderLabel.Text = label
		sliderLabel.Parent = panel

		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, -16, 0, 8)
		track.Position = UDim2.new(0, 8, 0, yPos + 18)
		track.BackgroundColor3 = Theme.Colors.SliderTrack
		track.BorderSizePixel = 0
		track.Parent = panel

		local trackCorner = Instance.new("UICorner")
		trackCorner.CornerRadius = UDim.new(0.5, 0)
		trackCorner.Parent = track

		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.new(initial, 0, 1, 0)
		fill.BackgroundColor3 = Theme.Colors.SliderFill
		fill.BorderSizePixel = 0
		fill.Parent = track

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0.5, 0)
		fillCorner.Parent = fill

		local clickArea = Instance.new("TextButton")
		clickArea.Size = UDim2.fromScale(1, 1)
		clickArea.BackgroundTransparency = 1
		clickArea.Text = ""
		clickArea.Parent = track

		local dragging = false
		local function updateFromInput(x: number)
			local abs = track.AbsolutePosition.X
			local width = track.AbsoluteSize.X
			if width <= 0 then return end
			local pct = math.clamp((x - abs) / width, 0, 1)
			fill.Size = UDim2.new(pct, 0, 1, 0)
			onChange(pct)
		end

		clickArea.MouseButton1Down:Connect(function()
			dragging = true
		end)
		clickArea.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				updateFromInput(input.Position.X)
			end
		end)
		clickArea.InputChanged:Connect(function(input: InputObject)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				updateFromInput(input.Position.X)
			end
		end)
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				if dragging then
					dragging = false
					updateFromInput(input.Position.X)
				end
			end
		end)
		clickArea.MouseButton1Click:Connect(function()
			local mouse = LocalPlayer:GetMouse()
			updateFromInput(mouse.X)
		end)
	end

	createSlider("Master Volume", 32, 0.5, function(pct)
		SoundService.Volume = pct
	end)

	createSlider("Music Volume", 72, 0.5, function(pct)
		local music = SoundService:FindFirstChild("AmbientMusic")
		if music and music:IsA("Sound") then
			music.Volume = pct * 0.2
		end
	end)

	local qualityLabels = { "LOW", "MED", "HIGH" }
	local initialGraphicsPct = if isMobile then 0 else 1
	local initialGraphicsLabel = if isMobile then "LOW" else "HIGH"
	createSlider("Graphics: " .. initialGraphicsLabel, 112, initialGraphicsPct, function(pct)
		local level = math.clamp(math.floor(pct * 3 + 0.5), 1, 3)
		pcall(function()
			local Controllers = script.Parent.Parent:FindFirstChild("Controllers")
			if Controllers ~= nil then
				local vfxModule = Controllers:FindFirstChild("VFXController")
				if vfxModule ~= nil then
					local vfx = require(vfxModule)
					vfx.SetQuality(level)
				end
			end
		end)
		local sliderLbl = panel:FindFirstChild("GraphicsLabel")
		if sliderLbl ~= nil and sliderLbl:IsA("TextLabel") then
			sliderLbl.Text = "Graphics: " .. (qualityLabels[level] or "HIGH")
		end
	end)
	for _, child in panel:GetChildren() do
		if child:IsA("TextLabel") and child.Text:find("Graphics") then
			child.Name = "GraphicsLabel"
			break
		end
	end

	toggleBtn.MouseButton1Click:Connect(function()
		playUISound(AudioManifest.UIClick)
		panel.Visible = not panel.Visible
	end)
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
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BackgroundTransparency = 0.15
	panel.Parent = parent

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromOffset(220, 26)
	title.Position = UDim2.fromOffset(6, 4)
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Theme.Colors.TextPrimary
	title.TextScaled = true
	title.Text = "Debug Controls"
	title.Parent = panel

	local function addButton(label: string, y: number, callback: () -> ())
		local button = Instance.new("TextButton")
		button.Size = UDim2.fromOffset(210, 30)
		button.Position = UDim2.fromOffset(10, y)
		button.BackgroundColor3 = Theme.Colors.PanelAlt
		button.TextColor3 = Theme.Colors.TextPrimary
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
	frame.Size = if isMobile then UDim2.new(0.17, 0, 0, 80) else UDim2.new(0.14, 0, 0, 110)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BackgroundTransparency = 0.15
	frame.Parent = parent
	Theme.StylePanel(frame, 8)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = if isMobile then UDim2.new(1, -8, 0, 16) else UDim2.new(1, -10, 0, 22)
	titleLabel.Position = UDim2.fromOffset(5, 4)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextColor3 = Theme.Colors.TextPrimary
	titleLabel.TextScaled = true
	titleLabel.Text = "TITAN - STAGE 0/4"
	titleLabel.Parent = frame
	titanStageLabel = titleLabel

	local barBg = Instance.new("Frame")
	barBg.Name = "IntegrityBarBg"
	barBg.Size = if isMobile then UDim2.new(1, -16, 0, 12) else UDim2.new(1, -20, 0, 16)
	barBg.Position = if isMobile then UDim2.new(0, 8, 0, 24) else UDim2.new(0, 10, 0, 30)
	barBg.BackgroundColor3 = Theme.Colors.IntegrityBarBg
	barBg.BorderSizePixel = 0
	barBg.Parent = frame
	titanIntegrityBar = barBg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Theme.Colors.IntegrityGood
	fill.BorderSizePixel = 0
	fill.Parent = barBg
	titanIntegrityFill = fill

	local intLabel = Instance.new("TextLabel")
	intLabel.Name = "IntLabel"
	intLabel.Size = UDim2.fromScale(1, 1)
	intLabel.BackgroundTransparency = 1
	intLabel.Font = Enum.Font.GothamBold
	intLabel.TextColor3 = Theme.Colors.TextPrimary
	intLabel.TextScaled = true
	intLabel.TextStrokeTransparency = 0.3
	intLabel.Text = "100%"
	intLabel.Parent = barBg

	local reqLabel = Instance.new("TextLabel")
	reqLabel.Name = "Requirements"
	reqLabel.Size = if isMobile then UDim2.new(1, -8, 0, 28) else UDim2.new(1, -10, 0, 44)
	reqLabel.Position = if isMobile then UDim2.new(0, 4, 0, 40) else UDim2.new(0, 5, 0, 52)
	reqLabel.BackgroundTransparency = 1
	reqLabel.Font = Enum.Font.GothamSemibold
	reqLabel.TextColor3 = Theme.Colors.TextMuted
	reqLabel.TextScaled = true
	reqLabel.TextWrapped = true
	reqLabel.Text = "Next: 200 Scrap"
	reqLabel.Parent = frame
	titanRequirementLabel = reqLabel

	local distLabel = Instance.new("TextLabel")
	distLabel.Name = "Distance"
	distLabel.Size = UDim2.new(1, -10, 0, 16)
	distLabel.Position = if isMobile then UDim2.new(0, 5, 1, -16) else UDim2.new(0, 5, 0, 96)
	distLabel.BackgroundTransparency = 1
	distLabel.Font = Enum.Font.Gotham
	distLabel.TextScaled = true
	distLabel.TextColor3 = Theme.Colors.TextMuted
	distLabel.Text = ""
	distLabel.Visible = not isMobile
	distLabel.Parent = frame
	titanDistanceLabel = distLabel
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
			titanIntegrityFill.BackgroundColor3 = Theme.Colors.IntegrityGood
		elseif intVal > 30 then
			titanIntegrityFill.BackgroundColor3 = Theme.Colors.IntegrityWarning
		else
			titanIntegrityFill.BackgroundColor3 = Theme.Colors.IntegrityBad
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
	EndScreenUI.ShowFinalStandBanner(rootGui)
end

local function showVictory()
	local rootGui = PlayerGui:FindFirstChild("MainHUDGui")
	if rootGui == nil or not rootGui:IsA("ScreenGui") then
		return
	end
	EndScreenUI.ShowVictory(rootGui, remotes)
end

local function createMainHUD()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MainHUDGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = PlayerGui

	local scrapFrame = Instance.new("Frame")
	scrapFrame.Name = "ScrapFrame"
	scrapFrame.AnchorPoint = if isMobile then Vector2.new(1, 0) else Vector2.new(0.5, 0)
	scrapFrame.Position = if isMobile then UDim2.new(1, -10, 0, 96) else UDim2.new(0.5, 0, 0.02, 0)
	scrapFrame.Size = if isMobile then UDim2.new(0.17, 0, 0, 36) else UDim2.new(0.14, 0, 0, 48)
	scrapFrame.BackgroundColor3 = Theme.Colors.Panel
	scrapFrame.BackgroundTransparency = 0.15
	scrapFrame.Parent = gui
	Theme.StylePanel(scrapFrame, 8)

	local label = Instance.new("TextLabel")
	label.Name = "ScrapLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Theme.Colors.Accent
	label.TextScaled = isMobile
	label.TextSize = if isMobile then 14 else 24
	label.Font = Enum.Font.GothamBold
	label.Text = "Scrap: 0"
	label.Parent = scrapFrame
	scrapLabel = label

	local steelLabel = Instance.new("TextLabel")
	steelLabel.Name = "StormSteelLabel"
	steelLabel.AnchorPoint = Vector2.new(1, 0)
	steelLabel.Position = if isMobile then UDim2.new(1, -4, 1, 2) else UDim2.new(1, -8, 0, 56)
	steelLabel.Size = if isMobile then UDim2.fromOffset(150, 20) else UDim2.fromOffset(200, 34)
	steelLabel.BackgroundTransparency = 1
	steelLabel.TextColor3 = Theme.Colors.RoleColors.Fixer
	steelLabel.Font = Enum.Font.GothamBold
	steelLabel.TextScaled = if isMobile then false else true
	steelLabel.TextSize = if isMobile then 12 else 14
	steelLabel.Text = "Storm Steel: 0"
	steelLabel.Visible = false
	steelLabel.Parent = scrapFrame
	stormSteelLabel = steelLabel

	local waveLabel = Instance.new("TextLabel")
	waveLabel.Name = "WaveTimer"
	waveLabel.AnchorPoint = Vector2.new(0.5, 0)
	waveLabel.Position = UDim2.new(0.5, 0, 0.095, 0)
	waveLabel.Size = if isMobile then UDim2.new(0.4, 0, 0, 32) else UDim2.fromOffset(300, 28)
	waveLabel.BackgroundTransparency = 1
	waveLabel.TextColor3 = Theme.Colors.Accent
	waveLabel.Font = Enum.Font.RobotoMono
	waveLabel.TextScaled = isMobile
	waveLabel.TextSize = if isMobile then 18 else 20
	waveLabel.Text = "NEXT SWARM: 00:00"
	waveLabel.Parent = gui
	waveTimerLabel = waveLabel

	local stormLabel = Instance.new("TextLabel")
	stormLabel.Name = "StormTimer"
	stormLabel.AnchorPoint = Vector2.new(0.5, 0)
	stormLabel.Position = UDim2.new(0.5, 0, 0.12, 0)
	stormLabel.Size = UDim2.fromOffset(300, 22)
	stormLabel.BackgroundTransparency = 1
	stormLabel.TextColor3 = Theme.Colors.TextMuted
	stormLabel.Font = Enum.Font.RobotoMono
	stormLabel.TextScaled = true
	stormLabel.TextSize = if isMobile then 14 else 16
	stormLabel.Text = ""
	stormLabel.Visible = false
	stormLabel.Parent = gui
	stormTimerLabel = stormLabel

	local seasonLabel = Instance.new("TextLabel")
	seasonLabel.Name = "WaveSeason"
	seasonLabel.AnchorPoint = Vector2.new(0.5, 0)
	seasonLabel.Position = UDim2.new(0.5, 0, 0.125, 0)
	seasonLabel.Size = UDim2.fromOffset(300, 18)
	seasonLabel.BackgroundTransparency = 1
	seasonLabel.TextColor3 = Theme.Colors.TextMuted
	seasonLabel.Font = Enum.Font.GothamBold
	seasonLabel.TextScaled = true
	seasonLabel.Text = ""
	seasonLabel.Visible = false
	seasonLabel.Parent = gui
	waveSeasonLabel = seasonLabel

	local threat = Instance.new("TextLabel")
	threat.Name = "ThreatBanner"
	threat.AnchorPoint = Vector2.new(0.5, 0)
	threat.Position = UDim2.new(0.5, 0, 0.1, 0)
	threat.Size = UDim2.fromOffset(520, 46)
	threat.BackgroundColor3 = Theme.Colors.ThreatBanner
	threat.BackgroundTransparency = 1
	threat.TextTransparency = 1
	threat.TextColor3 = Theme.Colors.TextPrimary
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
	stormBanner.BackgroundColor3 = Theme.Colors.StormBanner
	stormBanner.BackgroundTransparency = 1
	stormBanner.TextTransparency = 1
	stormBanner.TextColor3 = Theme.Colors.TetherStatus
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
	tetherLabel.TextColor3 = Theme.Colors.TetherStatus
	tetherLabel.TextTransparency = 1
	tetherLabel.Font = Enum.Font.GothamBold
	tetherLabel.TextScaled = true
	tetherLabel.Text = "Tethers: 0/0 ACTIVE"
	tetherLabel.Parent = gui
	tetherStatusLabel = tetherLabel

	createToolbar(gui)
	createToolPanel(gui)
	createTitanProgressPanel(gui)
	createSettingsPanel(gui)
	createDebugPanel(gui)

	local bpFrame = Instance.new("Frame")
	bpFrame.Name = "BuildProgressBar"
	bpFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	bpFrame.Position = UDim2.new(0.5, 0, 0.75, 0)
	bpFrame.Size = UDim2.new(0.18, 0, 0, 20)
	bpFrame.BackgroundColor3 = Theme.Colors.Panel
	bpFrame.BackgroundTransparency = 0.3
	bpFrame.Visible = false
	bpFrame.Parent = gui

	local bpCorner = Instance.new("UICorner")
	bpCorner.CornerRadius = UDim.new(0, 4)
	bpCorner.Parent = bpFrame

	local bpFill = Instance.new("Frame")
	bpFill.Name = "Fill"
	bpFill.Size = UDim2.fromScale(0, 1)
	bpFill.BackgroundColor3 = Theme.Colors.BuildProgressFill
	bpFill.BorderSizePixel = 0
	bpFill.Parent = bpFrame

	local bpFillCorner = Instance.new("UICorner")
	bpFillCorner.CornerRadius = UDim.new(0, 4)
	bpFillCorner.Parent = bpFill

	local bpLabel = Instance.new("TextLabel")
	bpLabel.Name = "Label"
	bpLabel.Size = UDim2.fromScale(1, 1)
	bpLabel.BackgroundTransparency = 1
	bpLabel.TextColor3 = Theme.Colors.TextPrimary
	bpLabel.Font = Enum.Font.GothamBold
	bpLabel.TextScaled = true
	bpLabel.Text = "BUILDING..."
	bpLabel.ZIndex = 2
	bpLabel.Parent = bpFrame

	buildProgressFrame = bpFrame
	buildProgressFill = bpFill
	buildProgressLabel = bpLabel
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

function MainHUD.ShowRepairMinigame(drillPart: BasePart)
	if not isInitialized then
		return
	end

	local rootGui = PlayerGui:FindFirstChild("MainHUDGui")
	if rootGui == nil or not rootGui:IsA("ScreenGui") then
		return
	end

	RepairMinigameUI.Show(drillPart, rootGui, remotes)
end

function MainHUD.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	createMainHUD()
	createRoleSelection()

	BlueprintController.ConnectBuildProgress(function(progress: number)
		if buildProgressFrame == nil or buildProgressFill == nil then
			return
		end
		if progress <= 0 then
			buildProgressFrame.Visible = false
			buildProgressFill.Size = UDim2.fromScale(0, 1)
		else
			buildProgressFrame.Visible = true
			buildProgressFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
			if buildProgressLabel ~= nil then
				buildProgressLabel.Text = string.format("BUILDING... %d%%", math.floor(progress * 100))
			end
		end
	end)

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
	remotes.WaveStarted.OnClientEvent:Connect(function(waveNumber: number, patternIdx: number?)
		local safePatternIdx = if typeof(patternIdx) == "number" then math.floor(patternIdx :: number) else 2
		updateWaveSeasonLabel(waveNumber, safePatternIdx)
	end)
	remotes.GlobalGameOver.OnClientEvent:Connect(function()
		showGameOver()
	end)
	remotes.GlobalVictory.OnClientEvent:Connect(function()
		showVictory()
	end)
	remotes.FinalStandStarted.OnClientEvent:Connect(function()
		showFinalStandBanner()
		if waveTimerLabel ~= nil then
			waveTimerLabel.Visible = false
		end
		if stormTimerLabel ~= nil then
			stormTimerLabel.Visible = false
		end
	end)
	remotes.TitanStageCompleted.OnClientEvent:Connect(function(stage: number)
		playUISound(AudioManifest.StageComplete, 0.5)
		if titanStageLabel ~= nil then
			local original = titanStageLabel.TextColor3
					TweenService:Create(titanStageLabel, TweenInfo.new(0.15), { TextColor3 = Theme.Colors.Accent }):Play()
			task.delay(0.3, function()
				if titanStageLabel ~= nil then
					TweenService:Create(titanStageLabel, TweenInfo.new(0.3), { TextColor3 = original }):Play()
				end
			end)
		end
		showUpgradeBanner(stage)
		refreshBuildCosts()
	end)

	remotes.SandboxStarted.OnClientEvent:Connect(function()
		enterSandboxMode()
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

	task.delay(2, function()
		local rootGui = PlayerGui:FindFirstChild("MainHUDGui")
		if rootGui == nil or not rootGui:IsA("ScreenGui") then
			return
		end
		local hints = {
			{
				delay = 0,
				text = if isMobile
					then "Tap T, D, or W at the bottom to select a building."
					else "Press [1] [2] [3] to select buildings, click to place",
			},
			{
				delay = 6,
				text = if isMobile
					then "Blueprint appears in front of you. Turn your character, then tap PLACE."
					else "Press [R] to rotate buildings before placing",
			},
			{
				delay = 12,
				text = if isMobile
					then "Walk near a blueprint, then hold BUILD to construct it."
					else "Walk to the Titan Core and hold [E] to deposit resources",
			},
			{
				delay = 18,
				text = "Collect scrap to build defenses and upgrade the Titan.",
			},
			{
				delay = 24,
				text = "Survive the swarms and protect the Titan core.",
			},
		}
		for _, hint in hints do
			task.delay(hint.delay, function()
				local hintLabel = Instance.new("TextLabel")
				hintLabel.Name = "TutorialHint"
				hintLabel.AnchorPoint = Vector2.new(0.5, 0)
				hintLabel.Position = UDim2.new(0.5, 0, 0.155, 0)
				hintLabel.Size = UDim2.new(0.35, 0, 0, 28)
				hintLabel.BackgroundColor3 = Theme.Colors.TutorialHintBg
				hintLabel.BackgroundTransparency = 0.2
				hintLabel.Font = Enum.Font.GothamSemibold
				hintLabel.TextScaled = true
				hintLabel.TextColor3 = Theme.Colors.TutorialHintText
				hintLabel.Text = hint.text
				hintLabel.Parent = rootGui

				local hintCorner = Instance.new("UICorner")
				hintCorner.CornerRadius = UDim.new(0, 4)
				hintCorner.Parent = hintLabel

				task.delay(5, function()
					if hintLabel.Parent ~= nil then
						local fade = TweenService:Create(hintLabel, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							TextTransparency = 1,
							BackgroundTransparency = 1,
						})
						fade:Play()
						fade.Completed:Connect(function()
							hintLabel:Destroy()
						end)
					end
				end)
			end)
		end
	end)

	local nextWaveTimeAttr = remotes.Folder:GetAttribute("NextWaveTime")
	if typeof(nextWaveTimeAttr) == "number" then
		local remaining = math.max(0, (nextWaveTimeAttr :: number) - os.time())
		updateWaveTimer(remaining)
	end

	updateStormTimer()

	task.spawn(function()
		while isInitialized do
			task.wait(1)
			updateStormTimer()
		end
	end)

	local dismantleBarAccum = 0
	local scrapRateAccum = 0
	RunService.Heartbeat:Connect(function(dt: number)
		dismantleBarAccum += dt
		scrapRateAccum += dt
		if dismantleBarAccum >= 0.1 then
			dismantleBarAccum = 0
			updateDismantleBars()
		end
		if scrapRateAccum >= 1 then
			scrapRateAccum = 0
			refreshScrapLabel()
		end
	end)

	task.spawn(watchTitanAttributes)

	task.spawn(function()
		local titanCore: BasePart? = nil
		for _, tagged in CollectionService:GetTagged("TitanObjective") do
			if tagged:IsA("BasePart") then
				titanCore = tagged
				break
			end
		end
		while true do
			task.wait(0.5)
			if titanDistanceLabel == nil then
				continue
			end
			local character = LocalPlayer.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if root == nil or not root:IsA("BasePart") or titanCore == nil then
				titanDistanceLabel.Text = ""
				continue
			end
			local dist = math.floor((root.Position - titanCore.Position).Magnitude + 0.5)
			titanDistanceLabel.Text = ("%dm to Core"):format(dist)
		end
	end)

	if not hudWatchdogStarted then
		hudWatchdogStarted = true
		task.spawn(function()
			while isInitialized do
				task.wait(1)
				local gui = PlayerGui:FindFirstChild("MainHUDGui")
				if gui == nil then
					local ok = pcall(function()
						createMainHUD()
					end)
					if ok then
						refreshScrapLabel()
						updateStormSteel(currentStormSteel)
						refreshBuildCosts()
					end
				end
			end
		end)
	end
end

function MainHUD.ConnectWaveTimerZero(callback: () -> ()): RBXScriptConnection
	return waveTimerSignal.Event:Connect(callback)
end

return MainHUD
