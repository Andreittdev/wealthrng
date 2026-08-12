-- Sidebar-triggered "Shop" panel: GAMEPASSES (one-time permanent perks),
-- CASH PACKS (repeatable Developer Product purchases, straight Cash, no
-- perk), and EXCLUSIVE CRATE (repeatable Developer Product purchases,
-- granting Crate-exclusive items -- CrateConfig.luau/CrateManager.luau).
-- The first two are a grid of square cards (image + name + price pill, no
-- description text -- per reference screenshot from another game's shop
-- UI), 2 per row. Crate is inline here too (not its own popup, per explicit
-- request) -- an odds row + a 2x2 grid of quantity/price cards, same "just
-- part of the Shop scroll" treatment as everything else on this panel. Not
-- to be confused with AssetShopPanel.luau, the physical proximity-triggered
-- Assets/Invest trading panel. The plaza's yellow "VIP" floor marker
-- (MapBuilder's buildVIPMarker) shows its own separate quick-glance popup
-- (VIPProximityPanel.luau) instead of opening this panel.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local AutoRollConfig = require(ReplicatedStorage.Modules.AutoRollConfig)
local LuckPassConfig = require(ReplicatedStorage.Modules.LuckPassConfig)
local UltraLuckPassConfig = require(ReplicatedStorage.Modules.UltraLuckPassConfig)
local FastRollConfig = require(ReplicatedStorage.Modules.FastRollConfig)
local DoubleCashConfig = require(ReplicatedStorage.Modules.DoubleCashConfig)
local CashPackConfig = require(ReplicatedStorage.Modules.CashPackConfig)
local CrateConfig = require(ReplicatedStorage.Modules.CrateConfig)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
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
-- Cash cards and Gamepass cards each get their OWN tiled texture
-- background (different asset per kind, per explicit request) instead of
-- each's own flat bgColor.
local CASH_CARD_TEXTURE_IMAGE = "rbxassetid://91010461833309"
local GAMEPASS_CARD_TEXTURE_IMAGE = "rbxassetid://111242948846202"

local function createCardBase(
	parent: Instance,
	layoutOrder: number,
	bgColor: Color3,
	imageId: string,
	name: string,
	nameMaxTextSize: number?,
	textureImage: string?
): TextButton
	local card = Instance.new("Frame")
	card.LayoutOrder = layoutOrder
	card.BorderSizePixel = 0
	card.Parent = parent
	Theme.Round(card, UDim.new(0, 16))
	Theme.Stroke(card, CARD_STROKE_COLOR, 4)

	if textureImage then
		card.BackgroundTransparency = 1
		card.ClipsDescendants = true

		local cardTexture = Instance.new("ImageLabel")
		cardTexture.Size = UDim2.new(1, 0, 1, 0)
		cardTexture.BackgroundTransparency = 1
		cardTexture.Image = textureImage
		cardTexture.ScaleType = Enum.ScaleType.Tile
		cardTexture.TileSize = UDim2.new(0, 48, 0, 48)
		cardTexture.ZIndex = 1
		cardTexture.Parent = card
		-- ClipsDescendants on `card` only clips to its plain RECTANGLE, not
		-- its UICorner-rounded shape (UICorner never affects clipping,
		-- only its own object's rendered corners) -- the tiled image was
		-- poking out past the rounded corners because of that. Rounding
		-- the image itself is what actually clips it correctly.
		Theme.Round(cardTexture, UDim.new(0, 16))
	else
		card.BackgroundColor3 = bgColor
	end

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

	-- Buy/OWNED pill -- always gets the tiled texture now (both Gamepass and
	-- Cash cards), regardless of whether the card body itself has it. The
	-- texture is a SEPARATE sibling Frame sitting exactly under the button,
	-- not a child of it -- a child ImageLabel would render on top of the
	-- button's own .Text (children always paint over their parent's own
	-- text, regardless of ZIndex, which only orders siblings against each
	-- other), which would have hidden the price text completely.
	local PRICE_BUTTON_SIZE = UDim2.new(1, -20, 0, 26)
	local PRICE_BUTTON_POSITION = UDim2.new(0, 10, 0, 114)

	local priceButtonTexture = Instance.new("Frame")
	priceButtonTexture.Size = PRICE_BUTTON_SIZE
	priceButtonTexture.Position = PRICE_BUTTON_POSITION
	priceButtonTexture.BackgroundTransparency = 1
	priceButtonTexture.ClipsDescendants = true
	priceButtonTexture.Parent = card
	-- Modest square-ish corners instead of a full pill (UDim.new(1,0)) --
	-- the full-round shape was letting the tiled texture's square tiles
	-- poke out slightly past the rounded edge at the corners.
	Theme.Round(priceButtonTexture, UDim.new(0, 8))

	-- Every Buy/OWNED button uses the Cash texture specifically, per
	-- explicit request -- regardless of which texture the card body itself
	-- has (Gamepass or Cash).
	local priceButtonTextureImage = Instance.new("ImageLabel")
	priceButtonTextureImage.Size = UDim2.new(1, 0, 1, 0)
	priceButtonTextureImage.BackgroundTransparency = 1
	priceButtonTextureImage.Image = CASH_CARD_TEXTURE_IMAGE
	priceButtonTextureImage.ScaleType = Enum.ScaleType.Tile
	priceButtonTextureImage.TileSize = UDim2.new(0, 32, 0, 32)
	priceButtonTextureImage.Parent = priceButtonTexture
	-- Same reasoning as cardTexture above -- ClipsDescendants alone doesn't
	-- respect the wrapper's rounded corners, the image needs its own match
	-- ing UICorner to actually clip to that shape.
	Theme.Round(priceButtonTextureImage, UDim.new(0, 8))

	local priceButton = Instance.new("TextButton")
	priceButton.Size = PRICE_BUTTON_SIZE
	priceButton.Position = PRICE_BUTTON_POSITION
	priceButton.BackgroundTransparency = 1
	priceButton.BorderSizePixel = 0
	priceButton.AutoButtonColor = true
	priceButton.Font = Theme.Fonts.Header
	priceButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	priceButton.TextScaled = true
	priceButton.TextStrokeTransparency = 0
	priceButton.TextStrokeColor3 = Color3.new(0, 0, 0)
	priceButton.Parent = card
	Theme.Stroke(priceButtonTexture, CARD_STROKE_COLOR, 2)
	local priceSizeConstraint = Instance.new("UITextSizeConstraint")
	priceSizeConstraint.MaxTextSize = 20
	priceSizeConstraint.Parent = priceButton

	return priceButton
end

-- Returns a `refresh(owned)` closure so handle.Update can drive it from the
-- matching StatsUpdated field without each card needing its own bespoke
-- refresh function.
local function createGamepassCard(parent: Instance, layoutOrder: number, bgColor: Color3, imageId: string, name: string, priceText: string, gamepassId: number): (boolean) -> ()
	local priceButton = createCardBase(parent, layoutOrder, bgColor, imageId, name, nil, GAMEPASS_CARD_TEXTURE_IMAGE)
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
	local priceButton = createCardBase(parent, layoutOrder, bgColor, CASH_ICON, NumberFormat.FormatCash(cashAmount), 30, CASH_CARD_TEXTURE_IMAGE)
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
	label.TextColor3 = Color3.new(1, 1, 1)

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

-- ===== Exclusive Crate: inline section, not its own popup =====
local function createCrateSection(parent: Instance, order: number, screenGui: ScreenGui, remotes: Folder)
	local titleLabel = Theme.Label(parent, UDim2.new(1, 0, 0, 26), "Exclusives Crate", true)
	titleLabel.LayoutOrder = order
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.TextColor3 = Color3.new(1, 1, 1)

	-- ===== ONE box, ONE shared background, for EVERYTHING below the title
	-- (crate image, the 4 Estate odds, AND the 4 buy buttons) -- per
	-- explicit correction: no separate boxes, no divider lines anywhere,
	-- just one shared background the whole section sits on. =====
	-- Premium SILVER gradient (not gold/dark) -- a metallic light-to-mid
	-- gray sheen with a bright silver stroke.
	local crateBox = Instance.new("Frame")
	crateBox.LayoutOrder = order + 1
	crateBox.Size = UDim2.new(1, 0, 0, 254)
	crateBox.BackgroundTransparency = 1
	crateBox.BorderSizePixel = 0
	crateBox.ClipsDescendants = true
	crateBox.Parent = parent
	Theme.Round(crateBox, UDim.new(0, 16))
	local crateBoxStroke = Theme.Stroke(crateBox, Color3.fromRGB(240, 242, 248), 3)
	crateBoxStroke.Transparency = 0

	-- Real tiled texture (the requested asset) instead of the flat/gradient
	-- fill -- ClipsDescendants on crateBox above keeps the tiled repeats
	-- from spilling past its own rounded corners. Sits behind mainRow/
	-- buttonsRow (added after it below), same "earlier sibling paints
	-- first" ordering already used elsewhere in this file.
	local crateBoxTexture = Instance.new("ImageLabel")
	crateBoxTexture.Size = UDim2.new(1, 0, 1, 0)
	crateBoxTexture.BackgroundTransparency = 1
	crateBoxTexture.Image = "rbxassetid://121876689166328"
	crateBoxTexture.ScaleType = Enum.ScaleType.Tile
	crateBoxTexture.TileSize = UDim2.new(0, 64, 0, 64)
	crateBoxTexture.ZIndex = 1
	crateBoxTexture.Parent = crateBox
	-- Same fix as the Store cards' textures -- ClipsDescendants alone
	-- doesn't respect a UICorner-rounded parent, the image needs its own
	-- matching UICorner to actually clip to the rounded shape.
	Theme.Round(crateBoxTexture, UDim.new(0, 16))

	-- Inner darker stroke, inset a few px from the outer bright one -- the
	-- 2-stroke gap is what reads as a beveled/embossed metal panel edge
	-- instead of a single flat outline, same "carved frame" language as the
	-- reference screenshot's wood panel.
	local crateBoxInnerFrame = Instance.new("Frame")
	crateBoxInnerFrame.Size = UDim2.new(1, -10, 1, -10)
	crateBoxInnerFrame.Position = UDim2.new(0, 5, 0, 5)
	crateBoxInnerFrame.BackgroundTransparency = 1
	crateBoxInnerFrame.Parent = crateBox
	Theme.Round(crateBoxInnerFrame, UDim.new(0, 12))
	local crateBoxInnerStroke = Theme.Stroke(crateBoxInnerFrame, Color3.fromRGB(120, 124, 134), 2)
	crateBoxInnerStroke.Transparency = 0.2

	local mainRow = Instance.new("Frame")
	mainRow.Position = UDim2.new(0, 12, 0, 12)
	mainRow.Size = UDim2.new(1, -24, 0, 132)
	mainRow.BackgroundTransparency = 1
	mainRow.Parent = crateBox

	local crateEmoji = Instance.new("ImageLabel")
	crateEmoji.Size = UDim2.new(0, 128, 0, 128)
	crateEmoji.BackgroundTransparency = 1
	crateEmoji.Image = "rbxassetid://79469514104514"
	crateEmoji.Parent = mainRow

	local itemsGrid = Instance.new("Frame")
	itemsGrid.Size = UDim2.new(1, -138, 1, -20)
	itemsGrid.Position = UDim2.new(0, 138, 0, 20)
	itemsGrid.BackgroundTransparency = 1
	itemsGrid.Parent = mainRow

	-- Single row, all 4 Estates side by side -- not a 2x2 grid anymore.
	local itemsLayout = Instance.new("UIGridLayout")
	itemsLayout.CellSize = UDim2.new(0.25, 0, 1, 0)
	itemsLayout.CellPadding = UDim2.new(0, 0, 0, 0)
	itemsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	itemsLayout.Parent = itemsGrid

	for chipOrder, entry in CrateConfig.GetEstateOdds() do
		local chip = Instance.new("Frame")
		chip.LayoutOrder = chipOrder
		chip.BackgroundTransparency = 1
		chip.BorderSizePixel = 0
		chip.Parent = itemsGrid

		local itemInfo = ItemDatabase.GetItem(entry.ItemId)

		if entry.ItemId == "CrateCastle" then
			local bestLabel = Instance.new("TextLabel")
			bestLabel.Size = UDim2.new(1.4, 0, 0, 16)
			bestLabel.Position = UDim2.new(1, 0, 0, -26)
			bestLabel.AnchorPoint = Vector2.new(1, 0)
			bestLabel.BackgroundTransparency = 1
			bestLabel.Font = Theme.Fonts.Header
			bestLabel.TextScaled = true
			bestLabel.Text = "Best in the game!"
			bestLabel.TextColor3 = Color3.fromRGB(255, 230, 80)
			bestLabel.Parent = chip

			-- Small connector line from the badge down to the item image, so
			-- it reads as pointing at Dream Castle instead of floating loose.
			local bestLine = Instance.new("Frame")
			bestLine.Size = UDim2.new(0, 5, 0, 10)
			bestLine.Position = UDim2.new(0.5, 0, 0, -10)
			bestLine.AnchorPoint = Vector2.new(0.5, 0)
			bestLine.BackgroundColor3 = Color3.fromRGB(255, 230, 80)
			bestLine.BorderSizePixel = 0
			bestLine.Parent = chip
		end

		local emojiLabel = Instance.new("ImageLabel")
		emojiLabel.Size = UDim2.new(0, 56, 0, 56)
		emojiLabel.Position = UDim2.new(0.5, 0, 0, 0)
		emojiLabel.AnchorPoint = Vector2.new(0.5, 0)
		emojiLabel.BackgroundTransparency = 1
		emojiLabel.Image = itemInfo and itemInfo.Image or ""
		emojiLabel.Parent = chip

		local percentLabel = Instance.new("TextLabel")
		percentLabel.Size = UDim2.new(1, 0, 0, 22)
		percentLabel.Position = UDim2.new(0, 0, 0, 56)
		percentLabel.BackgroundTransparency = 1
		percentLabel.Font = Theme.Fonts.Header
		percentLabel.TextScaled = true
		percentLabel.Text = string.format("%s%%", tostring(entry.Percent))
		percentLabel.TextColor3 = Color3.new(1, 1, 1)
		percentLabel.Parent = chip
	end

	local buttonsRow = Instance.new("Frame")
	buttonsRow.Position = UDim2.new(0, 12, 0, 156)
	buttonsRow.Size = UDim2.new(1, -24, 0, 86)
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Parent = crateBox

	local buttonsLayout = Instance.new("UIListLayout")
	buttonsLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonsLayout.Padding = UDim.new(0, 8)
	buttonsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buttonsLayout.Parent = buttonsRow

	local tierCount = #CrateConfig.PurchaseTiers
	for tierOrder, tier in CrateConfig.PurchaseTiers do
		-- Green square per tier, per explicit request -- back to its own
		-- background (just green this time, not the earlier per-tier
		-- purple/etc.), gapped from its neighbors instead of a shared flat
		-- background/dividers.
		local buyButton = Instance.new("TextButton")
		buyButton.LayoutOrder = tierOrder
		buyButton.Size = UDim2.new((1 - 0.03 * (tierCount - 1)) / tierCount, 0, 1, 0)
		buyButton.BackgroundColor3 = Theme.Colors.Success
		buyButton.BorderSizePixel = 0
		buyButton.AutoButtonColor = true
		buyButton.Text = ""
		buyButton.Parent = buttonsRow
		Theme.Round(buyButton, UDim.new(0, 10))
		Theme.Stroke(buyButton, CARD_STROKE_COLOR, 2.5)

		local quantityLabel = Instance.new("TextLabel")
		quantityLabel.Size = UDim2.new(1, -6, 0, 22)
		quantityLabel.Position = UDim2.new(0, 3, 0, 8)
		quantityLabel.BackgroundTransparency = 1
		quantityLabel.Font = Theme.Fonts.Header
		quantityLabel.TextScaled = true
		quantityLabel.Text = string.format("%d Crate%s", tier.Quantity, tier.Quantity == 1 and "" or "s")
		quantityLabel.TextColor3 = Color3.new(1, 1, 1)
		quantityLabel.TextStrokeTransparency = 0
		quantityLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		quantityLabel.Parent = buyButton
		local quantityTextSize = Instance.new("UITextSizeConstraint")
		quantityTextSize.MaxTextSize = 14
		quantityTextSize.Parent = quantityLabel

		-- Robux price -- the whole point of this correction, made sure it's
		-- the biggest/clearest text in the square.
		local priceLabel = Instance.new("TextLabel")
		priceLabel.Size = UDim2.new(1, -6, 0, 30)
		priceLabel.Position = UDim2.new(0, 3, 0, 40)
		priceLabel.BackgroundTransparency = 1
		priceLabel.Font = Theme.Fonts.Header
		priceLabel.TextScaled = true
		priceLabel.Text = "..."
		priceLabel.TextColor3 = Color3.new(1, 1, 1)
		priceLabel.TextStrokeTransparency = 0
		priceLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		priceLabel.Parent = buyButton
		local priceTextSize = Instance.new("UITextSizeConstraint")
		priceTextSize.MaxTextSize = 20
		priceTextSize.Parent = priceLabel

		if tier.ProductId == 0 then
			priceLabel.Text = "Soon"
			buyButton.Active = false
			buyButton.AutoButtonColor = false
			buyButton.BackgroundColor3 = Theme.Colors.Surface
		else
			task.spawn(function()
				local priceFormat = tier.Id == "Crate3" and "ONLY %d R$" or "%d R$"
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(tier.ProductId, Enum.InfoType.Product)
				end)
				if ok and info and info.PriceInRobux then
					priceLabel.Text = string.format(priceFormat, info.PriceInRobux)
				else
					priceLabel.Text = string.format(priceFormat, tier.RobuxPrice)
				end
			end)
			buyButton.Activated:Connect(function()
				MarketplaceService:PromptProductPurchase(Players.LocalPlayer, tier.ProductId)
			end)
		end
	end

	-- ===== Batch reveal overlay -- top-level (not nested in the Shop
	-- panel/its scroll), so it shows correctly regardless of scroll
	-- position or even if Shop gets closed right after buying. =====
	local crateOpenResult = remotes:WaitForChild("CrateOpenResult")

	local revealOverlay = Instance.new("TextButton")
	revealOverlay.Size = UDim2.new(1, 0, 1, 0)
	revealOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	revealOverlay.BackgroundTransparency = 0.35
	revealOverlay.BorderSizePixel = 0
	revealOverlay.Text = ""
	revealOverlay.AutoButtonColor = false
	revealOverlay.Visible = false
	revealOverlay.ZIndex = 20
	revealOverlay.Parent = screenGui

	local revealCard = Instance.new("Frame")
	revealCard.Size = UDim2.new(0, 320, 0, 340)
	revealCard.AnchorPoint = Vector2.new(0.5, 0.5)
	revealCard.Position = UDim2.new(0.5, 0, 0.5, 0)
	revealCard.BackgroundColor3 = Theme.Colors.Panel
	revealCard.BorderSizePixel = 0
	revealCard.ZIndex = 21
	revealCard.Parent = revealOverlay
	Theme.Round(revealCard, UDim.new(0, 18))
	Theme.Stroke(revealCard, Color3.fromRGB(200, 120, 255), 2)
	Theme.AutoScale(screenGui, revealCard, 320)

	local EXCLUSIVE_COLOR = Color3.fromRGB(200, 120, 255)

	local revealTitle = Theme.Label(revealCard, UDim2.new(1, -20, 0, 28), "OPENING CRATE...", true)
	revealTitle.Position = UDim2.new(0, 10, 0, 12)
	revealTitle.TextXAlignment = Enum.TextXAlignment.Center

	local revealIcon = Instance.new("ImageLabel")
	revealIcon.Size = UDim2.new(0, 140, 0, 140)
	revealIcon.AnchorPoint = Vector2.new(0.5, 0)
	revealIcon.Position = UDim2.new(0.5, 0, 0, 50)
	revealIcon.BackgroundTransparency = 1
	revealIcon.ScaleType = Enum.ScaleType.Fit
	revealIcon.Image = ""
	revealIcon.ZIndex = 21
	revealIcon.Parent = revealCard

	local revealLabel = Theme.Label(revealCard, UDim2.new(1, -20, 0, 32), "", true)
	revealLabel.Position = UDim2.new(0, 10, 0, 198)
	revealLabel.TextXAlignment = Enum.TextXAlignment.Center
	revealLabel.TextWrapped = true
	revealLabel.ZIndex = 21

	local revealTagLabel = Theme.Label(revealCard, UDim2.new(1, -20, 0, 24), "EXCLUSIVE", false)
	revealTagLabel.Position = UDim2.new(0, 10, 0, 232)
	revealTagLabel.TextXAlignment = Enum.TextXAlignment.Center
	revealTagLabel.TextColor3 = EXCLUSIVE_COLOR
	revealTagLabel.ZIndex = 21

	local revealOddsLabel = Theme.Label(revealCard, UDim2.new(1, -20, 0, 22), "", false)
	revealOddsLabel.Position = UDim2.new(0, 10, 0, 258)
	revealOddsLabel.TextXAlignment = Enum.TextXAlignment.Center
	revealOddsLabel.TextColor3 = Theme.Colors.TextSecondary
	revealOddsLabel.ZIndex = 21

	local revealDismissLabel = Theme.Label(revealCard, UDim2.new(1, -20, 0, 24), "Tap anywhere to continue", false)
	revealDismissLabel.Position = UDim2.new(0, 10, 1, -32)
	revealDismissLabel.TextXAlignment = Enum.TextXAlignment.Center
	revealDismissLabel.TextColor3 = Theme.Colors.TextSecondary

	local ESTATE_ODDS = CrateConfig.GetEstateOdds()
	local ESTATE_PERCENT_BY_ID: { [string]: number } = {}
	local ESTATE_ITEMS: { ItemDatabase.Item } = {}
	for _, odds in ESTATE_ODDS do
		ESTATE_PERCENT_BY_ID[odds.ItemId] = odds.Percent
		local estateItem = ItemDatabase.GetItem(odds.ItemId)
		if estateItem then
			table.insert(ESTATE_ITEMS, estateItem)
		end
	end

	local SPIN_INTERVAL = 0.08
	local SPIN_DURATION = 1.4
	local HOLD_SECONDS = 6

	-- A tap only skips the CURRENT item's hold (see the per-item reset
	-- below) -- it must never hide the overlay directly, or a batch of 2-3
	-- crates would silently keep resolving the rest in the background with
	-- nothing ever shown again (that was the "only one item appears" bug).
	local dismissRequested = false
	revealOverlay.Activated:Connect(function()
		dismissRequested = true
	end)

	local revealBusy = false
	-- A QUEUE of batches, not a single slot -- a single slot silently drops
	-- an earlier still-pending batch's reveal if a 3rd purchase lands while
	-- the 2nd is still waiting (items from all of them are still granted
	-- server-side regardless, only the reveal animation was going missing).
	local pendingWonItemsQueue: { { { ItemId: string } } } = {}

	local function playCrateReveal(wonItems: { { ItemId: string } })
		revealBusy = true
		revealOverlay.Visible = true

		for itemIndex, won in wonItems do
			-- Reset per item -- a skip on item 1's hold must not also skip
			-- item 2/3's spin+hold.
			dismissRequested = false
			local item = ItemDatabase.GetItem(won.ItemId)
			if item then
				revealTitle.Text = if #wonItems > 1
					then string.format("OPENING CRATE %d/%d...", itemIndex, #wonItems)
					else "OPENING CRATE..."

				-- Not interruptible by a stray tap-to-dismiss (e.g. the click
				-- that confirms the Robux purchase prompt can land on this
				-- overlay the instant it becomes visible) -- only the hold
				-- afterward can be skipped, so the spin always gets to play.
				local startTime = os.clock()
				while os.clock() - startTime < SPIN_DURATION do
					local randomItem = ESTATE_ITEMS[math.random(1, #ESTATE_ITEMS)]
					revealIcon.Image = randomItem.Image
					revealLabel.Text = randomItem.Name
					revealOddsLabel.Text = string.format("%d%% chance", ESTATE_PERCENT_BY_ID[randomItem.Id] or 0)
					task.wait(SPIN_INTERVAL)
				end

				revealIcon.Image = item.Image
				revealLabel.Text = item.Name
				revealOddsLabel.Text = string.format("%d%% chance", ESTATE_PERCENT_BY_ID[item.Id] or 0)
				revealTitle.Text = "YOU WON:"

				revealIcon.Size = UDim2.new(0, 154, 0, 154)
				TweenService:Create(
					revealIcon,
					TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = UDim2.new(0, 140, 0, 140) }
				):Play()

				local holdStart = os.clock()
				while os.clock() - holdStart < HOLD_SECONDS and not dismissRequested do
					task.wait(0.05)
				end
			end
		end

		revealOverlay.Visible = false
		revealBusy = false

		if #pendingWonItemsQueue > 0 then
			local nextItems = table.remove(pendingWonItemsQueue, 1)
			playCrateReveal(nextItems)
		end
	end

	crateOpenResult.OnClientEvent:Connect(function(wonItems: { { ItemId: string } })
		if revealBusy then
			table.insert(pendingWonItemsQueue, wonItems)
			return
		end
		task.spawn(playCrateReveal, wonItems)
	end)
end

function ShopPanel.Create(screenGui: ScreenGui, remotes: Folder)
	-- Anchored near the top (not dead-center) so it doesn't collide with
	-- RollPanel's bottom-anchored reveal window/button on shorter viewports.
	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 460, 0, 600), UDim2.new(0.5, -230, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10
	panel.ClipsDescendants = true

	-- Whole-panel tiled texture (the Store's own outer window, not any one
	-- section) -- inserted first so it paints behind titleLabel/closeButton/
	-- content, which are all added after it below.
	local panelTexture = Instance.new("ImageLabel")
	panelTexture.Size = UDim2.new(1, 0, 1, 0)
	panelTexture.BackgroundTransparency = 1
	panelTexture.Image = "rbxassetid://124958253272102"
	panelTexture.ScaleType = Enum.ScaleType.Tile
	panelTexture.TileSize = UDim2.new(0, 64, 0, 64)
	panelTexture.ZIndex = 1
	panelTexture.Parent = panel
	-- ClipsDescendants alone doesn't respect a UICorner-rounded parent (see
	-- every other texture in this file for the same fix) -- the image needs
	-- its own matching UICorner to actually clip to the panel's rounded shape.
	Theme.Round(panelTexture, Theme.CornerRadius)

	local titleLabel = Theme.Label(panel, UDim2.new(1, -120, 0, 32), "Store", true)
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
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

	local gamepassesGrid = createSection(content, 3, "GAMEPASSES")

	local refreshVIP =
		createGamepassCard(gamepassesGrid, 1, Color3.fromRGB(255, 200, 80), "rbxassetid://73540272717608", "VIP", "Buy", VIPConfig.GamepassId)
	local refreshAutoRoll = createGamepassCard(
		gamepassesGrid,
		6,
		Color3.fromRGB(90, 170, 255),
		"rbxassetid://115324216729484",
		"Auto Roll",
		"3 R$",
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
		2,
		Color3.fromRGB(255, 205, 80),
		"rbxassetid://110513806383474",
		"Double Cash",
		"299 R$",
		DoubleCashConfig.GamepassId
	)

	local cashPacksGrid = createSection(content, 5, "CASH")
	for index, pack in CashPackConfig.Packs do
		createCashPackCard(cashPacksGrid, index, Color3.fromRGB(120, 220, 150), pack.CashAmount, pack.RobuxPrice .. " R$", pack.ProductId)
	end

	if remotes then
		createCrateSection(content, 1, screenGui, remotes)
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
