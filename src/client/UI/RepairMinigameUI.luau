--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local AudioManifest = require(Shared:WaitForChild("AudioManifest"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local RepairMinigameUI = {}

local activeFrame: Frame? = nil
local renderConn: RBXScriptConnection? = nil
local inputConn: RBXScriptConnection? = nil

local function playUISound(soundId: string, volume: number?)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.3
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		if sound.Parent ~= nil then
			sound:Destroy()
		end
	end)
end

function RepairMinigameUI.Clear()
	if renderConn ~= nil then
		renderConn:Disconnect()
		renderConn = nil
	end
	if inputConn ~= nil then
		inputConn:Disconnect()
		inputConn = nil
	end
	if activeFrame ~= nil then
		activeFrame:Destroy()
		activeFrame = nil
	end
end

function RepairMinigameUI.Show(drillPart: BasePart, rootGui: ScreenGui, remotes: any)
	RepairMinigameUI.Clear()

	local frame = Instance.new("Frame")
	frame.Name = "RepairMinigame"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 0.86, 0)
	frame.Size = UDim2.fromOffset(360, 92)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BackgroundTransparency = 0.15
	frame.Parent = rootGui
	activeFrame = frame
	Theme.StylePanel(frame, 8)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -10, 0, 28)
	title.Position = UDim2.fromOffset(5, 6)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Theme.Colors.TextPrimary
	title.TextScaled = true
	title.Text = "Pressure Hiss - Click / Press E"
	title.Parent = frame

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBackground"
	barBg.AnchorPoint = Vector2.new(0.5, 0)
	barBg.Position = UDim2.new(0.5, 0, 0, 42)
	barBg.Size = UDim2.fromOffset(320, 28)
	barBg.BackgroundColor3 = Theme.Colors.MinigameBarBg
	barBg.BorderSizePixel = 0
	barBg.Parent = frame

	local successWidth = math.clamp(Constants.MAINTENANCE.MinigameSuccessZoneWidth, 0.08, 0.45)
	local successStart = math.random() * (1 - successWidth)

	local successZone = Instance.new("Frame")
	successZone.Name = "SuccessZone"
	successZone.Size = UDim2.new(successWidth, 0, 1, 0)
	successZone.Position = UDim2.new(successStart, 0, 0, 0)
	successZone.BackgroundColor3 = Theme.Colors.Good
	successZone.BorderSizePixel = 0
	successZone.Parent = barBg

	local needle = Instance.new("Frame")
	needle.Name = "Needle"
	needle.AnchorPoint = Vector2.new(0.5, 0)
	needle.Size = UDim2.new(0.02, 0, 1, 0)
	needle.Position = UDim2.new(0, 0, 0, 0)
	needle.BackgroundColor3 = Theme.Colors.Accent
	needle.BorderSizePixel = 0
	needle.Parent = barBg

	local feedback = Instance.new("TextLabel")
	feedback.Name = "Feedback"
	feedback.Size = UDim2.new(1, -10, 0, 22)
	feedback.Position = UDim2.new(0, 5, 1, -25)
	feedback.BackgroundTransparency = 1
	feedback.Font = Enum.Font.GothamBold
	feedback.TextScaled = true
	feedback.Text = ""
	feedback.Parent = frame

	local progress = 0
	local resolved = false
	local minigameSpeed = math.max(0.5, Constants.MAINTENANCE.MinigameBarSpeed)
	local successEnd = successStart + successWidth

	local function finish(success: boolean)
		if resolved then
			return
		end
		resolved = true

		if renderConn ~= nil then
			renderConn:Disconnect()
			renderConn = nil
		end
		if inputConn ~= nil then
			inputConn:Disconnect()
			inputConn = nil
		end

		remotes.RepairMinigameResult:FireServer(drillPart, success)
		if success then
			feedback.Text = ("+%d Stability!"):format(Constants.MAINTENANCE.WrenchSuccessRestore)
			feedback.TextColor3 = Theme.Colors.MinigameSuccess
			playUISound(AudioManifest.MinigameSuccess, 0.4)
		else
			feedback.Text = "CLOGGED!"
			feedback.TextColor3 = Theme.Colors.MinigameFail
			playUISound(AudioManifest.MinigameFail, 0.35)
		end

		local fadeTween = TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		})
		local titleTween = TweenService:Create(title, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
		})
		local feedbackTween = TweenService:Create(feedback, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 1,
		})
		fadeTween:Play()
		titleTween:Play()
		feedbackTween:Play()
		task.delay(0.5, function()
			if activeFrame == frame then
				RepairMinigameUI.Clear()
			end
		end)
	end

	local function submitAttempt()
		local hitPoint = progress
		if hitPoint >= successStart and hitPoint <= successEnd then
			finish(true)
		else
			finish(false)
		end
	end

	inputConn = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or resolved then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.E then
			submitAttempt()
		end
	end)

	renderConn = RunService.RenderStepped:Connect(function(dt: number)
		if resolved then
			return
		end

		progress += dt * minigameSpeed
		needle.Position = UDim2.new(math.clamp(progress, 0, 1), 0, 0, 0)

		if progress >= 1 then
			finish(false)
		end
	end)
end

return RepairMinigameUI
