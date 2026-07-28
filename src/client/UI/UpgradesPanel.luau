-- Sidebar-triggered panel for the 3 permanent Cash-bought upgrade tracks
-- (Roll Speed, Luck, Potion Boost Time) -- see UpgradeConfig.luau for the
-- cost/effect curves. Same scrollable-list shape as SettingsPanel (a
-- ScrollingFrame + UIListLayout, not fixed Y offsets) so it never depends
-- on guessing a panel height that fits every state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local UpgradesPanel = {}

-- Per-track flavor text + a function describing the CURRENT effect at a
-- given level, so the card shows something concrete ("-9% cooldown") not
-- just an abstract level number.
local TRACK_INFO: { [string]: { Description: string, EffectText: (number) -> string } } = {
	RollSpeed = {
		Description = "Reduces roll cooldown",
		EffectText = function(level: number): string
			return string.format("-%d%% cooldown", math.floor((1 - UpgradeConfig.GetCooldownMultiplier(level)) * 100 + 0.5))
		end,
	},
	Luck = {
		Description = "Boosts odds for Rare and above",
		EffectText = function(level: number): string
			local luxuryMult = UpgradeConfig.GetLuckMultiplier(level, "Luxury")
			return string.format("+%d%% Luxury odds", math.floor((luxuryMult - 1) * 100 + 0.5))
		end,
	},
	PotionBoost = {
		Description = "Extends potion duration",
		EffectText = function(level: number): string
			return string.format("+%d%% duration", math.floor((UpgradeConfig.GetPotionDurationMultiplier(level) - 1) * 100 + 0.5))
		end,
	},
}

function UpgradesPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local buyUpgrade = remotes:WaitForChild("BuyUpgrade")
	local upgradesUpdated = remotes:WaitForChild("UpgradesUpdated")

	local currentLevels: { [string]: number } = {}

	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 380, 0, 360), UDim2.new(0.5, -190, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	local titleLabel = Theme.Label(panel, UDim2.new(1, -120, 0, 32), "Upgrades", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	local closeButton = Theme.Button(panel, UDim2.new(0, 90, 0, 32), UDim2.new(1, -100, 0, 10), "Close")
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

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

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 10)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = content

	local buyButtons: { [string]: TextButton } = {}
	local levelLabels: { [string]: TextLabel } = {}
	local effectLabels: { [string]: TextLabel } = {}

	local function refreshCard(trackId: string)
		local track = UpgradeConfig.Tracks[trackId]
		local info = TRACK_INFO[trackId]
		local level = currentLevels[trackId] or 0

		levelLabels[trackId].Text = string.format("Level %d/%d", level, track.MaxLevel)
		effectLabels[trackId].Text = info.EffectText(level)

		local button = buyButtons[trackId]
		local cost = UpgradeConfig.GetCost(trackId, level)
		if cost then
			button.Text = "Buy - " .. NumberFormat.FormatCash(cost)
			button.AutoButtonColor = true
		else
			button.Text = "MAXED"
			button.AutoButtonColor = false
		end
	end

	for order, trackId in UpgradeConfig.Order do
		local track = UpgradeConfig.Tracks[trackId]
		local info = TRACK_INFO[trackId]

		local card = Instance.new("Frame")
		card.LayoutOrder = order
		card.Size = UDim2.new(1, 0, 0, 96)
		card.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
		card.BackgroundTransparency = 0
		card.BorderSizePixel = 0
		card.Parent = content
		Theme.Round(card, UDim.new(0, 8))
		local stroke = Theme.Stroke(card, Color3.fromRGB(90, 90, 98), 1.5)
		stroke.Transparency = 0

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 8)
		padding.PaddingLeft = UDim.new(0, 12)
		padding.PaddingRight = UDim.new(0, 12)
		padding.Parent = card

		local nameLabel = Theme.Label(card, UDim2.new(1, -110, 0, 22), track.Name, true)

		local levelLabel = Theme.Label(card, UDim2.new(0, 100, 0, 22), "")
		levelLabel.Position = UDim2.new(1, -100, 0, 0)
		levelLabel.TextXAlignment = Enum.TextXAlignment.Right
		levelLabel.TextColor3 = Theme.Colors.TextSecondary
		levelLabels[trackId] = levelLabel

		local descriptionLabel = Theme.Label(card, UDim2.new(1, 0, 0, 18), info.Description)
		descriptionLabel.Position = UDim2.new(0, 0, 0, 24)
		descriptionLabel.TextColor3 = Theme.Colors.TextSecondary

		local effectLabel = Theme.Label(card, UDim2.new(1, 0, 0, 20), "")
		effectLabel.Position = UDim2.new(0, 0, 0, 44)
		effectLabel.TextColor3 = Theme.Colors.Success
		effectLabels[trackId] = effectLabel

		local buyButton = Theme.Button(card, UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 1, -32), "Buy", true)
		buyButton.Activated:Connect(function()
			buyUpgrade:FireServer(trackId)
		end)
		buyButtons[trackId] = buyButton

		refreshCard(trackId)
	end

	upgradesUpdated.OnClientEvent:Connect(function(map: { [string]: number })
		currentLevels = map
		for _, trackId in UpgradeConfig.Order do
			refreshCard(trackId)
		end
	end)

	local handle = {}
	handle.Frame = panel

	function handle.Toggle()
		panel.Visible = not panel.Visible
	end

	return handle
end

return UpgradesPanel
