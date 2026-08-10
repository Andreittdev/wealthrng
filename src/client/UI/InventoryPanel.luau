-- Centered modal, master-detail layout: two tabs (Roll Items / Estates), a
-- simple scrollable list (name + a detail line per row) fills the whole
-- panel for whichever is open. Clicking a row doesn't push the list aside
-- -- it pops a detail square on top of it (image, name, stats, Equip/Sell),
-- dismissed via its X button or by clicking the dimmed backdrop behind it.
-- The SAME detail popup is reused for both tabs (fields relabeled per
-- selection) rather than duplicating the whole layout twice.
--
-- Items only earn IncomePerSecond while equipped -- only ItemDatabase.
-- MaxEquipped (currently 1) can be equipped at once, so tapping Equip on
-- the selected item just swaps out whichever one was equipped before
-- (server-side swap in InventoryManager.Equip, this panel doesn't need to
-- know). Estates (AssetDatabase.MaxEquipped, currently 2) work the same
-- way. Equip/Unequip for Estates lives ONLY here now -- AssetShopPanel.luau
-- (the physical Shop kiosk) is buy-only once something's owned.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local EstateRarityConfig = require(ReplicatedStorage.Modules.EstateRarityConfig)
local EstateExistenceConfig = require(ReplicatedStorage.Modules.EstateExistenceConfig)
local RollOdds = require(ReplicatedStorage.Modules.RollOdds)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local InventoryPanel = {}

local rarityRank: { [string]: number } = {}
for index, rarity in RarityConfig.Order do
	rarityRank[rarity] = index
end

local function formatOdds(itemId: string): string
	local oneInN = RollOdds.GetOneInN(itemId)
	if not oneInN then
		return ""
	end
	return string.format("1 in %d", math.floor(oneInN + 0.5))
end

function InventoryPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local sellItem = remotes:WaitForChild("SellItem")
	local equipItem = remotes:WaitForChild("EquipItem")
	local unequipItem = remotes:WaitForChild("UnequipItem")
	local equippedItemsUpdated = remotes:WaitForChild("EquippedItemsUpdated")
	-- Estates have no Sell -- equip-only once owned, see detailSellButton's
	-- visibility toggle below.
	local equipAsset = remotes:WaitForChild("EquipAsset")
	local unequipAsset = remotes:WaitForChild("UnequipAsset")
	local assetUpdated = remotes:WaitForChild("AssetUpdated")
	local estateExistenceCountsUpdated = remotes:WaitForChild("EstateExistenceCountsUpdated")

	local currentInventory: { { Uid: number, ItemId: string } } = {}
	local equippedUids: { number } = {}
	local selectedUid: number? = nil

	local ownedAssetIds: { [string]: boolean } = {}
	local equippedAssetIds: { string } = {}
	local selectedAssetId: string? = nil
	-- Global "X exist" counts, every Estate (EstateExistenceManager.luau) --
	-- keyed by assetId, updated on join and again whenever any Estate is
	-- newly granted to anyone.
	local estateExistenceCounts: { [string]: number } = {}
	-- THIS player's own permanent per-copy serials, keyed by assetId --
	-- always a list, even for single-copy Estates (session.
	-- AssetSerialNumbers, pushed alongside Owned/Equipped on AssetUpdated).
	local mySerialNumbers: { [string]: { number } } = {}

	-- "Items" or "Estates" -- which tab is currently showing in `list`/`detail`.
	local currentTab = "Items"

	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 600, 0, 460), UDim2.new(0.5, -300, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	-- Flat black instead of Theme.Panel's default purple-grey gradient --
	-- reads as a premium display case, and makes rarity colors actually
	-- pop instead of blending into a lighter backdrop.
	panel.BackgroundColor3 = Color3.fromRGB(6, 6, 8)
	local panelGradient = panel:FindFirstChildOfClass("UIGradient")
	if panelGradient then
		panelGradient:Destroy()
	end

	local titleLabel = Theme.Label(panel, UDim2.new(1, -140, 0, 32), "Inventory", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)
	titleLabel.TextColor3 = Theme.Colors.TextPrimary

	local statusLabel = Theme.Label(panel, UDim2.new(0, 120, 0, 20), "0/0 equipped")
	statusLabel.Position = UDim2.new(1, -230, 0, 16)
	statusLabel.TextColor3 = Theme.Colors.TextSecondary
	statusLabel.TextXAlignment = Enum.TextXAlignment.Right

	local closeButton = Theme.Button(panel, UDim2.new(0, 78, 0, 28), UDim2.new(1, -88, 0, 12), "Close")
	closeButton.TextScaled = false
	closeButton.TextSize = 14
	closeButton.BackgroundColor3 = Theme.Colors.Danger
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	local closeButtonStroke = closeButton:FindFirstChildOfClass("UIStroke")
	if closeButtonStroke then
		closeButtonStroke.Color = Color3.fromRGB(255, 140, 140)
		closeButtonStroke.Thickness = 1.5
		closeButtonStroke.Transparency = 0
	end
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	-- ===== Tabs -- Roll Items / Estates -- same toggle-highlight convention
	-- AssetShopPanel.luau's Assets/Investments tabs use. Both created plain
	-- (accent=false, no baked-in gold gradient) -- highlightTabs() toggles
	-- their flat BackgroundColor3/TextColor3 to show which is active, and a
	-- permanent gradient on one but not the other would look inconsistent
	-- once they swap states.
	local itemsTabButton = Theme.Button(panel, UDim2.new(0.5, -20, 0, 32), UDim2.new(0, 16, 0, 50), "Roll Items")
	local estatesTabButton = Theme.Button(panel, UDim2.new(0.5, -20, 0, 32), UDim2.new(0.5, 4, 0, 50), "Estates")

	local TAB_MAX_TEXT_SIZE = 18
	local itemsTabTextConstraint = Instance.new("UITextSizeConstraint")
	itemsTabTextConstraint.MaxTextSize = TAB_MAX_TEXT_SIZE
	itemsTabTextConstraint.Parent = itemsTabButton
	local estatesTabTextConstraint = Instance.new("UITextSizeConstraint")
	estatesTabTextConstraint.MaxTextSize = TAB_MAX_TEXT_SIZE
	estatesTabTextConstraint.Parent = estatesTabButton

	-- ===== Search bar -- filters the list below by name as you type, same
	-- convention on both tabs, just fewer rows visible. =====
	local searchBox = Instance.new("TextBox")
	searchBox.Size = UDim2.new(1, -32, 0, 32)
	searchBox.Position = UDim2.new(0, 16, 0, 90)
	searchBox.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	searchBox.BorderSizePixel = 0
	searchBox.Text = ""
	searchBox.PlaceholderText = "Search items..."
	searchBox.TextColor3 = Theme.Colors.TextPrimary
	searchBox.PlaceholderColor3 = Theme.Colors.TextSecondary
	searchBox.Font = Theme.Fonts.Body
	searchBox.TextSize = 16
	searchBox.TextXAlignment = Enum.TextXAlignment.Left
	searchBox.ClearTextOnFocus = false
	searchBox.ZIndex = 1
	searchBox.Parent = panel
	Theme.Round(searchBox, UDim.new(0, 8))
	local searchBoxStroke = Theme.Stroke(searchBox, Color3.fromRGB(90, 90, 98), 1.5)
	searchBoxStroke.Transparency = 0

	local searchBoxPadding = Instance.new("UIPadding")
	searchBoxPadding.PaddingLeft = UDim.new(0, 10)
	searchBoxPadding.PaddingRight = UDim.new(0, 10)
	searchBoxPadding.Parent = searchBox

	-- ===== List, name + chance per row -- takes the full content width, no
	-- space reserved for the detail pane (that's an overlay now, see below). =====
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -32, 1, -148)
	list.Position = UDim2.new(0, 16, 0, 132)
	list.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	list.BackgroundTransparency = 0
	list.BorderSizePixel = 0
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = Theme.Colors.Accent
	list.ZIndex = 1
	list.Parent = panel
	Theme.Round(list, UDim.new(0, 8))

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingTop = UDim.new(0, 6)
	listPadding.PaddingLeft = UDim.new(0, 6)
	listPadding.PaddingRight = UDim.new(0, 6)
	listPadding.Parent = list

	-- 2 columns -- CellSize halves are offset by half the gap so
	-- 2*(0.5W - 4) + 8 == W exactly, no matter how wide the responsive
	-- panel ends up on a given screen.
	local listLayout = Instance.new("UIGridLayout")
	listLayout.CellSize = UDim2.new(0.5, -4, 0, 56)
	listLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	-- Dims the WHOLE SCREEN (not just the panel) and catches "click outside"
	-- to dismiss the detail overlay -- both are parented to screenGui
	-- directly, not `panel`, and ZIndex'd above it (panel's own ZIndex is
	-- 10). They used to be nested inside `panel` at a FIXED 320x404 size
	-- with no scaling -- on a short/narrow phone screen, ResponsivePanel
	-- shrinks `panel` itself down (sometimes well under 320x404), so the
	-- detail popup routinely overflowed past the panel's own edges,
	-- reading as "buggy" when tapping an item. Detached + AutoScale'd
	-- against the full screen, it now shrinks correctly instead.
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.ZIndex = 11
	backdrop.Visible = false
	backdrop.Parent = screenGui

	-- ===== Detail pane -- a floating square that appears ON TOP of
	-- everything (screen-centered) only while an item is selected, instead
	-- of reserving a permanently-visible column next to the list. =====
	local detail = Instance.new("Frame")
	detail.Size = UDim2.new(0, 320, 0, 404)
	detail.AnchorPoint = Vector2.new(0.5, 0.5)
	detail.Position = UDim2.new(0.5, 0, 0.5, 20)
	detail.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	detail.BackgroundTransparency = 0
	detail.BorderSizePixel = 0
	detail.ZIndex = 12
	detail.Visible = false
	detail.Parent = screenGui
	Theme.Round(detail, UDim.new(0, 8))
	local detailStroke = Theme.Stroke(detail, Color3.fromRGB(110, 110, 122), 2)
	detailStroke.Transparency = 0
	local detailShadow = Theme.Shadow(detail)
	Theme.AutoScale(screenGui, detail, 320)
	Theme.AutoScale(screenGui, detailShadow, 320)

	local detailCloseButton = Theme.Button(detail, UDim2.new(0, 32, 0, 32), UDim2.new(1, -44, 0, 12), "X")
	detailCloseButton.ZIndex = 13

	local detailIcon = Instance.new("ImageLabel")
	detailIcon.Size = UDim2.new(0, 150, 0, 150)
	detailIcon.AnchorPoint = Vector2.new(0.5, 0)
	detailIcon.Position = UDim2.new(0.5, 0, 0, 16)
	detailIcon.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
	detailIcon.BackgroundTransparency = 0
	detailIcon.BorderSizePixel = 0
	detailIcon.ScaleType = Enum.ScaleType.Fit
	detailIcon.Image = ""
	detailIcon.Parent = detail
	Theme.Round(detailIcon, UDim.new(0, 8))

	local detailName = Theme.Label(detail, UDim2.new(1, -24, 0, 30), "", true)
	detailName.Position = UDim2.new(0, 12, 0, 174)
	detailName.TextXAlignment = Enum.TextXAlignment.Center
	detailName.TextWrapped = true

	local detailOdds = Theme.Label(detail, UDim2.new(1, -24, 0, 20), "")
	detailOdds.Position = UDim2.new(0, 12, 0, 206)
	detailOdds.TextXAlignment = Enum.TextXAlignment.Center
	detailOdds.TextColor3 = Theme.Colors.TextSecondary

	local detailRarity = Theme.Label(detail, UDim2.new(1, -24, 0, 22), "")
	detailRarity.Position = UDim2.new(0, 12, 0, 228)
	detailRarity.TextXAlignment = Enum.TextXAlignment.Center

	-- THIS player's own permanent serial(s) for the selected Estate -- just
	-- "#N" for a single copy, "#12, #47, #203" for a multi-owned one
	-- (Top1Estate/Top2Estate/Top3Estate "Sol Stadium"). Sits ABOVE the
	-- global "X exist" count below.
	local detailMySerial = Theme.Label(detail, UDim2.new(1, -24, 0, 20), "")
	detailMySerial.Position = UDim2.new(0, 12, 0, 256)
	detailMySerial.TextXAlignment = Enum.TextXAlignment.Center
	detailMySerial.TextColor3 = Theme.Colors.Accent

	-- Estates only (renderEstateDetail) -- "X exist" global flex stat, see
	-- EstateExistenceConfig.luau. Left empty for Roll Items (nothing
	-- repositions around it, so leaving it blank is enough).
	local detailExistCount = Theme.Label(detail, UDim2.new(1, -24, 0, 20), "")
	detailExistCount.Position = UDim2.new(0, 12, 0, 278)
	detailExistCount.TextXAlignment = Enum.TextXAlignment.Center
	detailExistCount.TextColor3 = Theme.Colors.TextSecondary

	local detailEquipButton = Theme.Button(detail, UDim2.new(1, -24, 0, 34), UDim2.new(0, 12, 1, -78), "Equip", true)

	local detailSellButton = Theme.Button(detail, UDim2.new(1, -24, 0, 34), UDim2.new(0, 12, 1, -40), "Sell")
	detailSellButton.BackgroundColor3 = Theme.Colors.Danger
	detailSellButton.TextColor3 = Color3.fromRGB(255, 255, 255)

	-- ===== Sell confirmation popup -- one shared instance =====
	local confirmPopup = Instance.new("Frame")
	confirmPopup.Size = UDim2.new(0, 300, 0, 168)
	confirmPopup.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmPopup.Position = UDim2.new(0.5, 0, 0.5, 0)
	confirmPopup.BackgroundColor3 = Theme.Colors.Panel
	confirmPopup.BackgroundTransparency = 0
	confirmPopup.BorderSizePixel = 0
	confirmPopup.ZIndex = 20
	confirmPopup.Visible = false
	confirmPopup.Parent = screenGui
	Theme.Round(confirmPopup)
	Theme.Stroke(confirmPopup, Color3.fromRGB(255, 215, 140), 1)
	local confirmPopupShadow = Theme.Shadow(confirmPopup)
	Theme.AutoScale(screenGui, confirmPopup, 300)
	Theme.AutoScale(screenGui, confirmPopupShadow, 300)

	local confirmLabel = Theme.Label(confirmPopup, UDim2.new(1, -24, 0, 56), "Are you sure you want to sell this?", true)
	confirmLabel.Position = UDim2.new(0, 12, 0, 12)
	confirmLabel.TextXAlignment = Enum.TextXAlignment.Center
	confirmLabel.TextWrapped = true

	-- Square, not the usual wide rectangle -- Yes/No as two equal-sized tiles.
	local yesButton = Theme.Button(confirmPopup, UDim2.new(0, 68, 0, 68), UDim2.new(0.5, -78, 1, -84), "Yes")
	yesButton.BackgroundColor3 = Theme.Colors.Success

	local noButton = Theme.Button(confirmPopup, UDim2.new(0, 68, 0, 68), UDim2.new(0.5, 10, 1, -84), "No")
	noButton.BackgroundColor3 = Theme.Colors.Danger

	-- Roll Items only -- Estates have no Sell (detailSellButton hides
	-- entirely on that tab, see renderEstateDetail).
	local pendingSellUid: number? = nil

	local function hideConfirm()
		confirmPopup.Visible = false
		pendingSellUid = nil
	end

	local function requestSell(uid: number)
		pendingSellUid = uid
		confirmPopup.Visible = true
	end

	-- Forward-declared here (not just above their `function name()`
	-- definitions further down) because handle.Toggle below is defined
	-- before those definitions are reached -- a `local` declared later in
	-- the file does NOT retroactively become visible to code above it, so
	-- without this, handle.Toggle's calls would resolve to nil globals.
	local renderList
	local renderEstatesList
	local renderDetail
	local refreshStatusLabel

	-- Dispatches to whichever tab is currently open -- every external
	-- caller (search box, tab switch, data-update handlers) goes through
	-- this instead of calling renderList/renderEstatesList directly.
	local function refreshList()
		if currentTab == "Items" then
			renderList()
		else
			renderEstatesList()
		end
	end

	local searchQuery = ""
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		searchQuery = string.lower(searchBox.Text)
		refreshList()
	end)

	local handle = {}
	handle.Frame = panel
	handle.CloseButton = closeButton

	-- Set whenever Render/equip updates arrive while the panel is closed
	-- -- rebuilding the full item-row list (destroy + recreate one Frame
	-- per item) is expensive and used to run on EVERY inventoryUpdated
	-- fire (i.e. every single roll, including Auto Roll's continuous
	-- ones) even with the panel not on screen. Now that work is deferred
	-- until the panel is actually opened.
	local pendingRerender = false

	function handle.Toggle()
		panel.Visible = not panel.Visible
		if panel.Visible and pendingRerender then
			pendingRerender = false
			refreshList()
			renderDetail()
		end
	end

	yesButton.Activated:Connect(function()
		if pendingSellUid then
			sellItem:FireServer(pendingSellUid)
			if selectedUid == pendingSellUid then
				-- Hide the detail popup immediately instead of leaving the
				-- just-sold item's stats/image on screen until the next
				-- inventoryUpdated push arrives.
				selectedUid = nil
				renderDetail()
			end
		end
		hideConfirm()
	end)
	noButton.Activated:Connect(hideConfirm)

	local function clearList()
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function findEntry(uid: number)
		for _, entry in currentInventory do
			if entry.Uid == uid then
				return entry
			end
		end
		return nil
	end

	local function closeDetail()
		selectedUid = nil
		selectedAssetId = nil
		detail.Visible = false
		backdrop.Visible = false
		refreshList()
	end

	detailCloseButton.Activated:Connect(closeDetail)
	backdrop.Activated:Connect(closeDetail)

	-- Catches EVERY way the panel can close (Close button, Sidebar toggle,
	-- clicking the Inventory sidebar icon again) in one place, instead of
	-- duplicating a reset call at each individual close path. Now that
	-- detail/backdrop are parented to screenGui (not `panel`), they no
	-- longer auto-hide when `panel` itself does -- this closes them
	-- explicitly, or they'd stay floating on screen after Inventory closes.
	panel:GetPropertyChangedSignal("Visible"):Connect(function()
		if not panel.Visible then
			searchBox.Text = ""
			closeDetail()
		end
	end)

	local function renderItemDetail()
		local entry = selectedUid and findEntry(selectedUid)
		local item = entry and ItemDatabase.GetItem(entry.ItemId)

		-- The detail square only exists as a temporary overlay once
		-- something is selected -- not a permanent empty column.
		local show = item ~= nil
		detail.Visible = show
		backdrop.Visible = show

		if not item then
			return
		end

		local isEquipped = table.find(equippedUids, entry.Uid) ~= nil
		local rarityColor = RarityConfig.GetColor(item.Rarity)

		detailIcon.Image = item.Image
		detailName.Text = item.Name
		detailOdds.Text = formatOdds(item.Id) .. "  \u{2022}  +" .. NumberFormat.FormatCash(item.IncomePerSecond) .. "/s"
		detailRarity.Text = item.Rarity
		detailRarity.TextColor3 = rarityColor
		detailStroke.Color = isEquipped and Theme.Colors.Accent or rarityColor
		detailExistCount.Text = ""
		detailMySerial.Text = ""

		-- Sell exists for Items, not Estates -- Equip sits higher to leave
		-- room for it here; renderEstateDetail below moves Equip down into
		-- Sell's spot instead of leaving a gap where Sell would've been.
		detailSellButton.Visible = true
		detailEquipButton.Position = UDim2.new(0, 12, 1, -78)
		detailEquipButton.Text = isEquipped and "Unequip" or "Equip"
		detailEquipButton.BackgroundColor3 = isEquipped and Theme.Colors.Surface or Theme.Colors.Accent
		detailEquipButton.TextColor3 = isEquipped and Theme.Colors.TextPrimary or Color3.fromRGB(20, 20, 20)
	end

	local function renderEstateDetail()
		local asset = selectedAssetId and AssetDatabase.GetAsset(selectedAssetId)

		local show = asset ~= nil
		detail.Visible = show
		backdrop.Visible = show

		if not asset then
			return
		end

		local isEquipped = table.find(equippedAssetIds, selectedAssetId) ~= nil
		local accentColor = EstateRarityConfig.GetColor(asset.Rarity)

		detailIcon.Image = asset.Image
		detailName.Text = asset.Name
		detailOdds.Text = "+" .. NumberFormat.FormatCash(asset.IncomePerMinute) .. "/min  \u{2022}  " .. NumberFormat.FormatCash(asset.Price)
		detailRarity.Text = asset.Rarity
		detailRarity.TextColor3 = accentColor
		detailStroke.Color = isEquipped and Theme.Colors.Accent or accentColor

		if EstateExistenceConfig.IsTracked(asset.Id) then
			local count = estateExistenceCounts[asset.Id] or 0
			detailExistCount.Text = string.format("%d exist", count)
		else
			detailExistCount.Text = ""
		end

		-- "#N" for a single copy, "#12, #47, #203" for a multi-owned Estate
		-- (Top1Estate/Top2Estate/Top3Estate). Pre-existing owners (from
		-- before this system shipped) get one backfilled the moment they
		-- next reconnect (EstateExistenceManager.BackfillOwnedAssets) --
		-- not their true historical purchase order (no record of that ever
		-- existed), just a permanent collector number assigned from here on.
		local mySerials = mySerialNumbers[asset.Id]
		if mySerials and #mySerials > 0 then
			local parts = {}
			for _, serial in mySerials do
				table.insert(parts, "#" .. serial)
			end
			detailMySerial.Text = table.concat(parts, ", ")
		else
			detailMySerial.Text = ""
		end

		-- No Sell for Estates -- Equip takes over Sell's lower spot instead
		-- of leaving an empty gap in the popup.
		detailSellButton.Visible = false
		detailEquipButton.Position = UDim2.new(0, 12, 1, -40)
		detailEquipButton.Text = isEquipped and "Unequip" or "Equip"
		detailEquipButton.BackgroundColor3 = isEquipped and Theme.Colors.Surface or Theme.Colors.Accent
		detailEquipButton.TextColor3 = isEquipped and Theme.Colors.TextPrimary or Color3.fromRGB(20, 20, 20)
	end

	function renderDetail()
		if currentTab == "Items" then
			renderItemDetail()
		else
			renderEstateDetail()
		end
	end

	detailEquipButton.Activated:Connect(function()
		if currentTab == "Items" then
			if not selectedUid then
				return
			end
			local isEquipped = table.find(equippedUids, selectedUid) ~= nil
			if isEquipped then
				unequipItem:FireServer(selectedUid)
			else
				equipItem:FireServer(selectedUid)
			end
		else
			if not selectedAssetId then
				return
			end
			local isEquipped = table.find(equippedAssetIds, selectedAssetId) ~= nil
			if isEquipped then
				unequipAsset:FireServer(selectedAssetId)
			else
				equipAsset:FireServer(selectedAssetId)
			end
		end
	end)

	detailSellButton.Activated:Connect(function()
		if selectedUid then
			requestSell(selectedUid)
		end
	end)

	-- Round green badge sitting right ON the row's top-right corner
	-- (centered exactly on the border, half in/half out) -- a plain text
	-- checkmark blended into whatever the row's own background color was
	-- (gold Estates rows especially); a solid badge on the border reads
	-- clearly regardless.
	local function addEquippedCheck(row: Frame)
		local badge = Instance.new("Frame")
		badge.Size = UDim2.new(0, 24, 0, 24)
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.new(1, 0, 0, 0)
		badge.BackgroundColor3 = Theme.Colors.Success
		badge.BorderSizePixel = 0
		badge.ZIndex = 3
		badge.Parent = row
		Theme.Round(badge, UDim.new(1, 0))
		local badgeStroke = Theme.Stroke(badge, Color3.new(0, 0, 0), 2)
		badgeStroke.Transparency = 0

		local check = Instance.new("TextLabel")
		check.Size = UDim2.new(1, -6, 1, -6)
		check.AnchorPoint = Vector2.new(0.5, 0.5)
		check.Position = UDim2.new(0.5, 0, 0.5, 0)
		check.BackgroundTransparency = 1
		check.Font = Theme.Fonts.Header
		check.TextScaled = true
		check.Text = "\u{2714}"
		check.TextColor3 = Color3.fromRGB(20, 20, 20)
		check.ZIndex = 4
		check.Parent = badge
	end

	-- Equipped-first display order, without disturbing currentInventory's
	-- own stored sort (rarity/weight, see handle.Render) -- re-derived every
	-- render instead of re-sorting the stored array, so it stays correct
	-- the instant equip status changes, not just when new inventory data
	-- arrives.
	local function equippedFirstOrder(uids: { number }, entries: { { Uid: number, ItemId: string } }): { { Uid: number, ItemId: string } }
		local ordered = {}
		for index, entry in entries do
			table.insert(ordered, { Entry = entry, Index = index, Equipped = table.find(uids, entry.Uid) ~= nil })
		end
		table.sort(ordered, function(a, b)
			if a.Equipped ~= b.Equipped then
				return a.Equipped
			end
			return a.Index < b.Index
		end)
		local result = {}
		for _, wrapped in ordered do
			table.insert(result, wrapped.Entry)
		end
		return result
	end

	function renderList()
		clearList()
		listLayout.CellSize = UDim2.new(0.5, -4, 0, 56)

		for order, entry in equippedFirstOrder(equippedUids, currentInventory) do
			local item = ItemDatabase.GetItem(entry.ItemId)
			if not item then
				continue
			end
			if searchQuery ~= "" and not string.find(string.lower(item.Name), searchQuery, 1, true) then
				continue
			end

			local isEquipped = table.find(equippedUids, entry.Uid) ~= nil
			local isSelected = selectedUid == entry.Uid
			local rarityColor = RarityConfig.GetColor(item.Rarity)

			local row = Instance.new("Frame")
			row.LayoutOrder = order
			row.Size = UDim2.new(1, 0, 0, 52)
			-- The whole card is filled with the rarity color (darkened so the
			-- name/odds text on top stays readable), not just a thin border --
			-- brighter/less-darkened when selected so it visibly pops.
			row.BackgroundColor3 = rarityColor:Lerp(Color3.new(0, 0, 0), isSelected and 0.35 or 0.55)
			row.BackgroundTransparency = 0
			row.BorderSizePixel = 0
			row.Parent = list
			Theme.Round(row, UDim.new(0, 6))
			local rowStroke = Theme.Stroke(row, isEquipped and Theme.Colors.Accent or rarityColor, isSelected and 3 or 2)
			rowStroke.Transparency = 0

			local nameLabel = Theme.Label(row, UDim2.new(1, -16, 0, 22), item.Name, true)
			nameLabel.Position = UDim2.new(0, 8, 0, 4)

			local oddsLabel = Theme.Label(row, UDim2.new(1, -16, 0, 18), formatOdds(item.Id))
			oddsLabel.Position = UDim2.new(0, 8, 0, 26)
			oddsLabel.TextColor3 = Theme.Colors.TextSecondary

			if isEquipped then
				addEquippedCheck(row)
			end

			local button = Instance.new("TextButton")
			button.Size = UDim2.new(1, 0, 1, 0)
			button.BackgroundTransparency = 1
			button.Text = ""
			button.Parent = row
			button.Activated:Connect(function()
				selectedUid = entry.Uid
				selectedAssetId = nil
				renderList()
				renderDetail()
			end)
		end
	end

	-- Equipped first (both slots), then weakest to strongest -- matches
	-- Roll Items' own ordering convention (see handle.Render below).
	function renderEstatesList()
		clearList()
		-- One full-width card per row (not the 2-column grid Roll Items
		-- uses) -- per explicit request, so each Estate's frame reads at
		-- full size instead of squeezed to half-width.
		listLayout.CellSize = UDim2.new(1, -4, 0, 56)

		local allAssets = AssetDatabase.GetAllAssets()
		local ownedIds = {}
		for id, owned in ownedAssetIds do
			if owned then
				table.insert(ownedIds, id)
			end
		end
		-- Equipped first (both slots), then weakest to strongest -- same
		-- "weak first" convention handle.Render uses for Roll Items
		-- (Common tier first, rarer/pricier later), not the old "priciest
		-- non-equipped first" order.
		table.sort(ownedIds, function(a, b)
			local equippedA = table.find(equippedAssetIds, a) ~= nil
			local equippedB = table.find(equippedAssetIds, b) ~= nil
			if equippedA ~= equippedB then
				return equippedA
			end
			return allAssets[a].Price < allAssets[b].Price
		end)

		local order = 0
		for _, id in ownedIds do
			local asset = allAssets[id]
			if not asset then
				continue
			end
			if searchQuery ~= "" and not string.find(string.lower(asset.Name), searchQuery, 1, true) then
				continue
			end
			order += 1

			local isEquipped = table.find(equippedAssetIds, id) ~= nil
			local isSelected = selectedAssetId == id
			local accentColor = EstateRarityConfig.GetColor(asset.Rarity)

			local row = Instance.new("Frame")
			row.LayoutOrder = order
			row.Size = UDim2.new(1, 0, 0, 52)
			row.BackgroundColor3 = accentColor:Lerp(Color3.new(0, 0, 0), isSelected and 0.35 or 0.55)
			row.BackgroundTransparency = 0
			row.BorderSizePixel = 0
			row.Parent = list
			Theme.Round(row, UDim.new(0, 6))
			local rowStroke = Theme.Stroke(row, isEquipped and Theme.Colors.Accent or accentColor, isSelected and 3 or 2)
			rowStroke.Transparency = 0

			local nameLabel = Theme.Label(row, UDim2.new(1, -16, 0, 22), asset.Name, true)
			nameLabel.Position = UDim2.new(0, 8, 0, 4)

			local incomeLabel = Theme.Label(row, UDim2.new(1, -16, 0, 18), string.format("%s  \u{2022}  +%s/min", asset.Rarity, NumberFormat.FormatCash(asset.IncomePerMinute)))
			incomeLabel.Position = UDim2.new(0, 8, 0, 26)
			incomeLabel.TextColor3 = Theme.Colors.TextSecondary

			if isEquipped then
				addEquippedCheck(row)
			end

			local button = Instance.new("TextButton")
			button.Size = UDim2.new(1, 0, 1, 0)
			button.BackgroundTransparency = 1
			button.Text = ""
			button.Parent = row
			button.Activated:Connect(function()
				selectedAssetId = id
				selectedUid = nil
				renderEstatesList()
				renderDetail()
			end)
		end

		if order == 0 then
			local emptyLabel = Theme.Label(list, UDim2.new(1, -16, 0, 40), "No Estates owned yet -- buy some at the Shop!")
			emptyLabel.Position = UDim2.new(0, 8, 0, 8)
			emptyLabel.TextColor3 = Theme.Colors.TextSecondary
			emptyLabel.TextWrapped = true
		end
	end

	function handle.Render(inventory: { { Uid: number, ItemId: string } })
		currentInventory = inventory
		-- Common first, Luxury (the rarest tier) last -- matches
		-- RarityConfig.Order, same rank the roll odds/weights are defined by.
		table.sort(currentInventory, function(a, b)
			local itemA = ItemDatabase.GetItem(a.ItemId)
			local itemB = ItemDatabase.GetItem(b.ItemId)
			local rankA = itemA and rarityRank[itemA.Rarity] or math.huge
			local rankB = itemB and rarityRank[itemB.Rarity] or math.huge
			if rankA ~= rankB then
				return rankA < rankB
			end

			-- Within the same rarity: easiest-to-roll first, matching
			-- ItemDatabase.GetRollWeight (higher weight = more common).
			local weightA = itemA and ItemDatabase.GetRollWeight(itemA) or 0
			local weightB = itemB and ItemDatabase.GetRollWeight(itemB) or 0
			if weightA ~= weightB then
				return weightA > weightB
			end
			return a.Uid < b.Uid
		end)
		if selectedUid and not findEntry(selectedUid) then
			selectedUid = nil
		end
		refreshStatusLabel()
		-- The actual row-by-row rebuild (destroy + recreate one Frame per
		-- item) only matters while the panel is on screen -- with Auto
		-- Roll firing this on every single roll, rebuilding it unseen was
		-- pure wasted work that scaled with however large the inventory
		-- had grown. handle.Toggle catches up on open.
		if panel.Visible then
			refreshList()
			renderDetail()
		else
			pendingRerender = true
		end
	end

	equippedItemsUpdated.OnClientEvent:Connect(function(uids: { number })
		equippedUids = uids
		refreshStatusLabel()
		if panel.Visible then
			refreshList()
			renderDetail()
		else
			pendingRerender = true
		end
	end)

	assetUpdated.OnClientEvent:Connect(function(payload: { Owned: { [string]: boolean }, Equipped: { string }, SerialNumbers: { [string]: { number } }? })
		ownedAssetIds = payload.Owned
		equippedAssetIds = payload.Equipped
		mySerialNumbers = payload.SerialNumbers or {}
		if selectedAssetId and not ownedAssetIds[selectedAssetId] then
			selectedAssetId = nil
		end
		refreshStatusLabel()
		if panel.Visible then
			refreshList()
			renderDetail()
		else
			pendingRerender = true
		end
	end)

	estateExistenceCountsUpdated.OnClientEvent:Connect(function(counts: { [string]: number })
		estateExistenceCounts = counts
		if panel.Visible and currentTab == "Estates" then
			renderDetail()
		end
	end)

	function refreshStatusLabel()
		if currentTab == "Items" then
			statusLabel.Text = string.format("%d/%d equipped", #equippedUids, ItemDatabase.MaxEquipped)
		else
			statusLabel.Text = string.format("%d/%d equipped", #equippedAssetIds, AssetDatabase.MaxEquipped)
		end
	end

	local function highlightTabs()
		local isItems = currentTab == "Items"
		itemsTabButton.BackgroundColor3 = isItems and Theme.Colors.Accent or Theme.Colors.Surface
		itemsTabButton.TextColor3 = isItems and Color3.fromRGB(20, 20, 20) or Theme.Colors.TextPrimary
		estatesTabButton.BackgroundColor3 = (not isItems) and Theme.Colors.Accent or Theme.Colors.Surface
		estatesTabButton.TextColor3 = (not isItems) and Color3.fromRGB(20, 20, 20) or Theme.Colors.TextPrimary
	end

	local function switchTab(tab: string)
		if tab == currentTab then
			return
		end
		currentTab = tab
		selectedUid = nil
		selectedAssetId = nil
		detail.Visible = false
		backdrop.Visible = false
		highlightTabs()
		refreshStatusLabel()
		refreshList()
	end

	itemsTabButton.Activated:Connect(function()
		switchTab("Items")
	end)
	estatesTabButton.Activated:Connect(function()
		switchTab("Estates")
	end)

	highlightTabs()
	refreshStatusLabel()

	-- Original half-width Size/Position -- SetEstatesOnly below stretches
	-- estatesTabButton to fill the whole row when it's the only tab left,
	-- this is what puts it back once Roll Items returns.
	local estatesTabHalfSize = estatesTabButton.Size
	local estatesTabHalfPosition = estatesTabButton.Position
	local estatesTabFullSize = UDim2.new(1, -32, 0, 32)
	local estatesTabFullPosition = UDim2.new(0, 16, 0, 50)

	-- Endless Mode only shows Estates (per explicit request) -- hides the
	-- Roll Items tab entirely (nothing left to switch to), stretches the
	-- Estates tab button across the full row instead of leaving it at its
	-- normal half-width, and forces onto Estates if Items was still showing.
	-- MainUI.luau drives this off the same PortalTeleport signal everything
	-- else in Endless Mode uses.
	function handle.SetEstatesOnly(value: boolean)
		itemsTabButton.Visible = not value
		estatesTabButton.Size = value and estatesTabFullSize or estatesTabHalfSize
		estatesTabButton.Position = value and estatesTabFullPosition or estatesTabHalfPosition
		if value then
			switchTab("Estates")
		end
	end

	return handle
end

return InventoryPanel
