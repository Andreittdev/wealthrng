-- "Premium Shop" mutat aici, in Store-ul principal (cerut explicit de user,
-- dupa modelul altui joc: un panou cu tab-uri jos -- Game Passes/Cash/Eggs
-- -- si randuri COMPACTE (iconita + nume + pret/Owned), fara text lung de
-- perks). Inlocuieste StoreGui.rbxmx (dezactivat, ramas doar ca fisier
-- mort) -- vezi MainHUD.rbxmx, care acum deschide "MainShopGui" (ScreenGui-ul
-- asta) in loc de "StoreGui".
--
-- Cash Packs si Premium Egg sunt Developer Products (repetabile) -- vezi
-- Economy.CashPacks / Economy.PremiumEgg in EconomyConfig.luau si
-- PremiumPurchaseManager.server.luau (singurul ProcessReceipt din joc).

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

local FONT_DISPLAY = Enum.Font.Bangers
local FONT_BODY = Enum.Font.FredokaOne

local PANEL_BG = Color3.fromRGB(42, 40, 48)
local HEADER_BG = Color3.fromRGB(58, 55, 64)
local ROW_ICON_BG = Color3.fromRGB(214, 160, 40)
local ROW_INFO_BG = Color3.fromRGB(120, 78, 16)
local PRICE_COLOR = Color3.fromRGB(120, 235, 150)
local OWNED_COLOR = Color3.fromRGB(100, 235, 140)

local TABS = {
	{Key = "GamePasses", Label = "Game\nPasses", Color = Color3.fromRGB(230, 150, 40)},
	{Key = "Cash", Label = "Cash", Color = Color3.fromRGB(70, 150, 230)},
	{Key = "Eggs", Label = "Eggs", Color = Color3.fromRGB(210, 200, 40)}
}

-- "$15,000" in loc de "Tiny Cash Pack" -- cerut explicit, jucatorul vrea sa
-- vada direct suma exacta, nu un nume de marime (Tiny/Small/...).
local function formatMoney(amount)
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	formatted = formatted:gsub("^,", "")
	return "$" .. formatted
end

-- Toate gamepass-urile din joc -- pretul ramane mereu vizibil (chiar si pe
-- cele detinute), dar cele detinute mai arata si "OWNED" sub nume.
-- Attribute = nil inseamna "nu are attribute dedicat, verificam ownership-ul
-- live" (cazul Inventory Pass -- vezi NPCManager.server.luau, care il
-- verifica la fel, live, fara attribute). Starter Pack scos intentionat --
-- nu apare in Shop (are propriul flow separat, StarterPackShop.client.luau).
local GAME_PASSES = {
	{Name = "VIP", Id = 1898198234, Attribute = "IsVIP", Icon = "rbxassetid://74375751325744"},
	{Name = "More NPC Speed", Id = Economy.SpeedPass.GamePassId, Attribute = "HasSpeedPass", Icon = "rbxassetid://111045527678748"},
	{Name = "Auto Sell", Id = Economy.AutoSellPass.GamePassId, Attribute = "HasAutoSellPass", Emoji = "💰"},
	{Name = "+100 Inventory Space", Id = 1899734044, Attribute = nil, Icon = "rbxassetid://71016405354553"}
}

local function computeIsMobile()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.X < 700 or viewport.Y < 500
end

-- Pretul REAL, luat de la Roblox (nu valorile afisate in EconomyConfig, care
-- pot fi incorecte -- acelasi motiv/tipar ca in vechiul StoreGui).
local passPriceCache = {}

local function getPassPrice(passId)
	if passPriceCache[passId] ~= nil then
		return passPriceCache[passId]
	end

	local price = nil
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
	end)

	if ok and info and info.PriceInRobux then
		price = info.PriceInRobux
	end

	passPriceCache[passId] = price
	return price
end

-- Cache pentru pass-urile FARA attribute dedicat (doar Inventory Pass) --
-- altfel interogam Marketplace-ul live la fiecare deschidere a tab-ului
-- Game Passes, degeaba (ownership-ul nu se schimba decat dupa o achizitie,
-- caz in care oricum re-verificam explicit mai jos).
local ownedPassCache = {}

local function isPassOwned(entry)
	if entry.Attribute then
		return player:GetAttribute(entry.Attribute) == true
	end

	if ownedPassCache[entry.Id] ~= nil then
		return ownedPassCache[entry.Id]
	end

	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, entry.Id)
	end)

	local result = ok and owns
	ownedPassCache[entry.Id] = result
	return result
end

-- ================= ScreenGui + MainFrame =================
-- ScreenGui>MainFrame -- acelasi tipar pe care MainHUD.rbxmx il astepta
-- deja de la vechiul StoreGui (doar Enabled/Visible, nimic altceva).

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainShopGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Enabled = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.BackgroundColor3 = PANEL_BG
mainFrame.Visible = false
mainFrame.Parent = screenGui

Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 18)

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = Color3.fromRGB(20, 18, 24)
mainStroke.Thickness = 3
mainStroke.Parent = mainFrame

local function applyLayout()
	if computeIsMobile() then
		mainFrame.Size = UDim2.new(0.92, 0, 0.84, 0)
	else
		mainFrame.Size = UDim2.new(0, 560, 0, 620)
	end
end

applyLayout()

-- ================= Header =================

local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 64)
header.BackgroundColor3 = HEADER_BG
header.Parent = mainFrame

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 18)
headerCorner.Parent = header

-- Colturile de jos ale header-ului trebuie drepte (nu rotunjite), altfel
-- se vede un gol intre el si restul panoului -- acoperim colturile de jos
-- cu un Frame simplu, fara UICorner, lipit direct dedesubt.
local headerMask = Instance.new("Frame")
headerMask.BackgroundColor3 = HEADER_BG
headerMask.BorderSizePixel = 0
headerMask.Position = UDim2.new(0, 0, 1, -18)
headerMask.Size = UDim2.new(1, 0, 0, 18)
headerMask.ZIndex = 0
headerMask.Parent = header

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 20, 0, 8)
titleLabel.Size = UDim2.new(1, -80, 1, -16)
titleLabel.Text = "GAME PASSES"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextStrokeColor3 = Color3.fromRGB(20, 18, 24)
titleLabel.TextStrokeTransparency = 0
titleLabel.Font = FONT_DISPLAY
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = header

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -14, 0.5, 0)
closeButton.Size = UDim2.new(0, 40, 0, 40)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Font = FONT_DISPLAY
closeButton.TextScaled = true
closeButton.Parent = header

Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0.3, 0)

-- ================= Continut (ScrollingFrame) =================

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "RowsScroll"
scroll.Position = UDim2.new(0, 14, 0, 76)
scroll.Size = UDim2.new(1, -28, 1, -148)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = mainFrame

local scrollLayout = Instance.new("UIListLayout")
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollLayout.Padding = UDim.new(0, 8)
scrollLayout.Parent = scroll

-- ================= Tab bar (jos) =================

local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.AnchorPoint = Vector2.new(0, 1)
tabBar.Position = UDim2.new(0, 14, 1, -14)
tabBar.Size = UDim2.new(1, -28, 0, 56)
tabBar.BackgroundTransparency = 1
tabBar.Parent = mainFrame

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Padding = UDim.new(0, 8)
tabLayout.Parent = tabBar

local tabButtons = {}

for _, tab in ipairs(TABS) do
	local tabButton = Instance.new("TextButton")
	tabButton.Name = tab.Key .. "Tab"
	tabButton.Size = UDim2.new(1 / #TABS, -6, 1, 0)
	tabButton.BackgroundColor3 = tab.Color
	tabButton.Text = tab.Label
	tabButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	tabButton.TextStrokeColor3 = Color3.fromRGB(20, 18, 24)
	tabButton.TextStrokeTransparency = 0
	tabButton.Font = FONT_DISPLAY
	tabButton.TextScaled = true
	tabButton.Parent = tabBar

	Instance.new("UICorner", tabButton).CornerRadius = UDim.new(0.18, 0)

	local tabStroke = Instance.new("UIStroke")
	tabStroke.Color = Color3.fromRGB(20, 18, 24)
	tabStroke.Thickness = 2
	tabStroke.Parent = tabButton

	tabButtons[tab.Key] = tabButton
end

-- ================= Randuri compacte (iconita + nume/pret) =================

local function buildRow(config)
	local row = Instance.new("Frame")
	row.Name = config.Name .. "Row"
	row.LayoutOrder = config.LayoutOrder or 0
	row.Size = UDim2.new(1, 0, 0, 64)
	row.BackgroundTransparency = 1
	row.Parent = scroll

	local iconBox = Instance.new("Frame")
	iconBox.Name = "IconBox"
	iconBox.Size = UDim2.new(0, 64, 0, 64)
	iconBox.BackgroundColor3 = ROW_ICON_BG
	iconBox.Parent = row

	Instance.new("UICorner", iconBox).CornerRadius = UDim.new(0.2, 0)

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Color = Color3.fromRGB(20, 18, 24)
	iconStroke.Thickness = 2
	iconStroke.Parent = iconBox

	if config.IconAsset then
		local icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Size = UDim2.new(0.72, 0, 0.72, 0)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Image = config.IconAsset
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = iconBox
	else
		local emojiLabel = Instance.new("TextLabel")
		emojiLabel.BackgroundTransparency = 1
		emojiLabel.Size = UDim2.new(1, 0, 1, 0)
		emojiLabel.Text = config.IconEmoji or "?"
		emojiLabel.TextScaled = true
		emojiLabel.Font = FONT_BODY
		emojiLabel.Parent = iconBox
	end

	local infoBox = Instance.new(config.OnClick and "TextButton" or "Frame")
	infoBox.Name = "InfoBox"
	infoBox.Position = UDim2.new(0, 72, 0, 0)
	infoBox.Size = UDim2.new(1, -72, 1, 0)
	infoBox.BackgroundColor3 = ROW_INFO_BG
	if infoBox:IsA("TextButton") then
		infoBox.Text = ""
		infoBox.AutoButtonColor = false
	end
	infoBox.Parent = row

	Instance.new("UICorner", infoBox).CornerRadius = UDim.new(0.14, 0)

	local infoStroke = Instance.new("UIStroke")
	infoStroke.Color = Color3.fromRGB(20, 18, 24)
	infoStroke.Thickness = 2
	infoStroke.Parent = infoBox

	-- Numele (+ "OWNED" dedesubt, daca e cazul) sta in stanga; pretul sta
	-- ANCORAT in dreapta de tot, mereu vizibil -- chiar si pe pass-urile
	-- detinute deja (cerut explicit).
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 14, 0, 4)
	nameLabel.Size = config.Owned and UDim2.new(0.6, -14, 0.5, 0) or UDim2.new(0.6, -14, 1, -8)
	nameLabel.Text = config.Name
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Font = FONT_DISPLAY
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.Parent = infoBox

	if config.Owned then
		local ownedLabel = Instance.new("TextLabel")
		ownedLabel.Name = "OwnedLabel"
		ownedLabel.BackgroundTransparency = 1
		ownedLabel.Position = UDim2.new(0, 14, 0.5, 0)
		ownedLabel.Size = UDim2.new(0.6, -14, 0.5, -4)
		ownedLabel.Text = "OWNED"
		ownedLabel.TextColor3 = OWNED_COLOR
		ownedLabel.Font = FONT_DISPLAY
		ownedLabel.TextScaled = true
		ownedLabel.TextXAlignment = Enum.TextXAlignment.Left
		ownedLabel.Parent = infoBox
	end

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "PriceLabel"
	priceLabel.AnchorPoint = Vector2.new(1, 0.5)
	priceLabel.Position = UDim2.new(1, -14, 0.5, 0)
	priceLabel.Size = UDim2.new(0.34, 0, 0.7, 0)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Text = config.PriceText
	priceLabel.TextColor3 = PRICE_COLOR
	priceLabel.Font = FONT_DISPLAY
	priceLabel.TextScaled = true
	priceLabel.TextXAlignment = Enum.TextXAlignment.Right
	priceLabel.Parent = infoBox

	if config.OnClick then
		infoBox.Activated:Connect(config.OnClick)
	end

	return row
end

local function clearScroll()
	-- Sterge TOT ce nu e UIListLayout-ul insusi -- nu doar Frame-uri.
	-- OddsLabel (pe tab-ul Eggs) e un TextLabel, nu un Frame -- ramanea
	-- nesters la fiecare schimbare de tab, adunandu-se la infinit (bug
	-- real, gasit la testare).
	for _, child in ipairs(scroll:GetChildren()) do
		if child ~= scrollLayout then
			child:Destroy()
		end
	end
end

local function buildGamePassesTab()
	-- Pretul ramane mereu vizibil, in dreapta -- si pe pass-urile detinute,
	-- care in plus arata "OWNED" sub nume (cerut explicit).
	for i, entry in ipairs(GAME_PASSES) do
		local price = getPassPrice(entry.Id)
		local owned = isPassOwned(entry)

		buildRow({
			Name = entry.Name,
			LayoutOrder = i,
			IconAsset = entry.Icon,
			IconEmoji = entry.Emoji,
			PriceText = price and (price .. " R$") or "BUY",
			Owned = owned,
			OnClick = function()
				MarketplaceService:PromptGamePassPurchase(player, entry.Id)
			end
		})
	end
end

local function buildCashTab()
	for i, pack in ipairs(Economy.CashPacks) do
		buildRow({
			Name = formatMoney(pack.Money),
			LayoutOrder = i,
			IconEmoji = "💵",
			PriceText = pack.RobuxPrice .. " R$",
			OnClick = function()
				MarketplaceService:PromptProductPurchase(player, pack.ProductId)
			end
		})
	end
end

local function buildEggsTab()
	local oddsParts = {}
	for _, entry in ipairs(Economy.PremiumEgg.RarityChances) do
		table.insert(oddsParts, entry.Rarity .. " " .. entry.Chance .. "%")
	end

	buildRow({
		Name = "Premium Egg",
		LayoutOrder = 1,
		IconEmoji = "🥚",
		PriceText = Economy.PremiumEgg.RobuxPrice .. " R$",
		OnClick = function()
			MarketplaceService:PromptProductPurchase(player, Economy.PremiumEgg.ProductId)
		end
	})

	local oddsLabel = Instance.new("TextLabel")
	oddsLabel.Name = "OddsLabel"
	oddsLabel.LayoutOrder = 2
	oddsLabel.BackgroundTransparency = 1
	oddsLabel.Size = UDim2.new(1, 0, 0, 26)
	oddsLabel.Text = "Odds: " .. table.concat(oddsParts, "  |  ")
	oddsLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	oddsLabel.Font = FONT_BODY
	oddsLabel.TextSize = 13
	oddsLabel.TextXAlignment = Enum.TextXAlignment.Left
	oddsLabel.Parent = scroll
end

local TAB_TITLES = {
	GamePasses = "GAME PASSES",
	Cash = "CASH",
	Eggs = "EGGS"
}

local TAB_BUILDERS = {
	GamePasses = buildGamePassesTab,
	Cash = buildCashTab,
	Eggs = buildEggsTab
}

local currentTab = "GamePasses"

local function selectTab(tabKey)
	currentTab = tabKey
	titleLabel.Text = TAB_TITLES[tabKey]

	for key, button in pairs(tabButtons) do
		local isSelected = key == tabKey
		local tabStroke = button:FindFirstChildOfClass("UIStroke")
		if tabStroke then
			tabStroke.Thickness = isSelected and 4 or 2
		end
		button.BackgroundTransparency = isSelected and 0 or 0.35
	end

	clearScroll()
	TAB_BUILDERS[tabKey]()
end

for _, tab in ipairs(TABS) do
	tabButtons[tab.Key].Activated:Connect(function()
		selectTab(tab.Key)
	end)
end

-- ================= Comportament =================

closeButton.Activated:Connect(function()
	mainFrame.Visible = false
end)

mainFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	-- Ascunde HUD-ul (bottom bar/cash/friend boost) cat timp shop-ul e
	-- deschis -- acelasi attribute pe care MainHUD.rbxmx il asculta deja.
	player:SetAttribute("ShopModalOpen", mainFrame.Visible)

	if mainFrame.Visible then
		applyLayout()
		selectTab(currentTab)
	end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchasedPlayer, gamePassId, wasPurchased)
	if purchasedPlayer ~= player or not wasPurchased then
		return
	end

	-- Invalidam cache-ul de ownership pentru pass-ul cumparat -- altfel
	-- Inventory Pass (singurul fara attribute dedicat) ar ramane cu "false"
	-- din cache pana la urmatorul rejoin.
	ownedPassCache[gamePassId] = nil

	if mainFrame.Visible and currentTab == "GamePasses" then
		selectTab("GamePasses")
	end
end)
