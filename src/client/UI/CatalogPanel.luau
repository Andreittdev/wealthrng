-- Physical read-only "Index" stand, triggered by walking up to the
-- "INDEX" kiosk MapBuilder builds next to the Shop (ProximityPrompt named
-- "CatalogPrompt"). Pure browser over the shared databases (ItemDatabase/
-- AssetDatabase/InvestmentDatabase) -- no remotes, no player-specific
-- state, just "here's everything that exists to roll/buy in the game."
-- Items are grouped by rarity (cheapest first within each) and colored by
-- RarityConfig, matching the same visual language as InventoryPanel/
-- RollPanel's reveal window.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local InvestmentDatabase = require(ReplicatedStorage.Modules.InvestmentDatabase)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local CatalogPanel = {}

local CARD_SIZE = UDim2.new(0, 150, 0, 108)

function CatalogPanel.Create(screenGui: ScreenGui)
	local openCategory = "Items"

	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 460, 0, 440), UDim2.new(0.5, -230, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	local titleLabel = Theme.Label(panel, UDim2.new(1, -120, 0, 32), "Index", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	local closeButton = Theme.Button(panel, UDim2.new(0, 90, 0, 32), UDim2.new(1, -100, 0, 10), "Close")
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	local itemsTabButton = Theme.Button(panel, UDim2.new(0.333, -12, 0, 32), UDim2.new(0, 16, 0, 50), "Items")
	local assetsTabButton = Theme.Button(panel, UDim2.new(0.333, -12, 0, 32), UDim2.new(0.333, 10, 0, 50), "Assets")
	local investTabButton = Theme.Button(panel, UDim2.new(0.333, -12, 0, 32), UDim2.new(0.666, 4, 0, 50), "Invest")

	local content = Instance.new("ScrollingFrame")
	content.Size = UDim2.new(1, -32, 1, -100)
	content.Position = UDim2.new(0, 16, 0, 90)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 6
	content.ScrollBarImageColor3 = Theme.Colors.Accent
	content.Parent = panel

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = CARD_SIZE
	gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = content

	local function clearContent()
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function createCard(order: number, name: string, priceText: string, detailText: string?, accentColor: Color3?): Frame
		local card = Instance.new("Frame")
		card.LayoutOrder = order
		card.BackgroundColor3 = Theme.Colors.Surface
		card.BackgroundTransparency = 0
		card.BorderSizePixel = 0
		card.Parent = content
		Theme.Round(card, UDim.new(0, 10))
		Theme.Stroke(card, accentColor or Color3.fromRGB(110, 110, 122), accentColor and 2 or 1)

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 8)
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingRight = UDim.new(0, 8)
		padding.Parent = card

		local nameLabel = Theme.Label(card, UDim2.new(1, 0, 0, 36), name, true)
		nameLabel.TextWrapped = true

		local priceLabel = Theme.Label(card, UDim2.new(1, 0, 0, 20), priceText)
		priceLabel.Position = UDim2.new(0, 0, 0, 40)
		priceLabel.TextColor3 = Theme.Colors.Accent

		if detailText then
			local detailLabel = Theme.Label(card, UDim2.new(1, 0, 0, 18), detailText)
			detailLabel.Position = UDim2.new(0, 0, 0, 62)
			detailLabel.TextColor3 = Theme.Colors.Success
		end

		return card
	end

	local function renderItems()
		clearContent()
		local order = 0
		for _, rarity in RarityConfig.Order do
			local candidates = ItemDatabase.GetItemsByRarity(rarity)
			table.sort(candidates, function(a, b)
				return a.Value < b.Value
			end)
			for _, item in candidates do
				order += 1
				createCard(
					order,
					item.Name,
					NumberFormat.FormatCash(item.Value),
					"+" .. NumberFormat.FormatCash(item.IncomePerSecond) .. "/s",
					RarityConfig.GetColor(rarity)
				)
			end
		end
	end

	local function renderAssets()
		clearContent()
		local order = 0
		for _, asset in AssetDatabase.GetAllAssets() do
			order += 1
			createCard(order, asset.Name, NumberFormat.FormatCash(asset.Price), "+" .. NumberFormat.FormatCash(asset.IncomePerMinute) .. "/min")
		end
	end

	local function renderInvestments()
		clearContent()
		local order = 0
		for _, investment in InvestmentDatabase.GetAllInvestments() do
			order += 1
			createCard(order, investment.Name, NumberFormat.FormatCash(investment.Price))
		end
	end

	local function highlightTabs()
		local function style(button: TextButton, isActive: boolean)
			button.BackgroundColor3 = isActive and Theme.Colors.Accent or Theme.Colors.Surface
			button.TextColor3 = isActive and Color3.fromRGB(20, 20, 20) or Theme.Colors.TextPrimary
		end
		style(itemsTabButton, openCategory == "Items")
		style(assetsTabButton, openCategory == "Assets")
		style(investTabButton, openCategory == "Investments")
	end

	local function refresh()
		if openCategory == "Items" then
			renderItems()
		elseif openCategory == "Assets" then
			renderAssets()
		else
			renderInvestments()
		end
	end

	local function switchTab(category: string)
		openCategory = category
		highlightTabs()
		refresh()
	end

	itemsTabButton.Activated:Connect(function()
		switchTab("Items")
	end)
	assetsTabButton.Activated:Connect(function()
		switchTab("Assets")
	end)
	investTabButton.Activated:Connect(function()
		switchTab("Investments")
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player ~= Players.LocalPlayer or prompt.Name ~= "CatalogPrompt" then
			return
		end

		panel.Visible = true
		highlightTabs()
		refresh()
	end)

	local handle = {}
	handle.Frame = panel
	return handle
end

return CatalogPanel
