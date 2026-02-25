--!strict

local Utils = {}

function Utils.SnapToGrid(position: Vector3, gridSize: number): Vector3
	return Vector3.new(
		math.round(position.X / gridSize) * gridSize,
		position.Y,
		math.round(position.Z / gridSize) * gridSize
	)
end

function Utils.RemoveToolByName(player: Player, toolName: string)
	for _, container in { player:FindFirstChild("Backpack"), player:FindFirstChild("StarterGear"), player.Character } do
		if container ~= nil then
			local existing = container:FindFirstChild(toolName)
			if existing ~= nil then
				existing:Destroy()
			end
		end
	end
end

return Utils
