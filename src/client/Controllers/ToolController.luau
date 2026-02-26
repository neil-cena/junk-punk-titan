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
local VisualManifest = require(Shared:WaitForChild("VisualManifest"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local BlueprintController = require(script.Parent:WaitForChild("BlueprintController"))

local ToolController = {}

local remotes = Remotes.Get()
local lastShotAt = 0
local lastPunchAt = 0
local isInitialized = false
local SHOTGUN_TOOL_NAME = "RustyShotgun"
local WRENCH_TOOL_NAME = "RustyWrench"
local activeShotgun: Tool? = nil
local activeWrench: Tool? = nil
local boundTools: { [Tool]: boolean } = {}
local cachedMainHUD: any = nil

local function getMainHUD(): any?
	if cachedMainHUD ~= nil then
		return cachedMainHUD
	end
	local ok, module = pcall(function()
		return require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("MainHUD"))
	end)
	if ok then
		cachedMainHUD = module
		return module
	end
	return nil
end

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

local function isHoldingAnyTool(): boolean
	local character = LocalPlayer.Character
	if character == nil then
		return false
	end
	return character:FindFirstChildOfClass("Tool") ~= nil
end

local function canPunchNow(): boolean
	return os.clock() - lastPunchAt >= Constants.COMBAT.PunchCooldown
end

local function playImpactFx(position: Vector3, color: Color3)
	local pulse = Instance.new("Part")
	pulse.Name = "HitPulse"
	pulse.Shape = Enum.PartType.Ball
	pulse.Anchored = true
	pulse.CanCollide = false
	pulse.Material = Enum.Material.Neon
	pulse.Color = color
	pulse.Size = Vector3.new(0.3, 0.3, 0.3)
	pulse.CFrame = CFrame.new(position)
	pulse.Parent = Workspace

	TweenService:Create(pulse, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(1.8, 1.8, 1.8),
		Transparency = 1,
	}):Play()
	task.delay(0.2, function()
		if pulse.Parent ~= nil then
			pulse:Destroy()
		end
	end)
end

local PUNCH_ANIM_ID = "rbxassetid://148840371"
local SHOT_ANIM_ID = "rbxassetid://94245658919699"
local cachedPunchTrack: AnimationTrack? = nil
local cachedPunchAnimHumanoid: Humanoid? = nil
local cachedShotTrack: AnimationTrack? = nil
local cachedShotAnimHumanoid: Humanoid? = nil

local function getPunchTrack(humanoid: Humanoid): AnimationTrack?
	if cachedPunchTrack ~= nil and cachedPunchAnimHumanoid == humanoid then
		return cachedPunchTrack
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = PUNCH_ANIM_ID
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if not ok or track == nil then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	cachedPunchTrack = track
	cachedPunchAnimHumanoid = humanoid
	return track
end

local function getShotTrack(humanoid: Humanoid): AnimationTrack?
	if cachedShotTrack ~= nil and cachedShotAnimHumanoid == humanoid then
		return cachedShotTrack
	end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = SHOT_ANIM_ID
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(anim)
	end)
	if not ok or track == nil then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = false
	cachedShotTrack = track
	cachedShotAnimHumanoid = humanoid
	return track
end

local function playPunchEffects()
	local character = LocalPlayer.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid.CameraOffset = Vector3.new(0, 0, -0.3)
		task.delay(0.08, function()
			if humanoid and humanoid.Parent then
				humanoid.CameraOffset = Vector3.zero
			end
		end)

		local track = getPunchTrack(humanoid)
		if track ~= nil then
			track:Play(0.05, 1, 2.5)
		end
	end
end

local function tryPunch()
	if isHoldingAnyTool() then
		return
	end
	if BlueprintController.IsPlacing() then
		return
	end
	if not canPunchNow() then
		return
	end

	local character = LocalPlayer.Character
	if character == nil then
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
	rayParams.FilterDescendantsInstances = { character }
	local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, rayParams)

	lastPunchAt = os.clock()
	playPunchEffects()

	local root = character:FindFirstChild("HumanoidRootPart")
	if root == nil or not root:IsA("BasePart") then
		return
	end

	local punchRange = Constants.COMBAT.PunchRange
	local ratModel: Model? = nil

	if result ~= nil then
		local candidate = findRatModel(result.Instance)
		if candidate ~= nil then
			local candidateRoot = candidate.PrimaryPart
			if candidateRoot ~= nil and (candidateRoot.Position - root.Position).Magnitude <= punchRange then
				ratModel = candidate
			end
		end
	end

	if ratModel == nil then
		local nearest: Model? = nil
		local nearestDist = punchRange + 0.5
		for _, rat in CollectionService:GetTagged("ScrapRatEnemy") do
			if rat:IsA("Model") and rat.Parent ~= nil then
				local ratRoot = rat.PrimaryPart
				if ratRoot ~= nil then
					local dist = (ratRoot.Position - root.Position).Magnitude
					if dist <= nearestDist then
						nearestDist = dist
						nearest = rat
					end
				end
			end
		end
		ratModel = nearest
	end

	if ratModel == nil then
		return
	end

	local ratRoot = ratModel.PrimaryPart
	if ratRoot ~= nil then
		playImpactFx(ratRoot.Position + Vector3.new(0, 0.8, 0), VisualManifest.Tools.ImpactPunchColor)
	end
	remotes.PunchEnemy:FireServer(ratModel)
end

local function playShotEffects(rayOrigin: Vector3, rayDirection: Vector3)
	local muzzlePos = rayOrigin + rayDirection.Unit * 2

	local muzzle = Instance.new("Part")
	muzzle.Name = "MuzzleFlash"
	muzzle.Anchored = true
	muzzle.CanCollide = false
	muzzle.Material = VisualManifest.Tools.MuzzleMaterial
	muzzle.Color = VisualManifest.Tools.MuzzleColor
	muzzle.Size = Vector3.new(0.25, 0.25, 0.25)
	muzzle.CFrame = CFrame.new(muzzlePos)
	muzzle.Parent = Workspace

	local trail = Instance.new("Part")
	trail.Name = "ShotTrail"
	trail.Anchored = true
	trail.CanCollide = false
	trail.Material = VisualManifest.Tools.ShotTrailMaterial
	trail.Color = VisualManifest.Tools.ShotTrailColor
	trail.Size = Vector3.new(0.12, 0.12, 8)
	trail.CFrame = CFrame.lookAt(muzzlePos, muzzlePos + rayDirection.Unit * 8) * CFrame.new(0, 0, -4)
	trail.Parent = Workspace

	local fade = TweenService:Create(muzzle, TweenInfo.new(0.05, Enum.EasingStyle.Linear), {
		Transparency = 1,
		Size = Vector3.new(0.05, 0.05, 0.05),
	})
	fade:Play()
	fade.Completed:Connect(function()
		muzzle:Destroy()
	end)
	local trailFade = TweenService:Create(trail, TweenInfo.new(0.08, Enum.EasingStyle.Linear), {
		Transparency = 1,
		Size = Vector3.new(0.03, 0.03, 10),
	})
	trailFade:Play()
	trailFade.Completed:Connect(function()
		if trail.Parent ~= nil then
			trail:Destroy()
		end
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

		local track = getShotTrack(humanoid)
		if track ~= nil then
			track:Play(0.05, 1, 2)
		end
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

	local ratRoot = ratModel.PrimaryPart
	if ratRoot ~= nil then
		playImpactFx(ratRoot.Position + Vector3.new(0, 0.8, 0), VisualManifest.Tools.ImpactShotColor)
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
		local mainHUD = getMainHUD()
		if mainHUD ~= nil and type(mainHUD.ShowRepairMinigame) == "function" then
			mainHUD.ShowRepairMinigame(drillPart)
		end
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
	for _, child in container:GetChildren() do
		if child:IsA("Tool") and child.Name == SHOTGUN_TOOL_NAME then
			bindShotgunTool(child)
		elseif child:IsA("Tool") and child.Name == WRENCH_TOOL_NAME then
			bindWrenchTool(child)
		end
	end

	container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child.Name == SHOTGUN_TOOL_NAME then
			bindShotgunTool(child)
		elseif child:IsA("Tool") and child.Name == WRENCH_TOOL_NAME then
			bindWrenchTool(child)
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
	end)

	local currentCharacter = LocalPlayer.Character
	if currentCharacter ~= nil then
		bindContainer(currentCharacter)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			tryPunch()
			return
		end
	end)
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
