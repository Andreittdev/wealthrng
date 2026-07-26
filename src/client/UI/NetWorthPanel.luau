-- Read-only portfolio breakdown: Cash, rolled-items value, owned Assets,
-- owned Investments, and the Net Worth total. No Buy/Sell buttons here on
-- purpose -- purchasing Assets/Investments stays exclusively at the
-- physical stand (AssetShopPanel.luau); this is a viewer, not a second shop.
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
	contentLayout.Parent = content

	local currentInventory: { { Uid: number, ItemId: string } } = {}
	local ownedAssets: { [string]: boolean } = {}
	local equippedAssets: { string } = {}
	local currentInvestments: { { Uid: number, Id: string, PurchasedAt: number } } = {}
	local currentNetWorth = 0
	local currentCash = 0

	local function addRow(text: string, color: Color3?, isHeader: boolean?)
		local label = Theme.Label(content, UDim2.new(1, 0, 0, isHeader and 26 or 22), text, isHeader)
		if color then
			label.TextColor3 = color
		end
		return label
	end

	local function refresh()
		for _, child in content:GetChildren() do
			if child:IsA("TextLabel") or child:IsA("Frame") then
				child:Destroy()
			end
		end

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
					addRow(string.format("  %s: %s%s", asset.Name, NumberFormat.FormatCash(asset.Price), equipped and " (equipped)" or ""))
				end
			end
		end
		if not anyAssetOwned then
			addRow("None yet")
		else
			addRow("Assets Total: " .. NumberFormat.FormatCash(assetsTotal))
		end

		addRow("Investments", Theme.Colors.Accent, true)
		if #currentInvestments == 0 then
			addRow("None yet")
		else
			local now = os.time()
			local investmentsTotal = 0
			for _, entry in currentInvestments do
				local investment = InvestmentDatabase.GetInvestment(entry.Id)
				if investment then
					local value = InvestmentDatabase.ComputeCurrentValue(entry.Id, entry.PurchasedAt, now)
					investmentsTotal += value
					addRow(string.format("  %s: %s", investment.Name, NumberFormat.FormatCash(value)))
				end
			end
			addRow("Investments Total: " .. NumberFormat.FormatCash(investmentsTotal))
		end

		addRow("Net Worth: " .. NumberFormat.FormatCash(currentNetWorth), Theme.Colors.Accent, true)
	end

	local handle = {}
	handle.Frame = panel

	function handle.Toggle()
		panel.Visible = not panel.Visible
	end

	local inventoryUpdated = remotes:WaitForChild("InventoryUpdated")
	local assetUpdated = remotes:WaitForChild("AssetUpdated")
	local investmentUpdated = remotes:WaitForChild("InvestmentUpdated")
	local statsUpdated = remotes:WaitForChild("StatsUpdated")

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
