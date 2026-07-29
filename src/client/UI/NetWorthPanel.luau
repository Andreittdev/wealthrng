-- Portfolio breakdown: Cash, rolled-items value, owned Assets, owned
-- Investments, and the Net Worth total -- plus a Sell button on every
-- owned Asset/Investment row. Buying still only happens at the physical
-- stand (AssetShopPanel.luau); this is where you liquidate what you
-- already bought, with a confirmation popup first (same shared-instance
-- pattern as InventoryPanel's sell confirm) since a sell can be a very
-- large amount of value to lose to a misclick. The quantity-to-sell input
-- for Investments lives IN that popup (a full-size, non-scrolling
-- overlay), not as a tiny textbox squeezed into the scrolling row itself
-- -- much more reliable to tap/type into, especially on phones.
--
-- Computes the item/asset/investment breakdown client-side from data
-- already flowing to the client (InventoryUpdated/AssetUpdated/
-- InvestmentUpdated) via the shared databases -- the Net Worth *total* still
-- comes from StatsUpdated (server-authoritative), never re-derived.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local InvestmentDatabase = require(ReplicatedStorage.Modules.InvestmentDatabase)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local NetWorthPanel = {}

function NetWorthPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local inventoryUpdated = remotes:WaitForChild("InventoryUpdated")
	local assetUpdated = remotes:WaitForChild("AssetUpdated")
	local investmentUpdated = remotes:WaitForChild("InvestmentUpdated")
	local statsUpdated = remotes:WaitForChild("StatsUpdated")
	local sellAsset = remotes:WaitForChild("SellAsset")
	local sellInvestment = remotes:WaitForChild("SellInvestment")

	-- Anchored near the top (not dead-center) so it doesn't collide with
	-- RollPanel's bottom-anchored reveal window/button on shorter viewports.
	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 380, 0, 380), UDim2.new(0.5, -190, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	local titleLabel = Theme.Label(panel, UDim2.new(1, -120, 0, 32), "Net Worth", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	local closeButton = Theme.Button(panel, UDim2.new(0, 90, 0, 32), UDim2.new(1, -100, 0, 10), "Close")
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	local content = Instance.new("ScrollingFrame")
	content.Size = UDim2.new(1, -32, 1, -70)
	content.Position = UDim2.new(0, 16, 0, 56)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 6
	content.ScrollBarImageColor3 = Theme.Colors.Accent
	content.Parent = panel

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.Padding = UDim.new(0, 6)
	-- Explicit, not left at whatever the engine defaults to -- rows were
	-- rendering out of insertion order (an Investment row jumping above
	-- Cash) even after every row got an explicit LayoutOrder, because
	-- SortOrder itself was never set to actually sort BY LayoutOrder.
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Parent = content

	-- ===== Sell confirmation popup -- one shared instance, reused for
	-- whichever Asset/Investment row's Sell button was last clicked.
	-- confirmQuantityBox only shows up for Investments (Assets are always
	-- exactly 1, nothing to type). =====
	local confirmPopup = Instance.new("Frame")
	confirmPopup.Size = UDim2.new(0, 300, 0, 210)
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

	local confirmLabel = Theme.Label(confirmPopup, UDim2.new(1, -24, 0, 56), "Are you sure you want to sell this?", true)
	confirmLabel.Position = UDim2.new(0, 12, 0, 12)
	confirmLabel.TextXAlignment = Enum.TextXAlignment.Center
	confirmLabel.TextWrapped = true

	local confirmLabelPadding = Instance.new("UIPadding")
	confirmLabelPadding.PaddingTop = UDim.new(0, 6)
	confirmLabelPadding.PaddingBottom = UDim.new(0, 6)
	confirmLabelPadding.Parent = confirmLabel

	local confirmQuantityBox = Instance.new("TextBox")
	confirmQuantityBox.Size = UDim2.new(0, 120, 0, 34)
	confirmQuantityBox.AnchorPoint = Vector2.new(0.5, 0)
	confirmQuantityBox.Position = UDim2.new(0.5, 0, 0, 70)
	confirmQuantityBox.BackgroundColor3 = Theme.Colors.Surface
	confirmQuantityBox.BorderSizePixel = 0
	confirmQuantityBox.Text = ""
	confirmQuantityBox.TextColor3 = Theme.Colors.TextPrimary
	confirmQuantityBox.Font = Theme.Fonts.Body
	confirmQuantityBox.TextScaled = true
	confirmQuantityBox.ClearTextOnFocus = false

	local confirmQuantityPadding = Instance.new("UIPadding")
	confirmQuantityPadding.PaddingTop = UDim.new(0, 8)
	confirmQuantityPadding.Parent = confirmQuantityBox
	confirmQuantityBox.Visible = false
	confirmQuantityBox.ZIndex = 21
	confirmQuantityBox.Parent = confirmPopup
	Theme.Round(confirmQuantityBox, UDim.new(0, 6))
	Theme.Stroke(confirmQuantityBox, Color3.fromRGB(255, 215, 140), 1)

	local yesButton = Theme.Button(confirmPopup, UDim2.new(0, 68, 0, 68), UDim2.new(0.5, -78, 1, -84), "Yes")
	yesButton.BackgroundColor3 = Theme.Colors.Success

	local noButton = Theme.Button(confirmPopup, UDim2.new(0, 68, 0, 68), UDim2.new(0.5, 10, 1, -84), "No")
	noButton.BackgroundColor3 = Theme.Colors.Danger

	-- Shrinks the Yes/No text a bit without shrinking the buttons
	-- themselves (still a full 68x68 tap target) -- TextScaled fills
	-- whatever space is left after padding.
	for _, button in { yesButton, noButton } do
		local buttonPadding = Instance.new("UIPadding")
		buttonPadding.PaddingTop = UDim.new(0.18, 0)
		buttonPadding.PaddingBottom = UDim.new(0.18, 0)
		buttonPadding.PaddingLeft = UDim.new(0.12, 0)
		buttonPadding.PaddingRight = UDim.new(0.12, 0)
		buttonPadding.Parent = button
	end

	local pendingSell: { MaxQuantity: number?, Fire: (number) -> () }? = nil

	local function hideConfirm()
		confirmPopup.Visible = false
		confirmQuantityBox.Visible = false
		pendingSell = nil
	end

	yesButton.Activated:Connect(function()
		if pendingSell then
			local quantity = 1
			if pendingSell.MaxQuantity then
				quantity = pendingSell.MaxQuantity
				local parsed = tonumber(confirmQuantityBox.Text)
				if parsed then
					quantity = math.clamp(math.floor(parsed), 1, pendingSell.MaxQuantity)
				end
			end
			pendingSell.Fire(quantity)
		end
		hideConfirm()
	end)
	noButton.Activated:Connect(hideConfirm)

	-- `maxQuantity` nil = Assets (always exactly 1, no input shown).
	-- Otherwise shows the quantity box pre-filled with the full owned
	-- amount -- change it (e.g. "100" -> "50") to only sell part of it.
	local function requestSell(maxQuantity: number?, fire: (number) -> ())
		pendingSell = { MaxQuantity = maxQuantity, Fire = fire }
		if maxQuantity then
			confirmLabel.Text = string.format("Sell how many? (max %d)", maxQuantity)
			confirmQuantityBox.Text = tostring(maxQuantity)
			confirmQuantityBox.Visible = true
		else
			confirmLabel.Text = "Are you sure you want to sell this?"
			confirmQuantityBox.Visible = false
		end
		confirmPopup.Visible = true
	end

	local currentInventory: { { Uid: number, ItemId: string } } = {}
	local ownedAssets: { [string]: boolean } = {}
	local equippedAssets: { string } = {}
	local currentInvestments: { { Uid: number, Id: string, PurchasedAt: number, Quantity: number } } = {}
	local currentNetWorth = 0
	local currentCash = 0

	-- UIListLayout with SortOrder left at its default doesn't reliably sort
	-- by insertion order once children have equal (unset) LayoutOrder --
	-- rows could render out of sequence (an Investment row jumping above
	-- Cash, etc). Every row gets an explicit, incrementing LayoutOrder;
	-- `rowOrder` resets to 0 at the top of every refresh() call.
	local rowOrder = 0

	local function addRow(text: string, color: Color3?, isHeader: boolean?)
		rowOrder += 1
		local label = Theme.Label(content, UDim2.new(1, 0, 0, isHeader and 26 or 22), text, isHeader)
		label.LayoutOrder = rowOrder
		if color then
			label.TextColor3 = color
		end
		return label
	end

	-- Same as addRow but with a Sell button on the right -- clicking it
	-- always opens the shared confirm popup (see requestSell); `onSell`
	-- only runs after the popup's Yes is clicked, called with the final
	-- quantity (always 1 when maxQuantity is nil).
	local function addOwnedRow(text: string, maxQuantity: number?, onSell: (number) -> ())
		rowOrder += 1
		local row = Instance.new("Frame")
		row.LayoutOrder = rowOrder
		row.Size = UDim2.new(1, 0, 0, 24)
		row.BackgroundTransparency = 1
		row.Parent = content

		local sellButton = Theme.Button(row, UDim2.new(0, 50, 0, 20), UDim2.new(1, -50, 0.5, -10), "Sell")
		sellButton.BackgroundColor3 = Theme.Colors.Danger
		sellButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		sellButton.Activated:Connect(function()
			requestSell(maxQuantity, onSell)
		end)

		if maxQuantity then
			local quantityLabel = Theme.Label(row, UDim2.new(0, 46, 1, 0), "x" .. maxQuantity)
			quantityLabel.Position = UDim2.new(1, -106, 0, 0)
			quantityLabel.TextColor3 = Theme.Colors.TextSecondary
			quantityLabel.TextXAlignment = Enum.TextXAlignment.Right
		end

		local label = Theme.Label(row, UDim2.new(1, maxQuantity and -106 or -56, 1, 0), text)

		return row
	end

	local function refresh()
		for _, child in content:GetChildren() do
			if child:IsA("TextLabel") or child:IsA("Frame") then
				child:Destroy()
			end
		end
		rowOrder = 0

		addRow("Cash: " .. NumberFormat.FormatCash(currentCash), Theme.Colors.Success)

		local itemsValue = 0
		for _, entry in currentInventory do
			local item = ItemDatabase.GetItem(entry.ItemId)
			if item then
				itemsValue += item.Value
			end
		end
		addRow(string.format("Rolled Items: %s (%d owned)", NumberFormat.FormatCash(itemsValue), #currentInventory))

		addRow("Assets", Theme.Colors.Accent, true)
		local anyAssetOwned = false
		local assetsTotal = 0
		for id, owned in ownedAssets do
			if owned then
				local asset = AssetDatabase.GetAsset(id)
				if asset then
					anyAssetOwned = true
					assetsTotal += asset.Price
					local equipped = table.find(equippedAssets, id) ~= nil
					addOwnedRow(string.format("  %s: %s%s", asset.Name, NumberFormat.FormatCash(asset.Price), equipped and " (equipped)" or ""), nil, function(_)
						sellAsset:FireServer(id)
					end)
				end
			end
		end
		if not anyAssetOwned then
			addRow("None yet")
		else
			addRow("Assets Total: " .. NumberFormat.FormatCash(assetsTotal), Color3.fromRGB(90, 160, 255))
		end

		addRow("Investments", Theme.Colors.Accent, true)
		if #currentInvestments == 0 then
			addRow("None yet")
		else
			local now = os.time()
			local investmentsTotal = 0

			-- One row per investment TYPE, not one per purchase batch --
			-- buying the same investment at different times (different
			-- PurchasedAt, so they can't be merged into one server-side
			-- entry) would otherwise list it multiple times. Batches are
			-- kept (not just a flat Uid list) so a partial sell (typing
			-- e.g. 50 out of 100 into the confirm popup) knows how many
			-- units to draw from each underlying entry, oldest first.
			local order: { string } = {}
			local aggregates: { [string]: { Quantity: number, Value: number, Batches: { { Uid: number, Quantity: number } } } } = {}
			for _, entry in currentInvestments do
				local investment = InvestmentDatabase.GetInvestment(entry.Id)
				if investment then
					local value = InvestmentDatabase.ComputeEntryValue(entry, now)
					investmentsTotal += value

					local aggregate = aggregates[entry.Id]
					if not aggregate then
						aggregate = { Quantity = 0, Value = 0, Batches = {} }
						aggregates[entry.Id] = aggregate
						table.insert(order, entry.Id)
					end
					local entryQuantity = entry.Quantity or 1
					aggregate.Quantity += entryQuantity
					aggregate.Value += value
					table.insert(aggregate.Batches, { Uid = entry.Uid, Quantity = entryQuantity })
				end
			end

			for _, id in order do
				local investment = InvestmentDatabase.GetInvestment(id)
				local aggregate = aggregates[id]
				addOwnedRow(string.format("  %s: %s", investment.Name, NumberFormat.FormatCash(aggregate.Value)), aggregate.Quantity, function(sellQuantity)
					local remaining = sellQuantity
					for _, batch in aggregate.Batches do
						if remaining <= 0 then
							break
						end
						local take = math.min(remaining, batch.Quantity)
						sellInvestment:FireServer(batch.Uid, take)
						remaining -= take
					end
				end)
			end

			addRow("Investments Total: " .. NumberFormat.FormatCash(investmentsTotal), Color3.fromRGB(90, 160, 255))
		end

		addRow("Net Worth: " .. NumberFormat.FormatCash(currentNetWorth), Theme.Colors.Accent, true)
	end

	local handle = {}
	handle.Frame = panel

	function handle.Toggle()
		panel.Visible = not panel.Visible
	end

	inventoryUpdated.OnClientEvent:Connect(function(inventory)
		currentInventory = inventory
		refresh()
	end)

	assetUpdated.OnClientEvent:Connect(function(payload: { Owned: { [string]: boolean }, Equipped: { string } })
		ownedAssets = payload.Owned
		equippedAssets = payload.Equipped
		refresh()
	end)

	investmentUpdated.OnClientEvent:Connect(function(investments)
		currentInvestments = investments
		refresh()
	end)

	statsUpdated.OnClientEvent:Connect(function(stats)
		currentCash = stats.Cash
		currentNetWorth = stats.NetWorth
		refresh()
	end)

	refresh()

	return handle
end

return NetWorthPanel
