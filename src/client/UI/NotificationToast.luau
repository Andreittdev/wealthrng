-- Small stacking toast notifications, top-center, auto-dismiss after a few
-- seconds. Fully self-contained (owns its own ScreenGui + SystemMessage
-- listener) -- Main.client.luau just calls NotificationToast.Init() once.
-- SystemMessage already existed for the chat-log notice (see
-- Main.client.luau's TextChatService call) -- this listens to the exact
-- same remote/event instead of adding a second one, so every server-side
-- "you bought/sold/claimed X" call (AssetManager, InvestmentManager,
-- SellManager, PotionManager, UpgradeManager, GroupRewardsManager,
-- Main.server.luau's gamepass grant) shows up both places for free.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local NotificationToast = {}

local TOAST_WIDTH = 340
local TOAST_HEIGHT = 52
local TOAST_GAP = 8
local TOAST_LIFETIME_SECONDS = 3.5
local TOAST_FADE_SECONDS = 0.25

function NotificationToast.Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "WealthRNG_Notifications"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 20
	screenGui.Parent = playerGui

	-- Bottom-right corner, not bottom-center -- the bottom-center band is
	-- already claimed by RollPanel's dice/upgrade/auto-roll HUD AND the
	-- VIP/Group Rewards proximity popups (both anchored around -230 from
	-- the bottom); stacking toasts in that same band made them overlap the
	-- proximity popups whenever one showed up while you were standing near
	-- a marker. Bottom-right is otherwise empty screen real estate.
	local container = Instance.new("Frame")
	-- Scale-based width (capped at TOAST_WIDTH via UISizeConstraint) instead
	-- of a flat 340px -- on a narrow phone, 340px + the 16px margin was
	-- wide enough to clip off the right edge of the screen.
	container.Size = UDim2.new(0.85, 0, 0.5, 0)
	container.AnchorPoint = Vector2.new(1, 1)
	container.Position = UDim2.new(1, -16, 1, -70)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	local containerSizeConstraint = Instance.new("UISizeConstraint")
	containerSizeConstraint.MaxSize = Vector2.new(TOAST_WIDTH, math.huge)
	containerSizeConstraint.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, TOAST_GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	-- Bottom-aligned so new toasts stack upward from the bottom edge
	-- (newest closest to the bottom) instead of hanging off the top of an
	-- otherwise-empty container.
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	local order = 0

	local function show(rawText: string)
		order += 1
		local currentOrder = order

		local toast = Instance.new("Frame")
		toast.Size = UDim2.new(1, 0, 0, TOAST_HEIGHT)
		toast.BackgroundColor3 = Theme.Colors.Panel
		toast.BackgroundTransparency = 1
		toast.BorderSizePixel = 0
		toast.LayoutOrder = currentOrder
		toast.Parent = container
		Theme.Round(toast, UDim.new(0, 10))
		local stroke = Theme.Stroke(toast, Color3.fromRGB(255, 215, 140), 1.5)
		stroke.Transparency = 1

		-- Strip rich-text tags (e.g. RollManager.luau's Ultra-unlock <font
		-- color="..."> callout) -- this label's RichText is off, so an
		-- untouched tag would render as literal "<font...>" text instead of
		-- being interpreted; the chat side (TextChatService) still shows it
		-- colored, this toast just shows the plain words.
		local text = rawText:gsub("<[^>]->", "")

		local label = Theme.Label(toast, UDim2.new(1, -20, 1, -12), text, false)
		label.Position = UDim2.new(0, 10, 0, 6)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.TextWrapped = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1

		local fadeIn = TweenInfo.new(TOAST_FADE_SECONDS, Enum.EasingStyle.Quad)
		TweenService:Create(toast, fadeIn, { BackgroundTransparency = 0 }):Play()
		TweenService:Create(stroke, fadeIn, { Transparency = 0.35 }):Play()
		TweenService:Create(label, fadeIn, { TextTransparency = 0, TextStrokeTransparency = 0 }):Play()

		task.delay(TOAST_LIFETIME_SECONDS, function()
			local fadeOut = TweenInfo.new(TOAST_FADE_SECONDS, Enum.EasingStyle.Quad)
			local outTween = TweenService:Create(toast, fadeOut, { BackgroundTransparency = 1 })
			TweenService:Create(stroke, fadeOut, { Transparency = 1 }):Play()
			TweenService:Create(label, fadeOut, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			outTween:Play()
			outTween.Completed:Wait()
			toast:Destroy()
		end)
	end

	local systemMessage = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SystemMessage")
	systemMessage.OnClientEvent:Connect(show)
end

return NotificationToast
