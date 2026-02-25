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

local function sculptTerrainBand()
	local terrain = Workspace.Terrain
	local materialA = Enum.Material.CrackedLava
	local materialB = Enum.Material.Ground

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

	createBurrowRing()
	pcall(sculptTerrainBand)
end

return EnvironmentController
