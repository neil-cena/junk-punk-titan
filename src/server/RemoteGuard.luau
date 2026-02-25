--!strict

local Players = game:GetService("Players")

local RemoteGuard = {}

type LimiterState = {
	callTimes: { [Player]: { number } },
	maxCalls: number,
	windowSeconds: number,
}

local limiters: { [string]: LimiterState } = {}

function RemoteGuard.Register(remoteName: string, maxCalls: number, windowSeconds: number)
	limiters[remoteName] = {
		callTimes = {},
		maxCalls = maxCalls,
		windowSeconds = windowSeconds,
	}
end

function RemoteGuard.Check(remoteName: string, player: Player): boolean
	local state = limiters[remoteName]
	if state == nil then
		return true
	end

	local now = os.clock()
	local times = state.callTimes[player]
	if times == nil then
		times = {}
		state.callTimes[player] = times
	end

	local cutoff = now - state.windowSeconds
	local pruned: { number } = {}
	for _, t in times do
		if t > cutoff then
			table.insert(pruned, t)
		end
	end

	if #pruned >= state.maxCalls then
		state.callTimes[player] = pruned
		return false
	end

	table.insert(pruned, now)
	state.callTimes[player] = pruned
	return true
end

function RemoteGuard.CleanupPlayer(player: Player)
	for _, state in limiters do
		state.callTimes[player] = nil
	end
end

Players.PlayerRemoving:Connect(function(player)
	RemoteGuard.CleanupPlayer(player)
end)

return RemoteGuard
