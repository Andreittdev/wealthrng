-- Physical shop, triggered by walking up to the single "SHOP" kiosk
-- MapBuilder builds (ProximityPrompt named "ShopPrompt" on its Counter
-- part). One shop, two categories inside it (Assets / Invest) switched via
-- tab buttons -- not two separate stands. Named AssetShopPanel (not
-- ShopPanel) since the sidebar's "Shop" button now means the VIP panel --
-- see ShopPanel.luau -- but this panel's own title still reads "Shop" to
-- the player.
--
-- Catalog-only: buying happens here as a grid of square item cards (no
-- Sell button, no bordered/"chenar" rows). Selling belongs to whatever
-- you're managing after the fact, not the shop you're browsing, so it
-- lives in NetWorthPanel instead (added separately).
--
-- Assets are bought outright (no upgrade ladder -- every type can be owned
-- at once), but only AssetDatabase.MaxEquipped of them actively earn income
-- -- Equip/Unequip on each owned card picks which.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local InvestmentDatabase = require(ReplicatedStorage.Modules.InvestmentDatabase)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local AssetShopPanel = {}

local CARD_SIZE = UDim2.new(0, 185, 0, 150)

function AssetShopPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local buyAsset = remotes:WaitForChild("BuyAsset")
	local equipAsset = remotes:WaitForChild("EquipAsset")
	local unequipAsset = remotes:WaitForChild("UnequipAsset")
	local assetUpdated = remotes:WaitForChild("AssetUpdated")
	local buyInvestment = remotes:WaitForChild("BuyInvestment")
	local investmentUpdated = remotes:WaitForChild("InvestmentUpdated")

	local ownedAssets: { [string]: boolean } = {}
	local equippedAssets: { string } = {}
	local currentInvestments: { { Uid: number, Id: string, PurchasedAt: number } } = {}
	local openCategory: string = "Assets"

	-- Anchored near the top (not dead-center) so it doesn't collide with
	-- RollPanel's bottom-anchored reveal window/button on shorter viewports.
	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 420, 0, 420), UDim2.new(0.5, -210, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	local titleLabel = Theme.Label(panel, UDim2.new(1, -120, 0, 32), "Shop", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	local closeButton = Theme.Button(panel, UDim2.new(0, 90, 0, 32), UDim2.new(1, -100, 0, 10), "Close")
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	-- Both created plain (accent=false, no baked-in gold gradient) --
	-- highlightTabs() toggles their flat BackgroundColor3/TextColor3 to show
	-- which is active, and a permanent gradient on one but not the other
	-- would look inconsistent once they swap states.
	local assetsTabButton = Theme.Button(panel, UDim2.new(0.5, -20, 0, 32), UDim2.new(0, 16, 0, 50), "Assets")
	local investTabButton = Theme.Button(panel, UDim2.new(0.5, -20, 0, 32), UDim2.new(0.5, 4, 0, 50), "Investments")

	local statusLabel = Theme.Label(panel, UDim2.new(1, -32, 0, 18), "")
	statusLabel.Position = UDim2.new(0, 16, 0, 86)
	statusLabel.TextColor3 = Theme.Colors.TextSecondary

	local content = Instance.new("ScrollingFrame")
	content.Size = UDim2.new(1, -32, 1, -126)
	content.Position = UDim2.new(0, 16, 0, 110)
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
		-- GuiObject (not just Frame) so the grid never accumulates leftover
		-- cards/buttons across re-renders -- clearing only Frames was the bug
		-- that let old "Sell" buttons pile up call after call.
		for _, child in content:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	-- Square item card: name, price, an optional detail line (income/s for
	-- Assets, "Owned: N" for Invest), and a footer slot for either a Buy/
	-- Equip/Unequip button or a plain status badge. Flat Surface square, no
	-- stroke/border -- reads as a catalog tile, not a bordered list row.
	local function createCard(order: number, name: string, priceText: string, detailText: string?): Frame
		local card = Instance.new("Frame")
		card.LayoutOrder = order
		card.BackgroundColor3 = Theme.Colors.Surface
		card.BackgroundTransparency = 0
		card.BorderSizePixel = 0
		card.Parent = content
		Theme.Round(card, UDim.new(0, 10))

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 10)
		padding.PaddingLeft = UDim.new(0, 10)
		padding.PaddingRight = UDim.new(0, 10)
		padding.PaddingBottom = UDim.new(0, 10)
		padding.Parent = card

		local nameLabel = Theme.Label(card, UDim2.new(1, 0, 0, 20), name, true)
		nameLabel.Position = UDim2.new(0, 0, 0, 0)

		local priceLabel = Theme.Label(card, UDim2.new(1, 0, 0, 20), priceText)
		priceLabel.Position = UDim2.new(0, 0, 0, 24)
		priceLabel.TextColor3 = Theme.Colors.Accent

		if detailText then
			local detailLabel = Theme.Label(card, UDim2.new(1, 0, 0, 18), detailText)
			detailLabel.Position = UDim2.new(0, 0, 0, 46)
			detailLabel.TextColor3 = Theme.Colors.Success
		end

		return card
	end

	local function addActionButton(card: Frame, text: string, accent: boolean, onClick: () -> ())
		local button = Theme.Button(card, UDim2.new(1, 0, 0, 30), UDim2.new(0, 0, 1, -30), text, accent)
		button.Activated:Connect(onClick)
	end

	-- Plain (non-interactive) status label instead of a disabled button --
	-- a greyed-out TextButton still hover-highlights, which reads as
	-- clickable when it isn't.
	local function addStatusBadge(card: Frame, text: string, color: Color3)
		local badge = Theme.Label(card, UDim2.new(1, 0, 0, 30), text, true)
		badge.Position = UDim2.new(0, 0, 1, -30)
		badge.TextColor3 = color
		badge.TextXAlignment = Enum.TextXAlignment.Center
	end

	local function renderAssets()
		clearContent()

		local equippedCount = #equippedAssets
		statusLabel.Text = string.format("Equipped: %d/%d", equippedCount, AssetDatabase.MaxEquipped)

		local order = 0
		for id, asset in AssetDatabase.GetAllAssets() do
			order += 1
			local card = createCard(order, asset.Name, NumberFormat.FormatCash(asset.Price), "+" .. NumberFormat.FormatCash(asset.IncomePerMinute) .. "/min")

			local owned = ownedAssets[id]
			local equipped = table.find(equippedAssets, id) ~= nil

			if not owned then
				addActionButton(card, "Buy", true, function()
					buyAsset:FireServer(id)
				end)
			elseif equipped then
				addActionButton(card, "Unequip", false, function()
					unequipAsset:FireServer(id)
				end)
			else
				addActionButton(card, "Equip", true, function()
					equipAsset:FireServer(id)
				end)
			end
		end
	end

	local function countOwnedInvestments(id: string): number
		local count = 0
		for _, entry in currentInvestments do
			if entry.Id == id then
				count += 1
			end
		end
		return count
	end

	local function renderInvestments()
		clearContent()
		statusLabel.Text = ""

		local order = 0
		for id, investment in InvestmentDatabase.GetAllInvestments() do
			order += 1
			local owned = countOwnedInvestments(id)
			local card = createCard(order, investment.Name, NumberFormat.FormatCash(investment.Price), owned > 0 and string.format("Owned: %d", owned) or nil)
			addActionButton(card, "Buy", true, function()
				buyInvestment:FireServer(id)
			end)
		end
	end

	local function highlightTabs()
		local isAssets = openCategory == "Assets"
		assetsTabButton.BackgroundColor3 = isAssets and Theme.Colors.Accent or Theme.Colors.Surface
		assetsTabButton.TextColor3 = isAssets and Color3.fromRGB(20, 20, 20) or Theme.Colors.TextPrimary
		investTabButton.BackgroundColor3 = (not isAssets) and Theme.Colors.Accent or Theme.Colors.Surface
		investTabButton.TextColor3 = (not isAssets) and Color3.fromRGB(20, 20, 20) or Theme.Colors.TextPrimary
	end

	local function refresh()
		if openCategory == "Assets" then
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

	assetsTabButton.Activated:Connect(function()
		switchTab("Assets")
	end)
	investTabButton.Activated:Connect(function()
		switchTab("Invest")
	end)

	assetUpdated.OnClientEvent:Connect(function(payload: { Owned: { [string]: boolean }, Equipped: { string } })
		ownedAssets = payload.Owned
		equippedAssets = payload.Equipped
		refresh()
	end)

	investmentUpdated.OnClientEvent:Connect(function(investments: { { Uid: number, Id: string, PurchasedAt: number } })
		currentInvestments = investments
		refresh()
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player ~= Players.LocalPlayer or prompt.Name ~= "ShopPrompt" then
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

return AssetShopPanel
