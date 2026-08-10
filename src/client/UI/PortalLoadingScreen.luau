-- Quick full-screen fade covering the hub<->Endless Mode teleport
-- (PortalManager.luau, server) -- same-server, no real loading involved, but
-- the instant HumanoidRootPart jump reads as a jarring glitch without
-- something covering it. Unlike LoadingScreen.luau's one-shot 6s join
-- splash, this listens on PortalTeleport forever and can fire many times in
-- one session.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local PortalLoadingScreen = {}

local FADE_IN_SECONDS = 0.2
-- Held opaque this long AFTER fading in before fading back out --
-- PortalManager.luau delays the actual teleport by (at least) FADE_IN_SECONDS
-- so the screen is already solid black by the time the player's position
-- actually jumps, and this hold covers the rest of the trip + the streamed-in
-- destination settling in behind the black screen.
local HOLD_SECONDS = 0.6
local FADE_OUT_SECONDS = 0.35

function PortalLoadingScreen.Init()
	local portalTeleport = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PortalTeleport")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	portalTeleport.OnClientEvent:Connect(function(destinationLabel: string)
		local screenGui = Instance.new("ScreenGui")
		screenGui.Name = "PortalLoadingScreen"
		screenGui.IgnoreGuiInset = true
		screenGui.ResetOnSpawn = false
		screenGui.DisplayOrder = 1000
		screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		screenGui.Parent = playerGui

		local background = Instance.new("Frame")
		background.Size = UDim2.new(1, 0, 1, 0)
		background.BackgroundColor3 = Theme.Colors.Background
		background.BackgroundTransparency = 1
		background.BorderSizePixel = 0
		background.ZIndex = 100
		background.Parent = screenGui

		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Size = UDim2.new(0.8, 0, 0, 60)
		label.Position = UDim2.new(0.5, 0, 0.5, 0)
		label.BackgroundTransparency = 1
		label.Font = Theme.Fonts.Header
		label.Text = destinationLabel
		label.TextColor3 = Theme.Colors.Accent
		label.TextTransparency = 1
		label.TextScaled = true
		label.TextStrokeTransparency = 1
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.ZIndex = 101
		label.Parent = background

		local fadeIn = TweenService:Create(background, TweenInfo.new(FADE_IN_SECONDS), { BackgroundTransparency = 0 })
		local labelFadeIn = TweenService:Create(label, TweenInfo.new(FADE_IN_SECONDS), { TextTransparency = 0, TextStrokeTransparency = 0.5 })
		fadeIn:Play()
		labelFadeIn:Play()
		fadeIn.Completed:Wait()

		task.wait(HOLD_SECONDS)

		local fadeOut = TweenService:Create(background, TweenInfo.new(FADE_OUT_SECONDS), { BackgroundTransparency = 1 })
		local labelFadeOut = TweenService:Create(label, TweenInfo.new(FADE_OUT_SECONDS), { TextTransparency = 1, TextStrokeTransparency = 1 })
		fadeOut:Play()
		labelFadeOut:Play()
		fadeOut.Completed:Wait()

		screenGui:Destroy()
	end)
end

return PortalLoadingScreen
