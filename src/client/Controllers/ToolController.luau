--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local BlueprintController = require(script.Parent:WaitForChild("BlueprintController"))

local ToolController = {}

local remotes = Remotes.Get()
local lastShotAt = 0
local isInitialized = false
local SHOTGUN_TOOL_NAME = "RustyShotgun"
local activeTool: Tool? = nil
local boundTools: { [Tool]: boolean } = {}

local function canFireNow(): boolean
	return os.clock() - lastShotAt >= Constants.COMBAT.ShotgunCooldown
end

local function findRatModel(instance: Instance?): Model?
	if instance == nil then
		return nil
	end

	if instance:IsA("Model") and instance.Name == "ScrapRat" then
		return instance
	end

	local ancestorModel = instance:FindFirstAncestorOfClass("Model")
	if ancestorModel ~= nil and ancestorModel.Name == "ScrapRat" then
		return ancestorModel
	end

	return nil
end

local function playShotEffects(rayOrigin: Vector3, rayDirection: Vector3)
	local muzzle = Instance.new("Part")
	muzzle.Name = "MuzzleFlash"
	muzzle.Anchored = true
	muzzle.CanCollide = false
	muzzle.Material = Enum.Material.Neon
	muzzle.Color = Color3.fromRGB(255, 187, 89)
	muzzle.Size = Vector3.new(0.25, 0.25, 0.25)
	muzzle.CFrame = CFrame.new(rayOrigin + rayDirection.Unit * 2)
	muzzle.Parent = Workspace

	local fade = TweenService:Create(muzzle, TweenInfo.new(0.05, Enum.EasingStyle.Linear), {
		Transparency = 1,
		Size = Vector3.new(0.05, 0.05, 0.05),
	})
	fade:Play()
	fade.Completed:Connect(function()
		muzzle:Destroy()
	end)

	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		local original = camera.CFrame
		local offset = CFrame.new(math.random(-5, 5) / 300, math.random(-5, 5) / 300, 0)
		local recoilOut = TweenService:Create(camera, TweenInfo.new(0.03, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = original * offset,
		})
		recoilOut:Play()
		recoilOut.Completed:Connect(function()
			local recoilBack = TweenService:Create(camera, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = original,
			})
			recoilBack:Play()
		end)
	end
end

local function fireShotgun()
	if activeTool == nil then
		return
	end

	local character = LocalPlayer.Character
	if character == nil or activeTool.Parent ~= character then
		return
	end

	if BlueprintController.IsPlacing() then
		return
	end

	if not canFireNow() then
		return
	end

	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end

	local mousePos = UserInputService:GetMouseLocation()
	local unitRay = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { LocalPlayer.Character }
	local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * Constants.COMBAT.ShotgunRange, rayParams)

	lastShotAt = os.clock()
	playShotEffects(unitRay.Origin, unitRay.Direction)

	if result == nil then
		return
	end

	local ratModel = findRatModel(result.Instance)
	if ratModel == nil then
		return
	end

	local damageMultAttr = LocalPlayer:GetAttribute("DamageMult")
	local damageMult = if typeof(damageMultAttr) == "number" then damageMultAttr :: number else 1
	remotes.HitEnemy:FireServer(ratModel, Constants.COMBAT.ShotgunDamage * damageMult)
end

local function bindShotgunTool(tool: Tool)
	if boundTools[tool] then
		return
	end
	boundTools[tool] = true

	tool.Equipped:Connect(function()
		activeTool = tool
	end)

	tool.Unequipped:Connect(function()
		if activeTool == tool then
			activeTool = nil
		end
	end)

	tool.Activated:Connect(function()
		fireShotgun()
	end)

	tool.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			boundTools[tool] = nil
			if activeTool == tool then
				activeTool = nil
			end
		end
	end)
end

local function bindContainer(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("Tool") and child.Name == SHOTGUN_TOOL_NAME then
			bindShotgunTool(child)
		end
	end

	container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == SHOTGUN_TOOL_NAME then
			bindShotgunTool(child)
		end
	end)
end

function ToolController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	local backpack = LocalPlayer:WaitForChild("Backpack")
	bindContainer(backpack)

	LocalPlayer.CharacterAdded:Connect(function(character)
		activeTool = nil
		bindContainer(character)
	end)

	local currentCharacter = LocalPlayer.Character
	if currentCharacter ~= nil then
		bindContainer(currentCharacter)
	end
end

return ToolController
