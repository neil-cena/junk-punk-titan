--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetPackResolver = require(Shared:WaitForChild("assetpacks"):WaitForChild("AssetPackResolver"))

return AssetPackResolver.GetVisualManifest()
