-- "Daily Rewards" card-grid popup (Day 1-6 as a 3x2 grid + a bigger Day 7
-- showcase card, matching the standard mobile-game daily-login layout) --
-- opens automatically when standing near the plaza's red "Daily Rewards"
-- floor marker (MapBuilder's buildFloorMarker), same proximity check as
-- VIPProximityPanel.luau/GroupRewardsProximityPanel.luau, but (unlike
-- those two) also has its own Close (X) button since this one has enough
-- content to want to dismiss deliberately instead of only by walking away.
-- Closing it suppresses auto-reopening until you leave and re-enter the
-- marker's radius, so it doesn't immediately pop back up.
--
-- Card states are derived purely from `currentDay` (session.DailyRewardDay,
-- the next day NOT yet claimed): days before it are "claimed" (checkmark),
-- that day itself is "current" (claimable now, or waiting out the cooldown
-- -- see the bottom button for which), days after are "locked" (dim).
-- Server-authoritative cooldown/payout is DailyRewardsManager.luau; this
-- is display + input only.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyRewardsConfig = require(ReplicatedStorage.Modules.DailyRewardsConfig)
local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local DailyRewardsProximityPanel = {}

local PROXIMITY_RADIUS_STUDS = 10

local CARD_SIZE = 130
local CARD_GAP = 10
local BIG_CARD_WIDTH = 150
local GRID_WIDTH = CARD_SIZE * 3 + CARD_GAP * 2
local CONTENT_HEIGHT = CARD_SIZE * 2 + CARD_GAP
local PANEL_WIDTH = 16 + GRID_WIDTH + CARD_GAP + BIG_CARD_WIDTH + 16
local PANEL_HEIGHT = 440

local CLAIMED_COLOR = Color3.fromRGB(70, 200, 110)
local CURRENT_COLOR = Color3.fromRGB(255, 205, 80)
local LOCKED_COLOR = Color3.fromRGB(80, 80, 92)
local LOCKED_TEXT_COLOR = Color3.fromRGB(120, 120, 132)

local MONEY_ICON = "\u{1F4B0}" -- money bag, Cash
local GIFT_ICON = "\u{1F381}" -- gift, Item
local HOUSE_ICON = "\u{1F3E0}" -- house, Asset
local BOLT_ICON = "\u{26A1}" -- lightning bolt, AutoRollGamepass
local CHECK_ICON = "\u{2714}"
-- Day 7's showcase icon -- the actual Auto Roll gamepass icon (same asset
-- RollPanel.luau's AUTO ROLL button uses), not a generic crown emoji like
-- every other day's plain-text icon, since Day 7 IS the Auto Roll gamepass.
local AUTO_ROLL_ICON = "rbxassetid://115324216729484"

-- One place mapping a reward (see DailyRewardsConfig.Days) to what a card
-- shows -- both the per-day grid cards and the bottom Claim button pull
-- from this so they can never disagree with each other.
local function describeReward(reward): (string, string)
	if reward.Type == "Cash" then
		return "+" .. NumberFormat.FormatCash(reward.Amount), MONEY_ICON
	elseif reward.Type == "Item" then
		local item = ItemDatabase.GetItem(reward.ItemId)
		return item and item.Name or "Item", GIFT_ICON
	elseif reward.Type == "Asset" then
		local asset = AssetDatabase.GetAsset(reward.AssetId)
		return asset and NumberFormat.FormatCash(asset.Price) .. " Asset" or "Asset", HOUSE_ICON
	elseif reward.Type == "AutoRollGamepass" then
		return "Auto Roll", BOLT_ICON
	end
	return "?", MONEY_ICON
end

local function formatDuration(totalSeconds: number): string
	totalSeconds = math.max(totalSeconds, 0)
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local seconds = totalSeconds % 60
	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %ds", minutes, seconds)
	end
	return string.format("%ds", seconds)
end

function DailyRewardsProximityPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local claimDailyReward = remotes:WaitForChild("ClaimDailyReward")
	local dailyRewardStateUpdated = remotes:WaitForChild("DailyRewardStateUpdated")

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
	Theme.Stroke(panel, Color3.fromRGB(120, 200, 255), 2)
	local panelShadow = Theme.Shadow(panel)
	-- PANEL_WIDTH (~600px, grid + big Day 7 card side by side) badly
	-- overflows any phone screen uncapped -- shrinks as one unit toward its
	-- bottom-center anchor instead. Lower minScale than the default 0.6
	-- (other proximity panels' default) since this one starts noticeably
	-- wider than they do -- 0.5 still keeps every card/button comfortably
	-- tappable, just smaller. Shadow needs its own matching call, see
	-- GroupRewardsProximityPanel's comment for why.
	Theme.AutoScale(screenGui, panel, PANEL_WIDTH, 0.5)
	Theme.AutoScale(screenGui, panelShadow, PANEL_WIDTH, 0.5)

	-- ===== Header =====
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(0, 36, 0, 36)
	iconLabel.Position = UDim2.new(0, 16, 0, 14)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = "\u{1F381}" -- gift
	iconLabel.TextScaled = true
	iconLabel.Parent = panel

	local titleLabel = Theme.Label(panel, UDim2.new(1, -150, 0, 36), "DAILY REWARDS", true)
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

	local subtitleLabel = Theme.Label(panel, UDim2.new(1, -32, 0, 20), "Come back every day for rewards!")
	subtitleLabel.Position = UDim2.new(0, 16, 0, 54)
	subtitleLabel.TextColor3 = Theme.Colors.TextSecondary

	-- ===== Day 1-6 grid + Day 7 showcase card =====
	local gridContainer = Instance.new("Frame")
	gridContainer.Size = UDim2.new(0, GRID_WIDTH, 0, CONTENT_HEIGHT)
	gridContainer.Position = UDim2.new(0, 16, 0, 84)
	gridContainer.BackgroundTransparency = 1
	gridContainer.Parent = panel

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, CARD_SIZE, 0, CARD_SIZE)
	gridLayout.CellPadding = UDim2.new(0, CARD_GAP, 0, CARD_GAP)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = gridContainer

	local bigCard = Instance.new("Frame")
	bigCard.Size = UDim2.new(0, BIG_CARD_WIDTH, 0, CONTENT_HEIGHT)
	bigCard.Position = UDim2.new(0, 16 + GRID_WIDTH + CARD_GAP, 0, 84)
	bigCard.BackgroundColor3 = Theme.Colors.Surface
	bigCard.BorderSizePixel = 0
	bigCard.Parent = panel
	Theme.Round(bigCard, UDim.new(0, 14))
	local bigStroke = Theme.Stroke(bigCard, LOCKED_COLOR, 2)

	local bigGradient = Instance.new("UIGradient")
	bigGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 190, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 150)),
	})
	bigGradient.Rotation = 90
	bigGradient.Enabled = false
	bigGradient.Parent = bigCard

	local function createCard(parent: Frame, layoutOrder: number, dayText: string, iconSize: number, amountBottomOffset: number)
		local card = parent
		local dayLabel = Theme.Label(card, UDim2.new(1, -12, 0, 22), dayText, true)
		dayLabel.Position = UDim2.new(0, 6, 0, 10)
		dayLabel.TextXAlignment = Enum.TextXAlignment.Center

		local icon = Instance.new("TextLabel")
		icon.Size = UDim2.new(0, iconSize, 0, iconSize)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, 0, 0.52, 0)
		icon.BackgroundTransparency = 1
		icon.TextScaled = true
		icon.ZIndex = card.ZIndex + 1
		icon.Parent = card

		local amountLabel = Theme.Label(card, UDim2.new(1, -12, 0, 22), "", true)
		amountLabel.Position = UDim2.new(0, 6, 1, -amountBottomOffset)
		amountLabel.TextXAlignment = Enum.TextXAlignment.Center

		return dayLabel, icon, amountLabel
	end

	-- Real image instead of a TextLabel icon's plain-text glyph -- same
	-- size/position/ZIndex, drawn on top (the TextLabel `icon` stays
	-- underneath, still used for the CHECK_ICON glyph once that day is
	-- actually claimed -- see refreshCards, which hides this and shows that
	-- instead once claimed).
	local function addIconImage(card: Frame, icon: TextLabel, imageId: string): ImageLabel
		local image = Instance.new("ImageLabel")
		image.Size = icon.Size
		image.AnchorPoint = icon.AnchorPoint
		image.Position = icon.Position
		image.BackgroundTransparency = 1
		image.ScaleType = Enum.ScaleType.Fit
		image.Image = imageId
		image.ZIndex = icon.ZIndex
		image.Parent = card
		return image
	end

	local dayCards: { [number]: { Stroke: UIStroke, Icon: TextLabel, IconImage: ImageLabel?, Amount: TextLabel, DayLabel: TextLabel } } = {}

	for day = 1, 6 do
		local card = Instance.new("Frame")
		card.LayoutOrder = day
		card.BackgroundColor3 = Theme.Colors.Surface
		card.BorderSizePixel = 0
		card.Parent = gridContainer
		Theme.Round(card, UDim.new(0, 14))
		local stroke = Theme.Stroke(card, LOCKED_COLOR, 2)

		local dayLabel, icon, amountLabel = createCard(card, day, "DAY " .. day, 46, 28)

		-- Day 2's fixed item (see DailyRewardsConfig.Days) gets its real
		-- item image instead of the generic GIFT_ICON emoji every other
		-- "Item"/"Asset"/etc. reward type still falls back to.
		local iconImage: ImageLabel? = nil
		if day == 2 then
			local day2Item = ItemDatabase.GetItem("Day2SpecialItem")
			if day2Item then
				iconImage = addIconImage(card, icon, day2Item.Image)
			end
		end

		dayCards[day] = { Stroke = stroke, Icon = icon, IconImage = iconImage, Amount = amountLabel, DayLabel = dayLabel }
	end

	local bigDayLabel, bigIcon, bigAmount = createCard(bigCard, 7, "DAY 7", 60, 34)
	local bigIconImage = addIconImage(bigCard, bigIcon, AUTO_ROLL_ICON)

	dayCards[7] = { Stroke = bigStroke, Icon = bigIcon, IconImage = bigIconImage, Amount = bigAmount, DayLabel = bigDayLabel }

	local bottomButton = Theme.Button(panel, UDim2.new(1, -32, 0, 44), UDim2.new(0, 16, 1, -60), "...", true)
	Theme.Round(bottomButton, UDim.new(0, 12))

	-- Pushes the text down and shrinks it a bit (TextScaled fills whatever
	-- space padding leaves) without changing the button's own size/tap area.
	local bottomButtonPadding = Instance.new("UIPadding")
	bottomButtonPadding.PaddingTop = UDim.new(0, 14)
	bottomButtonPadding.PaddingLeft = UDim.new(0, 10)
	bottomButtonPadding.PaddingRight = UDim.new(0, 10)
	bottomButtonPadding.Parent = bottomButton

	local currentDay = 1
	local canClaim = false
	local secondsRemaining = 0
	local lastPushAt = os.clock()
	local manuallyClosed = false

	local function refreshCards()
		for day = 1, 7 do
			local card = dayCards[day]
			local reward = DailyRewardsConfig.Days[day]
			local amountText, rewardIcon = describeReward(reward)

			if day == 7 then
				bigGradient.Enabled = day <= currentDay
			end

			local claimed = day < currentDay
			local current = day == currentDay

			if card.IconImage then
				-- Day 7: real Auto Roll image instead of a text glyph --
				-- shown while not yet claimed, swapped for the same plain
				-- CHECK_ICON text every other day uses once it has been.
				card.IconImage.Visible = not claimed
				card.IconImage.ImageColor3 = current and Color3.fromRGB(255, 255, 255) or LOCKED_TEXT_COLOR
				card.Icon.Text = claimed and CHECK_ICON or ""
			else
				card.Icon.Text = claimed and CHECK_ICON or rewardIcon
			end

			if claimed then
				card.Stroke.Color = CLAIMED_COLOR
				card.Icon.TextColor3 = CLAIMED_COLOR
				card.DayLabel.TextColor3 = Theme.Colors.TextSecondary
				card.Amount.TextColor3 = Theme.Colors.TextSecondary
			elseif current then
				card.Stroke.Color = CURRENT_COLOR
				card.Icon.TextColor3 = Color3.fromRGB(255, 255, 255)
				card.DayLabel.TextColor3 = CURRENT_COLOR
				card.Amount.TextColor3 = CURRENT_COLOR
			else
				card.Stroke.Color = LOCKED_COLOR
				card.Icon.TextColor3 = LOCKED_TEXT_COLOR
				card.DayLabel.TextColor3 = LOCKED_TEXT_COLOR
				card.Amount.TextColor3 = LOCKED_TEXT_COLOR
			end

			card.Amount.Text = amountText
		end
	end

	local function refreshButton()
		if canClaim then
			local amountText = describeReward(DailyRewardsConfig.Days[currentDay])
			bottomButton.Text = "CLAIM " .. amountText
			bottomButton.Active = true
			bottomButton.AutoButtonColor = true
			bottomButton.BackgroundColor3 = Theme.Colors.Success
			bottomButton.TextColor3 = Color3.fromRGB(20, 20, 20)
		else
			-- secondsRemaining ticks down locally between server pushes
			-- (see the task.spawn loop below) so the countdown doesn't just
			-- sit frozen at whatever value the last push had.
			local elapsedSincePush = os.clock() - lastPushAt
			local liveRemaining = math.max(secondsRemaining - elapsedSincePush, 0)
			bottomButton.Text = "NEXT IN " .. formatDuration(liveRemaining)
			bottomButton.Active = false
			bottomButton.AutoButtonColor = false
			bottomButton.BackgroundColor3 = Theme.Colors.Surface
			bottomButton.TextColor3 = Theme.Colors.TextSecondary
		end
	end

	refreshCards()
	refreshButton()

	bottomButton.Activated:Connect(function()
		if not canClaim then
			return
		end
		claimDailyReward:FireServer()
	end)

	closeButton.Activated:Connect(function()
		manuallyClosed = true
		panel.Visible = false
	end)

	dailyRewardStateUpdated.OnClientEvent:Connect(function(state: { Day: number, CanClaim: boolean, SecondsRemaining: number })
		currentDay = state.Day
		canClaim = state.CanClaim
		secondsRemaining = state.SecondsRemaining
		lastPushAt = os.clock()
		refreshCards()
		refreshButton()
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Visible and not canClaim then
				refreshButton()
			end
		end
	end)

	-- Same self-healing retry as VIPProximityPanel.luau/
	-- GroupRewardsProximityPanel.luau -- re-resolves Workspace.Map itself
	-- (not just the child lookup) in case a stale Map existed at t=0 and
	-- got destroyed/rebuilt out from under a cached reference.
	task.spawn(function()
		local marker: BasePart? = nil
		while not marker do
			local mapFolder = Workspace:WaitForChild("Map")
			marker = mapFolder:WaitForChild("DailyRewardsMarker_Disk", 5) :: BasePart?
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
				-- Re-entering the zone clears a previous manual close, so
				-- walking away and back re-shows the panel.
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

return DailyRewardsProximityPanel
