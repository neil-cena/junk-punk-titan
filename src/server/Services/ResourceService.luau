--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local RemotesModule = require(Shared:WaitForChild("Remotes"))

local EconomyService = require(script.Parent:WaitForChild("EconomyService"))

type DrillState = {
	overclockUntil: number,
	clogUntil: number,
}

type WrenchResponse = {
	allowed: boolean,
	reason: string?,
}

local DRILL_TAG = "Drill"
local ATTR_STABILITY = "Stability"
local ATTR_CLOGGED = "IsClogged"
local ATTR_OVERCLOCKED = "IsOverclocked"

local ResourceService = {}
ResourceService.__index = ResourceService

local remotes = RemotesModule.Get()
local peakPlayerCount = 0
local drillStates: { [BasePart]: DrillState } = {}
local trackedDrills: { [BasePart]: true } = {}
local pendingRepairs: { [number]: BasePart } = {}

local function getLegacyMultiplier(): number
	local currentPlayers = #Players:GetPlayers()
	if peakPlayerCount > 0 and currentPlayers < peakPlayerCount then
		return 1 + Constants.SCALING.LegacyScrapGatherBuff
	end
	return 1
end

local function updatePeakPlayerCount()
	peakPlayerCount = math.max(peakPlayerCount, #Players:GetPlayers())
end

local function getClampedStability(drill: BasePart): number
	local stabilityAttr = drill:GetAttribute(ATTR_STABILITY)
	if typeof(stabilityAttr) ~= "number" then
		return 100
	end
	return math.clamp(stabilityAttr :: number, 0, 100)
end

local function setStability(drill: BasePart, value: number)
	drill:SetAttribute(ATTR_STABILITY, math.clamp(value, 0, 100))
end

local function getOrCreateState(drill: BasePart): DrillState
	local existing = drillStates[drill]
	if existing ~= nil then
		return existing
	end

	local state: DrillState = {
		overclockUntil = 0,
		clogUntil = 0,
	}
	drillStates[drill] = state
	return state
end

local function updateTemporalAttributes(drill: BasePart, state: DrillState)
	local now = os.clock()
	drill:SetAttribute(ATTR_CLOGGED, state.clogUntil > now)
	drill:SetAttribute(ATTR_OVERCLOCKED, state.overclockUntil > now and state.clogUntil <= now)
end

local function trackDrill(drill: BasePart)
	if trackedDrills[drill] ~= nil then
		return
	end

	trackedDrills[drill] = true
	getOrCreateState(drill)
	if drill:GetAttribute(ATTR_STABILITY) == nil then
		setStability(drill, 100)
	end
	updateTemporalAttributes(drill, drillStates[drill] :: DrillState)

	drill.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil then
			return
		end
		trackedDrills[drill] = nil
		drillStates[drill] = nil
		for userId, pendingDrill in pendingRepairs do
			if pendingDrill == drill then
				pendingRepairs[userId] = nil
			end
		end
	end)
end

local function computeEfficiency(stability: number): number
	if stability >= 80 then
		return 1
	end
	if stability >= 20 then
		return 0.5
	end
	return 0
end

local function runDegradationLoop()
	task.spawn(function()
		while true do
			task.wait(Constants.MAINTENANCE.StabilityDegradationInterval)
			local now = os.clock()
			for drill in trackedDrills do
				if drill.Parent == nil then
					continue
				end

				local state = getOrCreateState(drill)
				if state.clogUntil > now then
					updateTemporalAttributes(drill, state)
					continue
				end

				local stability = getClampedStability(drill)
				if stability > 0 then
					stability -= Constants.MAINTENANCE.StabilityDegradationPercent
					setStability(drill, stability)
				end
				updateTemporalAttributes(drill, state)
			end
		end
	end)
end

local function runResourceLoop()
	task.spawn(function()
		while true do
			task.wait(Constants.MAINTENANCE.ResourceTickSeconds)

			local now = os.clock()
			local totalOutput = 0
			local legacyMult = getLegacyMultiplier()
			for drill in trackedDrills do
				if drill.Parent == nil then
					continue
				end

				local state = getOrCreateState(drill)
				updateTemporalAttributes(drill, state)

				if state.clogUntil > now then
					continue
				end

				local stability = getClampedStability(drill)
				local output = Constants.MAINTENANCE.DrillBaseOutput * computeEfficiency(stability)
				if output <= 0 then
					continue
				end

				if state.overclockUntil > now then
					output *= Constants.MAINTENANCE.OverclockMultiplier
				end

				output *= legacyMult
				totalOutput += output
			end

			local rounded = math.floor(totalOutput + 0.5)
			if rounded > 0 then
				EconomyService.AddScrap(rounded)
			end
		end
	end)
end

local function canUseWrench(player: Player, drill: BasePart): WrenchResponse
	if player:GetAttribute("Role") ~= "Fixer" then
		return {
			allowed = false,
			reason = "Role locked",
		}
	end

	if drill.Parent == nil or not CollectionService:HasTag(drill, DRILL_TAG) then
		return {
			allowed = false,
			reason = "Invalid drill",
		}
	end

	local existingPending = pendingRepairs[player.UserId]
	if existingPending ~= nil and existingPending ~= drill and existingPending.Parent ~= nil then
		return {
			allowed = false,
			reason = "Repair already active",
		}
	end

	local stability = getClampedStability(drill)
	if stability >= 100 then
		return {
			allowed = false,
			reason = "No repair needed",
		}
	end

	pendingRepairs[player.UserId] = drill
	return { allowed = true }
end

function ResourceService.DrainAllDrillStability(value: number)
	local clamped = math.clamp(value, 0, 100)
	for drill in trackedDrills do
		if drill.Parent ~= nil then
			setStability(drill, clamped)
		end
	end
end

function ResourceService.Init(): ()
	updatePeakPlayerCount()
	Players.PlayerAdded:Connect(updatePeakPlayerCount)
	Players.PlayerRemoving:Connect(function(player)
		pendingRepairs[player.UserId] = nil
		task.defer(updatePeakPlayerCount)
	end)

	for _, instance in CollectionService:GetTagged(DRILL_TAG) do
		if instance:IsA("BasePart") then
			trackDrill(instance)
		end
	end

	CollectionService:GetInstanceAddedSignal(DRILL_TAG):Connect(function(instance)
		if instance:IsA("BasePart") then
			trackDrill(instance)
		end
	end)

	remotes.UseWrench.OnServerInvoke = function(player: Player, drill: BasePart)
		if not drill:IsA("BasePart") then
			return {
				allowed = false,
				reason = "Invalid target",
			}
		end
		return canUseWrench(player, drill)
	end

	remotes.RepairMinigameResult.OnServerEvent:Connect(function(player: Player, drill: BasePart, wasSuccess: boolean)
		local pendingDrill = pendingRepairs[player.UserId]
		pendingRepairs[player.UserId] = nil
		if pendingDrill == nil or pendingDrill ~= drill then
			return
		end
		if drill.Parent == nil or not CollectionService:HasTag(drill, DRILL_TAG) then
			return
		end

		local state = getOrCreateState(drill)
		if wasSuccess then
			local newStability = getClampedStability(drill) + Constants.MAINTENANCE.WrenchSuccessRestore
			setStability(drill, newStability)
			state.overclockUntil = os.clock() + Constants.MAINTENANCE.OverclockDurationSeconds
			state.clogUntil = 0
			updateTemporalAttributes(drill, state)
			remotes.DrillRepaired:FireAllClients(drill.Position)
		else
			state.clogUntil = os.clock() + Constants.MAINTENANCE.ClogDurationSeconds
			updateTemporalAttributes(drill, state)
		end
	end)

	runDegradationLoop()
	runResourceLoop()
end

return ResourceService
