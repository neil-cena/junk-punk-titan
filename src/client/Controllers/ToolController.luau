--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local AudioManifest = require(Shared:WaitForChild("AudioManifest"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local BlueprintController = require(script.Parent:WaitForChild("BlueprintController"))
local MainHUD = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("MainHUD"))

local ToolController = {}

local remotes = Remotes.Get()
local lastShotAt = 0
local isInitialized = false
local SHOTGUN_TOOL_NAME = "RustyShotgun"
local WRENCH_TOOL_NAME = "RustyWrench"
local activeShotgun: Tool? = nil
local activeWrench: Tool? = nil
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
	local muzzlePos = rayOrigin + rayDirection.Unit * 2

	local muzzle = Instance.new("Part")
	muzzle.Name = "MuzzleFlash"
	muzzle.Anchored = true
	muzzle.CanCollide = false
	muzzle.Material = Enum.Material.Neon
	muzzle.Color = Color3.fromRGB(255, 187, 89)
	muzzle.Size = Vector3.new(0.25, 0.25, 0.25)
	muzzle.CFrame = CFrame.new(muzzlePos)
	muzzle.Parent = Workspace

	local fade = TweenService:Create(muzzle, TweenInfo.new(0.05, Enum.EasingStyle.Linear), {
		Transparency = 1,
		Size = Vector3.new(0.05, 0.05, 0.05),
	})
	fade:Play()
	fade.Completed:Connect(function()
		muzzle:Destroy()
	end)

	local shotSound = Instance.new("Sound")
	shotSound.SoundId = AudioManifest.ShotgunFire
	shotSound.Volume = 0.5
	shotSound.PlaybackSpeed = 0.9 + math.random() * 0.2
	shotSound.RollOffMode = Enum.RollOffMode.Linear
	shotSound.MaxDistance = 80
	shotSound.Parent = muzzle
	shotSound:Play()

	local character = LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid.CameraOffset = Vector3.new(math.random(-5, 5) / 200, math.random(-5, 5) / 200, 0)
		task.delay(0.04, function()
			if humanoid and humanoid.Parent then
				humanoid.CameraOffset = Vector3.zero
			end
		end)
	end
end

local function fireShotgun()
	if activeShotgun == nil then
		return
	end

	if LocalPlayer:GetAttribute("Role") ~= "Enforcer" then
		return
	end

	local character = LocalPlayer.Character
	if character == nil or activeShotgun.Parent ~= character then
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

	remotes.HitEnemy:FireServer(ratModel)
end

local function findDrillModel(instance: Instance?): BasePart?
	local current = instance
	while current ~= nil do
		if current:IsA("BasePart") and CollectionService:HasTag(current, "Drill") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function useWrench()
	if activeWrench == nil then
		return
	end

	if LocalPlayer:GetAttribute("Role") ~= "Fixer" then
		return
	end

	local character = LocalPlayer.Character
	if character == nil or activeWrench.Parent ~= character then
		return
	end

	if BlueprintController.IsPlacing() then
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
	local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * Constants.BUILDING.PlacementMaxDistance, rayParams)
	if result == nil then
		return
	end

	local drillPart = findDrillModel(result.Instance)
	if drillPart == nil then
		return
	end

	local ok, response = pcall(function()
		return remotes.UseWrench:InvokeServer(drillPart)
	end)
	if not ok or type(response) ~= "table" then
		return
	end

	if response.allowed == true then
		MainHUD.ShowRepairMinigame(drillPart)
	end
end

local function bindShotgunTool(tool: Tool)
	if boundTools[tool] then
		return
	end
	boundTools[tool] = true

	tool.Equipped:Connect(function()
		activeShotgun = tool
	end)

	tool.Unequipped:Connect(function()
		if activeShotgun == tool then
			activeShotgun = nil
		end
	end)

	tool.Activated:Connect(function()
		fireShotgun()
	end)

	tool.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			boundTools[tool] = nil
			if activeShotgun == tool then
				activeShotgun = nil
			end
		end
	end)
end

local function bindWrenchTool(tool: Tool)
	if boundTools[tool] then
		return
	end
	boundTools[tool] = true

	tool.Equipped:Connect(function()
		activeWrench = tool
	end)

	tool.Unequipped:Connect(function()
		if activeWrench == tool then
			activeWrench = nil
		end
	end)

	tool.Activated:Connect(function()
		useWrench()
	end)

	tool.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			boundTools[tool] = nil
			if activeWrench == tool then
				activeWrench = nil
			end
		end
	end)
end

local function tryAutoEquip(tool: Tool)
	local character = LocalPlayer.Character
	if character == nil then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return
	end
	if tool.Parent == character then
		return
	end
	humanoid:EquipTool(tool)
end

local function getRoleToolName(): string?
	local role = LocalPlayer:GetAttribute("Role")
	if role == "Enforcer" then
		return SHOTGUN_TOOL_NAME
	elseif role == "Fixer" then
		return WRENCH_TOOL_NAME
	end
	return nil
end

local function getToolInstance(toolName: string): Tool?
	local character = LocalPlayer.Character
	if character ~= nil then
		local equipped = character:FindFirstChild(toolName)
		if equipped ~= nil and equipped:IsA("Tool") then
			return equipped
		end
	end

	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if backpack ~= nil then
		local stored = backpack:FindFirstChild(toolName)
		if stored ~= nil and stored:IsA("Tool") then
			return stored
		end
	end

	return nil
end

local function bindContainer(container: Instance)
	local isBackpack = container:IsA("Backpack")

	for _, child in container:GetChildren() do
		if child:IsA("Tool") and child.Name == SHOTGUN_TOOL_NAME then
			bindShotgunTool(child)
			if isBackpack then
				tryAutoEquip(child)
			end
		elseif child:IsA("Tool") and child.Name == WRENCH_TOOL_NAME then
			bindWrenchTool(child)
			if isBackpack then
				tryAutoEquip(child)
			end
		end
	end

	container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == SHOTGUN_TOOL_NAME then
			bindShotgunTool(child)
			if isBackpack then
				tryAutoEquip(child)
			end
		elseif child:IsA("Tool") and child.Name == WRENCH_TOOL_NAME then
			bindWrenchTool(child)
			if isBackpack then
				tryAutoEquip(child)
			end
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
		activeShotgun = nil
		activeWrench = nil
		bindContainer(character)

		task.defer(function()
			local bp = LocalPlayer:FindFirstChild("Backpack")
			if bp then
				for _, child in bp:GetChildren() do
					if child:IsA("Tool") and (child.Name == SHOTGUN_TOOL_NAME or child.Name == WRENCH_TOOL_NAME) then
						tryAutoEquip(child)
						break
					end
				end
			end
		end)
	end)

	local currentCharacter = LocalPlayer.Character
	if currentCharacter ~= nil then
		bindContainer(currentCharacter)
	end
end

function ToolController.GetCurrentToolName(): string?
	return getRoleToolName()
end

function ToolController.IsCurrentToolEquipped(): boolean
	local toolName = getRoleToolName()
	if toolName == nil then
		return false
	end
	local character = LocalPlayer.Character
	return character ~= nil and character:FindFirstChild(toolName) ~= nil
end

function ToolController.EquipCurrentTool(): boolean
	local toolName = getRoleToolName()
	if toolName == nil then
		return false
	end

	local tool = getToolInstance(toolName)
	if tool == nil then
		return false
	end

	local character = LocalPlayer.Character
	if character == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return false
	end

	humanoid:EquipTool(tool)
	return true
end

function ToolController.UnequipCurrentTool(): boolean
	local character = LocalPlayer.Character
	if character == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return false
	end

	humanoid:UnequipTools()
	return true
end

return ToolController
