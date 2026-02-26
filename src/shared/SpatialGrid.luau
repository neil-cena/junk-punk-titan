--!strict

local SpatialGrid = {}
SpatialGrid.__index = SpatialGrid

export type Entry = {
	instance: Model,
	position: Vector3,
}

type Grid = {
	cellSize: number,
	cells: { [string]: { Entry } },
	entryCell: { [Model]: string },
}

local function cellKey(x: number, z: number): string
	return ("%d,%d"):format(x, z)
end

local function toCell(pos: Vector3, cellSize: number): (number, number)
	return math.floor(pos.X / cellSize), math.floor(pos.Z / cellSize)
end

function SpatialGrid.new(cellSize: number?): Grid
	local grid: Grid = {
		cellSize = cellSize or 16,
		cells = {},
		entryCell = {},
	}
	return setmetatable(grid, SpatialGrid) :: any
end

function SpatialGrid.Insert(self: Grid, model: Model, position: Vector3)
	local cx, cz = toCell(position, self.cellSize)
	local key = cellKey(cx, cz)
	local entry: Entry = { instance = model, position = position }

	local oldKey = self.entryCell[model]
	if oldKey ~= nil then
		if oldKey == key then
			local bucket = self.cells[key]
			if bucket ~= nil then
				for i, e in bucket do
					if e.instance == model then
						bucket[i].position = position
						return
					end
				end
			end
			return
		end
		SpatialGrid.Remove(self, model)
	end

	local bucket = self.cells[key]
	if bucket == nil then
		bucket = {}
		self.cells[key] = bucket
	end
	table.insert(bucket, entry)
	self.entryCell[model] = key
end

function SpatialGrid.Remove(self: Grid, model: Model)
	local key = self.entryCell[model]
	if key == nil then
		return
	end
	local bucket = self.cells[key]
	if bucket ~= nil then
		for i, e in bucket do
			if e.instance == model then
				table.remove(bucket, i)
				break
			end
		end
		if #bucket == 0 then
			self.cells[key] = nil
		end
	end
	self.entryCell[model] = nil
end

function SpatialGrid.Update(self: Grid, model: Model, newPosition: Vector3)
	SpatialGrid.Insert(self, model, newPosition)
end

function SpatialGrid.GetNearestInRadius(self: Grid, origin: Vector3, radius: number): (Model?, number)
	local cs = self.cellSize
	local cellRadius = math.ceil(radius / cs)
	local cx, cz = toCell(origin, cs)

	local nearest: Model? = nil
	local nearestDist = radius + 1

	for dx = -cellRadius, cellRadius do
		for dz = -cellRadius, cellRadius do
			local key = cellKey(cx + dx, cz + dz)
			local bucket = self.cells[key]
			if bucket ~= nil then
				for _, entry in bucket do
					local dist = (entry.position - origin).Magnitude
					if dist <= radius and dist < nearestDist then
						nearestDist = dist
						nearest = entry.instance
					end
				end
			end
		end
	end

	return nearest, nearestDist
end

function SpatialGrid.GetAllInRadius(self: Grid, origin: Vector3, radius: number): { Entry }
	local cs = self.cellSize
	local cellRadius = math.ceil(radius / cs)
	local cx, cz = toCell(origin, cs)
	local results: { Entry } = {}

	for dx = -cellRadius, cellRadius do
		for dz = -cellRadius, cellRadius do
			local key = cellKey(cx + dx, cz + dz)
			local bucket = self.cells[key]
			if bucket ~= nil then
				for _, entry in bucket do
					if (entry.position - origin).Magnitude <= radius then
						table.insert(results, entry)
					end
				end
			end
		end
	end

	return results
end

function SpatialGrid.Clear(self: Grid)
	table.clear(self.cells)
	table.clear(self.entryCell)
end

function SpatialGrid.Count(self: Grid): number
	local total = 0
	for _, bucket in self.cells do
		total += #bucket
	end
	return total
end

return SpatialGrid
