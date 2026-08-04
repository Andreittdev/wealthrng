-- Popup shown when a non-owner presses RollPanel.luau's AUTO ROLL button --
-- offers 2 paths: wait AutoRollConfig.FreeUnlockSeconds while staying
-- connected (server-tracked, resets if they disconnect -- see
-- AutoRollManager.luau) for it free, or skip straight to the real gamepass
-- purchase. Not proximity-triggered like the plaza popups -- opened
-- directly via handle.Show(), same trigger style as any other
-- click-to-open panel.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutoRollConfig = require(ReplicatedStorage.Modules.AutoRollConfig)
local Theme = require(script.Parent.Theme)

local AutoRollFreePanel = {}

local PANEL_WIDTH = 400
local PANEL_HEIGHT = 340
local ACCENT_COLOR = Color3.fromRGB(90, 170, 255)

local function formatDuration(totalSeconds: number): string
	totalSeconds = math.max(math.floor(totalSeconds), 0)
	local minutes = math.floor(totalSeconds / 60)
	local seconds = totalSeconds % 60
	return string.format("%d:%02d", minutes, seconds)
end

function AutoRollFreePanel.Create(screenGui: ScreenGui, remotes: Folder)
	local startAutoRollFreeTimer = remotes:WaitForChild("StartAutoRollFreeTimer")
	local autoRollFreeTimerUpdated = remotes:WaitForChild("AutoRollFreeTimerUpdated")
	local statsUpdated = remotes:WaitForChild("StatsUpdated")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 8
	panel.Parent = screenGui
	Theme.Round(panel)
	Theme.Stroke(panel, ACCENT_COLOR, 1.5)
	local panelShadow = Theme.Shadow(panel)
	-- Same AutoScale pattern (with the same 0.5 minScale floor) every other
	-- proximity/purchase popup in this codebase already uses -- proven to
	-- shrink safely toward center on short/narrow phone screens without
	-- overflowing, so a bigger base size here doesn't risk a new bug, just
	-- scales down from a bigger starting point.
	Theme.AutoScale(screenGui, panel, PANEL_WIDTH, 0.5)
	Theme.AutoScale(screenGui, panelShadow, PANEL_WIDTH, 0.5)

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.new(0, 36, 0, 36)
	closeButton.Position = UDim2.new(1, -50, 0, 14)
	closeButton.BackgroundColor3 = Theme.Colors.Danger
	closeButton.BorderSizePixel = 0
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.Font = Theme.Fonts.Header
	closeButton.TextScaled = true
	closeButton.ZIndex = 9
	closeButton.Parent = panel
	Theme.Round(closeButton, UDim.new(1, 0))

	local titleLabel = Theme.Label(panel, UDim2.new(1, -70, 0, 40), "Get Auto Roll Free", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 16)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center

	local subtitleLabel = Theme.Label(panel, UDim2.new(1, -40, 0, 50), "Stay in the game and it's yours -- free, forever. Leaving resets the wait.")
	subtitleLabel.Position = UDim2.new(0, 20, 0, 62)
	subtitleLabel.TextColor3 = Theme.Colors.TextSecondary
	subtitleLabel.TextWrapped = true
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Center

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Size = UDim2.new(1, -40, 0, 76)
	timerLabel.Position = UDim2.new(0, 20, 0, 122)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Font = Theme.Fonts.Header
	timerLabel.TextScaled = true
	timerLabel.Text = "30:00"
	timerLabel.TextColor3 = ACCENT_COLOR
	timerLabel.TextStrokeTransparency = 0.3
	timerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	timerLabel.Parent = panel

	local orLabel = Theme.Label(panel, UDim2.new(1, -40, 0, 24), "-- OR --")
	orLabel.Position = UDim2.new(0, 20, 0, 204)
	orLabel.TextColor3 = Theme.Colors.TextSecondary
	orLabel.TextXAlignment = Enum.TextXAlignment.Center

	local instantButton = Theme.Button(panel, UDim2.new(1, -40, 0, 54), UDim2.new(0, 20, 0, 238), "Get Auto Roll Instantly - 3 R$", true)

	instantButton.Activated:Connect(function()
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, AutoRollConfig.GamepassId)
	end)

	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	-- Ticks down locally between server pushes (same pattern as
	-- DailyRewardsProximityPanel's countdown) instead of needing the server
	-- to push every second.
	local secondsRemaining = AutoRollConfig.FreeUnlockSeconds
	local lastPushAt = os.clock()

	local function refreshTimerLabel()
		local elapsedSincePush = os.clock() - lastPushAt
		local liveRemaining = math.max(secondsRemaining - elapsedSincePush, 0)
		timerLabel.Text = formatDuration(liveRemaining)
	end
	refreshTimerLabel()

	autoRollFreeTimerUpdated.OnClientEvent:Connect(function(remaining: number)
		secondsRemaining = remaining
		lastPushAt = os.clock()
		refreshTimerLabel()
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Visible then
				refreshTimerLabel()
			end
		end
	end)

	-- The actual grant rides the normal StatsUpdated.OwnsAutoRoll push
	-- (AutoRollManager.FreeGranted -> Main.server.luau -> StatsManager.
	-- Recompute) -- close automatically the moment that lands instead of
	-- making the player notice on their own and close it manually.
	statsUpdated.OnClientEvent:Connect(function(stats)
		if stats.OwnsAutoRoll and panel.Visible then
			panel.Visible = false
		end
	end)

	local handle = {}
	handle.Frame = panel

	function handle.Show()
		panel.Visible = true
		startAutoRollFreeTimer:FireServer()
	end

	return handle
end

return AutoRollFreePanel
