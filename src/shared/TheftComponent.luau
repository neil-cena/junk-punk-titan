--!strict

local Constants = require(script.Parent.Constants)
local Types = require(script.Parent.Types)

type TheftData = Types.TheftData

type InternalState = TheftData & {
	runToken: number,
}

local ATTR_PROGRESS = "DismantleProgress"
local ATTR_ACTIVE = "IsBeingDismantled"

local states: { [BasePart]: InternalState } = {}
local dismantleCompleted = Instance.new("BindableEvent")

local TheftComponent = {}

local function setProgress(part: BasePart, progress: number)
	local clampedProgress = math.clamp(progress, 0, 100)
	part:SetAttribute(ATTR_PROGRESS, clampedProgress)
end

function TheftComponent.Attach(part: BasePart): TheftData
	local current = states[part]
	if current ~= nil then
		return current
	end

	local initialProgress = part:GetAttribute(ATTR_PROGRESS)
	local state: InternalState = {
		dismantleProgress = if typeof(initialProgress) == "number" then math.clamp(initialProgress :: number, 0, 100) else 0,
		isBeingDismantled = false,
		attachedEnemy = nil,
		runToken = 0,
	}

	states[part] = state
	setProgress(part, state.dismantleProgress)
	part:SetAttribute(ATTR_ACTIVE, false)
	return state
end

function TheftComponent.StartDismantle(part: BasePart, enemyModel: Model?): ()
	local state = (states[part] or TheftComponent.Attach(part)) :: InternalState

	if state.isBeingDismantled then
		return
	end

	state.isBeingDismantled = true
	state.attachedEnemy = enemyModel
	state.runToken += 1
	part:SetAttribute(ATTR_ACTIVE, true)

	local localToken = state.runToken
	task.spawn(function()
		local lastTick = os.clock()
		while part.Parent ~= nil
			and state.isBeingDismantled
			and state.runToken == localToken
			and state.dismantleProgress < 100
			and (enemyModel == nil or enemyModel.Parent ~= nil) do
			task.wait(0.2)

			local now = os.clock()
			local delta = now - lastTick
			lastTick = now

			state.dismantleProgress = math.min(100, state.dismantleProgress + Constants.THEFT_SETTINGS.ProgressPerSecond * delta)
			setProgress(part, state.dismantleProgress)
		end

		if state.runToken ~= localToken then
			return
		end

		state.isBeingDismantled = false
		part:SetAttribute(ATTR_ACTIVE, false)

		if state.dismantleProgress >= 100 then
			dismantleCompleted:Fire(part, enemyModel)
		end
	end)
end

function TheftComponent.StopDismantle(part: BasePart, preserveProgress: boolean?): ()
	local state = states[part]
	if state == nil then
		return
	end

	state.isBeingDismantled = false
	state.attachedEnemy = nil
	state.runToken += 1
	part:SetAttribute(ATTR_ACTIVE, false)

	if preserveProgress == false then
		state.dismantleProgress = 0
		setProgress(part, 0)
	end
end

function TheftComponent.GetProgress(part: BasePart): number
	local state = states[part]
	if state == nil then
		local fromAttribute = part:GetAttribute(ATTR_PROGRESS)
		if typeof(fromAttribute) == "number" then
			return math.clamp(fromAttribute :: number, 0, 100)
		end
		return 0
	end

	return state.dismantleProgress
end

function TheftComponent.IsComplete(part: BasePart): boolean
	return TheftComponent.GetProgress(part) >= 100
end

function TheftComponent.ConnectCompleted(callback: (BasePart, Model?) -> ()): RBXScriptConnection
	return dismantleCompleted.Event:Connect(callback)
end

function TheftComponent.Detach(part: BasePart): ()
	local state = states[part]
	if state == nil then
		return
	end

	state.isBeingDismantled = false
	state.runToken += 1
	states[part] = nil
end

return TheftComponent
