-- Physical read-only "Index" stand, triggered by walking up to the
-- "INDEX" kiosk MapBuilder builds next to the Shop (ProximityPrompt named
-- "CatalogPrompt"). Two tabs: "Roll" (every rollable Item, grouped into
-- Common/Rare/Epic/Legendary/Ultra/Luxury sub-sections -- RarityConfig's
-- own tiers/colors) and "Estates" (every AssetDatabase Asset PLUS
-- ItemDatabase's 4 CrateExclusive Estates, grouped into their OWN 7-tier
-- scheme -- Common/Rare/Epic/Legendary/Godly/Exclusive/Leaderboards, see
-- AssetDatabase.Asset's Rarity field comment for what each bucket means).
--
-- Dex/collection style, like the big RNG games -- each tile shows ONLY
-- the item's shape (image), silhouetted black until unlocked, full color
-- once it is, with a rarity-colored border. "Unlocked" means different
-- things per source: a rollable Item is unlocked the moment it's EVER
-- been obtained at least once (session.DiscoveredItemIds -- permanent,
-- survives selling every copy); an Asset is unlocked simply by owning it
-- (session.OwnedAssets -- Assets can't be sold, so ownership is already
-- permanent).
--
-- A 100%-complete tier isn't auto-rewarded -- it becomes CLAIMABLE, shown
-- as a "CLAIM" button next to that tier's header; the Luck%/Cash Earnings%
-- bonus (IndexRewardConfig.luau) only actually turns on once claimed
-- (IndexRewardManager.luau, server-authoritative -- re-validates
-- completion, this panel's button is just the trigger).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local EstateRarityConfig = require(ReplicatedStorage.Modules.EstateRarityConfig)
local IndexRewardConfig = require(ReplicatedStorage.Modules.IndexRewardConfig)
local Theme = require(script.Parent.Theme)

local CatalogPanel = {}

local ITEM_CELL_SIZE = UDim2.new(0, 88, 0, 88)

-- Estates' own tier scheme/colors now live in EstateRarityConfig.luau
-- (shared with InventoryPanel.luau's Estates detail view and
-- IndexRewardConfig.luau) -- "Exclusive" pulls from BOTH AssetDatabase
-- (Top3Estate) AND ItemDatabase's 4 CrateExclusive items -- handled
-- specially in renderEstatesTab below, not just a plain Rarity-field
-- filter like every other tier here.
local ESTATE_TIER_ORDER = EstateRarityConfig.Order

-- The 4 Crate-exclusive Estates, folded into the Estates tab's "Exclusive"
-- section alongside Top3Estate -- pulled by Id, not by scanning for a
-- CrateExclusive flag every render, since there's only ever these 4.
local CRATE_EXCLUSIVE_ITEM_IDS = { "CrateVilla", "CrateManor", "CratePalace", "CrateCastle" }

function CatalogPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local inventoryUpdated = remotes:WaitForChild("InventoryUpdated")
	local discoveredItemsUpdated = remotes:WaitForChild("DiscoveredItemsUpdated")
	local assetUpdated = remotes:WaitForChild("AssetUpdated")
	local claimedIndexRewardsUpdated = remotes:WaitForChild("ClaimedIndexRewardsUpdated")
	local claimIndexReward = remotes:WaitForChild("ClaimIndexReward")

	local discoveredItemIds: { [string]: boolean } = {}
	local ownedAssetIds: { [string]: boolean } = {}
	local claimedRollTiers: { [string]: boolean } = {}
	local claimedEstateTiers: { [string]: boolean } = {}
	local activeTab: "Roll" | "Estates" = "Roll"

	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 460, 0, 480), UDim2.new(0.5, -230, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	local titleLabel = Theme.Label(panel, UDim2.new(1, -120, 0, 32), "Index", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	local closeButton = Theme.Button(panel, UDim2.new(0, 90, 0, 32), UDim2.new(1, -100, 0, 10), "Close")
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	local rollTabButton = Theme.Button(panel, UDim2.new(0.5, -20, 0, 30), UDim2.new(0, 16, 0, 50), "Roll")
	local estatesTabButton = Theme.Button(panel, UDim2.new(0.5, -20, 0, 30), UDim2.new(0.5, 4, 0, 50), "Estates")

	local content = Instance.new("ScrollingFrame")
	content.Size = UDim2.new(1, -32, 1, -140)
	content.Position = UDim2.new(0, 16, 0, 88)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 6
	content.ScrollBarImageColor3 = Theme.Colors.Accent
	content.Parent = panel

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.Padding = UDim.new(0, 10)
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Parent = content

	-- Pinned below the scrolling content, not inside it, so it's always
	-- visible regardless of scroll position.
	local footerLabel = Theme.Label(panel, UDim2.new(1, -32, 0, 24), "", true)
	footerLabel.Position = UDim2.new(0, 16, 1, -34)
	footerLabel.TextXAlignment = Enum.TextXAlignment.Center
	footerLabel.TextColor3 = Theme.Colors.Accent

	local function clearContent()
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	-- Dex-style tile -- just the item's shape, nothing else. Silhouetted
	-- black (ImageColor3 multiplies the image, so black = solid
	-- silhouette of whatever shape/alpha the icon has) until unlocked,
	-- then full color + a rarity-colored border to mark it as found.
	local function createItemCard(parent: Instance, order: number, image: string, isUnlocked: boolean, borderColor: Color3): Frame
		local card = Instance.new("Frame")
		card.LayoutOrder = order
		card.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
		card.BackgroundTransparency = 0
		card.BorderSizePixel = 0
		card.Parent = parent
		Theme.Round(card, UDim.new(0, 10))

		local stroke = Theme.Stroke(card, isUnlocked and borderColor or Color3.fromRGB(60, 60, 66), isUnlocked and 2.5 or 1.5)
		stroke.Transparency = isUnlocked and 0 or 0.3

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(1, -20, 1, -20)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = image or ""
		icon.ImageColor3 = isUnlocked and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
		icon.Parent = card

		return card
	end

	-- One tier = a header row (colored label + an optional CLAIM button) +
	-- its own small grid underneath, NOT part of one shared grid --
	-- UIGridLayout can't mix a full-width header row with fixed-size
	-- cells, so each tier gets its own self-contained block instead,
	-- stacked vertically via contentLayout.
	local function renderTierSection(
		order: number,
		tierName: string,
		color: Color3,
		candidates: { { Id: string, Image: string, Unlocked: boolean } },
		bonusPercent: number?,
		isComplete: boolean?,
		isClaimed: boolean?,
		bonusLabel: string?,
		onClaim: (() -> ())?
	)
		if #candidates == 0 then
			return
		end

		local unlockedCount = 0
		for _, candidate in candidates do
			if candidate.Unlocked then
				unlockedCount += 1
			end
		end

		local showClaimButton = bonusPercent ~= nil and isComplete and not isClaimed

		-- Only shows anything once actually claimed (the permanent bonus
		-- text) -- while still locked or merely complete-but-unclaimed, the
		-- CLAIM button below is the only indicator, no "+X% at 100%" preview
		-- text cluttering the header before then.
		local bonusText = ""
		if bonusPercent and isClaimed then
			bonusText = string.format("  +%d%% %s \u{2714}", bonusPercent, bonusLabel)
		end

		local headerRow = Instance.new("Frame")
		headerRow.LayoutOrder = order
		headerRow.Size = UDim2.new(1, 0, 0, 22)
		headerRow.BackgroundTransparency = 1
		headerRow.Parent = content

		local header = Instance.new("TextLabel")
		header.Size = showClaimButton and UDim2.new(1, -68, 1, 0) or UDim2.new(1, 0, 1, 0)
		header.BackgroundTransparency = 1
		header.Font = Theme.Fonts.Header
		header.TextScaled = true
		header.TextXAlignment = Enum.TextXAlignment.Left
		header.Text = string.format("%s (%d/%d)%s", string.upper(tierName), unlockedCount, #candidates, bonusText)
		header.TextColor3 = color
		header.Parent = headerRow

		if showClaimButton then
			local claimButton = Theme.Button(headerRow, UDim2.new(0, 64, 0, 22), UDim2.new(1, 0, 0, 0), "CLAIM", true)
			claimButton.AnchorPoint = Vector2.new(1, 0)
			claimButton.Activated:Connect(function()
				if onClaim then
					onClaim()
				end
			end)
		end

		local grid = Instance.new("Frame")
		grid.LayoutOrder = order + 1
		grid.Size = UDim2.new(1, 0, 0, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.BackgroundTransparency = 1
		grid.Parent = content

		local gridLayout = Instance.new("UIGridLayout")
		gridLayout.CellSize = ITEM_CELL_SIZE
		gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
		gridLayout.Parent = grid

		for i, candidate in candidates do
			createItemCard(grid, i, candidate.Image, candidate.Unlocked, color)
		end
	end

	local function renderRollTab()
		local order = 0
		for _, rarity in RarityConfig.Order do
			-- Rollable only -- deliberately NOT GetItemsByRarity, which also
			-- includes NotRollable/CrateExclusive specials (GroupRewardChest,
			-- the 4 Crate items -- e.g. Dream Castle also carries Rarity=
			-- "Luxury"). Those aren't obtainable by rolling at all, so
			-- counting them here made the displayed "(2/3)" disagree with
			-- IsTierComplete's own rollable-only math (which correctly saw
			-- 2/2 and allowed the claim) -- same list both places now. The 4
			-- Crate items still show up in the Estates tab's "Exclusive"
			-- section instead, not duplicated here.
			local rawCandidates = ItemDatabase.GetRollableItemsByRarity(rarity)
			table.sort(rawCandidates, function(a, b)
				return a.Value < b.Value
			end)
			local candidates = {}
			for _, item in rawCandidates do
				table.insert(candidates, { Id = item.Id, Image = item.Image, Unlocked = discoveredItemIds[item.Id] == true })
			end
			order += 1
			renderTierSection(
				order,
				rarity,
				RarityConfig.GetColor(rarity),
				candidates,
				IndexRewardConfig.CompletionBonusPercent[rarity],
				IndexRewardConfig.IsTierComplete(discoveredItemIds, rarity),
				claimedRollTiers[rarity] == true,
				"LUCK",
				function()
					claimIndexReward:FireServer("Roll", rarity)
				end
			)
			order += 1
		end
	end

	local function renderEstatesTab()
		local order = 0
		for _, tier in ESTATE_TIER_ORDER do
			local candidates = {}
			if tier == "Exclusive" then
				local top3 = AssetDatabase.GetAsset("Top3Estate")
				if top3 then
					table.insert(candidates, { Id = top3.Id, Image = top3.Image, Unlocked = ownedAssetIds[top3.Id] == true })
				end
				for _, itemId in CRATE_EXCLUSIVE_ITEM_IDS do
					local item = ItemDatabase.GetItem(itemId)
					if item then
						table.insert(candidates, { Id = item.Id, Image = item.Image, Unlocked = discoveredItemIds[item.Id] == true })
					end
				end
				-- Any other Exclusive-tier Estate (e.g. LARP Battles Rank
				-- Rewards' OldFarm/Supermarket/SolarPark/ConstructionShop) --
				-- anything with this Rarity that isn't Top3Estate/a Crate item
				-- above, sorted by Price like every other tier's own-branch below.
				local rawExtras = {}
				for _, asset in AssetDatabase.GetAllAssets() do
					if asset.Rarity == tier and asset.Id ~= "Top3Estate" then
						table.insert(rawExtras, asset)
					end
				end
				table.sort(rawExtras, function(a, b)
					return a.Price < b.Price
				end)
				for _, asset in rawExtras do
					table.insert(candidates, { Id = asset.Id, Image = asset.Image, Unlocked = ownedAssetIds[asset.Id] == true })
				end
			else
				local rawAssets = {}
				for _, asset in AssetDatabase.GetAllAssets() do
					if asset.Rarity == tier and asset.Id ~= "Top3Estate" then
						table.insert(rawAssets, asset)
					end
				end
				table.sort(rawAssets, function(a, b)
					return a.Price < b.Price
				end)
				for _, asset in rawAssets do
					table.insert(candidates, { Id = asset.Id, Image = asset.Image, Unlocked = ownedAssetIds[asset.Id] == true })
				end
			end

			order += 1
			renderTierSection(
				order,
				tier,
				EstateRarityConfig.GetColor(tier),
				candidates,
				IndexRewardConfig.EstateCompletionBonusPercent[tier],
				IndexRewardConfig.IsEstateTierComplete(ownedAssetIds, discoveredItemIds, tier),
				claimedEstateTiers[tier] == true,
				"CASH",
				function()
					claimIndexReward:FireServer("Estate", tier)
				end
			)
			order += 1
		end
	end

	local function render()
		clearContent()
		rollTabButton.BackgroundColor3 = activeTab == "Roll" and Theme.Colors.Accent or Theme.Colors.Surface
		estatesTabButton.BackgroundColor3 = activeTab == "Estates" and Theme.Colors.Accent or Theme.Colors.Surface

		if activeTab == "Roll" then
			renderRollTab()
			footerLabel.Text = string.format("TOTAL LUCK BONUS: +%d%%", IndexRewardConfig.GetTotalBonusPercent(claimedRollTiers))
		else
			renderEstatesTab()
			footerLabel.Text = string.format(
				"TOTAL CASH EARNINGS BONUS: +%d%%",
				IndexRewardConfig.GetEstateTotalBonusPercent(claimedEstateTiers)
			)
		end
	end

	rollTabButton.Activated:Connect(function()
		activeTab = "Roll"
		render()
	end)
	estatesTabButton.Activated:Connect(function()
		activeTab = "Estates"
		render()
	end)

	discoveredItemsUpdated.OnClientEvent:Connect(function(discovered: { [string]: boolean })
		discoveredItemIds = discovered
		if panel.Visible then
			render()
		end
	end)

	assetUpdated.OnClientEvent:Connect(function(payload: { Owned: { [string]: boolean }, Equipped: { string } })
		ownedAssetIds = payload.Owned
		if panel.Visible then
			render()
		end
	end)

	claimedIndexRewardsUpdated.OnClientEvent:Connect(function(claimed: { Roll: { [string]: boolean }, Estate: { [string]: boolean } })
		claimedRollTiers = claimed.Roll or {}
		claimedEstateTiers = claimed.Estate or {}
		if panel.Visible then
			render()
		end
	end)

	-- Legacy fallback -- if DiscoveredItemsUpdated hasn't landed yet for
	-- some reason, current Inventory contents still count as "at least
	-- discovered" so the Index isn't empty-looking on a slow join.
	inventoryUpdated.OnClientEvent:Connect(function(inventory: { { Uid: number, ItemId: string } })
		for _, entry in inventory do
			if not discoveredItemIds[entry.ItemId] then
				discoveredItemIds[entry.ItemId] = true
			end
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
