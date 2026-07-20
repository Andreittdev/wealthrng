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

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local redeemCodeEvent = remotes:WaitForChild("RedeemCode")
local codeResultEvent = remotes:WaitForChild("CodeResult")
local setGiftTargetEvent = remotes:WaitForChild("SetGiftTarget")

local FONT_DISPLAY = Enum.Font.Bangers
local FONT_BODY = Enum.Font.FredokaOne

local PANEL_BG = Color3.fromRGB(42, 40, 48)
local HEADER_BG = Color3.fromRGB(58, 55, 64)
local ROW_ICON_BG = Color3.fromRGB(214, 160, 40)
local ROW_INFO_BG = Color3.fromRGB(120, 78, 16)
local PRICE_COLOR = Color3.fromRGB(120, 235, 150)
local OWNED_COLOR = Color3.fromRGB(100, 235, 140)

local GIFT_TAB_COLOR = Color3.fromRGB(230, 100, 180)

local TABS = {
	{Key = "GamePasses", Label = "Game\nPasses", Color = Color3.fromRGB(230, 150, 40)},
	{Key = "Cash", Label = "Cash", Color = Color3.fromRGB(70, 150, 230)},
	{Key = "Eggs", Label = "Eggs", Color = Color3.fromRGB(210, 200, 40)},
	{Key = "Codes", Label = "Codes", Color = Color3.fromRGB(90, 210, 130)},
	{Key = "Gift", Label = "Gift", Color = GIFT_TAB_COLOR}
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
-- Attribute e folosit DOAR pentru badge-ul "OWNED". Auto Sell e singurul
-- dintre pass-urile "clasice" cu toggle propriu -- foloseste OwnsAutoSellPass
-- (proprietatea reala), nu HasAutoSellPass (care poate fi oprit temporar din
-- Settings), altfel un jucator care il opreste ar vedea magazinul spunandu-i
-- ca nu-l mai detine deloc.
local GAME_PASSES = {
	{Name = "VIP", Id = 1898198234, Attribute = "IsVIP", Icon = "rbxassetid://74375751325744"},
	{Name = "More NPC Speed", Id = Economy.SpeedPass.GamePassId, Attribute = "HasSpeedPass", Icon = "rbxassetid://111045527678748"},
	{Name = "Auto Sell", Id = Economy.AutoSellPass.GamePassId, Attribute = "OwnsAutoSellPass", Icon = "rbxassetid://90788671280233"},
	{Name = "+100 Inventory Space", Id = 1899734044, Attribute = nil, Icon = "rbxassetid://71016405354553"},
	{Name = "Auto Buy", Id = Economy.AutoBuyPass.GamePassId, Attribute = "HasAutoBuyPass", Icon = "rbxassetid://87364006551417"},
	{Name = "Auto Rebirth", Id = Economy.AutoRebirthPass.GamePassId, Attribute = "HasAutoRebirthPass", Emoji = "♻️"}
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

-- Acelasi tipar ca getPassPrice, dar pentru Developer Products (Enum.InfoType
-- .Product, nu .GamePass) -- folosit de tab-ul Gift, ca preturile afisate
-- pentru cele 4 Gift Passes sa fie mereu cele REALE din Creator Dashboard.
local giftPassPriceCache = {}

local function getGiftPassPrice(productId)
	if giftPassPriceCache[productId] ~= nil then
		return giftPassPriceCache[productId]
	end

	local price = nil
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)

	if ok and info and info.PriceInRobux then
		price = info.PriceInRobux
	end

	giftPassPriceCache[productId] = price
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
		IconAsset = "rbxassetid://104309601579573",
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

-- Nu exista niciun API Roblox prin care un jucator sa transfere efectiv un
-- Gamepass real altui cont -- vezi comentariul din Economy.GiftPasses
-- (EconomyConfig.luau). Alegi un jucator din server, apoi cumperi un
-- Developer Product dedicat -- serverul (PremiumPurchaseManager) acorda
-- perk-ul direct pe contul ALES.
local selectedGiftTargetUserId = nil

local function buildGiftTab()
	selectedGiftTargetUserId = nil

	local pickerLabel = Instance.new("TextLabel")
	pickerLabel.Name = "PickerLabel"
	pickerLabel.LayoutOrder = 1
	pickerLabel.BackgroundTransparency = 1
	pickerLabel.Size = UDim2.new(1, 0, 0, 24)
	pickerLabel.Text = "Choose a player, then tap Gift below:"
	pickerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	pickerLabel.Font = FONT_BODY
	pickerLabel.TextSize = 15
	pickerLabel.TextXAlignment = Enum.TextXAlignment.Left
	pickerLabel.Parent = scroll

	local others = {}
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			table.insert(others, otherPlayer)
		end
	end

	if #others == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Name = "NoPlayersLabel"
		emptyLabel.LayoutOrder = 2
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Size = UDim2.new(1, 0, 0, 40)
		emptyLabel.Text = "No other players in the server right now"
		emptyLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
		emptyLabel.Font = FONT_BODY
		emptyLabel.TextSize = 14
		emptyLabel.TextWrapped = true
		emptyLabel.Parent = scroll
	end

	local playerButtons = {}

	local function refreshPlayerButtons()
		for userId, entry in pairs(playerButtons) do
			local isSelected = userId == selectedGiftTargetUserId
			entry.Stroke.Thickness = isSelected and 4 or 2
			entry.Stroke.Color = isSelected and GIFT_TAB_COLOR or Color3.fromRGB(20, 18, 24)
		end
	end

	for i, otherPlayer in ipairs(others) do
		local playerButton = Instance.new("TextButton")
		playerButton.Name = "PlayerButton_" .. otherPlayer.UserId
		playerButton.LayoutOrder = 2 + i
		playerButton.Size = UDim2.new(1, 0, 0, 40)
		playerButton.AutoButtonColor = false
		playerButton.BackgroundColor3 = ROW_INFO_BG
		playerButton.Text = otherPlayer.DisplayName
		playerButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		playerButton.Font = FONT_DISPLAY
		playerButton.TextScaled = true
		playerButton.Parent = scroll

		Instance.new("UICorner", playerButton).CornerRadius = UDim.new(0.14, 0)

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(20, 18, 24)
		stroke.Thickness = 2
		stroke.Parent = playerButton

		playerButtons[otherPlayer.UserId] = {Button = playerButton, Stroke = stroke}

		playerButton.Activated:Connect(function()
			selectedGiftTargetUserId = otherPlayer.UserId
			refreshPlayerButtons()
		end)
	end

	local anyConfigured = false

	for i, giftEntry in ipairs(Economy.GiftPasses) do
		if giftEntry.ProductId ~= 0 then
			anyConfigured = true
			local price = getGiftPassPrice(giftEntry.ProductId)

			buildRow({
				Name = "Gift " .. giftEntry.Name,
				LayoutOrder = 2 + #others + i,
				IconEmoji = "🎁",
				PriceText = price and (price .. " R$") or "BUY",
				OnClick = function()
					if not selectedGiftTargetUserId then
						return
					end
					setGiftTargetEvent:FireServer(giftEntry.ProductId, selectedGiftTargetUserId)
					MarketplaceService:PromptProductPurchase(player, giftEntry.ProductId)
				end
			})
		end
	end

	if not anyConfigured then
		local comingSoonLabel = Instance.new("TextLabel")
		comingSoonLabel.Name = "ComingSoonLabel"
		comingSoonLabel.LayoutOrder = 999
		comingSoonLabel.BackgroundTransparency = 1
		comingSoonLabel.Size = UDim2.new(1, 0, 0, 40)
		comingSoonLabel.Text = "🚧 Gifting coming soon!"
		comingSoonLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		comingSoonLabel.Font = FONT_BODY
		comingSoonLabel.TextScaled = true
		comingSoonLabel.Parent = scroll
	end
end

-- Cat timp asteptam raspunsul serverului la un cod, blocam butonul de Redeem
-- -- fara asta, un dublu-click rapid trimite acelasi cod de 2 ori inainte de
-- primul raspuns (server-ul e oricum protejat de re-redeem, dar rezultatele
-- s-ar putea intoarce in alta ordine si arata gresit in UI).
local codesWaitingForResult = false

-- Referinta catre label-ul de rezultat curent -- actualizata de fiecare data
-- cand buildCodesTab ruleaza (la fiecare selectare a tab-ului). Handler-ul
-- codeResultEvent.OnClientEvent e conectat O SINGURA DATA, la nivel de modul
-- (mai jos) -- NU aici, in interiorul builder-ului, ca sa nu se acumuleze o
-- conexiune noua de fiecare data cand jucatorul revine pe tab-ul Codes
-- (exact tiparul de bug reparat mai devreme in ItemsGui.rbxmx).
local codesResultLabel = nil
local codesInputBox = nil

local function setCodesResult(text, color)
	-- Verificam .Parent, nu doar existenta referintei -- daca jucatorul a
	-- schimbat tab-ul intre timp, clearScroll() a distrus deja acest label
	-- (codesResultLabel ramane o referinta "moarta" pana la urmatorul
	-- buildCodesTab).
	if not codesResultLabel or not codesResultLabel.Parent then
		return
	end
	codesResultLabel.Text = text
	codesResultLabel.TextColor3 = color
end

local function buildCodesTab()
	codesWaitingForResult = false

	local inputRow = Instance.new("Frame")
	inputRow.Name = "CodeInputRow"
	inputRow.LayoutOrder = 1
	inputRow.Size = UDim2.new(1, 0, 0, 56)
	inputRow.BackgroundColor3 = ROW_INFO_BG
	inputRow.Parent = scroll

	Instance.new("UICorner", inputRow).CornerRadius = UDim.new(0.14, 0)

	local inputStroke = Instance.new("UIStroke")
	inputStroke.Color = Color3.fromRGB(20, 18, 24)
	inputStroke.Thickness = 2
	inputStroke.Parent = inputRow

	local codeBox = Instance.new("TextBox")
	codeBox.Name = "CodeBox"
	codeBox.BackgroundTransparency = 1
	codeBox.Position = UDim2.new(0, 14, 0, 0)
	codeBox.Size = UDim2.new(1, -28, 1, 0)
	codeBox.Text = ""
	codeBox.PlaceholderText = "Enter code..."
	codeBox.PlaceholderColor3 = Color3.fromRGB(200, 200, 210)
	codeBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	codeBox.Font = FONT_BODY
	codeBox.TextScaled = true
	codeBox.ClearTextOnFocus = false
	codeBox.TextXAlignment = Enum.TextXAlignment.Left
	codeBox.Parent = inputRow

	codesInputBox = codeBox

	local redeemButton = Instance.new("TextButton")
	redeemButton.Name = "RedeemButton"
	redeemButton.LayoutOrder = 2
	redeemButton.Size = UDim2.new(1, 0, 0, 56)
	redeemButton.AutoButtonColor = false
	redeemButton.BackgroundColor3 = Color3.fromRGB(90, 200, 120)
	redeemButton.Text = "REDEEM"
	redeemButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	redeemButton.Font = FONT_DISPLAY
	redeemButton.TextScaled = true
	redeemButton.Parent = scroll

	Instance.new("UICorner", redeemButton).CornerRadius = UDim.new(0.14, 0)

	local redeemStroke = Instance.new("UIStroke")
	redeemStroke.Color = Color3.fromRGB(20, 18, 24)
	redeemStroke.Thickness = 2
	redeemStroke.Parent = redeemButton

	local resultLabel = Instance.new("TextLabel")
	resultLabel.Name = "CodeResultLabel"
	resultLabel.LayoutOrder = 3
	resultLabel.BackgroundTransparency = 1
	resultLabel.Size = UDim2.new(1, 0, 0, 40)
	resultLabel.Text = ""
	resultLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	resultLabel.TextWrapped = true
	resultLabel.Font = FONT_BODY
	resultLabel.TextSize = 14
	resultLabel.TextXAlignment = Enum.TextXAlignment.Left
	resultLabel.Parent = scroll

	codesResultLabel = resultLabel

	redeemButton.Activated:Connect(function()
		if codesWaitingForResult then
			return
		end

		local code = codeBox.Text

		if code == "" then
			setCodesResult("Enter a code first", Color3.fromRGB(255, 110, 110))
			return
		end

		codesWaitingForResult = true
		setCodesResult("Checking...", Color3.fromRGB(200, 200, 210))
		redeemCodeEvent:FireServer(code)
	end)
end

codeResultEvent.OnClientEvent:Connect(function(data)
	codesWaitingForResult = false

	if not data then
		return
	end

	if data.Success then
		setCodesResult("✅ Redeemed \"" .. tostring(data.Code) .. "\"!", Color3.fromRGB(90, 230, 130))
		if codesInputBox and codesInputBox.Parent then
			codesInputBox.Text = ""
		end
	else
		setCodesResult("❌ " .. tostring(data.Message or "Something went wrong"), Color3.fromRGB(255, 110, 110))
	end
end)

local TAB_TITLES = {
	GamePasses = "GAME PASSES",
	Cash = "CASH",
	Eggs = "EGGS",
	Codes = "CODES",
	Gift = "GIFT"
}

local TAB_BUILDERS = {
	GamePasses = buildGamePassesTab,
	Cash = buildCashTab,
	Eggs = buildEggsTab,
	Codes = buildCodesTab,
	Gift = buildGiftTab
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

-- Lista de jucatori din tab-ul Gift trebuie sa ramana la zi cat timp panoul
-- e deschis -- conectate O SINGURA DATA, la nivel de modul (nu in
-- buildGiftTab), ca sa nu se acumuleze conexiuni la fiecare rebuild.
local function refreshGiftTabIfOpen()
	if mainFrame.Visible and currentTab == "Gift" then
		selectTab("Gift")
	end
end

Players.PlayerAdded:Connect(refreshGiftTabIfOpen)
Players.PlayerRemoving:Connect(refreshGiftTabIfOpen)
