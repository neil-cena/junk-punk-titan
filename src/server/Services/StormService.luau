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
local nextStormTime = 0
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
				local destroyedPos = instance.Position - Vector3.new(0, instance.Size.Y * 0.5, 0)
				local buildingType = instance:GetAttribute("BuildingType")
				local rotationAttr = instance:GetAttribute("BuildingRotation")
				local buildingRotation = if typeof(rotationAttr) == "number"
					then (rotationAttr :: number)
					else math.deg(select(2, instance.CFrame:ToEulerAnglesYXZ()))
				remotes.BuildingDismantled:FireAllClients("StormDamage", destroyedPos)
				instance:Destroy()
				BuildingService.RegisterDestroyedSlot(destroyedPos, buildingType)
				BuildingService.PlaceRuinGhost(destroyedPos, buildingType, buildingRotation)
				BuildingService.TriggerCatchupBoost("storm_damage")
			else
				instance:SetAttribute("BuildingHP", nextHP)
			end
		end
	end
end

local function spawnStormSteelDuringStorm()
	local dropCount = Constants.STORM.StormSteelDropCount
	local minRadius = Constants.STORM.SteelSpawnMinRadius or 50
	local maxRadius = Constants.STORM.SteelSpawnMaxRadius or 58
	for i = 1, dropCount do
		local angle = (i / dropCount) * math.pi * 2 + math.random() * 0.3
		local dist = minRadius + math.random() * (maxRadius - minRadius)
		local x = math.cos(angle) * dist
		local z = math.sin(angle) * dist
		local drop = Instance.new("Part")
		drop.Name = "StormHardenedSteel"
		drop.Shape = Enum.PartType.Ball
		drop.Material = VisualManifest.Loot.StormSteel.material
		drop.Color = VisualManifest.Loot.StormSteel.color
		drop.Size = Vector3.new(1.6, 1.6, 1.6)
		drop.Position = Vector3.new(x, 3, z)
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
	nextStormTime = 0
	remotes.Folder:SetAttribute("NextStormTime", 0)
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
	nextStormTime = os.time() + Constants.STORM.IntervalSeconds
	remotes.Folder:SetAttribute("NextStormTime", nextStormTime)
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
	nextStormTime = os.time() + Constants.STORM.IntervalSeconds
	remotes.Folder:SetAttribute("NextStormTime", nextStormTime)

	task.spawn(function()
		while gameActive do
			task.wait(1)
			remotes.Folder:SetAttribute("NextStormTime", nextStormTime)
		end
	end)

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

	local STEEL_MAGNET_TICK = 0.15
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

			local nearestPlayer: Player? = nil
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
					nearestPlayer = player
				end
			end

			if nearestPlayer ~= nil and nearestDist <= STEEL_MAGNET_RADIUS then
				pickedSteel[drop] = true
				local isInstant = nearestDist <= Constants.SCRAP_SPAWNS.InstantPickupRadius
				drop:SetAttribute("MagnetTarget", nearestPlayer.Name)
				if isInstant then
					drop:SetAttribute("InstantPickup", true)
				end
				EconomyService.AddStormSteel(1)
				if isInstant then
					task.defer(function()
						if drop.Parent ~= nil then
							drop:Destroy()
						end
					end)
				else
					task.delay(0.5, function()
						if drop.Parent ~= nil then
							drop:Destroy()
						end
					end)
				end
			else
				if drop:GetAttribute("MagnetTarget") ~= nil then
					drop:SetAttribute("MagnetTarget", nil)
				end
			end
		end
	end)
end

return StormService
