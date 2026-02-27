--!strict

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local VisualManifest = require(Shared:WaitForChild("VisualManifest"))

local function applyCameraZoomLimits()
	local cameraConfig = VisualManifest.Camera
	local minZoom = 6
	local maxZoom = 28

	if type(cameraConfig) == "table" then
		if typeof(cameraConfig.MinZoomDistance) == "number" then
			minZoom = math.max(0.5, cameraConfig.MinZoomDistance)
		end
		if typeof(cameraConfig.MaxZoomDistance) == "number" then
			maxZoom = math.max(minZoom, cameraConfig.MaxZoomDistance)
		end
	end

	LocalPlayer.CameraMinZoomDistance = minZoom
	LocalPlayer.CameraMaxZoomDistance = maxZoom
end

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

applyCameraZoomLimits()
LocalPlayer.CharacterAdded:Connect(function()
	applyCameraZoomLimits()
end)

local Controllers = script:WaitForChild("Controllers")
local UI = script:WaitForChild("UI")

local initOrder: { { name: string, fn: () -> () } } = {
	{
		name = "BlueprintController",
		fn = function()
			local module = require(Controllers:WaitForChild("BlueprintController"))
			module.Init()
		end,
	},
	{
		name = "ToolController",
		fn = function()
			local module = require(Controllers:WaitForChild("ToolController"))
			module.Init()
		end,
	},
	{
		name = "EnvironmentController",
		fn = function()
			local module = require(Controllers:WaitForChild("EnvironmentController"))
			module.Init()
		end,
	},
	{
		name = "VFXController",
		fn = function()
			local module = require(Controllers:WaitForChild("VFXController"))
			module.Init()
		end,
	},
	{
		name = "MainHUD",
		fn = function()
			local module = require(UI:WaitForChild("MainHUD"))
			module.Init()
		end,
	},
	{
		name = "MobileControls",
		fn = function()
			local module = require(UI:WaitForChild("MobileControls"))
			module.Init()
		end,
	},
}

for _, entry in initOrder do
	local ok, err = pcall(entry.fn)
	if not ok then
		warn(("[ClientInit] %s.Init() FAILED: %s"):format(entry.name, tostring(err)))
	end
end
