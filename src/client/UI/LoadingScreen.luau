-- Full-screen "Become Rich RNG" loading screen, shown for a fixed 5-6s on
-- EVERY join. Lives under src/client/UI (StarterPlayerScripts), same as
-- every other client script -- NOT ReplicatedFirst. A ReplicatedFirst
-- version would paint over the screen a moment earlier, but ReplicatedFirst
-- is a DataModel folder Rojo has to be told about separately, and a live
-- sync session started before that mapping existed won't pick it up without
-- an explicit plugin reconnect -- which is exactly why the first attempt at
-- this never actually showed up in-game. src/client is already proven to
-- sync (MainUI, NotificationToast, etc. all run from here), so this is the
-- reliable place for it even though it starts a beat later.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local LoadingScreen = {}

local HOLD_SECONDS = 6
local FADE_SECONDS = 0.5

function LoadingScreen.Run()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LoadingScreen"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 1000
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local background = Instance.new("Frame")
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Theme.Colors.Background
	background.BorderSizePixel = 0
	background.ZIndex = 100
	background.Parent = screenGui

	local title = Instance.new("TextLabel")
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Size = UDim2.new(0.8, 0, 0, 90)
	title.Position = UDim2.new(0.5, 0, 0.46, 0)
	title.BackgroundTransparency = 1
	title.Font = Theme.Fonts.Header
	title.Text = "Become Rich RNG"
	title.TextColor3 = Theme.Colors.Accent
	title.TextScaled = true
	title.TextStrokeTransparency = 0.5
	title.TextStrokeColor3 = Color3.new(0, 0, 0)
	title.ZIndex = 101
	title.Parent = background

	local subtitle = Instance.new("TextLabel")
	subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
	subtitle.Size = UDim2.new(0.6, 0, 0, 30)
	subtitle.Position = UDim2.new(0.5, 0, 0.58, 0)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Theme.Fonts.Header
	subtitle.Text = "Loading..."
	subtitle.TextColor3 = Theme.Colors.TextSecondary
	subtitle.TextScaled = true
	subtitle.ZIndex = 101
	subtitle.Parent = background
	local subtitleSizeConstraint = Instance.new("UITextSizeConstraint")
	subtitleSizeConstraint.MaxTextSize = 22
	subtitleSizeConstraint.Parent = subtitle

	-- Progress bar near the bottom, filling left-to-right over the same
	-- HOLD_SECONDS the screen is held for -- purely cosmetic (nothing real
	-- is being tracked/loaded), same as most games' loading bars during a
	-- fixed-length splash.
	local barTrack = Instance.new("Frame")
	barTrack.AnchorPoint = Vector2.new(0.5, 1)
	barTrack.Size = UDim2.new(0.4, 0, 0, 14)
	barTrack.Position = UDim2.new(0.5, 0, 1, -60)
	barTrack.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
	barTrack.BorderSizePixel = 0
	barTrack.ZIndex = 101
	barTrack.Parent = background
	Theme.Round(barTrack, UDim.new(1, 0))
	local barTrackStroke = Theme.Stroke(barTrack, Theme.Colors.Accent, 1.5)
	barTrackStroke.Transparency = 0.3

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = Theme.Colors.Accent
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 102
	barFill.Parent = barTrack
	Theme.Round(barFill, UDim.new(1, 0))

	local barTween = TweenService:Create(barFill, TweenInfo.new(HOLD_SECONDS, Enum.EasingStyle.Linear), { Size = UDim2.new(1, 0, 1, 0) })
	barTween:Play()

	task.wait(HOLD_SECONDS)

	local backgroundFade = TweenService:Create(background, TweenInfo.new(FADE_SECONDS), { BackgroundTransparency = 1 })
	local titleFade = TweenService:Create(title, TweenInfo.new(FADE_SECONDS), { TextTransparency = 1, TextStrokeTransparency = 1 })
	local subtitleFade = TweenService:Create(subtitle, TweenInfo.new(FADE_SECONDS), { TextTransparency = 1 })
	local barTrackFade = TweenService:Create(barTrack, TweenInfo.new(FADE_SECONDS), { BackgroundTransparency = 1 })
	local barTrackStrokeFade = TweenService:Create(barTrackStroke, TweenInfo.new(FADE_SECONDS), { Transparency = 1 })
	local barFillFade = TweenService:Create(barFill, TweenInfo.new(FADE_SECONDS), { BackgroundTransparency = 1 })
	backgroundFade:Play()
	titleFade:Play()
	subtitleFade:Play()
	barTrackFade:Play()
	barTrackStrokeFade:Play()
	barFillFade:Play()
	backgroundFade.Completed:Wait()

	screenGui:Destroy()
end

return LoadingScreen
