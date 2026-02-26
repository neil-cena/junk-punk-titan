--!strict

local RunService = game:GetService("RunService")

if not RunService:IsClient() then
	return {
		IsMobile = false,
		IsTouch = false,
	}
end

local UserInputService = game:GetService("UserInputService")

return {
	IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,
	IsTouch = UserInputService.TouchEnabled,
}
