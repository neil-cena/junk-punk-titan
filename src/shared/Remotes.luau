--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_FOLDER_NAME = "Remotes"

local RemoteNames = {
	RequestPurchase = "RequestPurchase",
	RequestEconomyState = "RequestEconomyState",
	RequestBuildCosts = "RequestBuildCosts",
	DebugCommand = "DebugCommand",
	PlaceBlueprint = "PlaceBlueprint",
	FinishBlueprint = "FinishBlueprint",
	BlueprintPlaced = "BlueprintPlaced",
	BlueprintFinished = "BlueprintFinished",
	BuildingDismantled = "BuildingDismantled",
	HitEnemy = "HitEnemy",
	EnemyKilled = "EnemyKilled",
	ThreatDetected = "ThreatDetected",
	ScrapUpdated = "ScrapUpdated",
	StormSteelUpdated = "StormSteelUpdated",
	StormStarted = "StormStarted",
	StormEnded = "StormEnded",
	TetherStatus = "TetherStatus",
	RoleSelected = "RoleSelected",
	WaveStarted = "WaveStarted",
}

local function getOrCreateRemoteFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	local createdFolder = Instance.new("Folder")
	createdFolder.Name = REMOTE_FOLDER_NAME
	createdFolder.Parent = ReplicatedStorage
	return createdFolder
end

local function getOrCreateRemoteFunction(folder: Folder, remoteName: string): RemoteFunction
	local existing = folder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end

	local remoteFunction = Instance.new("RemoteFunction")
	remoteFunction.Name = remoteName
	remoteFunction.Parent = folder
	return remoteFunction
end

local function getOrCreateRemoteEvent(folder: Folder, remoteName: string): RemoteEvent
	local existing = folder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = remoteName
	remoteEvent.Parent = folder
	return remoteEvent
end

local function waitForRemoteFolder(): Folder
	return ReplicatedStorage:WaitForChild(REMOTE_FOLDER_NAME) :: Folder
end

local function waitForRemoteFunction(folder: Folder, remoteName: string): RemoteFunction
	return folder:WaitForChild(remoteName) :: RemoteFunction
end

local function waitForRemoteEvent(folder: Folder, remoteName: string): RemoteEvent
	return folder:WaitForChild(remoteName) :: RemoteEvent
end

local Remotes = {
	Names = RemoteNames,
}

function Remotes.Get()
	if RunService:IsServer() then
		local folder = getOrCreateRemoteFolder()

		return {
			Folder = folder,
			RequestPurchase = getOrCreateRemoteFunction(folder, RemoteNames.RequestPurchase),
			RequestEconomyState = getOrCreateRemoteFunction(folder, RemoteNames.RequestEconomyState),
			RequestBuildCosts = getOrCreateRemoteFunction(folder, RemoteNames.RequestBuildCosts),
			DebugCommand = getOrCreateRemoteEvent(folder, RemoteNames.DebugCommand),
			PlaceBlueprint = getOrCreateRemoteEvent(folder, RemoteNames.PlaceBlueprint),
			FinishBlueprint = getOrCreateRemoteFunction(folder, RemoteNames.FinishBlueprint),
			BlueprintPlaced = getOrCreateRemoteEvent(folder, RemoteNames.BlueprintPlaced),
			BlueprintFinished = getOrCreateRemoteEvent(folder, RemoteNames.BlueprintFinished),
			BuildingDismantled = getOrCreateRemoteEvent(folder, RemoteNames.BuildingDismantled),
			HitEnemy = getOrCreateRemoteEvent(folder, RemoteNames.HitEnemy),
			EnemyKilled = getOrCreateRemoteEvent(folder, RemoteNames.EnemyKilled),
			ThreatDetected = getOrCreateRemoteEvent(folder, RemoteNames.ThreatDetected),
			ScrapUpdated = getOrCreateRemoteEvent(folder, RemoteNames.ScrapUpdated),
			StormSteelUpdated = getOrCreateRemoteEvent(folder, RemoteNames.StormSteelUpdated),
			StormStarted = getOrCreateRemoteEvent(folder, RemoteNames.StormStarted),
			StormEnded = getOrCreateRemoteEvent(folder, RemoteNames.StormEnded),
			TetherStatus = getOrCreateRemoteEvent(folder, RemoteNames.TetherStatus),
			RoleSelected = getOrCreateRemoteEvent(folder, RemoteNames.RoleSelected),
			WaveStarted = getOrCreateRemoteEvent(folder, RemoteNames.WaveStarted),
		}
	end

	local folder = waitForRemoteFolder()

	return {
		Folder = folder,
		RequestPurchase = waitForRemoteFunction(folder, RemoteNames.RequestPurchase),
		RequestEconomyState = waitForRemoteFunction(folder, RemoteNames.RequestEconomyState),
		RequestBuildCosts = waitForRemoteFunction(folder, RemoteNames.RequestBuildCosts),
		DebugCommand = waitForRemoteEvent(folder, RemoteNames.DebugCommand),
		PlaceBlueprint = waitForRemoteEvent(folder, RemoteNames.PlaceBlueprint),
		FinishBlueprint = waitForRemoteFunction(folder, RemoteNames.FinishBlueprint),
		BlueprintPlaced = waitForRemoteEvent(folder, RemoteNames.BlueprintPlaced),
		BlueprintFinished = waitForRemoteEvent(folder, RemoteNames.BlueprintFinished),
		BuildingDismantled = waitForRemoteEvent(folder, RemoteNames.BuildingDismantled),
		HitEnemy = waitForRemoteEvent(folder, RemoteNames.HitEnemy),
		EnemyKilled = waitForRemoteEvent(folder, RemoteNames.EnemyKilled),
		ThreatDetected = waitForRemoteEvent(folder, RemoteNames.ThreatDetected),
		ScrapUpdated = waitForRemoteEvent(folder, RemoteNames.ScrapUpdated),
		StormSteelUpdated = waitForRemoteEvent(folder, RemoteNames.StormSteelUpdated),
		StormStarted = waitForRemoteEvent(folder, RemoteNames.StormStarted),
		StormEnded = waitForRemoteEvent(folder, RemoteNames.StormEnded),
		TetherStatus = waitForRemoteEvent(folder, RemoteNames.TetherStatus),
		RoleSelected = waitForRemoteEvent(folder, RemoteNames.RoleSelected),
		WaveStarted = waitForRemoteEvent(folder, RemoteNames.WaveStarted),
	}
end

return Remotes
