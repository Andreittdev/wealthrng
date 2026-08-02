-- Sidebar-triggered "Shop" panel: two sections, GAMEPASSES (one-time
-- permanent perks) and CASH PACKS (repeatable Developer Product purchases,
-- straight Cash, no perk). Both are a grid of square cards (image + name +
-- price pill, no description text -- per reference screenshot from another
-- game's shop UI), 2 per row, so adding another entry later is just another
-- create*Card call, not a layout restructure. Not to be confused with
-- AssetShopPanel.luau, the physical proximity-triggered Assets/Invest
-- trading panel. The plaza's yellow "VIP" floor marker (MapBuilder's
-- buildVIPMarker) shows its own separate quick-glance popup
-- (VIPProximityPanel.luau) instead of opening this panel.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local AutoRollConfig = require(ReplicatedStorage.Modules.AutoRollConfig)
local LuckPassConfig = require(ReplicatedStorage.Modules.LuckPassConfig)
local UltraLuckPassConfig = require(ReplicatedStorage.Modules.UltraLuckPassConfig)
local FastRollConfig = require(ReplicatedStorage.Modules.FastRollConfig)
local DoubleCashConfig = require(ReplicatedStorage.Modules.DoubleCashConfig)
local CashPackConfig = require(ReplicatedStorage.Modules.CashPackConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local ShopPanel = {}

local CARD_STROKE_COLOR = Color3.fromRGB(15, 15, 18)
local CASH_ICON = "rbxassetid://72463281853990"

-- Shared by both card kinds -- builds the square frame + icon + name, and
-- returns the empty price-pill button for the caller to finish wiring
-- (gamepass cards need an Owned state, cash pack cards don't, so gluing the
-- Activated handler on here would mean threading that difference through
-- anyway).
local function createCardBase(parent: Instance, layoutOrder: number, bgColor: Color3, imageId: string, name: string, nameMaxTextSize: number?): TextButton
	local card = Instance.new("Frame")
	card.LayoutOrder = layoutOrder
	card.BackgroundColor3 = bgColor
	card.BorderSizePixel = 0
	card.Parent = parent
	Theme.Round(card, UDim.new(0, 16))
	Theme.Stroke(card, CARD_STROKE_COLOR, 4)

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(1, -20, 0, 78)
	icon.Position = UDim2.new(0, 10, 0, 8)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = imageId
	icon.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -12, 0, 20)
	nameLabel.Position = UDim2.new(0, 6, 0, 90)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Theme.Fonts.Header
	nameLabel.Text = name
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextScaled = true
	nameLabel.TextStrokeTransparency = 0
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.Parent = card
	local nameSizeConstraint = Instance.new("UITextSizeConstraint")
	nameSizeConstraint.MaxTextSize = nameMaxTextSize or 22
	nameSizeConstraint.Parent = nameLabel

	local priceButton = Instance.new("TextButton")
	priceButton.Size = UDim2.new(1, -20, 0, 26)
	priceButton.Position = UDim2.new(0, 10, 0, 114)
	priceButton.BackgroundColor3 = Theme.Colors.Success
	priceButton.BorderSizePixel = 0
	priceButton.AutoButtonColor = true
	priceButton.Font = Theme.Fonts.Header
	priceButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	priceButton.TextScaled = true
	priceButton.Parent = card
	Theme.Round(priceButton, UDim.new(1, 0))
	Theme.Stroke(priceButton, CARD_STROKE_COLOR, 2)
	local priceSizeConstraint = Instance.new("UITextSizeConstraint")
	priceSizeConstraint.MaxTextSize = 20
	priceSizeConstraint.Parent = priceButton

	return priceButton
end

-- Returns a `refresh(owned)` closure so handle.Update can drive it from the
-- matching StatsUpdated field without each card needing its own bespoke
-- refresh function.
local function createGamepassCard(parent: Instance, layoutOrder: number, bgColor: Color3, imageId: string, name: string, priceText: string, gamepassId: number): (boolean) -> ()
	local priceButton = createCardBase(parent, layoutOrder, bgColor, imageId, name)
	priceButton.Text = priceText

	local owned = false
	local function refresh(newOwned: boolean)
		owned = newOwned
		priceButton.Text = owned and "OWNED" or priceText
		priceButton.Active = not owned
		priceButton.AutoButtonColor = not owned
	end
	refresh(false)

	priceButton.Activated:Connect(function()
		if owned then
			return
		end
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, gamepassId)
	end)

	return refresh
end

-- No Owned state -- Developer Products are meant to be bought again and
-- again, so the price pill always stays active.
local function createCashPackCard(parent: Instance, layoutOrder: number, bgColor: Color3, cashAmount: number, priceText: string, productId: number)
	local priceButton = createCardBase(parent, layoutOrder, bgColor, CASH_ICON, NumberFormat.FormatCash(cashAmount), 30)
	priceButton.Text = priceText

	priceButton.Activated:Connect(function()
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
	end)
end

-- A full-width section: a "TITLE" label followed by its own 2-column card
-- grid, both stacked into `parent`'s outer UIListLayout via `order`/`order+1`.
-- Returns the grid Frame so the caller can populate it with cards.
local function createSection(parent: Instance, order: number, title: string): Frame
	local label = Theme.Label(parent, UDim2.new(1, 0, 0, 26), title, true)
	label.LayoutOrder = order
	label.TextXAlignment = Enum.TextXAlignment.Center

	local grid = Instance.new("Frame")
	grid.LayoutOrder = order + 1
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.BackgroundTransparency = 1
	grid.Parent = parent

	-- 2 columns -- CellSize halves are offset by half the gap so
	-- 2*(0.5W - 8) + 16 == W exactly, same trick InventoryPanel uses.
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.5, -8, 0, 150)
	gridLayout.CellPadding = UDim2.new(0, 16, 0, 16)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid

	return grid
end

function ShopPanel.Create(screenGui: ScreenGui)
	-- Anchored near the top (not dead-center) so it doesn't collide with
	-- RollPanel's bottom-anchored reveal window/button on shorter viewports.
	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 460, 0, 600), UDim2.new(0.5, -230, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	local titleLabel = Theme.Label(panel, UDim2.new(1, -120, 0, 32), "Store", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	local closeButton = Theme.Button(panel, UDim2.new(0, 90, 0, 32), UDim2.new(1, -100, 0, 10), "Close")
	closeButton.BackgroundColor3 = Theme.Colors.Danger
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.TextScaled = false
	closeButton.TextSize = 16
	local closeButtonStroke = closeButton:FindFirstChildOfClass("UIStroke")
	if closeButtonStroke then
		closeButtonStroke.Color = Color3.fromRGB(255, 140, 140)
	end
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

	local outerLayout = Instance.new("UIListLayout")
	outerLayout.Padding = UDim.new(0, 16)
	outerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	outerLayout.Parent = content

	local gamepassesGrid = createSection(content, 1, "GAMEPASSES")

	local refreshVIP =
		createGamepassCard(gamepassesGrid, 1, Color3.fromRGB(255, 200, 80), "rbxassetid://73540272717608", "VIP", "Buy", VIPConfig.GamepassId)
	local refreshAutoRoll = createGamepassCard(
		gamepassesGrid,
		2,
		Color3.fromRGB(90, 170, 255),
		"rbxassetid://115324216729484",
		"Auto Roll",
		"Buy",
		AutoRollConfig.GamepassId
	)
	local refreshLuckPass = createGamepassCard(
		gamepassesGrid,
		3,
		Color3.fromRGB(110, 220, 130),
		"rbxassetid://72576762798024",
		"Luck Pass",
		"49 R$",
		LuckPassConfig.GamepassId
	)
	local refreshUltraLuckPass = createGamepassCard(
		gamepassesGrid,
		4,
		Color3.fromRGB(180, 110, 255),
		"rbxassetid://75300488764415",
		"Ultra Luck Pass",
		"249 R$",
		UltraLuckPassConfig.GamepassId
	)
	local refreshFastRoll = createGamepassCard(
		gamepassesGrid,
		5,
		Color3.fromRGB(255, 110, 90),
		"rbxassetid://120595892822392",
		"Fast Roll",
		"149 R$",
		FastRollConfig.GamepassId
	)
	local refreshDoubleCash = createGamepassCard(
		gamepassesGrid,
		6,
		Color3.fromRGB(255, 205, 80),
		"rbxassetid://110513806383474",
		"Double Cash",
		"299 R$",
		DoubleCashConfig.GamepassId
	)

	local cashPacksGrid = createSection(content, 3, "CASH")
	for index, pack in CashPackConfig.Packs do
		createCashPackCard(cashPacksGrid, index, Color3.fromRGB(120, 220, 150), pack.CashAmount, pack.RobuxPrice .. " R$", pack.ProductId)
	end

	local handle = {}
	handle.Frame = panel

	function handle.Toggle()
		panel.Visible = not panel.Visible
	end

	function handle.Update(stats: {
		IsVIP: boolean,
		OwnsAutoRoll: boolean,
		OwnsLuckPass: boolean,
		OwnsUltraLuckPass: boolean,
		OwnsFastRoll: boolean,
		OwnsDoubleCash: boolean,
	})
		refreshVIP(stats.IsVIP)
		refreshAutoRoll(stats.OwnsAutoRoll)
		refreshLuckPass(stats.OwnsLuckPass)
		refreshUltraLuckPass(stats.OwnsUltraLuckPass)
		refreshFastRoll(stats.OwnsFastRoll)
		refreshDoubleCash(stats.OwnsDoubleCash)
	end

	return handle
end

return ShopPanel
