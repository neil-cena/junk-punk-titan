--!strict

local BlueprintController = require(script:WaitForChild("Controllers"):WaitForChild("BlueprintController"))
local VFXController = require(script:WaitForChild("Controllers"):WaitForChild("VFXController"))
local MainHUD = require(script:WaitForChild("UI"):WaitForChild("MainHUD"))

BlueprintController.Init()
VFXController.Init()
MainHUD.Init()
