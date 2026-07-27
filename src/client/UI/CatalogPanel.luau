-- Physical read-only "Index" stand, triggered by walking up to the
-- "INDEX" kiosk MapBuilder builds next to the Shop (ProximityPrompt named
-- "CatalogPrompt"). Roll items only -- Assets/Investments have their own
-- physical shop with full pricing already, this is purely the roll dex.
--
-- Dex/collection style, like the big RNG games -- each tile shows ONLY
-- the item's shape (image), silhouetted black if the player has never
-- rolled it, full color once they have. That needs player state (the
-- current inventory), so this panel listens to InventoryUpdated even
-- though it fires no remotes of its own.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local Theme = require(script.Parent.Theme)

local CatalogPanel = {}

local ITEM_CELL_SIZE = UDim2.new(0, 96, 0, 96)

function CatalogPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local inventoryUpdated = remotes:WaitForChild("InventoryUpdated")

	local ownedItemIds: { [string]: boolean } = {}

	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 460, 0, 440), UDim2.new(0.5, -230, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	local titleLabel = Theme.Label(panel, UDim2.new(1, -120, 0, 32), "Index", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	local closeButton = Theme.Button(panel, UDim2.new(0, 90, 0, 32), UDim2.new(1, -100, 0, 10), "Close")
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	local content = Instance.new("ScrollingFrame")
	content.Size = UDim2.new(1, -32, 1, -96)
	content.Position = UDim2.new(0, 16, 0, 56)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 6
	content.ScrollBarImageColor3 = Theme.Colors.Accent
	content.Parent = panel

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = ITEM_CELL_SIZE
	gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = content

	-- Pinned below the scrolling grid, not inside it, so it's always
	-- visible regardless of scroll position.
	local footerLabel = Theme.Label(panel, UDim2.new(1, -32, 0, 24), "INDEX REWARDS SOON!", true)
	footerLabel.Position = UDim2.new(0, 16, 1, -34)
	footerLabel.TextXAlignment = Enum.TextXAlignment.Center

	local function clearContent()
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	-- Dex-style tile -- just the item's shape, nothing else. Silhouetted
	-- black (ImageColor3 multiplies the image, so black = solid
	-- silhouette of whatever shape/alpha the icon has) until the player
	-- has actually rolled it at least once, then full color + a
	-- rarity-colored border to mark it as found.
	local function createItemCard(order: number, item, isUnlocked: boolean): Frame
		local card = Instance.new("Frame")
		card.LayoutOrder = order
		card.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
		card.BackgroundTransparency = 0
		card.BorderSizePixel = 0
		card.Parent = content
		Theme.Round(card, UDim.new(0, 10))

		local rarityColor = RarityConfig.GetColor(item.Rarity)
		local borderColor = isUnlocked and rarityColor or Color3.fromRGB(60, 60, 66)
		local stroke = Theme.Stroke(card, borderColor, isUnlocked and 2.5 or 1.5)
		stroke.Transparency = isUnlocked and 0 or 0.3

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(1, -20, 1, -20)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = item.Image or ""
		icon.ImageColor3 = isUnlocked and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
		icon.Parent = card

		return card
	end

	local function render()
		clearContent()
		local order = 0
		for _, rarity in RarityConfig.Order do
			local candidates = ItemDatabase.GetItemsByRarity(rarity)
			table.sort(candidates, function(a, b)
				return a.Value < b.Value
			end)
			for _, item in candidates do
				order += 1
				createItemCard(order, item, ownedItemIds[item.Id] == true)
			end
		end
	end

	inventoryUpdated.OnClientEvent:Connect(function(inventory: { { Uid: number, ItemId: string } })
		ownedItemIds = {}
		for _, entry in inventory do
			ownedItemIds[entry.ItemId] = true
		end
		if panel.Visible then
			render()
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player ~= Players.LocalPlayer or prompt.Name ~= "CatalogPrompt" then
			return
		end

		panel.Visible = true
		render()
	end)

	local handle = {}
	handle.Frame = panel
	return handle
end

return CatalogPanel
