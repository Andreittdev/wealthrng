-- "Playtime Rewards" card-grid popup -- same visual convention as
-- DailyRewardsProximityPanel.luau (header bar with icon + title + Close
-- (X), card grid below) but every milestone card tracks its OWN
-- claimed/unlocked state independently (see PlaytimeRewardsConfig.luau),
-- instead of a single "current day" pointer -- so several can be sitting
-- ready to claim (or counting down) at once. Opens automatically when
-- standing near the plaza's purple "Playtime Rewards" floor marker
-- (MapBuilder's buildFloorMarker), same proximity check as the other
-- reward panels. Closing it suppresses auto-reopening until you leave and
-- re-enter the marker's radius.
--
-- Server-authoritative accrual/cooldown/payout is
-- PlaytimeRewardsManager.luau; this is display + input only.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlaytimeRewardsConfig = require(ReplicatedStorage.Modules.PlaytimeRewardsConfig)
local PotionDatabase = require(ReplicatedStorage.Modules.PotionDatabase)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local PlaytimeRewardsProximityPanel = {}

local PROXIMITY_RADIUS_STUDS = 10

local CARD_SIZE = 140
local CARD_GAP = 10
local COLUMNS = 3
local PANEL_WIDTH = 16 + CARD_SIZE * COLUMNS + CARD_GAP * (COLUMNS - 1) + 16
local PANEL_HEIGHT = 460

-- Cycled per card index (1,2,3,1,2,3,...) purely for visual variety, same
-- idea as the reference layout's alternating card colors.
local CARD_COLORS = {
	Color3.fromRGB(200, 110, 40),
	Color3.fromRGB(120, 70, 200),
	Color3.fromRGB(210, 60, 130),
}

local READY_COLOR = Color3.fromRGB(90, 220, 130)
local CLAIMED_COLOR = Color3.fromRGB(90, 90, 100)

local MONEY_ICON = "\u{1F4B0}"
local POTION_ICON = "\u{1F9EA}"
local CHECK_ICON = "\u{2714}"

local function formatDuration(totalSeconds: number): string
	totalSeconds = math.max(math.floor(totalSeconds), 0)
	local minutes = totalSeconds // 60
	local seconds = totalSeconds % 60
	return string.format("%d:%02d", minutes, seconds)
end

local function describeMilestone(milestone): string
	local potionDurationMinutes = milestone.PotionDurationSeconds and math.floor(milestone.PotionDurationSeconds / 60) or nil

	-- CashAmount = 0 marks a Potion-only "special item" slot (no $ shown,
	-- see PlaytimeRewardsConfig.luau) -- mirrors the reference layout's
	-- named-item cards (no cash figure on those either).
	if milestone.CashAmount <= 0 and milestone.PotionIds then
		local name: string
		if #milestone.PotionIds == 1 then
			local potion = PotionDatabase.GetPotion(milestone.PotionIds[1])
			name = potion and potion.Name or milestone.PotionIds[1]
		else
			name = "All Potions"
		end
		return potionDurationMinutes and string.format("%s\n(%dm)", name, potionDurationMinutes) or name
	end

	local text = "+" .. NumberFormat.FormatCash(milestone.CashAmount)
	if milestone.PotionIds and #milestone.PotionIds == 1 then
		local potion = PotionDatabase.GetPotion(milestone.PotionIds[1])
		if potion then
			text ..= "\n" .. potion.Name
		end
	elseif milestone.PotionIds then
		text ..= "\nAll Potions"
	end
	return text
end

function PlaytimeRewardsProximityPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local claimPlaytimeReward = remotes:WaitForChild("ClaimPlaytimeReward")
	local playtimeRewardStateUpdated = remotes:WaitForChild("PlaytimeRewardStateUpdated")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -230)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 8
	panel.Parent = screenGui
	Theme.Round(panel, UDim.new(0, 20))
	Theme.Stroke(panel, Color3.fromRGB(180, 120, 255), 2)
	Theme.Shadow(panel)

	-- ===== Header =====
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(0, 36, 0, 36)
	iconLabel.Position = UDim2.new(0, 16, 0, 14)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = "\u{23F3}" -- hourglass
	iconLabel.TextScaled = true
	iconLabel.Parent = panel

	local titleLabel = Theme.Label(panel, UDim2.new(1, -150, 0, 36), "PLAYTIME REWARDS", true)
	titleLabel.Position = UDim2.new(0, 60, 0, 14)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.new(0, 36, 0, 36)
	closeButton.Position = UDim2.new(1, -52, 0, 14)
	closeButton.BackgroundColor3 = Theme.Colors.Danger
	closeButton.BorderSizePixel = 0
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.Font = Theme.Fonts.Header
	closeButton.TextScaled = true
	closeButton.AutoButtonColor = true
	closeButton.ZIndex = 9
	closeButton.Parent = panel
	Theme.Round(closeButton, UDim.new(1, 0))

	local subtitleLabel = Theme.Label(panel, UDim2.new(1, -32, 0, 20), "Earn Cash (and sometimes a Potion) the longer you play!")
	subtitleLabel.Position = UDim2.new(0, 16, 0, 54)
	subtitleLabel.TextColor3 = Theme.Colors.TextSecondary

	local playtimeLabel = Theme.Label(panel, UDim2.new(1, -32, 0, 18), "")
	playtimeLabel.Position = UDim2.new(0, 16, 0, 74)
	playtimeLabel.TextColor3 = Theme.Colors.Accent

	-- ===== Milestone card grid =====
	local content = Instance.new("ScrollingFrame")
	content.Size = UDim2.new(1, -32, 1, -108)
	content.Position = UDim2.new(0, 16, 0, 96)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 6
	content.ScrollBarImageColor3 = Theme.Colors.Accent
	content.Parent = panel

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, CARD_SIZE, 0, CARD_SIZE)
	gridLayout.CellPadding = UDim2.new(0, CARD_GAP, 0, CARD_GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = content

	local cards: { { Frame: Frame, Stroke: UIStroke, StateLabel: TextLabel } } = {}

	for index, milestone in PlaytimeRewardsConfig.Milestones do
		local card = Instance.new("Frame")
		card.LayoutOrder = index
		card.BackgroundColor3 = CARD_COLORS[(index - 1) % #CARD_COLORS + 1]
		card.BorderSizePixel = 0
		card.Parent = content
		Theme.Round(card, UDim.new(0, 14))
		local stroke = Theme.Stroke(card, Color3.fromRGB(255, 255, 255), 0)
		stroke.Transparency = 1

		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(0, 44, 0, 44)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 10)
		icon.BackgroundTransparency = 1
		icon.Text = milestone.PotionIds and POTION_ICON or MONEY_ICON
		icon.TextScaled = true
		icon.Parent = card

		local rewardLabel = Theme.Label(card, UDim2.new(1, -10, 0, 40), describeMilestone(milestone), true)
		rewardLabel.Position = UDim2.new(0, 5, 0, 58)
		rewardLabel.TextXAlignment = Enum.TextXAlignment.Center
		rewardLabel.TextWrapped = true
		rewardLabel.TextColor3 = Color3.fromRGB(255, 235, 150)

		local stateLabel = Theme.Label(card, UDim2.new(1, -10, 0, 22), "", true)
		stateLabel.Position = UDim2.new(0, 5, 1, -28)
		stateLabel.TextXAlignment = Enum.TextXAlignment.Center
		stateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)

		local clickButton = Instance.new("TextButton")
		clickButton.Size = UDim2.new(1, 0, 1, 0)
		clickButton.BackgroundTransparency = 1
		clickButton.Text = ""
		clickButton.AutoButtonColor = false
		clickButton.Parent = card
		clickButton.Activated:Connect(function()
			claimPlaytimeReward:FireServer(index)
		end)

		cards[index] = { Frame = card, Stroke = stroke, StateLabel = stateLabel }
	end

	local playtimeSeconds = 0
	local claimed: { [string]: boolean } = {}
	local cycleStartSeconds = 0
	local lastPushAt = os.clock()

	local function refresh()
		local liveElapsed = os.clock() - lastPushAt
		local livePlaytimeSeconds = playtimeSeconds + liveElapsed

		playtimeLabel.Text = "Time played: " .. formatDuration(livePlaytimeSeconds)

		for index, milestone in PlaytimeRewardsConfig.Milestones do
			local card = cards[index]
			local key = tostring(index)
			-- Cycle-relative, not the raw config value -- once the whole
			-- ladder has looped (see PlaytimeRewardsManager.luau), each
			-- milestone's actual threshold shifts forward by
			-- cycleStartSeconds so the countdown restarts from this cycle,
			-- not from lifetime playtime 0.
			local actualThreshold = cycleStartSeconds + milestone.ThresholdSeconds

			if claimed[key] then
				card.Stroke.Transparency = 0
				card.Stroke.Color = CLAIMED_COLOR
				card.StateLabel.Text = CHECK_ICON .. " Claimed"
				card.StateLabel.TextColor3 = Color3.fromRGB(220, 220, 225)
			elseif livePlaytimeSeconds >= actualThreshold then
				card.Stroke.Transparency = 0
				card.Stroke.Color = READY_COLOR
				card.StateLabel.Text = "CLAIM"
				card.StateLabel.TextColor3 = READY_COLOR
			else
				card.Stroke.Transparency = 1
				card.StateLabel.Text = formatDuration(actualThreshold - livePlaytimeSeconds)
				card.StateLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end

	refresh()

	playtimeRewardStateUpdated.OnClientEvent:Connect(
		function(state: { PlaytimeSeconds: number, Claimed: { [string]: boolean }, CycleStartSeconds: number })
			playtimeSeconds = state.PlaytimeSeconds
			claimed = state.Claimed
			cycleStartSeconds = state.CycleStartSeconds
			lastPushAt = os.clock()
			refresh()
		end
	)

	local manuallyClosed = false

	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)

	closeButton.Activated:Connect(function()
		manuallyClosed = true
		panel.Visible = false
	end)

	-- Same self-healing retry as VIPProximityPanel.luau/
	-- GroupRewardsProximityPanel.luau -- re-resolves Workspace.Map itself
	-- (not just the child lookup) in case a stale Map existed at t=0 and
	-- got destroyed/rebuilt out from under a cached reference.
	task.spawn(function()
		local marker: BasePart? = nil
		while not marker do
			local mapFolder = Workspace:WaitForChild("Map")
			marker = mapFolder:WaitForChild("PlaytimeRewardsMarker_Disk", 5) :: BasePart?
		end

		local wasInRange = false
		RunService.Heartbeat:Connect(function()
			local character = Players.LocalPlayer.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not rootPart then
				panel.Visible = false
				wasInRange = false
				return
			end

			local inRange = (rootPart.Position - marker.Position).Magnitude <= PROXIMITY_RADIUS_STUDS
			if inRange and not wasInRange then
				manuallyClosed = false
			end
			wasInRange = inRange

			if inRange and not manuallyClosed then
				panel.Visible = true
			elseif not inRange then
				panel.Visible = false
			end
		end)
	end)

	local handle = {}
	handle.Frame = panel
	return handle
end

return PlaytimeRewardsProximityPanel
