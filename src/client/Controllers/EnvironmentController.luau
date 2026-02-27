--!strict

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local VisualManifest = require(Shared:WaitForChild("VisualManifest"))

local EnvironmentController = {}

local initialized = false

local function ensureEffect(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing ~= nil and existing:IsA(className :: any) then
		return existing
	end
	local effect = Instance.new(className :: any)
	effect.Name = name
	effect.Parent = Lighting
	return effect
end

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return Color3.new(
		a.R + (b.R - a.R) * t,
		a.G + (b.G - a.G) * t,
		a.B + (b.B - a.B) * t
	)
end

local function applyLightingManifest()
	local lighting = VisualManifest.Lighting
	Lighting.Ambient = lighting.Ambient
	Lighting.OutdoorAmbient = lighting.OutdoorAmbient
	Lighting.Brightness = lighting.Brightness
	Lighting.ClockTime = lighting.ClockTime
	Lighting.ExposureCompensation = lighting.ExposureCompensation
	Lighting.FogColor = lighting.FogColor
	Lighting.FogStart = lighting.FogStart
	Lighting.FogEnd = lighting.FogEnd

	local atmosphere = ensureEffect("Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Color = VisualManifest.Atmosphere.Color
	atmosphere.Decay = VisualManifest.Atmosphere.Decay
	atmosphere.Density = VisualManifest.Atmosphere.Density
	atmosphere.Glare = VisualManifest.Atmosphere.Glare
	atmosphere.Haze = VisualManifest.Atmosphere.Haze

	local bloom = ensureEffect("BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = VisualManifest.PostProcessing.Bloom.Intensity
	bloom.Size = VisualManifest.PostProcessing.Bloom.Size
	bloom.Threshold = VisualManifest.PostProcessing.Bloom.Threshold
	bloom.Enabled = true

	local colorCorrection = ensureEffect("ColorCorrectionEffect", "BaseColorCorrection") :: ColorCorrectionEffect
	colorCorrection.Brightness = VisualManifest.PostProcessing.ColorCorrection.Brightness
	colorCorrection.Contrast = VisualManifest.PostProcessing.ColorCorrection.Contrast
	colorCorrection.Saturation = VisualManifest.PostProcessing.ColorCorrection.Saturation
	colorCorrection.TintColor = VisualManifest.PostProcessing.ColorCorrection.TintColor
	colorCorrection.Enabled = true

	local sunRays = ensureEffect("SunRaysEffect", "BaseSunRays") :: SunRaysEffect
	sunRays.Intensity = VisualManifest.PostProcessing.SunRays.Intensity
	sunRays.Spread = VisualManifest.PostProcessing.SunRays.Spread
	sunRays.Enabled = true
end

local function applyGroundManifest()
	local ground = VisualManifest.Ground
	if type(ground) ~= "table" then
		return
	end

	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate ~= nil and baseplate:IsA("BasePart") then
		if ground.BaseplateColor ~= nil then
			baseplate.Color = ground.BaseplateColor
		end
		if ground.BaseplateMaterial ~= nil then
			baseplate.Material = ground.BaseplateMaterial
		end
	end
end

local function applySkyManifest()
	local skyManifest = VisualManifest.Sky
	if type(skyManifest) ~= "table" then
		return
	end

	for _, child in Lighting:GetChildren() do
		if child:IsA("Sky") and child.Name ~= "AssetPackSky" then
			child:Destroy()
		end
	end

	local sky = Lighting:FindFirstChild("AssetPackSky")
	if sky == nil or not sky:IsA("Sky") then
		local newSky = Instance.new("Sky")
		newSky.Name = "AssetPackSky"
		newSky.Parent = Lighting
		sky = newSky
	end

	local skyObj = sky :: Sky
	skyObj.SkyboxBk = skyManifest.SkyboxBk or skyObj.SkyboxBk
	skyObj.SkyboxDn = skyManifest.SkyboxDn or skyObj.SkyboxDn
	skyObj.SkyboxFt = skyManifest.SkyboxFt or skyObj.SkyboxFt
	skyObj.SkyboxLf = skyManifest.SkyboxLf or skyObj.SkyboxLf
	skyObj.SkyboxRt = skyManifest.SkyboxRt or skyObj.SkyboxRt
	skyObj.SkyboxUp = skyManifest.SkyboxUp or skyObj.SkyboxUp
	skyObj.MoonTextureId = skyManifest.MoonTextureId or skyObj.MoonTextureId
	skyObj.SunTextureId = skyManifest.SunTextureId or skyObj.SunTextureId
	skyObj.StarCount = skyManifest.StarCount or 0
	skyObj.CelestialBodiesShown = if skyManifest.CelestialBodiesShown == nil then true else skyManifest.CelestialBodiesShown

	local cloudsManifest = skyManifest.Clouds
	if type(cloudsManifest) ~= "table" then
		return
	end

	local clouds = Lighting:FindFirstChild("AssetPackClouds")
	if clouds == nil or not clouds:IsA("Clouds") then
		local newClouds = Instance.new("Clouds")
		newClouds.Name = "AssetPackClouds"
		newClouds.Parent = Lighting
		clouds = newClouds
	end

	local cloudsObj = clouds :: Clouds
	cloudsObj.Enabled = if cloudsManifest.Enabled == nil then true else cloudsManifest.Enabled
	if cloudsManifest.Color ~= nil then
		cloudsObj.Color = cloudsManifest.Color
	end
	if cloudsManifest.Cover ~= nil then
		cloudsObj.Cover = cloudsManifest.Cover
	end
	if cloudsManifest.Density ~= nil then
		cloudsObj.Density = cloudsManifest.Density
	end
end

local function ensurePermanentBurrowMarker(parent: Instance, position: Vector3, index: number)
	local model = Instance.new("Model")
	model.Name = ("BurrowMarker%d"):format(index)

	local crater = Instance.new("Part")
	crater.Name = "Crater"
	crater.Anchored = true
	crater.CanCollide = false
	crater.Material = VisualManifest.BurrowMarker.CraterMaterial
	crater.Color = VisualManifest.BurrowMarker.CraterColor
	crater.Size = Vector3.new(10, 0.2, 10)
	crater.CFrame = CFrame.new(position)
	crater.Parent = model

	local rim = Instance.new("Part")
	rim.Name = "Rim"
	rim.Shape = Enum.PartType.Cylinder
	rim.Anchored = true
	rim.CanCollide = false
	rim.Material = VisualManifest.BurrowMarker.RimMaterial
	rim.Color = VisualManifest.BurrowMarker.RimColor
	rim.Transparency = 0.35
	rim.Size = Vector3.new(0.18, 11, 11)
	rim.CFrame = CFrame.new(position + Vector3.new(0, 0.12, 0)) * CFrame.Angles(math.rad(90), 0, 0)
	rim.Parent = model

	model.Parent = parent
	CollectionService:AddTag(model, "PermanentBurrowMarker")
end

local function createBurrowRing()
	local existing = Workspace:FindFirstChild("PermanentBurrows")
	if existing ~= nil then
		existing:Destroy()
	end

	local container = Instance.new("Folder")
	container.Name = "PermanentBurrows"
	container.Parent = Workspace

	local d = Constants.WAVES.RetreatBurrowDistance
	local points = {
		Vector3.new(-d, 0.06, -d),
		Vector3.new(d, 0.06, -d),
		Vector3.new(-d, 0.06, d),
		Vector3.new(d, 0.06, d),
	}
	for i, pos in points do
		ensurePermanentBurrowMarker(container, pos, i)
	end
end

local function createHorizonBackdrop()
	local horizon = VisualManifest.Horizon
	if type(horizon) ~= "table" then
		return
	end

	local existing = Workspace:FindFirstChild("HorizonBackdrop")
	if existing ~= nil then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "HorizonBackdrop"
	folder.Parent = Workspace

	if horizon.Enabled == false then
		return
	end

	local radius = horizon.Radius or 340
	local segments = math.max(8, math.floor(horizon.Segments or 20))
	local heightMin = horizon.HeightMin or 65
	local heightMax = math.max(heightMin + 10, horizon.HeightMax or 130)
	local width = horizon.Width or 70
	local depth = horizon.Depth or 40
	local mat = horizon.MountainMaterial or Enum.Material.Slate
	local colorNear = horizon.MountainColorNear or Color3.fromRGB(104, 126, 107)
	local colorFar = horizon.MountainColorFar or Color3.fromRGB(142, 162, 147)

	for i = 1, segments do
		local alpha = (i - 1) / segments
		local angle = alpha * math.pi * 2
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius
		local yHeight = heightMin + (heightMax - heightMin) * (0.5 + 0.5 * math.sin(i * 1.73))
		local color = lerpColor(colorNear, colorFar, 0.5 + 0.5 * math.sin(i * 0.67))

		local ridge = Instance.new("WedgePart")
		ridge.Name = ("Mountain_%d"):format(i)
		ridge.Anchored = true
		ridge.CanCollide = false
		ridge.CastShadow = false
		ridge.Material = mat
		ridge.Color = color
		ridge.Size = Vector3.new(width, yHeight, depth)
		ridge.CFrame = CFrame.lookAt(Vector3.new(x, yHeight * 0.5 - 8, z), Vector3.new(0, yHeight * 0.3 - 8, 0))
		ridge.Parent = folder
	end
end

local function sculptTerrainBand()
	local terrain = Workspace.Terrain
	local materialA = VisualManifest.Map.TerrainBandMaterialA
	local materialB = VisualManifest.Map.TerrainBandMaterialB

	for i = 1, 22 do
		local angle = (i / 22) * math.pi * 2
		local radius = 130 + math.sin(i * 0.9) * 35
		local center = Vector3.new(math.cos(angle) * radius, -3, math.sin(angle) * radius)
		terrain:FillBlock(CFrame.new(center), Vector3.new(42, 6, 28), if i % 2 == 0 then materialA else materialB)
	end
end

function EnvironmentController.Init()
	if initialized then
		return
	end
	initialized = true

	applyLightingManifest()
	applyGroundManifest()
	applySkyManifest()

	createBurrowRing()
	createHorizonBackdrop()
	pcall(sculptTerrainBand)
end

return EnvironmentController
