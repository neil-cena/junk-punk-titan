--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RemotesModule = require(Shared:WaitForChild("Remotes"))
local TheftComponent = require(Shared:WaitForChild("TheftComponent"))

local ObjectiveService = {}
ObjectiveService.__index = ObjectiveService

local TITAN_TAG = "TitanObjective"
local TITAN_MODEL_NAME = "TitanChassis"
local TITAN_CORE_NAME = "TitanCore"
local ATTR_INTEGRITY = "TitanIntegrity"
local ATTR_STAGE = "TitanStage"

local remotes = RemotesModule.Get()
local titanModel: Model? = nil
local titanCore: BasePart? = nil
local integrity = 100
local completedStages: { [number]: true } = {}
local isGameOver = false

local function resolveMapCenterY(): number
	local rayResult = Workspace:Raycast(Vector3.new(0, 200, 0), Vector3.new(0, -500, 0))
	if rayResult ~= nil then
		return rayResult.Position.Y
	end
	return 0
end

local function setIntegrity(value: number)
	integrity = math.clamp(value, 0, 100)
	if titanModel ~= nil then
		titanModel:SetAttribute(ATTR_INTEGRITY, integrity)
	end
end

local function createTitan(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = TITAN_MODEL_NAME

	local centerY = resolveMapCenterY()

	local base = Instance.new("Part")
	base.Name = "TitanBase"
	base.Size = Vector3.new(14, 2, 14)
	base.Anchored = true
	base.CanCollide = true
	base.Material = Enum.Material.Metal
	base.Color = Color3.fromRGB(70, 70, 80)
	base.Position = Vector3.new(0, centerY + 1, 0)
	base.Parent = model

	local core = Instance.new("Part")
	core.Name = TITAN_CORE_NAME
	core.Size = Vector3.new(6, 8, 6)
	core.Anchored = true
	core.CanCollide = true
	core.Material = Enum.Material.DiamondPlate
	core.Color = Color3.fromRGB(100, 110, 125)
	core.Position = Vector3.new(0, centerY + 6, 0)
	core.Parent = model

	model.PrimaryPart = core
	model.Parent = Workspace
	model:SetAttribute(ATTR_INTEGRITY, integrity)
	model:SetAttribute(ATTR_STAGE, 0)

	CollectionService:AddTag(model, TITAN_TAG)
	CollectionService:AddTag(core, TITAN_TAG)

	core:SetAttribute("TheftProgressPerSecond", 0.1)
	TheftComponent.Attach(core)

	return model, core
end

local function triggerGameOver()
	if isGameOver then
		return
	end
	isGameOver = true
	remotes.GlobalGameOver:FireAllClients()
end

local function startIntegrityDrainLoop()
	task.spawn(function()
		local lastTick = os.clock()
		while true do
			task.wait(0.2)
			if isGameOver then
				continue
			end
			local core = titanCore
			if core == nil or core.Parent == nil then
				continue
			end

			local now = os.clock()
			local delta = now - lastTick
			lastTick = now

			if core:GetAttribute("IsBeingDismantled") == true then
				setIntegrity(integrity - delta)
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

function ObjectiveService.GetIntegrity(): number
	return integrity
end

function ObjectiveService.CompleteStage(stageNumber: number): boolean
	if stageNumber < 1 or stageNumber > 4 then
		return false
	end
	if completedStages[stageNumber] then
		return false
	end

	completedStages[stageNumber] = true
	local model = titanModel
	if model ~= nil then
		model:SetAttribute(ATTR_STAGE, stageNumber)
	end

	-- Titan repairs only on stage completion.
	setIntegrity(integrity + 25)
	return true
end

function ObjectiveService.Init(): ()
	local model, core = createTitan()
	titanModel = model
	titanCore = core
	setIntegrity(100)
	startIntegrityDrainLoop()
end

return ObjectiveService
