--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local REMOTE_FOLDER_NAME = "Remotes"

local RemoteNames = {
	RequestPurchase = "RequestPurchase",
	BuildingDismantled = "BuildingDismantled",
	ScrapUpdated = "ScrapUpdated",
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
			BuildingDismantled = getOrCreateRemoteEvent(folder, RemoteNames.BuildingDismantled),
			ScrapUpdated = getOrCreateRemoteEvent(folder, RemoteNames.ScrapUpdated),
			RoleSelected = getOrCreateRemoteEvent(folder, RemoteNames.RoleSelected),
			WaveStarted = getOrCreateRemoteEvent(folder, RemoteNames.WaveStarted),
		}
	end

	local folder = waitForRemoteFolder()

	return {
		Folder = folder,
		RequestPurchase = waitForRemoteFunction(folder, RemoteNames.RequestPurchase),
		BuildingDismantled = waitForRemoteEvent(folder, RemoteNames.BuildingDismantled),
		ScrapUpdated = waitForRemoteEvent(folder, RemoteNames.ScrapUpdated),
		RoleSelected = waitForRemoteEvent(folder, RemoteNames.RoleSelected),
		WaveStarted = waitForRemoteEvent(folder, RemoteNames.WaveStarted),
	}
end

return Remotes
