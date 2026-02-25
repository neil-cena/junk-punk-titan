--!strict

local BlueprintController = require(script:WaitForChild("Controllers"):WaitForChild("BlueprintController"))
local ToolController = require(script:WaitForChild("Controllers"):WaitForChild("ToolController"))
local VFXController = require(script:WaitForChild("Controllers"):WaitForChild("VFXController"))
local MainHUD = require(script:WaitForChild("UI"):WaitForChild("MainHUD"))

local initOrder: { { name: string, fn: () -> () } } = {
	{ name = "BlueprintController", fn = function() BlueprintController.Init() end },
	{ name = "ToolController", fn = function() ToolController.Init() end },
	{ name = "VFXController", fn = function() VFXController.Init() end },
	{ name = "MainHUD", fn = function() MainHUD.Init() end },
}

for _, entry in initOrder do
	local ok, err = pcall(entry.fn)
	if not ok then
		warn(("[ClientInit] %s.Init() FAILED: %s"):format(entry.name, tostring(err)))
	end
end
