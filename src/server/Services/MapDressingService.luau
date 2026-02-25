--!strict

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local VisualManifest = require(Shared:WaitForChild("VisualManifest"))

local MapDressingService = {}

local function makePart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Parent = parent
	return part
end

local function createBoundary(parent: Folder)
	local radius = 255
	local height = 28
	local segmentCount = 42
	for i = 1, segmentCount do
		local angle = (i / segmentCount) * math.pi * 2
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius
		local look = Vector3.new(math.cos(angle + 0.08) * radius, 0, math.sin(angle + 0.08) * radius)
		makePart(
			parent,
			("Boundary_%d"):format(i),
			Vector3.new(8, height, 4),
			CFrame.lookAt(Vector3.new(x, height * 0.5 - 4, z), Vector3.new(look.X, height * 0.5 - 4, look.Z)),
			VisualManifest.Map.BoundaryColor,
			VisualManifest.Map.BoundaryMaterial
		)
	end
end

local function createScatterProps(parent: Folder)
	for i = 1, 70 do
		local angle = math.random() * math.pi * 2
		local dist = 35 + math.random() * 210
		local x = math.cos(angle) * dist
		local z = math.sin(angle) * dist
		local y = -0.2 + math.random() * 1.2

		local base = makePart(
			parent,
			("JunkProp_%d"):format(i),
			Vector3.new(2 + math.random() * 5, 0.8 + math.random() * 2.8, 2 + math.random() * 4),
			CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(math.random(0, 180)), math.rad(math.random(-8, 8))),
			Color3.new(
				math.clamp(VisualManifest.Map.ScatterPropColorBase.R * 255 + math.random(0, 40), 0, 255) / 255,
				math.clamp(VisualManifest.Map.ScatterPropColorBase.G * 255 + math.random(0, 25), 0, 255) / 255,
				math.clamp(VisualManifest.Map.ScatterPropColorBase.B * 255 + math.random(0, 25), 0, 255) / 255
			),
			if i % 2 == 0 then VisualManifest.Map.ScatterPropMaterialA else VisualManifest.Map.ScatterPropMaterialB
		)
		base.CanCollide = false
	end
end

local function createBurrowZones(parent: Folder)
	local d = Constants.WAVES.RetreatBurrowDistance
	local burrows = {
		Vector3.new(-d, 0.03, -d),
		Vector3.new(d, 0.03, -d),
		Vector3.new(-d, 0.03, d),
		Vector3.new(d, 0.03, d),
	}
	for i, pos in burrows do
		local stain = makePart(
			parent,
			("BurrowZone_%d"):format(i),
			Vector3.new(28, 0.1, 28),
			CFrame.new(pos),
			VisualManifest.Map.BurrowZoneColor,
			VisualManifest.Map.BurrowZoneMaterial
		)
		stain.CanCollide = false
		stain.Transparency = 0.25
	end
end

function MapDressingService.Init(): ()
	local existing = Workspace:FindFirstChild("MapDressing")
	if existing ~= nil then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "MapDressing"
	folder.Parent = Workspace

	createBoundary(folder)
	createScatterProps(folder)
	createBurrowZones(folder)
end

return MapDressingService
