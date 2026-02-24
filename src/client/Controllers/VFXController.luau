--!strict

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local VFXController = {}

local POOL_SIZE = 20
local isInitialized = false
local remotes = Remotes.Get()
local lastScrap = 0

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
local baseAmbient = Lighting.Ambient
local baseBrightness = Lighting.Brightness

local function createGearPart(): BasePart
	local part = Instance.new("Part")
	part.Name = "LootGear"
	part.Size = Vector3.new(0.6, 0.6, 0.2)
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.Metal
	part.Color = Color3.fromRGB(184, 171, 94)
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

	task.spawn(function()
		local count = math.clamp(math.floor(increaseAmount / 5), 5, 8)
		for _ = 1, count do
			local gear = acquireGear()
			local spawnBase = if sourcePosition ~= nil then sourcePosition else root.Position
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
		end
	end)
end

local function createSparkEmitter(part: BasePart): ParticleEmitter
	local attachment = Instance.new("Attachment")
	attachment.Name = "DismantleSparkAttachment"
	attachment.Parent = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "DismantleSparks"
	emitter.Parent = attachment
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 80, 60), Color3.fromRGB(255, 140, 50))
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

local function bindDismantlable(part: BasePart)
	part:GetAttributeChangedSignal("IsBeingDismantled"):Connect(function()
		refreshDismantleState(part)
	end)
	part.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			stopDismantleEffect(part)
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
	emitter.Color = ColorSequence.new(Color3.fromRGB(70, 70, 70), Color3.fromRGB(30, 30, 30))
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

local function bindDrillFx(drill: BasePart)
	drill:GetAttributeChangedSignal("Stability"):Connect(function()
		refreshDrillSmoke(drill)
	end)
	drill.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clearDrillSmoke(drill)
		end
	end)
	refreshDrillSmoke(drill)
end

local function playBuildFlash(position: Vector3)
	local ring = Instance.new("Part")
	ring.Name = "BuildFlashRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 170, 60)
	ring.Anchored = true
	ring.CanCollide = false
	ring.Size = Vector3.new(0.3, 5, 5)
	ring.CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(math.rad(90), 0, 0)
	ring.Parent = Workspace

	local expandTween = TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, 16, 16),
		Transparency = 1,
	})
	expandTween:Play()
	expandTween.Completed:Connect(function()
		ring:Destroy()
	end)

	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		local original = camera.CFrame
		local offset = CFrame.new(math.random(-10, 10) / 120, math.random(-10, 10) / 120, 0)
		local shakeOut = TweenService:Create(camera, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = original * offset,
		})
		shakeOut:Play()
		shakeOut.Completed:Connect(function()
			local shakeBack = TweenService:Create(camera, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = original,
			})
			shakeBack:Play()
		end)
	end
end

local function startStormFx()
	local ambientTarget = Color3.fromRGB(30, 20, 10)
	local brightnessTarget = 0.5
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
	TweenService:Create(stormBlur, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = 12 }):Play()

	if stormColor == nil then
		stormColor = Instance.new("ColorCorrectionEffect")
		stormColor.Name = "StormColor"
		stormColor.TintColor = Color3.fromRGB(255, 255, 255)
		stormColor.Parent = Lighting
	end
	TweenService:Create(stormColor, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TintColor = Color3.fromRGB(130, 95, 65),
	}):Play()

	if stormWindSound == nil then
		stormWindSound = Instance.new("Sound")
		stormWindSound.Name = "StormWind"
		stormWindSound.SoundId = "rbxassetid://9125347736"
		stormWindSound.Looped = true
		stormWindSound.Volume = 0.3
		stormWindSound.Parent = SoundService
	end
	stormWindSound:Play()

	if stormRattleSound == nil then
		stormRattleSound = Instance.new("Sound")
		stormRattleSound.Name = "StormRattle"
		stormRattleSound.SoundId = "rbxassetid://130797915"
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
			TintColor = Color3.fromRGB(255, 255, 255),
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
	burst.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 215, 130))
	burst.Lifetime = NumberRange.new(0.2, 0.35)
	burst.Speed = NumberRange.new(4, 8)
	burst.SpreadAngle = Vector2.new(60, 60)
	burst.Rate = 0
	burst.Parent = attachment
	burst:Emit(24)

	local hiss = Instance.new("Sound")
	hiss.Name = "RepairSteamHiss"
	hiss.SoundId = "rbxassetid://9118823107"
	hiss.Volume = 0.25
	hiss.Parent = SoundService
	hiss:Play()

	local clank = Instance.new("Sound")
	clank.Name = "RepairClank"
	clank.SoundId = "rbxassetid://12222253"
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

function VFXController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	for _ = 1, POOL_SIZE do
		table.insert(gearPool, createGearPart())
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
		end
	end

	CollectionService:GetInstanceAddedSignal("Drill"):Connect(function(instance)
		if instance:IsA("BasePart") then
			bindDrillFx(instance)
		end
	end)

	remotes.ScrapUpdated.OnClientEvent:Connect(function(newValue: number)
		local delta = newValue - lastScrap
		if delta > 0 then
			playLootFountain(delta)
		end
		lastScrap = newValue
	end)
	remotes.EnemyKilled.OnClientEvent:Connect(function(position: Vector3)
		playLootFountain(Constants.COMBAT.RatKillScrapReward, position)
	end)

	remotes.BlueprintFinished.OnClientEvent:Connect(function(_blueprintId: string, position: Vector3)
		playBuildFlash(position)
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
end

return VFXController
