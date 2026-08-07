-- Profile panel: shows the Title/VIP/Cash/Net Worth/Income card that used
-- to be an always-visible top-left StatsPanel -- moved here so that corner
-- stays free and the info is opt-in via the sidebar instead. Same card
-- layout/logic StatsPanel used to have, just nested inside a modal shell.
-- Also shows currently-active Potions (from the Potions stand) so their
-- buff status stays visible without needing that stand open.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PotionDatabase = require(ReplicatedStorage.Modules.PotionDatabase)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local BattleRankConfig = require(ReplicatedStorage.Modules.BattleRankConfig)
local Theme = require(script.Parent.Theme)

local ProfilePanel = {}

export type StatsPayload = {
	Cash: number,
	NetWorth: number,
	Title: string,
	IsVIP: boolean,
	BattleRankPoints: number,
	ItemsIncomePerSecond: number,
	AssetsIncomePerMinute: number,
}

local function formatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function ProfilePanel.Create(screenGui: ScreenGui)
	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 320, 0, 372), UDim2.new(0.5, -160, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	local titleLabel = Theme.Label(panel, UDim2.new(1, -120, 0, 32), "Profile", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	local closeButton = Theme.Button(panel, UDim2.new(0, 90, 0, 32), UDim2.new(1, -100, 0, 10), "Close")
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	-- Scrolls instead of overflowing -- ProfilePanel's card + potions list
	-- used to be absolutely positioned assuming the panel was always a
	-- fixed 372px tall. Theme.ResponsivePanel now legitimately shrinks
	-- that height on short (landscape phone) screens, which pushed the
	-- Active Potions section past the visible bottom with no way to reach
	-- it. Same ScrollingFrame + UIListLayout pattern ShopPanel already uses.
	local content = Instance.new("ScrollingFrame")
	content.Size = UDim2.new(1, -32, 1, -66)
	content.Position = UDim2.new(0, 16, 0, 56)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 6
	content.ScrollBarImageColor3 = Theme.Colors.Accent
	content.Parent = panel

	local outerLayout = Instance.new("UIListLayout")
	outerLayout.Padding = UDim.new(0, 12)
	outerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	outerLayout.Parent = content

	local card = Instance.new("Frame")
	card.LayoutOrder = 1
	card.Size = UDim2.new(1, 0, 0, 202)
	card.BackgroundColor3 = Theme.Colors.Surface
	card.BorderSizePixel = 0
	card.Parent = content
	Theme.Round(card, UDim.new(0, 10))

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = card

	local cardTitleRow = Instance.new("Frame")
	cardTitleRow.Size = UDim2.new(1, 0, 0, 28)
	cardTitleRow.BackgroundTransparency = 1
	cardTitleRow.Parent = card

	local cardTitleLabel = Theme.Label(cardTitleRow, UDim2.new(1, -60, 1, 0), "Beginner", true)

	local vipPill = Instance.new("TextLabel")
	vipPill.Size = UDim2.new(0, 50, 0, 22)
	vipPill.AnchorPoint = Vector2.new(1, 0.5)
	vipPill.Position = UDim2.new(1, 0, 0.5, 0)
	vipPill.BackgroundColor3 = Theme.Colors.Accent
	vipPill.TextColor3 = Color3.fromRGB(20, 20, 20)
	vipPill.Font = Theme.Fonts.Header
	vipPill.TextScaled = true
	vipPill.Text = "VIP"
	vipPill.Visible = false
	vipPill.Parent = cardTitleRow
	Theme.Round(vipPill, UDim.new(0, 6))
	Theme.Stroke(vipPill, Color3.fromRGB(255, 245, 210), 1)

	local cashLabel = Theme.Label(card, UDim2.new(1, 0, 0, 26), "Cash: $0")
	cashLabel.TextColor3 = Theme.Colors.Success

	local netWorthLabel = Theme.Label(card, UDim2.new(1, 0, 0, 26), "Net Worth: $0")
	netWorthLabel.TextColor3 = Theme.Colors.Accent

	local itemsIncomeLabel = Theme.Label(card, UDim2.new(1, 0, 0, 22), "Items: $0/s")
	itemsIncomeLabel.TextColor3 = Theme.Colors.TextSecondary

	local assetsIncomeLabel = Theme.Label(card, UDim2.new(1, 0, 0, 22), "Estates: $0/min")
	assetsIncomeLabel.TextColor3 = Theme.Colors.TextSecondary

	local rankLabel = Theme.Label(card, UDim2.new(1, 0, 0, 22), "Rank: Bronze (0 RP)")
	rankLabel.TextColor3 = BattleRankConfig.Tiers[1].Color

	local potionsHeader = Theme.Label(content, UDim2.new(1, 0, 0, 22), "Active Potions")
	potionsHeader.LayoutOrder = 2
	potionsHeader.TextColor3 = Theme.Colors.Accent

	local potionsList = Instance.new("Frame")
	potionsList.LayoutOrder = 3
	potionsList.Size = UDim2.new(1, 0, 0, 0)
	potionsList.AutomaticSize = Enum.AutomaticSize.Y
	potionsList.BackgroundTransparency = 1
	potionsList.Parent = content

	local potionsLayout = Instance.new("UIListLayout")
	potionsLayout.Padding = UDim.new(0, 4)
	potionsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	potionsLayout.Parent = potionsList

	local activePotions: { [string]: number } = {}

	local function refreshPotions()
		local now = os.time()
		for _, child in potionsList:GetChildren() do
			if child:IsA("TextLabel") then
				child:Destroy()
			end
		end

		local anyActive = false
		for potionId, expiresAt in activePotions do
			if expiresAt > now then
				anyActive = true
				local potion = PotionDatabase.GetPotion(potionId)
				local label = Theme.Label(potionsList, UDim2.new(1, 0, 0, 20), string.format("%s - %s", potion and potion.Name or potionId, formatDuration(expiresAt - now)))
				label.TextColor3 = Theme.Colors.Success
			end
		end

		if not anyActive then
			local label = Theme.Label(potionsList, UDim2.new(1, 0, 0, 20), "None active")
			label.TextColor3 = Theme.Colors.TextSecondary
		end
	end

	refreshPotions()

	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Visible then
				refreshPotions()
			end
		end
	end)

	local handle = {}
	handle.Frame = panel

	function handle.Toggle()
		panel.Visible = not panel.Visible
	end

	function handle.Update(stats: StatsPayload)
		cardTitleLabel.Text = stats.Title
		vipPill.Visible = stats.IsVIP
		cashLabel.Text = "Cash: " .. NumberFormat.FormatCash(stats.Cash)
		netWorthLabel.Text = "Net Worth: " .. NumberFormat.FormatCash(stats.NetWorth)
		itemsIncomeLabel.Text = "Items: " .. NumberFormat.FormatCash(stats.ItemsIncomePerSecond) .. "/s"
		assetsIncomeLabel.Text = "Estates: " .. NumberFormat.FormatCash(stats.AssetsIncomePerMinute) .. "/min"

		local tier = BattleRankConfig.GetTier(stats.BattleRankPoints, stats.NetWorth)
		rankLabel.Text = string.format("Rank: %s (%d RP)", tier.Name, stats.BattleRankPoints)
		rankLabel.TextColor3 = tier.Color
	end

	function handle.UpdatePotions(potions: { [string]: number })
		activePotions = potions
		refreshPotions()
	end

	return handle
end

return ProfilePanel
