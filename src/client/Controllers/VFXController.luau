--!strict

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local AudioManifest = require(Shared:WaitForChild("AudioManifest"))
local VisualManifest = require(Shared:WaitForChild("VisualManifest"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Platform = require(Shared:WaitForChild("Platform"))
local MainHUD = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("MainHUD"))

local VFXController = {}

local POOL_SIZE = 20
local isInitialized = false
local remotes = Remotes.Get()
local lastScrap = 0
local lastStormSteel = 0

type ActiveDismantleEffect = {
	baseCFrame: CFrame,
	emitter: ParticleEmitter,
}

local gearPool: { BasePart } = {}
local activeEffects: { [BasePart]: ActiveDismantleEffect } = {}
local drillSmokeEffects: { [BasePart]: ParticleEmitter } = {}
local stormBlur: BlurEffect? = nil
local stormColor: ColorCorrectionEffect? = nil
local stormWindSound: Sound? = nil
local stormRattleSound: Sound? = nil
local lastWaveHornAt = 0
local baseAmbient = Lighting.Ambient
local baseBrightness = Lighting.Brightness
local dayMusic: Sound? = nil
local waveMusic: Sound? = nil
local waveIntensityActive = false
local ratHealthBars: { [Model]: BillboardGui } = {}
local ratHealthConnections: { [Model]: { RBXScriptConnection } } = {}
local baseRadiusMarker: Instance? = nil
local scrapComboCount = 0
local lastScrapPickupAt = 0
local ambientDustPart: BasePart? = nil

type MagnetFlight = {
	part: BasePart,
	startPos: Vector3,
	elapsed: number,
}
local activeMagnetFlights: { MagnetFlight } = {}
local MAGNET_FLIGHT_SPEED = 40
local MAGNET_ARC_HEIGHT = 1.5
local MAGNET_SPIN_RATE = 5

local RAT_LOD_DETAIL_DISTANCE = 80
local RAT_LOD_HIDE_DISTANCE = 150
local ratLodState: { [Model]: string } = {}
local LOD_DETAIL_PARTS = { "Head", "Tail", "EyeL", "EyeR", "LootBag" }

local QUALITY_HIGH = 3
local QUALITY_MEDIUM = 2
local QUALITY_LOW = 1
local currentQuality = QUALITY_HIGH
local manualQualityOverride: number? = nil
local frameTimes: { number } = {}
local FRAME_BUDGET_WINDOW = 60
local FRAME_BUDGET_THRESHOLD_MS = 33

local function createGearPart(): BasePart
	local part = Instance.new("Part")
	part.Name = "LootGear"
	part.Size = Vector3.new(0.6, 0.6, 0.2)
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Metal
	part.Color = VisualManifest.VFX.LootGearColor
	part.Material = VisualManifest.VFX.LootGearMaterial
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = Workspace
	return part
end

local function acquireGear(): BasePart
	if #gearPool > 0 then
		local part = gearPool[#gearPool]
		table.remove(gearPool, #gearPool)
		return part
	end
	return createGearPart()
end

local function releaseGear(part: BasePart)
	part.Transparency = 1
	part.Parent = Workspace
	table.insert(gearPool, part)
end

local function playLootFountain(increaseAmount: number, sourcePosition: Vector3?)
	local character = LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local count = math.clamp(math.floor(increaseAmount / 5), 3, 8)
	local spawnBase = if sourcePosition ~= nil then sourcePosition else root.Position

	for i = 1, count do
		task.delay((i - 1) * 0.05, function()
			local gear = acquireGear()
			local startPos = spawnBase + Vector3.new(math.random(-3, 3), math.random(2, 5), math.random(-3, 3))
			local apexPos = startPos + Vector3.new(math.random(-2, 2), math.random(3, 6), math.random(-2, 2))

			gear.CFrame = CFrame.new(startPos) * CFrame.Angles(0, 0, math.rad(90))
			gear.Transparency = 0

			local arcTween = TweenService:Create(gear, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(apexPos) * CFrame.Angles(0, 0, math.rad(90 + math.random(0, 180))),
			})
			arcTween:Play()
			arcTween.Completed:Wait()

			local targetRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			if targetRoot and targetRoot:IsA("BasePart") then
				local collectTween = TweenService:Create(gear, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
					Position = targetRoot.Position + Vector3.new(0, 2, 0),
					Transparency = 1,
				})
				collectTween:Play()
				collectTween.Completed:Wait()
			end

			releaseGear(gear)
		end)
	end
end

local function createSparkEmitter(part: BasePart): ParticleEmitter
	local attachment = Instance.new("Attachment")
	attachment.Name = "DismantleSparkAttachment"
	attachment.Parent = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DismantleSparks"
	emitter.Parent = attachment
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(VisualManifest.VFX.DismantleSparksA, VisualManifest.VFX.DismantleSparksB)
	emitter.Lifetime = NumberRange.new(0.12, 0.25)
	emitter.Rate = 22
	emitter.Speed = NumberRange.new(3, 8)
	emitter.SpreadAngle = Vector2.new(40, 40)
	emitter.Size = NumberSequence.new(0.12, 0.03)
	emitter.Enabled = true
	return emitter
end

local function applyWobble(part: BasePart, baseCFrame: CFrame)
	local x = math.rad(math.random(-5, 5))
	local z = math.rad(math.random(-5, 5))
	local target = baseCFrame * CFrame.Angles(x, 0, z)
	local tween = TweenService:Create(part, TweenInfo.new(0.15, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { CFrame = target })
	tween:Play()
	tween.Completed:Connect(function()
		if part.Parent ~= nil and activeEffects[part] ~= nil then
			local reset = TweenService:Create(part, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = baseCFrame })
			reset:Play()
		end
	end)
end

local function stopDismantleEffect(part: BasePart)
	local effect = activeEffects[part]
	if effect == nil then
		return
	end

	part.CFrame = effect.baseCFrame

	local attachment = effect.emitter.Parent
	effect.emitter.Enabled = false
	effect.emitter:Destroy()
	if attachment and attachment:IsA("Attachment") then
		attachment:Destroy()
	end

	activeEffects[part] = nil
end

local function ensureDismantleEffect(part: BasePart)
	if activeEffects[part] ~= nil then
		applyWobble(part, activeEffects[part].baseCFrame)
		return
	end

	local effect: ActiveDismantleEffect = {
		baseCFrame = part.CFrame,
		emitter = createSparkEmitter(part),
	}
	activeEffects[part] = effect
	applyWobble(part, effect.baseCFrame)
end

local function refreshDismantleState(part: BasePart)
	local isActive = part:GetAttribute("IsBeingDismantled") == true
	if isActive then
		ensureDismantleEffect(part)
	else
		stopDismantleEffect(part)
	end
end

local function playBuildingDestroyFx(position: Vector3)
	local marker = Instance.new("Part")
	marker.Name = "BuildDestroyMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 1
	marker.Size = Vector3.new(0.2, 0.2, 0.2)
	marker.Position = position + Vector3.new(0, 2, 0)
	marker.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = marker

	local dust = Instance.new("ParticleEmitter")
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(VisualManifest.VFX.DestroyDustColor)
	dust.Lifetime = NumberRange.new(0.8, 1.5)
	dust.Speed = NumberRange.new(3, 8)
	dust.SpreadAngle = Vector2.new(90, 90)
	dust.Rate = 0
	dust.Size = NumberSequence.new(1.5, 3.0)
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Parent = attachment
	dust:Emit(15)

	local debris = Instance.new("ParticleEmitter")
	debris.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	debris.Color = ColorSequence.new(VisualManifest.VFX.DestroyDebrisA, VisualManifest.VFX.DestroyDebrisB)
	debris.Lifetime = NumberRange.new(0.3, 0.6)
	debris.Speed = NumberRange.new(8, 16)
	debris.SpreadAngle = Vector2.new(120, 120)
	debris.Rate = 0
	debris.Size = NumberSequence.new(0.2, 0.05)
	debris.Parent = attachment
	debris:Emit(12)

	local destroySound = Instance.new("Sound")
	destroySound.SoundId = AudioManifest.BuildDestroy
	destroySound.Volume = 0.4
	destroySound.Parent = marker
	destroySound:Play()

	task.delay(2, function()
		if marker.Parent ~= nil then
			marker:Destroy()
		end
	end)
end

local function bindDismantlable(part: BasePart)
	local lastPosition = part.Position
	part:GetAttributeChangedSignal("IsBeingDismantled"):Connect(function()
		refreshDismantleState(part)
	end)
	part.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			stopDismantleEffect(part)
			playBuildingDestroyFx(lastPosition)
		end
	end)
	refreshDismantleState(part)
end

local function ensureDrillSmoke(drill: BasePart): ParticleEmitter
	local existing = drillSmokeEffects[drill]
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "DrillSmokeAttachment"
	attachment.Position = Vector3.new(0, drill.Size.Y * 0.4, 0)
	attachment.Parent = drill

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DrillSmoke"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(VisualManifest.VFX.DrillSmokeA, VisualManifest.VFX.DrillSmokeB)
	emitter.Lifetime = NumberRange.new(1.2, 1.8)
	emitter.Speed = NumberRange.new(0.5, 1.3)
	emitter.SpreadAngle = Vector2.new(20, 35)
	emitter.Rate = 16
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 2.2),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = attachment
	drillSmokeEffects[drill] = emitter
	return emitter
end

local function clearDrillSmoke(drill: BasePart)
	local emitter = drillSmokeEffects[drill]
	if emitter == nil then
		return
	end
	local attachment = emitter.Parent
	emitter:Destroy()
	if attachment ~= nil and attachment:IsA("Attachment") then
		attachment:Destroy()
	end
	drillSmokeEffects[drill] = nil
end

local function refreshDrillSmoke(drill: BasePart)
	local stabilityAttr = drill:GetAttribute("Stability")
	local stability = if typeof(stabilityAttr) == "number" then math.clamp(stabilityAttr :: number, 0, 100) else 100
	if stability < 20 then
		ensureDrillSmoke(drill)
	else
		clearDrillSmoke(drill)
	end
end

local overclockGlows: { [BasePart]: PointLight } = {}

local function refreshOverclockGlow(drill: BasePart)
	local isOverclocked = drill:GetAttribute("IsOverclocked") == true
	if isOverclocked then
		if overclockGlows[drill] == nil then
			local light = Instance.new("PointLight")
			light.Name = "OverclockGlow"
			light.Color = VisualManifest.VFX.OverclockLightColor
			light.Range = 12
			light.Brightness = 2
			light.Parent = drill
			overclockGlows[drill] = light
		end
	else
		local light = overclockGlows[drill]
		if light ~= nil then
			light:Destroy()
			overclockGlows[drill] = nil
		end
	end
end

local function clearOverclockGlow(drill: BasePart)
	local light = overclockGlows[drill]
	if light ~= nil then
		light:Destroy()
		overclockGlows[drill] = nil
	end
end

local function computeDrillEfficiency(stability: number): number
	if stability >= 80 then
		return 1
	elseif stability >= 20 then
		return 0.5
	end
	return 0
end

local function refreshDrillRateLabel(drill: BasePart, rateLabel: TextLabel)
	local isClogged = drill:GetAttribute("IsClogged")
	if isClogged == true then
		rateLabel.Text = "+0.0/s"
		rateLabel.TextColor3 = VisualManifest.VFX.HealthBad
		return
	end

	local stabilityAttr = drill:GetAttribute("Stability")
	local stability = if typeof(stabilityAttr) == "number" then (stabilityAttr :: number) else 100
	local efficiency = computeDrillEfficiency(stability)

	local isOverclocked = drill:GetAttribute("IsOverclocked")
	local overclockMult = if isOverclocked == true then Constants.MAINTENANCE.OverclockMultiplier else 1

	local drillLevel = drill:GetAttribute("BuildingLevel") or 1
	local levelStats = Constants.BUILDING_UPGRADES.Drill[drillLevel]
	local lv1Stats = Constants.BUILDING_UPGRADES.Drill[1]
	local levelMult = 1
	if levelStats ~= nil and lv1Stats ~= nil then
		levelMult = (levelStats.scrapPerTick / levelStats.tickInterval) / (lv1Stats.scrapPerTick / lv1Stats.tickInterval)
	end
	local rate = Constants.MAINTENANCE.DrillBaseOutput * levelMult * efficiency * overclockMult / Constants.MAINTENANCE.ResourceTickSeconds
	if rate > 0 then
		rateLabel.Text = ("+%.1f/s"):format(rate)
		rateLabel.TextColor3 = VisualManifest.VFX.HealthGood
	else
		rateLabel.Text = "+0.0/s"
		rateLabel.TextColor3 = VisualManifest.VFX.HealthBad
	end
end

local function bindDrillFx(drill: BasePart)
	drill:GetAttributeChangedSignal("Stability"):Connect(function()
		refreshDrillSmoke(drill)
	end)
	drill:GetAttributeChangedSignal("IsOverclocked"):Connect(function()
		refreshOverclockGlow(drill)
	end)
	drill.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clearDrillSmoke(drill)
			clearOverclockGlow(drill)
		end
	end)
	refreshDrillSmoke(drill)
	refreshOverclockGlow(drill)

	local rateGui = Instance.new("BillboardGui")
	rateGui.Name = "DrillRateGui"
	rateGui.Size = UDim2.new(5, 0, 0.6, 0)
	rateGui.StudsOffset = Vector3.new(0, 4, 0)
	rateGui.AlwaysOnTop = false
	rateGui.MaxDistance = 60
	rateGui.Adornee = drill
	rateGui.Parent = drill

	local rateLabel = Instance.new("TextLabel")
	rateLabel.Name = "RateLabel"
	rateLabel.Size = UDim2.fromScale(1, 1)
	rateLabel.BackgroundTransparency = 1
	rateLabel.Font = Enum.Font.GothamBold
	rateLabel.TextScaled = true
	rateLabel.TextStrokeTransparency = 0.4
	rateLabel.TextColor3 = VisualManifest.VFX.HealthGood
	rateLabel.Parent = rateGui

	refreshDrillRateLabel(drill, rateLabel)

	drill:GetAttributeChangedSignal("Stability"):Connect(function()
		refreshDrillRateLabel(drill, rateLabel)
	end)
	drill:GetAttributeChangedSignal("IsOverclocked"):Connect(function()
		refreshDrillRateLabel(drill, rateLabel)
	end)
	drill:GetAttributeChangedSignal("IsClogged"):Connect(function()
		refreshDrillRateLabel(drill, rateLabel)
	end)
end

local function playBuildFlash(position: Vector3)
	local ring = Instance.new("Part")
	ring.Name = "BuildFlashRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = VisualManifest.VFX.BuildFlashMaterial
	ring.Color = VisualManifest.VFX.BuildFlashColor
	ring.Anchored = true
	ring.CanCollide = false
	ring.Size = Vector3.new(0.3, 7.5, 7.5)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(math.rad(90), 0, 0)
	ring.Parent = Workspace

	local expandTween = TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, 24, 24),
		Transparency = 1,
	})
	expandTween:Play()
	expandTween.Completed:Connect(function()
		ring:Destroy()
	end)

	local character = LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid.CameraOffset = Vector3.new(math.random(-10, 10) / 100, math.random(-10, 10) / 100, 0)
		task.delay(0.08, function()
			if humanoid and humanoid.Parent then
				humanoid.CameraOffset = Vector3.zero
			end
		end)
	end

	local buildSound = Instance.new("Sound")
	buildSound.SoundId = AudioManifest.BuildPlace
	buildSound.Volume = 0.35
	buildSound.Parent = Workspace
	buildSound:Play()
	buildSound.Ended:Connect(function()
		if buildSound.Parent ~= nil then
			buildSound:Destroy()
		end
	end)

	local burst = Instance.new("Part")
	burst.Name = "BuildFlashBurst"
	burst.Shape = Enum.PartType.Ball
	burst.Material = Enum.Material.Neon
	burst.Color = VisualManifest.VFX.BuildFlashColor
	burst.Anchored = true
	burst.CanCollide = false
	burst.Size = Vector3.new(1.2, 1.2, 1.2)
	burst.Position = position + Vector3.new(0, 1.4, 0)
	burst.Transparency = 0.25
	burst.Parent = Workspace
	TweenService:Create(burst, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(4.5, 4.5, 4.5),
		Transparency = 1,
	}):Play()
	task.delay(0.32, function()
		if burst.Parent ~= nil then
			burst:Destroy()
		end
	end)
end

local function startStormFx()
	local ambientTarget = VisualManifest.Storm.Ambient
	local brightnessTarget = VisualManifest.Storm.Brightness
	local lightingTween = TweenService:Create(Lighting, TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Ambient = ambientTarget,
		Brightness = brightnessTarget,
	})
	lightingTween:Play()

	if stormBlur == nil then
		stormBlur = Instance.new("BlurEffect")
		stormBlur.Name = "StormBlur"
		stormBlur.Size = 0
		stormBlur.Parent = Lighting
	end
	TweenService:Create(stormBlur, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = VisualManifest.Storm.BlurSize }):Play()

	if stormColor == nil then
		stormColor = Instance.new("ColorCorrectionEffect")
		stormColor.Name = "StormColor"
		stormColor.TintColor = VisualManifest.Storm.ClearTintColor
		stormColor.Parent = Lighting
	end
	TweenService:Create(stormColor, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TintColor = VisualManifest.Storm.TintColor,
	}):Play()

	if stormWindSound == nil then
		stormWindSound = Instance.new("Sound")
		stormWindSound.Name = "StormWind"
		stormWindSound.SoundId = AudioManifest.StormWind
		stormWindSound.Looped = true
		stormWindSound.Volume = 0.3
		stormWindSound.Parent = SoundService
	end
	stormWindSound:Play()

	if stormRattleSound == nil then
		stormRattleSound = Instance.new("Sound")
		stormRattleSound.Name = "StormRattle"
		stormRattleSound.SoundId = AudioManifest.StormRattle
		stormRattleSound.Looped = true
		stormRattleSound.Volume = 0.15
		stormRattleSound.Parent = SoundService
	end
	stormRattleSound:Play()
end

local function stopStormFx()
	local lightingTween = TweenService:Create(Lighting, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Ambient = baseAmbient,
		Brightness = baseBrightness,
	})
	lightingTween:Play()

	if stormBlur ~= nil then
		local blurRef = stormBlur
		local tween = TweenService:Create(blurRef, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = 0 })
		tween:Play()
		tween.Completed:Connect(function()
			if blurRef.Parent ~= nil then
				blurRef:Destroy()
			end
		end)
		stormBlur = nil
	end

	if stormColor ~= nil then
		local colorRef = stormColor
		local tween = TweenService:Create(colorRef, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TintColor = VisualManifest.Storm.ClearTintColor,
		})
		tween:Play()
		tween.Completed:Connect(function()
			if colorRef.Parent ~= nil then
				colorRef:Destroy()
			end
		end)
		stormColor = nil
	end

	if stormWindSound ~= nil then
		stormWindSound:Stop()
		stormWindSound:Destroy()
		stormWindSound = nil
	end

	if stormRattleSound ~= nil then
		stormRattleSound:Stop()
		stormRattleSound:Destroy()
		stormRattleSound = nil
	end
end

local function playRepairSuccessFx(position: Vector3)
	local marker = Instance.new("Part")
	marker.Name = "RepairBurstMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 1
	marker.Size = Vector3.new(0.2, 0.2, 0.2)
	marker.Position = position + Vector3.new(0, 2, 0)
	marker.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = marker

	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Color = ColorSequence.new(VisualManifest.VFX.RepairBurstA, VisualManifest.VFX.RepairBurstB)
	burst.Lifetime = NumberRange.new(0.2, 0.35)
	burst.Speed = NumberRange.new(4, 8)
	burst.SpreadAngle = Vector2.new(60, 60)
	burst.Rate = 0
	burst.Parent = attachment
	burst:Emit(24)

	local hiss = Instance.new("Sound")
	hiss.Name = "RepairSteamHiss"
	hiss.SoundId = AudioManifest.RepairHiss
	hiss.Volume = 0.25
	hiss.Parent = SoundService
	hiss:Play()

	local clank = Instance.new("Sound")
	clank.Name = "RepairClank"
	clank.SoundId = AudioManifest.RepairClank
	clank.Volume = 0.3
	clank.Parent = SoundService
	clank:Play()

	task.delay(1.2, function()
		if hiss.Parent ~= nil then
			hiss:Destroy()
		end
		if clank.Parent ~= nil then
			clank:Destroy()
		end
		if marker.Parent ~= nil then
			marker:Destroy()
		end
	end)
end

local function playEnemyDeathFx(position: Vector3)
	local marker = Instance.new("Part")
	marker.Name = "EnemyDeathMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 1
	marker.Size = Vector3.new(0.2, 0.2, 0.2)
	marker.Position = position + Vector3.new(0, 1, 0)
	marker.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = marker

	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Color = ColorSequence.new(VisualManifest.VFX.EnemyDeathA, VisualManifest.VFX.EnemyDeathB)
	burst.Lifetime = NumberRange.new(0.15, 0.4)
	burst.Speed = NumberRange.new(5, 12)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Rate = 0
	burst.Size = NumberSequence.new(0.15, 0.03)
	burst.Parent = attachment
	burst:Emit(20)

	local deathSound = Instance.new("Sound")
	deathSound.SoundId = AudioManifest.EnemyDeath
	deathSound.Volume = 0.35
	deathSound.Parent = marker
	deathSound:Play()

	task.delay(0.6, function()
		if marker.Parent ~= nil then
			marker:Destroy()
		end
	end)
end

local function playWaveHorn()
	local now = os.clock()
	if now - lastWaveHornAt < 1 then
		return
	end
	lastWaveHornAt = now

	local horn = Instance.new("Sound")
	horn.Name = "WaveHorn"
	horn.SoundId = AudioManifest.WaveHorn
	horn.Volume = 0.45
	horn.PlaybackSpeed = 0.85
	horn.RollOffMode = Enum.RollOffMode.Linear
	horn.MaxDistance = 140
	horn.Parent = SoundService
	horn:Play()
	horn.Ended:Connect(function()
		if horn.Parent ~= nil then
			horn:Destroy()
		end
	end)
end

local function clearRatHealthBar(ratModel: Model)
	local bar = ratHealthBars[ratModel]
	if bar ~= nil then
		bar:Destroy()
		ratHealthBars[ratModel] = nil
	end

	local conns = ratHealthConnections[ratModel]
	if conns ~= nil then
		for _, conn in conns do
			conn:Disconnect()
		end
		ratHealthConnections[ratModel] = nil
	end
end

local function healthColor(percent: number): Color3
	if percent >= 0.66 then
		return VisualManifest.VFX.HealthGood
	elseif percent >= 0.33 then
		return VisualManifest.VFX.HealthWarning
	end
	return VisualManifest.VFX.HealthBad
end

local function showDamageNumber(position: Vector3, amount: number)
	local marker = Instance.new("Part")
	marker.Name = "DamageNumberMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 1
	marker.Size = Vector3.new(0.2, 0.2, 0.2)
	marker.Position = position
	marker.Parent = Workspace

	local gui = Instance.new("BillboardGui")
	gui.Name = "DamageNumber"
	gui.Size = UDim2.fromOffset(90, 34)
	gui.StudsOffset = Vector3.new(0, 1.6, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = marker
	gui.Parent = marker

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextStrokeTransparency = 0.45
	text.TextColor3 = VisualManifest.VFX.DamageNumberColor
	text.Text = ("-%d"):format(math.max(1, amount))
	text.Parent = gui

	TweenService:Create(gui, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 3.2, 0),
	}):Play()
	TweenService:Create(text, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(0.4, function()
		if marker.Parent ~= nil then
			marker:Destroy()
		end
	end)
end

local function showScrapCombo(combo: number)
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	local hud = playerGui:FindFirstChild("MainHUDGui")
	if hud == nil or not hud:IsA("ScreenGui") then
		return
	end

	local existing = hud:FindFirstChild("ScrapCombo")
	if existing ~= nil then
		existing:Destroy()
	end

	local label = Instance.new("TextLabel")
	label.Name = "ScrapCombo"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0.125, 0)
	label.Size = UDim2.fromOffset(240, 32)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = VisualManifest.VFX.ScrapComboColor
	label.TextStrokeTransparency = 0.5
	label.Text = ("SCRAP x%d COMBO"):format(combo)
	label.Parent = hud

	local sound = Instance.new("Sound")
	sound.SoundId = AudioManifest.LootCombo
	sound.Volume = 0.2
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		if sound.Parent ~= nil then
			sound:Destroy()
		end
	end)

	TweenService:Create(label, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.095, 0),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(0.5, function()
		if label.Parent ~= nil then
			label:Destroy()
		end
	end)
end

local function showPickupNumber(position: Vector3, textValue: string, color: Color3)
	local marker = Instance.new("Part")
	marker.Name = "PickupNumberMarker"
	marker.Anchored = true
	marker.CanCollide = false
	marker.Transparency = 1
	marker.Size = Vector3.new(0.2, 0.2, 0.2)
	marker.Position = position + Vector3.new(0, 2, 0)
	marker.Parent = Workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(90, 30)
	gui.StudsOffset = Vector3.new(0, 1, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = marker
	gui.Parent = marker

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextStrokeTransparency = 0.4
	text.TextColor3 = color
	text.Text = textValue
	text.Parent = gui

	TweenService:Create(gui, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, 2.4, 0),
	}):Play()
	TweenService:Create(text, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(0.55, function()
		if marker.Parent ~= nil then
			marker:Destroy()
		end
	end)
end

local function playScrapSparkleBurst(position: Vector3, amount: number)
	local bursts = math.clamp(math.floor(amount / 2), 6, 10)
	for _ = 1, bursts do
		local p = Instance.new("Part")
		p.Name = "ScrapSparkle"
		p.Shape = Enum.PartType.Ball
		p.Material = Enum.Material.Neon
		p.Color = VisualManifest.VFX.ScrapPickupSparkle
		p.Anchored = true
		p.CanCollide = false
		p.Size = Vector3.new(0.25, 0.25, 0.25)
		p.Transparency = 0.15
		p.Position = position + Vector3.new(0, 1.8, 0)
		p.Parent = Workspace
		local dir = (Vector3.new(math.random() - 0.5, math.random() * 0.7 + 0.2, math.random() - 0.5)).Unit
		TweenService:Create(p, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = p.Position + (dir * (math.random(6, 10) * 0.25)),
			Size = Vector3.new(0.05, 0.05, 0.05),
			Transparency = 1,
		}):Play()
		task.delay(0.25, function()
			if p.Parent ~= nil then
				p:Destroy()
			end
		end)
	end
end

local function flashScrapComboVignette()
	local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	local hud = playerGui:FindFirstChild("MainHUDGui")
	if hud == nil or not hud:IsA("ScreenGui") then
		return
	end
	local existing = hud:FindFirstChild("ScrapComboVignette")
	if existing ~= nil then
		existing:Destroy()
	end
	local vignette = Instance.new("Frame")
	vignette.Name = "ScrapComboVignette"
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3 = VisualManifest.VFX.ScrapPickupSparkle
	vignette.BackgroundTransparency = 0.92
	vignette.BorderSizePixel = 0
	vignette.ZIndex = 60
	vignette.Parent = hud
	TweenService:Create(vignette, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.18, function()
		if vignette.Parent ~= nil then
			vignette:Destroy()
		end
	end)
end

local function bumpCamera()
	local character = LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid == nil then
		return
	end
	TweenService:Create(humanoid, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CameraOffset = Vector3.new(0, 0.08, 0),
	}):Play()
	task.delay(0.06, function()
		if humanoid.Parent ~= nil then
			TweenService:Create(humanoid, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CameraOffset = Vector3.zero,
			}):Play()
		end
	end)
end

local function playPowerUpSound(powerUpType: string)
	local s = Instance.new("Sound")
	local soundByType = {
		Lightning = AudioManifest.PowerUpLightning,
		Shockwave = AudioManifest.PowerUpShockwave,
		RepairAura = AudioManifest.PowerUpRepairAura,
		TitanPush = AudioManifest.PowerUpTitanPush,
		LootVacuum = AudioManifest.PowerUpLootVacuum,
	}
	s.SoundId = soundByType[powerUpType] or AudioManifest.WaveSlam
	s.Volume = 0.25
	if powerUpType == "Lightning" then
		s.PlaybackSpeed = 1.25
	elseif powerUpType == "Shockwave" then
		s.PlaybackSpeed = 0.75
	elseif powerUpType == "RepairAura" then
		s.PlaybackSpeed = 1.4
	elseif powerUpType == "TitanPush" then
		s.PlaybackSpeed = 0.7
	elseif powerUpType == "LootVacuum" then
		s.PlaybackSpeed = 1.6
	else
		s.PlaybackSpeed = 1
	end
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		if s.Parent ~= nil then
			s:Destroy()
		end
	end)
end

local function playLightningPowerUpVFX(origin: Vector3, hitPositions: { Vector3 }?)
	local points = hitPositions or {}
	if #points == 0 then
		for _ = 1, math.random(5, 8) do
			table.insert(points, origin + Vector3.new(math.random(-18, 18), 0, math.random(-18, 18)))
		end
	end
	for _, strikePos in points do
		local top = strikePos + Vector3.new(0, 200, 0)
		local beam = Instance.new("Part")
		beam.Name = "LightningBeam"
		beam.Anchored = true
		beam.CanCollide = false
		beam.Material = Enum.Material.Neon
		beam.Color = VisualManifest.Loot.PowerUps.Lightning
		beam.Transparency = 0.15
		local length = (top - strikePos).Magnitude
		beam.Size = Vector3.new(0.55, length, 0.55)
		beam.CFrame = CFrame.lookAt((top + strikePos) * 0.5, strikePos) * CFrame.Angles(math.rad(90), 0, 0)
		beam.Parent = Workspace
		TweenService:Create(beam, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.1, length, 0.1),
		}):Play()
		task.delay(0.35, function()
			if beam.Parent ~= nil then
				beam:Destroy()
			end
		end)
	end
	bumpCamera()
	playPowerUpSound("Lightning")
end

local function playRepairAuraVFX(origin: Vector3, hitPositions: { Vector3 }?)
	local ring = Instance.new("Part")
	ring.Name = "RepairAuraRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = VisualManifest.Loot.PowerUps.RepairAura
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = CFrame.new(origin + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.2
	ring.Parent = Workspace
	local target = Constants.POWERUPS.RepairAura.radius * 2
	TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.4, target, target),
		Transparency = 1,
	}):Play()
	task.delay(0.45, function()
		if ring.Parent ~= nil then
			ring:Destroy()
		end
	end)

	for _, pos in hitPositions or {} do
		local spark = Instance.new("Part")
		spark.Name = "RepairAuraSpark"
		spark.Shape = Enum.PartType.Ball
		spark.Anchored = true
		spark.CanCollide = false
		spark.Material = Enum.Material.Neon
		spark.Color = VisualManifest.Loot.PowerUps.RepairAura
		spark.Size = Vector3.new(0.5, 0.5, 0.5)
		spark.Position = pos + Vector3.new(0, 2, 0)
		spark.Transparency = 0.1
		spark.Parent = Workspace
		TweenService:Create(spark, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(2.2, 2.2, 2.2),
			Transparency = 1,
		}):Play()
		task.delay(0.28, function()
			if spark.Parent ~= nil then
				spark:Destroy()
			end
		end)
	end
	bumpCamera()
	playPowerUpSound("RepairAura")
end

local function playTitanPushVFX(origin: Vector3, hitPositions: { Vector3 }?)
	local ring = Instance.new("Part")
	ring.Name = "TitanPushRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = VisualManifest.Loot.PowerUps.TitanPush
	ring.Size = Vector3.new(0.5, 2, 2)
	ring.CFrame = CFrame.new(origin + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.2
	ring.Parent = Workspace
	local target = Constants.POWERUPS.TitanPush.radius * 2
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.5, target, target),
		Transparency = 1,
	}):Play()
	task.delay(0.4, function()
		if ring.Parent ~= nil then
			ring:Destroy()
		end
	end)

	for _, pos in hitPositions or {} do
		local trail = Instance.new("Part")
		trail.Name = "TitanPushTrail"
		trail.Anchored = true
		trail.CanCollide = false
		trail.Material = Enum.Material.Neon
		trail.Color = VisualManifest.Loot.PowerUps.TitanPush
		trail.Size = Vector3.new(0.2, 0.2, 2)
		trail.CFrame = CFrame.new(pos + Vector3.new(0, 0.8, 0))
		trail.Transparency = 0.15
		trail.Parent = Workspace
		TweenService:Create(trail, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.1, 0.1, 6),
			Transparency = 1,
		}):Play()
		task.delay(0.28, function()
			if trail.Parent ~= nil then
				trail:Destroy()
			end
		end)
	end
	bumpCamera()
	playPowerUpSound("TitanPush")
end

local function playLootVacuumVFX(origin: Vector3)
	local ring = Instance.new("Part")
	ring.Name = "LootVacuumRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = VisualManifest.Loot.PowerUps.LootVacuum
	local startDiameter = Constants.POWERUPS.LootVacuum.radius * 2
	ring.Size = Vector3.new(0.4, startDiameter, startDiameter)
	ring.CFrame = CFrame.new(origin + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.15
	ring.Parent = Workspace
	TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.4, 0.1, 0.1),
		Transparency = 1,
	}):Play()
	task.delay(0.35, function()
		if ring.Parent ~= nil then
			ring:Destroy()
		end
	end)

	local core = Instance.new("Part")
	core.Name = "LootVacuumCore"
	core.Shape = Enum.PartType.Ball
	core.Anchored = true
	core.CanCollide = false
	core.Material = Enum.Material.Neon
	core.Color = VisualManifest.Loot.PowerUps.LootVacuum
	core.Size = Vector3.new(1.5, 1.5, 1.5)
	core.Position = origin + Vector3.new(0, 1.2, 0)
	core.Transparency = 0.1
	core.Parent = Workspace
	TweenService:Create(core, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
	}):Play()
	task.delay(0.25, function()
		if core.Parent ~= nil then
			core:Destroy()
		end
	end)

	bumpCamera()
	playPowerUpSound("LootVacuum")
end

local function playDrillBonusShowerVFX(drillPositions: { Vector3 })
	for _, position in drillPositions do
		local burst = Instance.new("Part")
		burst.Name = "DrillBonusBurst"
		burst.Shape = Enum.PartType.Ball
		burst.Anchored = true
		burst.CanCollide = false
		burst.Material = Enum.Material.Neon
		burst.Color = Color3.fromRGB(255, 220, 90)
		burst.Size = Vector3.new(2, 2, 2)
		burst.Position = position + Vector3.new(0, 3, 0)
		burst.Transparency = 0.2
		burst.Parent = Workspace
		TweenService:Create(burst, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(8, 8, 8),
			Transparency = 1,
		}):Play()
		task.delay(0.4, function()
			if burst.Parent ~= nil then
				burst:Destroy()
			end
		end)
	end

	local showerSfx = Instance.new("Sound")
	showerSfx.SoundId = AudioManifest.DrillShower or AudioManifest.LootCollect
	showerSfx.Volume = 0.22
	showerSfx.PlaybackSpeed = 1.15
	showerSfx.Parent = SoundService
	showerSfx:Play()
	showerSfx.Ended:Connect(function()
		if showerSfx.Parent ~= nil then
			showerSfx:Destroy()
		end
	end)
end

local function playShockwavePowerUpVFX(origin: Vector3)
	local ring = Instance.new("Part")
	ring.Name = "ShockwaveRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.Material = Enum.Material.Neon
	ring.Color = VisualManifest.Loot.PowerUps.Shockwave
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = CFrame.new(origin + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Transparency = 0.2
	ring.Parent = Workspace
	local target = Constants.POWERUPS.Shockwave.radius * 2
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.4, target, target),
		Transparency = 1,
	}):Play()
	task.delay(0.4, function()
		if ring.Parent ~= nil then
			ring:Destroy()
		end
	end)
	bumpCamera()
	playPowerUpSound("Shockwave")
end

local function bindRatHealthBar(ratModel: Model)
	if ratHealthBars[ratModel] ~= nil then
		return
	end

	local humanoid: Humanoid? = ratModel:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		local found = ratModel:WaitForChild("Humanoid", 5)
		if found and found:IsA("Humanoid") then
			humanoid = found :: Humanoid
		end
	end

	local root: BasePart? = ratModel.PrimaryPart
	if root == nil then
		local found = ratModel:WaitForChild("HumanoidRootPart", 5)
		if found and found:IsA("BasePart") then
			root = found :: BasePart
		end
	end

	if humanoid == nil or root == nil then
		return
	end

	if ratModel.Parent == nil then
		return
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "RatHealthBar"
	gui.Size = UDim2.new(3, 0, 0.3, 0)
	gui.StudsOffset = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 100
	gui.Adornee = root
	gui.Parent = ratModel
	gui.Enabled = false

	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = VisualManifest.VFX.HealthBarBackground
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = VisualManifest.VFX.HealthGood
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local previousHealth = humanoid.Health

	local function refresh()
		if humanoid.Parent == nil then
			return
		end
		local maxHealth = math.max(1, humanoid.MaxHealth)
		local percent = math.clamp(humanoid.Health / maxHealth, 0, 1)
		if humanoid.Health < previousHealth then
			showDamageNumber(root.Position + Vector3.new(0, 2, 0), math.floor(previousHealth - humanoid.Health + 0.5))
		end
		previousHealth = humanoid.Health
		gui.Enabled = humanoid.Health < maxHealth
		fill.Size = UDim2.fromScale(percent, 1)
		fill.BackgroundColor3 = healthColor(percent)
	end

	refresh()
	ratHealthBars[ratModel] = gui
	ratHealthConnections[ratModel] = {
		humanoid.HealthChanged:Connect(refresh),
		humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh),
		ratModel.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				clearRatHealthBar(ratModel)
			end
		end),
	}
end

local function refreshBaseRadiusMarker()
	if baseRadiusMarker ~= nil and baseRadiusMarker.Parent ~= nil then
		baseRadiusMarker:Destroy()
	end
	baseRadiusMarker = nil

	local titanCore: BasePart? = nil
	for _, tagged in CollectionService:GetTagged("TitanObjective") do
		if tagged:IsA("BasePart") then
			titanCore = tagged
			break
		end
	end
	if titanCore == nil then
		return
	end

	local radius = Constants.WAVES.MinSpawnDistanceFromCenter
	local ring = Instance.new("Model")
	ring.Name = "BaseRadiusMarker"

	local center = Vector3.new(titanCore.Position.X, titanCore.Position.Y, titanCore.Position.Z)
	local groundRayParams = RaycastParams.new()
	groundRayParams.FilterType = Enum.RaycastFilterType.Include
	groundRayParams.FilterDescendantsInstances = { Workspace.Terrain }

	local segmentCount = 56
	local segmentHeight = 0.12
	local segmentThickness = 0.35
	for i = 1, segmentCount do
		local a0 = ((i - 1) / segmentCount) * math.pi * 2
		local a1 = (i / segmentCount) * math.pi * 2

		local x0 = center.X + math.cos(a0) * radius
		local z0 = center.Z + math.sin(a0) * radius
		local x1 = center.X + math.cos(a1) * radius
		local z1 = center.Z + math.sin(a1) * radius

		local hit0 = Workspace:Raycast(Vector3.new(x0, center.Y + 60, z0), Vector3.new(0, -200, 0), groundRayParams)
		local y0 = if hit0 then hit0.Position.Y + 0.08 else 0.08
		local hit1 = Workspace:Raycast(Vector3.new(x1, center.Y + 60, z1), Vector3.new(0, -200, 0), groundRayParams)
		local y1 = if hit1 then hit1.Position.Y + 0.08 else 0.08

		local p0 = Vector3.new(x0, y0, z0)
		local p1 = Vector3.new(x1, y1, z1)
		local mid = (p0 + p1) * 0.5
		local length = (p1 - p0).Magnitude

		local segment = Instance.new("Part")
		segment.Name = "BorderSegment"
		segment.Anchored = true
		segment.CanCollide = false
		segment.Material = Enum.Material.Neon
		segment.Color = VisualManifest.VFX.BaseRadiusMarkerColor
		segment.Transparency = 0.2
		segment.Size = Vector3.new(segmentThickness, segmentHeight, length + 0.04)
		segment.CFrame = CFrame.lookAt(mid, p1)
		segment.Parent = ring
	end

	ring.Parent = Workspace
	baseRadiusMarker = ring
end

local function ensureAmbientDust()
	if ambientDustPart ~= nil and ambientDustPart.Parent ~= nil then
		return
	end
	local part = Instance.new("Part")
	part.Name = "AmbientDustEmitter"
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Position = Vector3.new(0, 8, 0)
	part.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local dust = Instance.new("ParticleEmitter")
	dust.Name = "AmbientDust"
	dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
	dust.Color = ColorSequence.new(VisualManifest.VFX.AmbientDustA, VisualManifest.VFX.AmbientDustB)
	dust.Lifetime = NumberRange.new(4, 6)
	dust.Speed = NumberRange.new(16, 22)
	dust.Acceleration = Vector3.new(2, 0.2, 0)
	dust.Rate = 3
	dust.SpreadAngle = Vector2.new(10, 10)
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(1, 7),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.75),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Parent = attachment

	ambientDustPart = part
end

local function getPlayerRootByName(playerName: string): BasePart?
	for _, player in Players:GetPlayers() do
		if player.Name == playerName then
			local character = player.Character
			if character ~= nil then
				local root = character:FindFirstChild("HumanoidRootPart")
				if root ~= nil and root:IsA("BasePart") then
					return root
				end
			end
		end
	end
	return nil
end

local function startMagnetFlight(part: BasePart)
	for _, flight in activeMagnetFlights do
		if flight.part == part then
			return
		end
	end
	table.insert(activeMagnetFlights, {
		part = part,
		startPos = part.Position,
		elapsed = 0,
	})
end

local function bindMagnetAttribute(part: BasePart)
	part:GetAttributeChangedSignal("MagnetTarget"):Connect(function()
		local target = part:GetAttribute("MagnetTarget")
		if typeof(target) == "string" then
			startMagnetFlight(part)
		end
	end)
	local current = part:GetAttribute("MagnetTarget")
	if typeof(current) == "string" then
		startMagnetFlight(part)
	end
end

local function runMagnetHeartbeat(dt: number)
	local alive: { MagnetFlight } = {}
	for _, flight in activeMagnetFlights do
		if flight.part.Parent == nil then
			continue
		end
		if flight.part:GetAttribute("InstantPickup") then
			continue
		end
		local targetName = flight.part:GetAttribute("MagnetTarget")
		if typeof(targetName) ~= "string" then
			continue
		end
		local root = getPlayerRootByName(targetName :: string)
		if root == nil then
			table.insert(alive, flight)
			continue
		end
		flight.elapsed += dt
		local dist = (root.Position - flight.part.Position).Magnitude
		if dist < 0.5 then
			flight.part.Transparency = 1
			if flight.part:GetAttribute("CriticalHarvest") then
				playCritHarvestVFX(root.Position)
			end
			continue
		end
		local totalDist = (root.Position - flight.startPos).Magnitude
		local progress = if totalDist > 0.1 then math.clamp(1 - dist / totalDist, 0, 1) else 1
		local arcY = math.sin(progress * math.pi) * MAGNET_ARC_HEIGHT
		local targetPos = root.Position + Vector3.new(0, arcY, 0)
		local dir = (targetPos - flight.part.Position)
		local dirMag = dir.Magnitude
		if dirMag > 0.001 then
			local step = MAGNET_FLIGHT_SPEED * dt
			local newPos = flight.part.Position + dir.Unit * math.min(step, dirMag)
			local spinAngle = os.clock() * MAGNET_SPIN_RATE
			flight.part.CFrame = CFrame.new(newPos) * CFrame.Angles(spinAngle, spinAngle * 0.6, math.sin(spinAngle) * 0.3)
		end
		table.insert(alive, flight)
	end
	activeMagnetFlights = alive
end

local function playUpgradeVFX(buildingPart: BasePart, newLevel: number, buildingType: string)
	if buildingPart.Parent == nil then
		return
	end

	local tintTable = VisualManifest.Buildings.UpgradeTints
	local tint = tintTable[newLevel] or tintTable[1]
	local baseColor = VisualManifest.Buildings.BaseColors[buildingType]
	if baseColor ~= nil then
		local t = math.clamp((newLevel - 1) / math.max(1, Constants.BUILDING.MaxLevel - 1), 0, 1) * 0.4
		buildingPart.Color = baseColor:Lerp(tint, t)
	end

	local flash = Instance.new("Part")
	flash.Name = "UpgradeFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = VisualManifest.Buildings.UpgradeFlashColor
	flash.Anchored = true
	flash.CanCollide = false
	flash.Size = Vector3.new(3, 3, 3)
	flash.Position = buildingPart.Position
	flash.Transparency = 0.3
	flash.Parent = Workspace

	TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(18, 18, 18),
		Transparency = 1,
	}):Play()

	task.delay(0.55, function()
		if flash.Parent ~= nil then
			flash:Destroy()
		end
	end)
end

local function playCritHarvestVFX(position: Vector3)
	local flash = Instance.new("Part")
	flash.Name = "CritFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = VisualManifest.VFX.CritHarvestFlashA
	flash.Anchored = true
	flash.CanCollide = false
	flash.Size = Vector3.new(1.5, 1.5, 1.5)
	flash.Position = position
	flash.Transparency = 0.2
	flash.Parent = Workspace

	TweenService:Create(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(8, 8, 8),
		Transparency = 1,
	}):Play()

	task.delay(0.45, function()
		if flash.Parent ~= nil then
			flash:Destroy()
		end
	end)
end

local function bindDrillRotation(drill: BasePart)
	local conn: RBXScriptConnection? = nil
	local rotAcc = 0
	conn = RunService.Heartbeat:Connect(function(dt)
		if drill.Parent == nil then
			if conn ~= nil then
				conn:Disconnect()
			end
			return
		end
		rotAcc += dt
		if rotAcc >= Constants.BUILDING.DrillTickInterval then
			rotAcc -= Constants.BUILDING.DrillTickInterval
			drill.CFrame = drill.CFrame * CFrame.Angles(0, math.rad(20), 0)
			local attachment = drill:FindFirstChild("DrillFxAttachment")
			if attachment ~= nil then
				local emitter = attachment:FindFirstChild("DrillSparks")
				if emitter ~= nil and emitter:IsA("ParticleEmitter") then
					emitter:Emit(18)
				end
			end
		end
	end)
end

local function playClientMuzzleFlash(turretPart: BasePart, targetPos: Vector3)
	local direction = (targetPos - turretPart.Position)
	if direction.Magnitude < 0.01 then
		direction = Vector3.new(0, 0, -1)
	end
	local flash = Instance.new("Part")
	flash.Name = "TurretMuzzleFlash"
	flash.Anchored = true
	flash.CanCollide = false
	flash.Material = VisualManifest.Buildings.TurretMuzzleFlash.material
	flash.Color = VisualManifest.Buildings.TurretMuzzleFlash.color
	flash.Size = Vector3.new(0.25, 0.25, 0.25)
	flash.CFrame = CFrame.lookAt(turretPart.Position + Vector3.new(0, turretPart.Size.Y * 0.35, 0), targetPos) * CFrame.new(0, 0, -1.8)
	flash.Parent = Workspace
	task.delay(0.06, function()
		if flash.Parent ~= nil then
			flash:Destroy()
		end
	end)
end

local function updateRatLOD()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local camPos = camera.CFrame.Position

	for _, instance in CollectionService:GetTagged("ScrapRatEnemy") do
		if not instance:IsA("Model") then
			continue
		end
		local root = instance.PrimaryPart
		if root == nil then
			continue
		end
		local dist = (root.Position - camPos).Magnitude
		local prevState = ratLodState[instance] or "full"
		local newState: string

		if dist > RAT_LOD_HIDE_DISTANCE then
			newState = "hidden"
		elseif dist > RAT_LOD_DETAIL_DISTANCE then
			newState = "simple"
		else
			newState = "full"
		end

		if newState ~= prevState then
			ratLodState[instance] = newState
			if newState == "hidden" then
				for _, child in instance:GetChildren() do
					if child:IsA("BasePart") then
						child.Transparency = 1
					end
				end
			elseif newState == "simple" then
				for _, child in instance:GetChildren() do
					if child:IsA("BasePart") then
						local isDetail = false
						for _, detailName in LOD_DETAIL_PARTS do
							if child.Name == detailName then
								isDetail = true
								break
							end
						end
						child.Transparency = if isDetail then 1 else 0
					end
				end
			else
				for _, child in instance:GetChildren() do
					if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
						child.Transparency = 0
					end
				end
				root.Transparency = 0
			end
		end
	end
end

local function bindTurretFireWatch(turretPart: BasePart)
	turretPart:GetAttributeChangedSignal("LastFireTarget"):Connect(function()
		local targetVal = turretPart:GetAttribute("LastFireTarget")
		if typeof(targetVal) == "Vector3" then
			playClientMuzzleFlash(turretPart, targetVal :: Vector3)
		end
	end)
end

local function applyQualityLevel(level: number)
	currentQuality = level
	RAT_LOD_DETAIL_DISTANCE = if level == QUALITY_LOW then 40 elseif level == QUALITY_MEDIUM then 60 else 80
	RAT_LOD_HIDE_DISTANCE = if level == QUALITY_LOW then 80 elseif level == QUALITY_MEDIUM then 120 else 150

	if ambientDustPart ~= nil and ambientDustPart.Parent ~= nil then
		local attachment = ambientDustPart:FindFirstChildOfClass("Attachment")
		if attachment ~= nil then
			local dust = attachment:FindFirstChild("AmbientDust")
			if dust ~= nil and dust:IsA("ParticleEmitter") then
				if level == QUALITY_LOW then
					dust.Rate = 0
				elseif level == QUALITY_MEDIUM then
					dust.Rate = 1.5
				else
					dust.Rate = 3
				end
			end
		end
	end

	MAGNET_ARC_HEIGHT = if level == QUALITY_LOW then 0 else 1.5
end

local function updateFrameBudget(dt: number)
	if manualQualityOverride ~= nil then
		return
	end
	table.insert(frameTimes, dt * 1000)
	if #frameTimes > FRAME_BUDGET_WINDOW then
		table.remove(frameTimes, 1)
	end
	if #frameTimes < FRAME_BUDGET_WINDOW then
		return
	end
	local total = 0
	for _, ms in frameTimes do
		total += ms
	end
	local avg = total / #frameTimes
	if avg > FRAME_BUDGET_THRESHOLD_MS and currentQuality > QUALITY_LOW then
		applyQualityLevel(currentQuality - 1)
	elseif avg < FRAME_BUDGET_THRESHOLD_MS * 0.7 and currentQuality < QUALITY_HIGH then
		applyQualityLevel(currentQuality + 1)
	end
end

function VFXController.SetQuality(level: number)
	local clamped = math.clamp(math.floor(level + 0.5), QUALITY_LOW, QUALITY_HIGH)
	manualQualityOverride = clamped
	applyQualityLevel(clamped)
end

function VFXController.GetQuality(): number
	return currentQuality
end

function VFXController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	for _ = 1, POOL_SIZE do
		table.insert(gearPool, createGearPart())
	end

	if Platform.IsMobile and manualQualityOverride == nil then
		applyQualityLevel(QUALITY_LOW)
	end

	ensureAmbientDust()

	local lodAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		runMagnetHeartbeat(dt)
		updateFrameBudget(dt)
		lodAcc += dt
		if lodAcc >= 0.5 then
			lodAcc = 0
			updateRatLOD()
		end
	end)

	Workspace.ChildAdded:Connect(function(child)
		if child:IsA("BasePart")
			and (child.Name == "JunkBlock" or child.Name == "RatCache" or child.Name == "StormHardenedSteel" or child.Name == "PowerUpOrb")
		then
			bindMagnetAttribute(child)
		end
	end)
	for _, child in Workspace:GetChildren() do
		if child:IsA("BasePart")
			and (child.Name == "JunkBlock" or child.Name == "RatCache" or child.Name == "StormHardenedSteel" or child.Name == "PowerUpOrb")
		then
			bindMagnetAttribute(child)
		end
	end

	for _, instance in CollectionService:GetTagged("DismantlableBuilding") do
		if instance:IsA("BasePart") then
			bindDismantlable(instance)
		end
	end

	CollectionService:GetInstanceAddedSignal("DismantlableBuilding"):Connect(function(instance)
		if instance:IsA("BasePart") then
			bindDismantlable(instance)
		end
	end)

	for _, instance in CollectionService:GetTagged("Drill") do
		if instance:IsA("BasePart") then
			bindDrillFx(instance)
			bindDrillRotation(instance)
		end
	end

	CollectionService:GetInstanceAddedSignal("Drill"):Connect(function(instance)
		if instance:IsA("BasePart") then
			bindDrillFx(instance)
			bindDrillRotation(instance)
		end
	end)

	for _, instance in CollectionService:GetTagged("DismantlableBuilding") do
		if instance:IsA("BasePart") and instance:GetAttribute("BuildingType") == "Turret" then
			bindTurretFireWatch(instance)
		end
	end
	CollectionService:GetInstanceAddedSignal("DismantlableBuilding"):Connect(function(instance)
		if instance:IsA("BasePart") and instance:GetAttribute("BuildingType") == "Turret" then
			bindTurretFireWatch(instance)
		end
	end)

	for _, instance in CollectionService:GetTagged("ScrapRatEnemy") do
		if instance:IsA("Model") then
			task.spawn(bindRatHealthBar, instance)
		end
	end

	CollectionService:GetInstanceAddedSignal("ScrapRatEnemy"):Connect(function(instance)
		if instance:IsA("Model") then
			task.spawn(bindRatHealthBar, instance)
		end
	end)

	refreshBaseRadiusMarker()
	CollectionService:GetInstanceAddedSignal("TitanObjective"):Connect(function(instance)
		if instance:IsA("BasePart") then
			task.defer(refreshBaseRadiusMarker)
		end
	end)

	remotes.ScrapUpdated.OnClientEvent:Connect(function(newValue: number)
		local delta = newValue - lastScrap
		if delta > 0 then
			playLootFountain(delta)
			local character = LocalPlayer.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if root ~= nil and root:IsA("BasePart") then
				playScrapSparkleBurst(root.Position, delta)
				showPickupNumber(root.Position, ("+%d"):format(delta), VisualManifest.VFX.ScrapPickupSparkle)
			end
			local now = os.clock()
			if now - lastScrapPickupAt <= 1.2 then
				scrapComboCount += 1
			else
				scrapComboCount = 1
			end
			lastScrapPickupAt = now
			if scrapComboCount >= 3 then
				showScrapCombo(scrapComboCount)
			end
			if scrapComboCount >= 5 then
				flashScrapComboVignette()
			end
			local ching = Instance.new("Sound")
			ching.SoundId = AudioManifest.LootCollect
			ching.Volume = 0.25
			ching.PlaybackSpeed = math.min(1.8, 1.2 + (scrapComboCount * 0.03))
			ching.Parent = SoundService
			ching:Play()
			ching.Ended:Connect(function()
				if ching.Parent ~= nil then
					ching:Destroy()
				end
			end)
		end
		lastScrap = newValue
	end)

	remotes.StormSteelUpdated.OnClientEvent:Connect(function(newValue: number)
		local delta = newValue - lastStormSteel
		if delta > 0 then
			local chime = Instance.new("Sound")
			chime.SoundId = AudioManifest.SteelCollect
			chime.Volume = 0.4
			chime.PlaybackSpeed = 1.3 + math.random() * 0.2
			chime.Parent = SoundService
			chime:Play()
			chime.Ended:Connect(function()
				if chime.Parent ~= nil then
					chime:Destroy()
				end
			end)

			local character = LocalPlayer.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if root ~= nil and root:IsA("BasePart") then
				local ring = Instance.new("Part")
				ring.Name = "SteelPickupFlash"
				ring.Shape = Enum.PartType.Ball
				ring.Material = Enum.Material.Neon
				ring.Color = VisualManifest.VFX.SteelPickupFlashColor
				ring.Anchored = true
				ring.CanCollide = false
				ring.Size = Vector3.new(2, 2, 2)
				ring.Position = root.Position
				ring.Transparency = 0.4
				ring.Parent = Workspace
				TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = Vector3.new(12, 12, 12),
					Transparency = 1,
				}):Play()
				task.delay(0.45, function()
					if ring.Parent ~= nil then
						ring:Destroy()
					end
				end)
			end
		end
		lastStormSteel = newValue
	end)

	remotes.EnemyKilled.OnClientEvent:Connect(function(position: Vector3)
		playEnemyDeathFx(position)
	end)

	remotes.PowerUpSpawned.OnClientEvent:Connect(function(orbPart: Instance, _powerUpType: string)
		if orbPart:IsA("BasePart") then
			bindMagnetAttribute(orbPart)
		end
	end)
	remotes.PowerUpCollected.OnClientEvent:Connect(function(_collector: Player, powerUpType: string, position: Vector3, hitPositions: { Vector3 }?)
		if powerUpType == "Lightning" then
			playLightningPowerUpVFX(position, hitPositions)
		elseif powerUpType == "Shockwave" then
			playShockwavePowerUpVFX(position)
		elseif powerUpType == "RepairAura" then
			playRepairAuraVFX(position, hitPositions)
		elseif powerUpType == "TitanPush" then
			local titanCenter = position
			for _, tagged in CollectionService:GetTagged("TitanObjective") do
				if tagged:IsA("BasePart") then
					titanCenter = tagged.Position
					break
				end
			end
			playTitanPushVFX(titanCenter, hitPositions)
		elseif powerUpType == "LootVacuum" then
			playLootVacuumVFX(position)
		end
	end)

	remotes.BlueprintFinished.OnClientEvent:Connect(function(_blueprintId: string, position: Vector3)
		playBuildFlash(position)
	end)

	remotes.BuildingUpgraded.OnClientEvent:Connect(function(buildingPart: BasePart, newLevel: number, buildingType: string)
		if typeof(buildingPart) == "Instance" and buildingPart:IsA("BasePart") then
			playUpgradeVFX(buildingPart, newLevel, buildingType)
		end
	end)
	remotes.StormStarted.OnClientEvent:Connect(function()
		startStormFx()
	end)
	remotes.StormEnded.OnClientEvent:Connect(function()
		stopStormFx()
	end)
	remotes.DrillRepaired.OnClientEvent:Connect(function(position: Vector3)
		playRepairSuccessFx(position)
	end)
	remotes.DrillBonusShower.OnClientEvent:Connect(function(drillPositions: { Vector3 })
		playDrillBonusShowerVFX(drillPositions)
	end)
	remotes.GlobalVictory.OnClientEvent:Connect(function()
		local titanCore: BasePart? = nil
		for _, tagged in CollectionService:GetTagged("TitanObjective") do
			if tagged:IsA("BasePart") then
				titanCore = tagged
				break
			end
		end
		if titanCore == nil then
			return
		end

		local sphere = Instance.new("Part")
		sphere.Name = "VictoryShockwave"
		sphere.Shape = Enum.PartType.Ball
		sphere.Material = Enum.Material.Neon
		sphere.Color = VisualManifest.VFX.VictoryShockwaveColor
		sphere.Anchored = true
		sphere.CanCollide = false
		sphere.Size = Vector3.new(4, 4, 4)
		sphere.Position = titanCore.Position
		sphere.Transparency = 0.3
		sphere.Parent = Workspace

		TweenService:Create(sphere, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(500, 500, 500),
			Transparency = 1,
		}):Play()

		task.delay(2.6, function()
			if sphere.Parent ~= nil then
				sphere:Destroy()
			end
		end)
	end)
	MainHUD.ConnectWaveTimerZero(function()
		playWaveHorn()
	end)

	remotes.WaveStarted.OnClientEvent:Connect(function()
		waveIntensityActive = true
		local splashGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if splashGui ~= nil then
			local hud = splashGui:FindFirstChild("MainHUDGui")
			if hud ~= nil and hud:IsA("ScreenGui") then
				local splash = Instance.new("TextLabel")
				splash.Name = "WaveSplash"
				splash.AnchorPoint = Vector2.new(0.5, 0.5)
				splash.Position = UDim2.new(0.5, 0, 0.2, 0)
				splash.Size = UDim2.fromOffset(460, 72)
				splash.BackgroundTransparency = 1
				splash.Font = Enum.Font.GothamBlack
				splash.TextScaled = true
				splash.TextStrokeTransparency = 0.45
				splash.TextColor3 = VisualManifest.VFX.WaveSplashColor
				splash.Text = "WAVE INCOMING"
				splash.Parent = hud
				TweenService:Create(splash, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					TextTransparency = 1,
					TextStrokeTransparency = 1,
					Position = UDim2.new(0.5, 0, 0.14, 0),
				}):Play()
				task.delay(0.52, function()
					if splash.Parent ~= nil then
						splash:Destroy()
					end
				end)
			end
		end
		local slam = Instance.new("Sound")
		slam.SoundId = AudioManifest.WaveSlam
		slam.Volume = 0.25
		slam.PlaybackSpeed = 1.12
		slam.Parent = SoundService
		slam:Play()
		slam.Ended:Connect(function()
			if slam.Parent ~= nil then
				slam:Destroy()
			end
		end)
		if dayMusic and dayMusic.Parent then
			TweenService:Create(dayMusic, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Volume = 0,
			}):Play()
		end
		if waveMusic and waveMusic.Parent then
			TweenService:Create(waveMusic, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Volume = 0.18,
			}):Play()
		end
	end)

	remotes.SwarmEnded.OnClientEvent:Connect(function()
		waveIntensityActive = false
		if waveMusic and waveMusic.Parent then
			TweenService:Create(waveMusic, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Volume = 0,
			}):Play()
		end
		if dayMusic and dayMusic.Parent then
			TweenService:Create(dayMusic, TweenInfo.new(2.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Volume = 0.12,
			}):Play()
		end
	end)

	dayMusic = Instance.new("Sound")
	dayMusic.Name = "DayMusic"
	dayMusic.SoundId = AudioManifest.WaveCombat or AudioManifest.AmbientBase
	dayMusic.Looped = true
	dayMusic.Volume = 0
	dayMusic.Parent = SoundService
	dayMusic:Play()

	waveMusic = Instance.new("Sound")
	waveMusic.Name = "WaveMusic"
	waveMusic.SoundId = AudioManifest.DayAmbient or AudioManifest.AmbientBase
	waveMusic.Looped = true
	waveMusic.Volume = 0
	waveMusic.Parent = SoundService
	waveMusic:Play()
	task.delay(3, function()
		if waveMusic == nil or waveMusic.Parent == nil then
			return
		end
		if not waveMusic.IsLoaded then
			warn("[VFXController] WaveCombat failed to load; using fallback track.")
			waveMusic.SoundId = AudioManifest.AmbientBase
			waveMusic:Play()
		end
	end)

	TweenService:Create(dayMusic, TweenInfo.new(4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Volume = 0.12,
	}):Play()
end

return VFXController
