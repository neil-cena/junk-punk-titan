--!strict

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

local EndScreenUI = {}

local gameOverGui: Frame? = nil
local victoryGui: Frame? = nil
local finalStandBanner: TextLabel? = nil

local function buildStatsText(remotes: any): string
	local ok, stats = pcall(function()
		return remotes.RequestSessionStats:InvokeServer()
	end)
	if not ok or type(stats) ~= "table" then
		return ""
	end

	local elapsed = stats.timeElapsed or 0
	local mins = math.floor(elapsed / 60)
	local secs = math.floor(elapsed % 60)
	return string.format(
		"Scrap Gathered: %d\nRats Eliminated: %d\nBuildings Lost: %d\nWaves Survived: %d\nTime: %02d:%02d",
		stats.scrapGathered or 0,
		stats.ratsKilled or 0,
		stats.buildingsLost or 0,
		stats.wavesCompleted or 0,
		mins, secs
	)
end

function EndScreenUI.ShowGameOver(rootGui: ScreenGui, remotes: any)
	if gameOverGui ~= nil then
		return
	end

	local overlay = Instance.new("Frame")
	overlay.Name = "GameOverOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(10, 5, 5)
	overlay.BackgroundTransparency = 0.2
	overlay.Parent = rootGui
	gameOverGui = overlay

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 0.2)
	title.Position = UDim2.new(0, 0, 0.35, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 70, 70)
	title.TextStrokeTransparency = 0.4
	title.Text = "THE TITAN HAS COLLAPSED"
	title.Parent = overlay

	local statsLabel = Instance.new("TextLabel")
	statsLabel.Size = UDim2.new(0.5, 0, 0.25, 0)
	statsLabel.Position = UDim2.new(0.25, 0, 0.5, 0)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Font = Enum.Font.GothamSemibold
	statsLabel.TextColor3 = Color3.fromRGB(220, 200, 200)
	statsLabel.TextScaled = true
	statsLabel.TextWrapped = true
	statsLabel.Text = buildStatsText(remotes)
	statsLabel.Parent = overlay

	task.delay(5, function()
		local ok = pcall(function()
			TeleportService:Teleport(game.PlaceId, LocalPlayer)
		end)
		if not ok then
			LocalPlayer:Kick("Titan collapsed. Session reset.")
		end
	end)
end

function EndScreenUI.ShowVictory(rootGui: ScreenGui, remotes: any)
	if victoryGui ~= nil then
		return
	end

	EndScreenUI.ClearFinalStandBanner()

	local overlay = Instance.new("Frame")
	overlay.Name = "VictoryOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(5, 5, 15)
	overlay.BackgroundTransparency = 0.15
	overlay.Parent = rootGui
	victoryGui = overlay

	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.8, 0.15)
	title.Position = UDim2.new(0.1, 0, 0.18, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 230, 80)
	title.TextStrokeTransparency = 0.3
	title.Text = "VICTORY"
	title.Parent = overlay

	local subtitle = Instance.new("TextLabel")
	subtitle.Size = UDim2.fromScale(0.6, 0.06)
	subtitle.Position = UDim2.new(0.2, 0, 0.34, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamBold
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromRGB(200, 220, 180)
	subtitle.Text = "The Titan stands."
	subtitle.Parent = overlay

	local statsLabel = Instance.new("TextLabel")
	statsLabel.Size = UDim2.new(0.5, 0, 0.3, 0)
	statsLabel.Position = UDim2.new(0.25, 0, 0.44, 0)
	statsLabel.BackgroundTransparency = 1
	statsLabel.Font = Enum.Font.GothamSemibold
	statsLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	statsLabel.TextScaled = true
	statsLabel.TextWrapped = true
	statsLabel.Text = buildStatsText(remotes)
	statsLabel.Parent = overlay

	task.delay(6, function()
		local teleOk = pcall(function()
			TeleportService:Teleport(game.PlaceId, LocalPlayer)
		end)
		if not teleOk then
			LocalPlayer:Kick("Victory! Session complete.")
		end
	end)
end

function EndScreenUI.ShowFinalStandBanner(rootGui: ScreenGui)
	if finalStandBanner ~= nil then
		return
	end

	local banner = Instance.new("TextLabel")
	banner.Name = "FinalStandBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0.13, 0)
	banner.Size = UDim2.new(0.3, 0, 0, 40)
	banner.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
	banner.BackgroundTransparency = 0.15
	banner.Font = Enum.Font.GothamBlack
	banner.TextColor3 = Color3.fromRGB(255, 230, 100)
	banner.TextScaled = true
	banner.Text = "FINAL STAND - DEFEND THE TITAN"
	banner.Parent = rootGui
	finalStandBanner = banner

	task.spawn(function()
		while finalStandBanner ~= nil and finalStandBanner.Parent ~= nil do
			TweenService:Create(finalStandBanner, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				TextColor3 = Color3.fromRGB(255, 100, 100),
			}):Play()
			task.wait(0.6)
			if finalStandBanner == nil then
				break
			end
			TweenService:Create(finalStandBanner, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				TextColor3 = Color3.fromRGB(255, 230, 100),
			}):Play()
			task.wait(0.6)
		end
	end)
end

function EndScreenUI.ClearFinalStandBanner()
	if finalStandBanner ~= nil then
		finalStandBanner:Destroy()
		finalStandBanner = nil
	end
end

return EndScreenUI
