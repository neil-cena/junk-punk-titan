--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local VisualManifest = require(Shared:WaitForChild("VisualManifest"))
local RemotesModule = require(Shared:WaitForChild("Remotes"))
local TheftComponent = require(Shared:WaitForChild("TheftComponent"))
local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

local ObjectiveService = {}

local TITAN_TAG = "TitanObjective"
local TITAN_MODEL_NAME = "TitanChassis"
local TITAN_CORE_NAME = "TitanCore"
local ATTR_INTEGRITY = "TitanIntegrity"
local ATTR_STAGE = "TitanStage"
local ATTR_GAME_STATE = "GameState"

local remotes = RemotesModule.Get()
local gameStateSignal = Instance.new("BindableEvent")

local titanModel: Model? = nil
local titanCore: BasePart? = nil
local depositPrompt: ProximityPrompt? = nil
local integrity = 100
local currentStage = 0
local gameState = "playing"
local sessionStartTime = 0

local STAGE_VISUALS = VisualManifest.Titan.StageVisuals

local function resolveMapCenterY(): number
	local rayResult = Workspace:Raycast(Vector3.new(0, 200, 0), Vector3.new(0, -500, 0))
	if rayResult ~= nil then
		return rayResult.Position.Y
	end
	return 0
end

local function setGameState(newState: string)
	gameState = newState
	if titanModel ~= nil then
		titanModel:SetAttribute(ATTR_GAME_STATE, gameState)
	end
	gameStateSignal:Fire(newState)
end

local function setIntegrity(value: number)
	integrity = math.clamp(value, 0, 100)
	if titanModel ~= nil then
		titanModel:SetAttribute(ATTR_INTEGRITY, integrity)
	end
end

local function updateTitanVisuals(stage: number)
	local core = titanCore
	if core == nil then
		return
	end

	local visuals = STAGE_VISUALS[stage]
	if visuals then
		core.Color = visuals.color
		core.Material = visuals.material
	end

	local light = core:FindFirstChild("TitanGlow") :: PointLight?
	if stage >= 1 and light == nil then
		local newLight = Instance.new("PointLight")
		newLight.Name = "TitanGlow"
		newLight.Color = VisualManifest.Titan.GlowColor
		newLight.Parent = core
		light = newLight
	end
	if light ~= nil then
		light.Brightness = stage * 1.5
		light.Range = 15 + stage * 5
	end

	local parentModel = core.Parent
	if parentModel ~= nil and parentModel:IsA("Model") then
		for ringIndex = 1, 4 do
			local ring = parentModel:FindFirstChild(("StageRing%d"):format(ringIndex))
			if ring ~= nil and ring:IsA("BasePart") then
				ring.Material = if ringIndex <= stage then VisualManifest.Titan.StageRingActiveMaterial else VisualManifest.Titan.StageRingInactiveMaterial
				ring.Color = if ringIndex <= stage then VisualManifest.Titan.StageRingActiveColor else VisualManifest.Titan.StageRingInactiveColor
			end
		end
	end
end

local function updatePromptText()
	if depositPrompt == nil then
		return
	end

	local nextStage = currentStage + 1
	if nextStage > 4 then
		depositPrompt.Enabled = false
		return
	end

	local req = Constants.TITAN.Stages[nextStage]
	if req.steel > 0 then
		depositPrompt.ActionText = ("Stage %d: %d Scrap + %d Steel"):format(nextStage, req.scrap, req.steel)
	else
		depositPrompt.ActionText = ("Stage %d: %d Scrap"):format(nextStage, req.scrap)
	end
end

local function triggerGameOver()
	if gameState == "defeat" or gameState == "victory" then
		return
	end
	setGameState("defeat")
	remotes.GlobalGameOver:FireAllClients()
end

local function triggerVictory()
	if gameState ~= "final_stand" then
		return
	end
	setGameState("victory")
	remotes.GlobalVictory:FireAllClients()
end

local function startFinalStand()
	setGameState("final_stand")
	remotes.FinalStandStarted:FireAllClients()

	task.delay(Constants.TITAN.FinalStandDurationSeconds, function()
		if gameState == "final_stand" and integrity > 0 then
			triggerVictory()
		end
	end)
end

function ObjectiveService.CompleteStage(stageNumber: number): boolean
	if stageNumber < 1 or stageNumber > 4 then
		return false
	end
	if stageNumber ~= currentStage + 1 then
		return false
	end

	local req = Constants.TITAN.Stages[stageNumber]
	if EconomyService.GetScrap() < req.scrap then
		return false
	end
	if req.steel > 0 and EconomyService.GetStormSteel() < req.steel then
		return false
	end

	if not EconomyService.DeductScrap(req.scrap) then
		return false
	end
	if req.steel > 0 then
		if not EconomyService.DeductStormSteel(req.steel) then
			EconomyService.AddScrap(req.scrap)
			return false
		end
	end

	currentStage = stageNumber
	if titanModel ~= nil then
		titanModel:SetAttribute(ATTR_STAGE, currentStage)
	end

	setIntegrity(math.min(100, integrity + Constants.TITAN.IntegrityRepairPerStage))
	updateTitanVisuals(currentStage)
	updatePromptText()
	remotes.TitanStageCompleted:FireAllClients(currentStage)

	if currentStage >= 4 then
		task.defer(startFinalStand)
	end

	return true
end

local function onDepositTriggered(_player: Player)
	if gameState ~= "playing" then
		return
	end
	ObjectiveService.CompleteStage(currentStage + 1)
end

local function createTitan(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = TITAN_MODEL_NAME

	local centerY = resolveMapCenterY()

	local base = Instance.new("Part")
	base.Name = "TitanBase"
	base.Size = Vector3.new(20, 2.5, 20)
	base.Anchored = true
	base.CanCollide = true
	base.Material = VisualManifest.Titan.BaseMaterial
	base.Color = VisualManifest.Titan.BaseColor
	base.Position = Vector3.new(0, centerY + 1.25, 0)
	base.Parent = model

	local core = Instance.new("Part")
	core.Name = TITAN_CORE_NAME
	core.Size = Vector3.new(6, 10, 6)
	core.Anchored = true
	core.CanCollide = true
	core.Material = VisualManifest.Titan.CoreMaterial
	core.Color = VisualManifest.Titan.CoreColor
	core.Position = Vector3.new(0, centerY + 7.2, 0)
	core.Parent = model

	local scaffoldOffsets = {
		Vector3.new(7.5, 4, 0),
		Vector3.new(-7.5, 4, 0),
		Vector3.new(0, 4, 7.5),
		Vector3.new(0, 4, -7.5),
	}
	for i, offset in scaffoldOffsets do
		local strut = Instance.new("Part")
		strut.Name = ("Scaffold%d"):format(i)
		strut.Size = Vector3.new(1.1, 8, 1.1)
		strut.Anchored = true
		strut.CanCollide = false
		strut.Material = VisualManifest.Titan.ScaffoldMaterial
		strut.Color = VisualManifest.Titan.ScaffoldColor
		strut.Position = Vector3.new(offset.X, centerY + 4, offset.Z)
		strut.Parent = model
	end

	for ringIndex = 1, 4 do
		local ring = Instance.new("Part")
		ring.Name = ("StageRing%d"):format(ringIndex)
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.4, 8.2 + ringIndex * 0.4, 8.2 + ringIndex * 0.4)
		ring.Anchored = true
		ring.CanCollide = false
		ring.Material = VisualManifest.Titan.StageRingInactiveMaterial
		ring.Color = VisualManifest.Titan.StageRingInactiveColor
		ring.CFrame = CFrame.new(0, centerY + 2.1 + ringIndex * 2.1, 0) * CFrame.Angles(math.rad(90), 0, 0)
		ring.Parent = model
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ObjectText = "Titan Core"
	prompt.ActionText = "Stage 1: 200 Scrap"
	prompt.HoldDuration = 1.5
	prompt.MaxActivationDistance = Constants.TITAN.DepositRange
	prompt.RequiresLineOfSight = false
	prompt.Parent = core
	depositPrompt = prompt

	prompt.Triggered:Connect(onDepositTriggered)

	model.PrimaryPart = core
	model.Parent = Workspace
	model:SetAttribute(ATTR_INTEGRITY, integrity)
	model:SetAttribute(ATTR_STAGE, 0)
	model:SetAttribute(ATTR_GAME_STATE, "playing")

	CollectionService:AddTag(model, TITAN_TAG)
	CollectionService:AddTag(core, TITAN_TAG)

	core:SetAttribute("TheftProgressPerSecond", 0.1)
	TheftComponent.Attach(core)

	return model, core
end

local function startIntegrityDrainLoop()
	task.spawn(function()
		local lastTick = os.clock()
		while true do
			task.wait(0.2)
			if gameState == "defeat" or gameState == "victory" then
				break
			end
			local core = titanCore
			if core == nil or core.Parent == nil then
				continue
			end

			local now = os.clock()
			local delta = now - lastTick
			lastTick = now

			if core:GetAttribute("IsBeingDismantled") == true then
				setIntegrity(integrity - (delta * Constants.TITAN.IntegrityDrainPerSecond))
				if integrity <= 0 then
					setIntegrity(0)
					triggerGameOver()
				end
			end
		end
	end)
end

function ObjectiveService.GetTitanCore(): BasePart?
	return titanCore
end

function ObjectiveService.GetTitanModel(): Model?
	return titanModel
end

function ObjectiveService.GetIntegrity(): number
	return integrity
end

function ObjectiveService.GetCurrentStage(): number
	return currentStage
end

function ObjectiveService.GetGameState(): string
	return gameState
end

function ObjectiveService.ConnectGameStateChanged(callback: (string) -> ()): RBXScriptConnection
	return gameStateSignal.Event:Connect(callback)
end

function ObjectiveService.Init(): ()
	sessionStartTime = os.clock()

	local model, core = createTitan()
	titanModel = model
	titanCore = core
	setIntegrity(100)
	updateTitanVisuals(0)
	updatePromptText()
	startIntegrityDrainLoop()

	remotes.RequestSessionStats.OnServerInvoke = function(_player: Player)
		local EnemyService = require(script.Parent:WaitForChild("EnemyService"))
		local BuildingService = require(script.Parent:WaitForChild("BuildingService"))
		return {
			scrapGathered = EconomyService.GetTotalScrapGathered(),
			ratsKilled = EnemyService.GetTotalKills(),
			buildingsLost = BuildingService.GetBuildingsLost(),
			stagesCompleted = currentStage,
			wavesCompleted = EnemyService.GetCurrentWave(),
			timeElapsed = os.clock() - sessionStartTime,
		}
	end
end

return ObjectiveService
