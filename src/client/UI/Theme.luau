--!strict

local Theme = {}

Theme.Colors = {
	Panel = Color3.fromRGB(28, 24, 21),
	PanelAlt = Color3.fromRGB(36, 30, 26),
	PanelStroke = Color3.fromRGB(128, 98, 69),
	Accent = Color3.fromRGB(255, 189, 102),
	TextPrimary = Color3.fromRGB(243, 232, 210),
	TextMuted = Color3.fromRGB(179, 164, 144),
	Good = Color3.fromRGB(118, 228, 122),
	Bad = Color3.fromRGB(255, 105, 92),
	WaveTimerNormal = Color3.fromRGB(255, 193, 64),
	WaveTimerUrgent = Color3.fromRGB(255, 60, 60),
	DismantleBarBg = Color3.fromRGB(120, 25, 25),
	DismantleBarFill = Color3.fromRGB(255, 70, 70),
	DismantleBarText = Color3.fromRGB(255, 255, 255),
	RoleCardBg = Color3.fromRGB(30, 30, 38),
	RoleOverlay = Color3.fromRGB(10, 10, 15),
	RoleTitle = Color3.fromRGB(255, 230, 140),
	RoleColors = {
		Scrapper = Color3.fromRGB(255, 200, 60),
		Fixer = Color3.fromRGB(100, 200, 255),
		Enforcer = Color3.fromRGB(255, 100, 80),
	},
	HealthGood = Color3.fromRGB(80, 200, 100),
	HealthWarning = Color3.fromRGB(255, 180, 50),
	HealthBad = Color3.fromRGB(255, 60, 60),
	DamageNumber = Color3.fromRGB(255, 160, 120),
	ScrapCombo = Color3.fromRGB(255, 221, 130),
	WaveSplash = Color3.fromRGB(255, 124, 92),
	IntegrityBarBg = Color3.fromRGB(60, 20, 20),
	IntegrityGood = Color3.fromRGB(80, 200, 100),
	IntegrityWarning = Color3.fromRGB(255, 180, 50),
	IntegrityBad = Color3.fromRGB(255, 60, 60),
	StormBanner = Color3.fromRGB(120, 80, 40),
	ThreatBanner = Color3.fromRGB(172, 35, 35),
	TetherStatus = Color3.fromRGB(255, 230, 180),
	BuildProgressFill = Color3.fromRGB(90, 220, 120),
	ToolEquipped = Color3.fromRGB(78, 140, 76),
	ToolUnequipped = Color3.fromRGB(48, 48, 58),
	FinalStandBanner = Color3.fromRGB(160, 40, 40),
	FinalStandPulseA = Color3.fromRGB(255, 100, 100),
	FinalStandPulseB = Color3.fromRGB(255, 230, 100),
	GameOverOverlay = Color3.fromRGB(10, 5, 5),
	VictoryOverlay = Color3.fromRGB(5, 5, 15),
	SliderTrack = Color3.fromRGB(60, 60, 70),
	SliderFill = Color3.fromRGB(255, 200, 80),
	TutorialHintBg = Color3.fromRGB(20, 20, 30),
	TutorialHintText = Color3.fromRGB(220, 220, 200),
	ScrapDeltaPositive = Color3.fromRGB(120, 255, 120),
	ScrapDeltaNegative = Color3.fromRGB(255, 120, 120),
	MinigameBarBg = Color3.fromRGB(70, 70, 75),
	MinigameSuccess = Color3.fromRGB(120, 245, 120),
	MinigameFail = Color3.fromRGB(255, 110, 110),
}

Theme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Body = Enum.Font.Gotham,
	Emphasis = Enum.Font.GothamBold,
}

local function addCorner(guiObject: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = guiObject
end

function Theme.StylePanel(frame: Frame, radius: number?)
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BackgroundTransparency = 0.12
	addCorner(frame, radius or 6)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.PanelStroke
	stroke.Thickness = 1
	stroke.Transparency = 0.25
	stroke.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Colors.PanelAlt),
		ColorSequenceKeypoint.new(1, Theme.Colors.Panel),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	gradient.Parent = frame
end

function Theme.StyleButton(button: TextButton)
	Theme.StylePanel(button, 6)
	button.Font = Theme.Fonts.Emphasis
	button.TextColor3 = Theme.Colors.TextPrimary
	button.AutoButtonColor = true
end

return Theme
