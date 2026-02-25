--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local VisualManifest = require(Shared:WaitForChild("VisualManifest"))
local RemotesModule = require(Shared:WaitForChild("Remotes"))

local TweenService = game:GetService("TweenService")

local EconomyService = require(script.Parent:WaitForChild("EconomyService"))
local BuildingService = require(script.Parent:WaitForChild("BuildingService"))
local PlayerTrackingService = require(script.Parent:WaitForChild("PlayerTrackingService"))
local ObjectiveService = require(script.Parent:WaitForChild("ObjectiveService"))

local EnemyService: any = nil
local function getEnemyService()
	if EnemyService == nil then
		EnemyService = require(script.Parent:WaitForChild("EnemyService"))
	end
	return EnemyService
end

local StormService = {}

local remotes = RemotesModule.Get()
local activeStorm = false
local permanentStorm = false
local gameActive = true
local tetherPads: { BasePart } = {}
local activeStormSteel: { BasePart } = {}
local pickedSteel: { [BasePart]: boolean } = {}

local function spawnTetherPads()
	local center = Vector3.new(0, 0.5, 0)
	local spacing = 16
	local offsets = {
		Vector3.new(-spacing, 0, -spacing),
		Vector3.new(spacing, 0, -spacing),
		Vector3.new(0, 0, spacing),
	}

	for index, offset in offsets do
		local pad = Instance.new("Part")
		pad.Name = ("TetherPad%d"):format(index)
		pad.Anchored = true
		pad.CanCollide = false
		pad.Material = VisualManifest.TetherPad.PadMaterial
		pad.Color = VisualManifest.TetherPad.PadColor
		pad.Size = Vector3.new(0.2, 0.05, 0.2)
		pad.Position = center + offset
		pad.Parent = Workspace
		CollectionService:AddTag(pad, "TetherPad")
		table.insert(tetherPads, pad)

		local ring = Instance.new("Part")
		ring.Name = "TetherRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.Material = VisualManifest.TetherPad.RingMaterial
		ring.Color = VisualManifest.TetherPad.RingColor
		ring.Transparency = 0.25
		ring.Size = Vector3.new(0.18, 0.2, 0.2)
		ring.CFrame = CFrame.new(pad.Position + Vector3.new(0, 0.16, 0)) * CFrame.Angles(math.rad(90), 0, 0)
		ring.Parent = pad

		local bolt = Instance.new("Part")
		bolt.Name = "TetherBolt"
		bolt.Anchored = true
		bolt.CanCollide = false
		bolt.Material = VisualManifest.TetherPad.BoltMaterial
		bolt.Color = VisualManifest.TetherPad.BoltColor
		bolt.Size = Vector3.new(0.8, 0.2, 0.8)
		bolt.CFrame = CFrame.new(pad.Position + Vector3.new(0, 0.2, 0))
		bolt.Parent = pad

		local tween = TweenService:Create(pad, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = Vector3.new(8, 0.6, 8),
		})
		task.delay(index * 0.15, function()
			tween:Play()
		end)
	end
end

local function clearTetherPads()
	for _, pad in tetherPads do
		if pad.Parent ~= nil then
			pad:Destroy()
		end
	end
	tetherPads = {}
end

local function countAnchoredPads(): number
	local occupied = 0
	for _, pad in tetherPads do
		if pad.Parent ~= nil then
			local touchingPlayers = {}
			for _, player in Players:GetPlayers() do
				local character = player.Character
				local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
				if root ~= nil and root:IsA("BasePart") then
					local distance = (root.Position - pad.Position).Magnitude
					if distance <= Constants.STORM.TetherPadRadius then
						touchingPlayers[player.UserId] = true
					end
				end
			end

			if next(touchingPlayers) ~= nil then
				occupied += 1
			end
		end
	end

	return occupied
end

local function requiredPadCount(): number
	if PlayerTrackingService.HasLostPlayers() then
		return Constants.STORM.TetherPadsReducedOnLeave
	end

	return Constants.STORM.TetherPadsRequired
end

local function applyStormWindDamage()
	for _, instance in CollectionService:GetTagged("DismantlableBuilding") do
		if instance:IsA("BasePart") and instance.Parent ~= nil then
			local hpAttr = instance:GetAttribute("BuildingHP")
			local currentHP = if typeof(hpAttr) == "number" then (hpAttr :: number) else Constants.BUILDING.DefaultHP
			local nextHP = currentHP - Constants.STORM.WindDamagePerSecond

			if nextHP <= 0 then
				local destroyedPos = instance.Position
				local buildingType = instance:GetAttribute("BuildingType")
				remotes.BuildingDismantled:FireAllClients("StormDamage", destroyedPos)
				instance:Destroy()
				BuildingService.RegisterDestroyedSlot(destroyedPos, buildingType)
			else
				instance:SetAttribute("BuildingHP", nextHP)
			end
		end
	end
end

local function spawnStormSteelDuringStorm()
	local radius = Constants.STORM.SteelSpawnRadius
	for _ = 1, Constants.STORM.StormSteelDropCount do
		local drop = Instance.new("Part")
		drop.Name = "StormHardenedSteel"
		drop.Shape = Enum.PartType.Ball
		drop.Material = VisualManifest.Loot.StormSteel.material
		drop.Color = VisualManifest.Loot.StormSteel.color
		drop.Size = Vector3.new(1.6, 1.6, 1.6)
		drop.Position = Vector3.new(math.random(-radius, radius), 3, math.random(-radius, radius))
		drop.Anchored = false
		drop.CanCollide = true
		drop.Parent = Workspace
		table.insert(activeStormSteel, drop)

		local picked = false
		drop.Touched:Connect(function(hit: BasePart)
			if picked then
				return
			end

			local model = hit:FindFirstAncestorOfClass("Model")
			if model == nil then
				return
			end

			local player = Players:GetPlayerFromCharacter(model)
			if player == nil then
				return
			end

			picked = true
			EconomyService.AddStormSteel(1)
			drop:Destroy()
		end)
	end
end

local function clearStormSteel()
	for _, drop in activeStormSteel do
		if drop.Parent ~= nil then
			drop:Destroy()
		end
	end
	activeStormSteel = {}
end

local function runStorm()
	activeStorm = true
	remotes.StormStarted:FireAllClients()
	spawnTetherPads()
	spawnStormSteelDuringStorm()

	local elapsed = 0
	local duration = if permanentStorm then math.huge else Constants.STORM.DurationSeconds

	while activeStorm and elapsed < duration and gameActive do
		task.wait(1)
		elapsed += 1

		local occupiedPads = countAnchoredPads()
		local neededPads = requiredPadCount()
		remotes.TetherStatus:FireAllClients(occupiedPads, neededPads)

		if occupiedPads < neededPads then
			applyStormWindDamage()
		end

		if permanentStorm and elapsed % 30 == 0 then
			spawnStormSteelDuringStorm()
		end
	end

	clearTetherPads()
	task.delay(3, clearStormSteel)
	remotes.TetherStatus:FireAllClients(0, 0)
	activeStorm = false
	remotes.StormEnded:FireAllClients()
end

function StormService.TriggerStormNow(): boolean
	if activeStorm then
		return false
	end

	task.spawn(runStorm)
	return true
end

function StormService.StartPermanentStorm(): ()
	permanentStorm = true
	if activeStorm then
		return
	end
	task.spawn(runStorm)
end

function StormService.StopStorm(): ()
	gameActive = false
	activeStorm = false
	permanentStorm = false
	clearTetherPads()
	clearStormSteel()
end

function StormService.Init(): ()
	ObjectiveService.ConnectGameStateChanged(function(state: string)
		if state == "final_stand" then
			StormService.StartPermanentStorm()
		elseif state == "victory" then
			StormService.StopStorm()
			remotes.StormEnded:FireAllClients()
		end
	end)

	task.spawn(function()
		while gameActive do
			task.wait(Constants.STORM.IntervalSeconds)
			if not activeStorm and gameActive then
				while gameActive do
					local isSwarm = false
					pcall(function()
						isSwarm = getEnemyService().IsSwarmActive()
					end)
					if not isSwarm then
						break
					end
					task.wait(1)
				end
				if gameActive and not activeStorm then
					StormService.TriggerStormNow()
				end
			end
		end
	end)

	local STEEL_MAGNET_TICK = 0.05
	local STEEL_PULL_SPEED = 35
	local STEEL_MAGNET_RADIUS = 7
	local steelMagnetAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		steelMagnetAcc += dt
		if steelMagnetAcc < STEEL_MAGNET_TICK then
			return
		end
		steelMagnetAcc = 0

		for _, drop in activeStormSteel do
			if drop.Parent == nil or pickedSteel[drop] then
				continue
			end

			local nearestRoot: BasePart? = nil
			local nearestDist = STEEL_MAGNET_RADIUS + 1

			for _, player in Players:GetPlayers() do
				local character = player.Character
				if character == nil then
					continue
				end
				local root = character:FindFirstChild("HumanoidRootPart")
				if root == nil or not root:IsA("BasePart") then
					continue
				end
				local pDist = (root.Position - drop.Position).Magnitude
				if pDist < nearestDist then
					nearestDist = pDist
					nearestRoot = root
				end
			end

			if nearestRoot ~= nil and nearestDist <= STEEL_MAGNET_RADIUS then
				if not drop.Anchored then
					drop.Anchored = true
					local sparkle = Instance.new("ParticleEmitter")
					sparkle.Name = "SteelSparkle"
					sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
					sparkle.Color = ColorSequence.new(VisualManifest.VFX.SteelSparkleA, VisualManifest.VFX.SteelSparkleB)
					sparkle.Lifetime = NumberRange.new(0.15, 0.3)
					sparkle.Speed = NumberRange.new(2, 5)
					sparkle.Rate = 40
					sparkle.SpreadAngle = Vector2.new(180, 180)
					sparkle.Size = NumberSequence.new(0.15, 0.03)
					sparkle.LightEmission = 1
					sparkle.Parent = drop
				end

				if nearestDist <= 1.5 then
					pickedSteel[drop] = true
					EconomyService.AddStormSteel(1)
					drop:Destroy()
				else
					local distRatio = nearestDist / STEEL_MAGNET_RADIUS
					local arcY = math.sin(distRatio * math.pi) * 2.0
					local targetPos = nearestRoot.Position + Vector3.new(0, arcY, 0)
					local dir = (targetPos - drop.Position).Unit
					local step = STEEL_PULL_SPEED * STEEL_MAGNET_TICK
					drop.Position = drop.Position + dir * math.min(step, nearestDist)
				end
			end
		end
	end)
end

return StormService
