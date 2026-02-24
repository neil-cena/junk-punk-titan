--!strict

local BlueprintController = require(script:WaitForChild("Controllers"):WaitForChild("BlueprintController"))
local ToolController = require(script:WaitForChild("Controllers"):WaitForChild("ToolController"))
local VFXController = require(script:WaitForChild("Controllers"):WaitForChild("VFXController"))
local MainHUD = require(script:WaitForChild("UI"):WaitForChild("MainHUD"))

BlueprintController.Init()
ToolController.Init()
VFXController.Init()
MainHUD.Init()
