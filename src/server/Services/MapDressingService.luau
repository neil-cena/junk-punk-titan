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

local function createWorldBorder(parent: Folder)
	local border = VisualManifest.Map.WorldBorder
	if type(border) ~= "table" then
		return
	end

	local segmentCount = math.max(24, math.floor(border.SegmentCount or 48))
	local colliderRadius = border.ColliderRadius or 248
	local colliderHeight = border.ColliderHeight or 140
	local colliderThickness = border.ColliderThickness or 14
	local colliderYOffset = border.ColliderYOffset or 30
	local cliffRadius = border.CliffRadius or 240
	local cliffHeight = border.CliffHeight or 45
	local cliffThickness = border.CliffThickness or 22
	local cliffYOffset = border.CliffYOffset or 8
	local cliffColor = border.CliffColor or Color3.fromRGB(106, 112, 96)
	local cliffMaterial = border.CliffMaterial or Enum.Material.Rock

	for i = 1, segmentCount do
		local angle = (i / segmentCount) * math.pi * 2
		local x = math.cos(angle)
		local z = math.sin(angle)
		local lookVec = Vector3.new(math.cos(angle + 0.06), 0, math.sin(angle + 0.06))

		local cliffPos = Vector3.new(x * cliffRadius, cliffYOffset, z * cliffRadius)
		makePart(
			parent,
			("CliffBorder_%d"):format(i),
			Vector3.new(cliffThickness, cliffHeight, 26),
			CFrame.lookAt(cliffPos, cliffPos + lookVec),
			cliffColor,
			cliffMaterial
		)

		local colliderPos = Vector3.new(x * colliderRadius, colliderYOffset, z * colliderRadius)
		local blocker = makePart(
			parent,
			("WorldBorder_%d"):format(i),
			Vector3.new(colliderThickness, colliderHeight, 18),
			CFrame.lookAt(colliderPos, colliderPos + lookVec),
			cliffColor,
			Enum.Material.SmoothPlastic
		)
		blocker.Transparency = 1
		blocker.CastShadow = false
		blocker.CanQuery = false
	end
end

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(
		a.R + (b.R - a.R) * t,
		a.G + (b.G - a.G) * t,
		a.B + (b.B - a.B) * t
	)
end

local function createTree(parent: Folder, index: number, position: Vector3, forestConfig: { [string]: any })
	local model = Instance.new("Model")
	model.Name = ("ForestTree_%d"):format(index)
	model.Parent = parent

	local trunkHeight = 9 + math.random() * 8
	local trunkWidth = 1.6 + math.random() * 1.1

	local trunk = Instance.new("Part")
	trunk.Name = "Trunk"
	trunk.Anchored = true
	trunk.CanCollide = true
	trunk.Material = forestConfig.TrunkMaterial or Enum.Material.Wood
	trunk.Color = forestConfig.TrunkColor or Color3.fromRGB(96, 78, 62)
	trunk.Size = Vector3.new(trunkWidth, trunkHeight, trunkWidth)
	trunk.CFrame = CFrame.new(position + Vector3.new(0, trunkHeight * 0.5, 0))
	trunk.Parent = model

	local canopy = Instance.new("Part")
	canopy.Name = "Canopy"
	canopy.Shape = Enum.PartType.Ball
	canopy.Anchored = true
	canopy.CanCollide = true
	canopy.Material = forestConfig.LeafMaterial or Enum.Material.Grass
	local colorT = math.random()
	canopy.Color = lerpColor(
		forestConfig.LeafColorA or Color3.fromRGB(74, 120, 68),
		forestConfig.LeafColorB or Color3.fromRGB(88, 138, 82),
		colorT
	)
	local canopySize = 8 + math.random() * 7
	canopy.Size = Vector3.new(canopySize, canopySize * (0.75 + math.random() * 0.15), canopySize)
	canopy.CFrame = CFrame.new(position + Vector3.new(0, trunkHeight + canopy.Size.Y * 0.35, 0))
	canopy.Parent = model
end

local function createForest(parent: Folder)
	local forestConfig = VisualManifest.Map.Forest
	if type(forestConfig) ~= "table" then
		return
	end

	local count = math.max(0, math.floor(forestConfig.TreeCount or 170))
	local innerRadius = forestConfig.InnerRadius or 95
	local outerRadius = forestConfig.OuterRadius or 220
	local outwardExp = math.clamp(forestConfig.OutwardDensityExponent or 0.55, 0.1, 2)

	for i = 1, count do
		local angle = math.random() * math.pi * 2
		local radialT = math.random() ^ outwardExp
		local dist = innerRadius + (outerRadius - innerRadius) * radialT
		local x = math.cos(angle) * dist
		local z = math.sin(angle) * dist
		local y = -0.15 + math.random() * 0.6
		createTree(parent, i, Vector3.new(x, y, z), forestConfig)
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
	createWorldBorder(folder)
	createForest(folder)
	createScatterProps(folder)
	createBurrowZones(folder)
end

return MapDressingService
