--!strict

local StarterGui = game:GetService("StarterGui")
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
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
}

for _, entry in initOrder do
	local ok, err = pcall(entry.fn)
	if not ok then
		warn(("[ClientInit] %s.Init() FAILED: %s"):format(entry.name, tostring(err)))
	end
end
