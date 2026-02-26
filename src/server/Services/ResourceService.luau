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

local PlayerTrackingService = require(script.Parent:WaitForChild("PlayerTrackingService"))
local RemoteGuard = require(script.Parent.Parent:WaitForChild("RemoteGuard"))

local ResourceService = {}

local REPAIR_TIMEOUT_SECONDS = 10

local remotes = RemotesModule.Get()
local drillStates: { [BasePart]: DrillState } = {}
local trackedDrills: { [BasePart]: true } = {}
local pendingRepairs: { [number]: BasePart } = {}
local pendingRepairTimestamps: { [number]: number } = {}

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
			local legacyMult = PlayerTrackingService.GetLegacyScrapMultiplier()
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
				local drillLevel = drill:GetAttribute("BuildingLevel") or 1
				local levelStats = Constants.BUILDING_UPGRADES.Drill[drillLevel]
				local lv1Stats = Constants.BUILDING_UPGRADES.Drill[1]
				local levelMult = 1
				if levelStats ~= nil and lv1Stats ~= nil then
					levelMult = (levelStats.scrapPerTick / levelStats.tickInterval) / (lv1Stats.scrapPerTick / lv1Stats.tickInterval)
				end
				local output = Constants.MAINTENANCE.DrillBaseOutput * levelMult * computeEfficiency(stability)
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
		local timestamp = pendingRepairTimestamps[player.UserId]
		if timestamp ~= nil and (os.clock() - timestamp) < REPAIR_TIMEOUT_SECONDS then
			return {
				allowed = false,
				reason = "Repair already active",
			}
		end
		pendingRepairs[player.UserId] = nil
		pendingRepairTimestamps[player.UserId] = nil
	end

	local stability = getClampedStability(drill)
	if stability >= 100 then
		return {
			allowed = false,
			reason = "No repair needed",
		}
	end

	pendingRepairs[player.UserId] = drill
	pendingRepairTimestamps[player.UserId] = os.clock()
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
	Players.PlayerRemoving:Connect(function(player)
		pendingRepairs[player.UserId] = nil
		pendingRepairTimestamps[player.UserId] = nil
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

	RemoteGuard.Register("RepairMinigameResult", 2, 1)

	remotes.RepairMinigameResult.OnServerEvent:Connect(function(player: Player, drill: BasePart, wasSuccess: boolean)
		if not RemoteGuard.Check("RepairMinigameResult", player) then
			return
		end
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
