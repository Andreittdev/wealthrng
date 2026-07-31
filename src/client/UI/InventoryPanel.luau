-- Centered modal, master-detail layout: a simple scrollable list (name +
-- roll chance per row) fills the whole panel. Clicking a row doesn't push
-- the list aside -- it pops a detail square on top of it (image, name,
-- chance, rarity, Equip/Sell), dismissed via its X button or by clicking
-- the dimmed backdrop behind it.
--
-- Items only earn IncomePerSecond while equipped -- only ItemDatabase.
-- MaxEquipped (currently 1) can be equipped at once, so tapping Equip on
-- the selected item just swaps out whichever one was equipped before
-- (server-side swap in InventoryManager.Equip, this panel doesn't need to
-- know).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
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

	local currentInventory: { { Uid: number, ItemId: string } } = {}
	local equippedUids: { number } = {}
	local selectedUid: number? = nil

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

	-- ===== List, name + chance per row -- takes the full content width, no
	-- space reserved for the detail pane (that's an overlay now, see below). =====
	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -32, 1, -72)
	list.Position = UDim2.new(0, 16, 0, 56)
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

	-- Dims the list and catches "click outside" to dismiss the detail
	-- overlay -- sits between the list and the detail pane in ZIndex.
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.ZIndex = 5
	backdrop.Visible = false
	backdrop.Parent = panel

	-- ===== Detail pane -- a floating square that appears ON TOP of the
	-- list (centered over it) only while an item is selected, instead of
	-- reserving a permanently-visible column next to the list. =====
	local detail = Instance.new("Frame")
	detail.Size = UDim2.new(0, 320, 0, 404)
	detail.AnchorPoint = Vector2.new(0.5, 0.5)
	detail.Position = UDim2.new(0.5, 0, 0.5, 20)
	detail.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	detail.BackgroundTransparency = 0
	detail.BorderSizePixel = 0
	detail.ZIndex = 6
	detail.Visible = false
	detail.Parent = panel
	Theme.Round(detail, UDim.new(0, 8))
	local detailStroke = Theme.Stroke(detail, Color3.fromRGB(110, 110, 122), 2)
	detailStroke.Transparency = 0
	Theme.Shadow(detail)

	local detailCloseButton = Theme.Button(detail, UDim2.new(0, 32, 0, 32), UDim2.new(1, -44, 0, 12), "X")
	detailCloseButton.ZIndex = 7

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
	Theme.Shadow(confirmPopup)

	local confirmLabel = Theme.Label(confirmPopup, UDim2.new(1, -24, 0, 56), "Are you sure you want to sell this item?", true)
	confirmLabel.Position = UDim2.new(0, 12, 0, 12)
	confirmLabel.TextXAlignment = Enum.TextXAlignment.Center
	confirmLabel.TextWrapped = true

	-- Square, not the usual wide rectangle -- Yes/No as two equal-sized tiles.
	local yesButton = Theme.Button(confirmPopup, UDim2.new(0, 68, 0, 68), UDim2.new(0.5, -78, 1, -84), "Yes")
	yesButton.BackgroundColor3 = Theme.Colors.Success

	local noButton = Theme.Button(confirmPopup, UDim2.new(0, 68, 0, 68), UDim2.new(0.5, 10, 1, -84), "No")
	noButton.BackgroundColor3 = Theme.Colors.Danger

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
	local renderDetail

	local handle = {}
	handle.Frame = panel

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
			renderList()
			renderDetail()
		end
	end

	yesButton.Activated:Connect(function()
		if pendingSellUid then
			sellItem:FireServer(pendingSellUid)
			if selectedUid == pendingSellUid then
				selectedUid = nil
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
		detail.Visible = false
		backdrop.Visible = false
		renderList()
	end

	detailCloseButton.Activated:Connect(closeDetail)
	backdrop.Activated:Connect(closeDetail)

	function renderDetail()
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

		detailEquipButton.Text = isEquipped and "Unequip" or "Equip"
		detailEquipButton.BackgroundColor3 = isEquipped and Theme.Colors.Surface or Theme.Colors.Accent
		detailEquipButton.TextColor3 = isEquipped and Theme.Colors.TextPrimary or Color3.fromRGB(20, 20, 20)
	end

	detailEquipButton.Activated:Connect(function()
		if not selectedUid then
			return
		end
		local isEquipped = table.find(equippedUids, selectedUid) ~= nil
		if isEquipped then
			unequipItem:FireServer(selectedUid)
		else
			equipItem:FireServer(selectedUid)
		end
	end)

	detailSellButton.Activated:Connect(function()
		if selectedUid then
			requestSell(selectedUid)
		end
	end)

	function renderList()
		clearList()

		for order, entry in currentInventory do
			local item = ItemDatabase.GetItem(entry.ItemId)
			if not item then
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

			local button = Instance.new("TextButton")
			button.Size = UDim2.new(1, 0, 1, 0)
			button.BackgroundTransparency = 1
			button.Text = ""
			button.Parent = row
			button.Activated:Connect(function()
				selectedUid = entry.Uid
				renderList()
				renderDetail()
			end)
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
		statusLabel.Text = string.format("%d/%d equipped", #equippedUids, ItemDatabase.MaxEquipped)
		-- The actual row-by-row rebuild (destroy + recreate one Frame per
		-- item) only matters while the panel is on screen -- with Auto
		-- Roll firing this on every single roll, rebuilding it unseen was
		-- pure wasted work that scaled with however large the inventory
		-- had grown. handle.Toggle catches up on open.
		if panel.Visible then
			renderList()
			renderDetail()
		else
			pendingRerender = true
		end
	end

	equippedItemsUpdated.OnClientEvent:Connect(function(uids: { number })
		equippedUids = uids
		statusLabel.Text = string.format("%d/%d equipped", #equippedUids, ItemDatabase.MaxEquipped)
		if panel.Visible then
			renderList()
			renderDetail()
		else
			pendingRerender = true
		end
	end)

	return handle
end

return InventoryPanel
