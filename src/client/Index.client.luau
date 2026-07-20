local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))
local PetDatabase = require(modulesFolder:WaitForChild("PetDatabase"))
local Clothing = require(modulesFolder:WaitForChild("Clothing"))
local Shoes = require(modulesFolder:WaitForChild("Shoes"))
local Electronics = require(modulesFolder:WaitForChild("Electronics"))
local Luxury = require(modulesFolder:WaitForChild("Luxury"))
local Collectibles = require(modulesFolder:WaitForChild("Collectibles"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local openIndexEvent = remotes:WaitForChild("OpenIndex")

-- Folder replicat automat de PetManager -- un copil per PetId prin care a
-- trecut vreodata jucatorul (chiar daca a fost duplicat/vandut). Cautam LIVE
-- (FindFirstChild), fara sa cache-uim referinta o singura data la pornire --
-- WaitForChild cu timeout risca sa ramana nil pentru tot restul sesiunii daca
-- folderul nu exista inca in primele secunde (incarcare lenta a datelor).
local function isPetDiscovered(petId)
	local folder = player:FindFirstChild("DiscoveredPets")
	return folder ~= nil and folder:FindFirstChild(petId) ~= nil
end

-- Acelasi tipar, dar pentru iteme de tranzactionat -- folder replicat de
-- InventoryManager, un copil per ItemId (cheia din Clothing/Shoes/etc.)
-- prin care a trecut vreodata jucatorul.
local function isItemDiscovered(itemId)
	local folder = player:FindFirstChild("DiscoveredItems")
	return folder ~= nil and folder:FindFirstChild(itemId) ~= nil
end

local FONT_DISPLAY = Enum.Font.Bangers
local FONT_BODY = Enum.Font.FredokaOne

-- Tema "index/biblioteca", violet inchis -- diferita de toate celelalte
-- (auriu StarterPack, mov Rebirth, portocaliu TokenShop, cyan DailyRewards).
local BG_DARK = Color3.fromRGB(18, 15, 26)
local BG_MID = Color3.fromRGB(34, 26, 48)
local CARD_BG = Color3.fromRGB(30, 24, 42)
local ACCENT = Color3.fromRGB(170, 120, 255)
local OUTLINE_DARK = Color3.fromRGB(50, 20, 80)
local TEXT_LIGHT = Color3.fromRGB(235, 225, 245)
local TEXT_DIM = Color3.fromRGB(175, 160, 195)

local RARITY_COLORS = {
	Common = Color3.fromRGB(160, 160, 160),
	Rare = Color3.fromRGB(60, 150, 255),
	Epic = Color3.fromRGB(170, 90, 255),
	Legendary = Color3.fromRGB(255, 180, 40),
	Mythic = Color3.fromRGB(255, 70, 105),
	Secret = Color3.fromRGB(255, 255, 255)
}

local RARITY_ORDER = {"Common", "Rare", "Epic", "Legendary", "Mythic", "Secret"}

-- ================= Responsive sizing =================

local function computeIsMobile()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.X < 700 or viewport.Y < 500
end

local function getMainFrameSize()
	local isMobile = computeIsMobile()

	if not isMobile then
		return UDim2.fromOffset(820, 600)
	end

	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(400, 700)

	local width = math.min(viewport.X * 0.92, viewport.X - 24)
	local height = math.min(viewport.Y * 0.85, viewport.Y - 24)

	return UDim2.fromOffset(width, height)
end

-- ================= Date -- construim listele o singura data =================

local function buildPetList()
	local list = {}
	for petId, petData in pairs(PetDatabase.Pets) do
		-- Clonam (nu mutam direct petData) ca sa nu atingem tabelul
		-- PetDatabase.Pets partajat cu alte scripturi client -- avem nevoie
		-- de PetId aici (cheia din PetDatabase.Pets), ca sa stim ce e
		-- descoperit sau nu, dar entry-urile originale nu au campul asta.
		local entry = table.clone(petData)
		entry.PetId = petId
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		return a.DisplayName < b.DisplayName
	end)
	return list
end

local function buildItemList()
	local list = {}
	for _, categoryModule in ipairs({Clothing, Shoes, Electronics, Luxury, Collectibles}) do
		for key, item in pairs(categoryModule) do
			-- Clonam (nu mutam direct item) -- acelasi motiv ca la buildPetList:
			-- avem nevoie de cheia din modul (ItemId, acelasi folosit de
			-- InventoryManager/TradeManager) ca sa stim ce e descoperit, dar
			-- entry-urile originale nu au campul asta.
			local entry = table.clone(item)
			entry.ItemKey = key
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		if a.Category ~= b.Category then
			return a.Category < b.Category
		end
		return (a.BuyPrice or 0) < (b.BuyPrice or 0)
	end)
	return list
end

local allPets = buildPetList()
local allItems = buildItemList()

local function groupByRarity(list)
	local groups = {}
	for _, entry in ipairs(list) do
		local rarity = entry.Rarity or "Common"
		groups[rarity] = groups[rarity] or {}
		table.insert(groups[rarity], entry)
	end
	return groups
end

local petsByRarity = groupByRarity(allPets)
local itemsByRarity = groupByRarity(allItems)

local function formatMoney(amount)
	amount = math.floor(amount or 0)
	local formatted = tostring(amount)
	while true do
		local newValue, count = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = newValue
		if count == 0 then
			break
		end
	end
	return "$" .. formatted
end

-- ================= ScreenGui =================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "IndexGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local overlay = Instance.new("Frame")
overlay.Name = "IndexOverlay"
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.35
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.Visible = false
overlay.ZIndex = 20
overlay.Parent = screenGui

local card = Instance.new("Frame")
card.Name = "Card"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.new(0.5, 0, 0.5, 0)
card.Size = getMainFrameSize()
card.BackgroundColor3 = BG_DARK
card.ClipsDescendants = true
card.ZIndex = 21
card.Parent = overlay

Instance.new("UICorner", card).CornerRadius = UDim.new(0, 18)

local cardStroke = Instance.new("UIStroke")
cardStroke.Color = ACCENT
cardStroke.Thickness = 3
cardStroke.Parent = card

local cardGradient = Instance.new("UIGradient")
cardGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, BG_MID),
	ColorSequenceKeypoint.new(1, BG_DARK),
})
cardGradient.Rotation = 90
cardGradient.Parent = card

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -14, 0, 14)
closeButton.Size = UDim2.new(0, 36, 0, 36)
closeButton.BackgroundColor3 = Color3.fromRGB(210, 65, 75)
closeButton.Text = "×"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Font = FONT_BODY
closeButton.TextSize = 26
closeButton.ZIndex = 30
closeButton.Parent = card

Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 10)

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 20, 0, 14)
titleLabel.Size = UDim2.new(1, -80, 0, 38)
titleLabel.Text = "📖 INDEX"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextStrokeColor3 = OUTLINE_DARK
titleLabel.TextStrokeTransparency = 0
titleLabel.Font = FONT_DISPLAY
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 22
titleLabel.Parent = card

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Position = UDim2.new(0, 20, 0, 52)
subtitleLabel.Size = UDim2.new(1, -80, 0, 20)
subtitleLabel.Text = "Every pet and item in the game, Common to Secret"
subtitleLabel.TextColor3 = TEXT_DIM
subtitleLabel.Font = FONT_BODY
subtitleLabel.TextSize = 14
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.ZIndex = 22
subtitleLabel.Parent = card

-- ================= Tabs (PETS / ITEMS) =================

local tabBar = Instance.new("Frame")
tabBar.BackgroundTransparency = 1
tabBar.Position = UDim2.new(0, 20, 0, 82)
tabBar.Size = UDim2.new(1, -40, 0, 38)
tabBar.ZIndex = 22
tabBar.Parent = card

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 10)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabBar

local function createTabButton(text, order)
	local button = Instance.new("TextButton")
	button.Name = text .. "Tab"
	button.LayoutOrder = order
	button.Size = UDim2.new(0, 140, 1, 0)
	button.BackgroundColor3 = CARD_BG
	button.AutoButtonColor = false
	button.Text = text
	button.TextColor3 = TEXT_LIGHT
	button.Font = FONT_DISPLAY
	button.TextScaled = true
	button.ZIndex = 22
	button.Parent = tabBar

	Instance.new("UICorner", button).CornerRadius = UDim.new(0.25, 0)

	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE_DARK
	stroke.Thickness = 2
	stroke.Parent = button

	return button, stroke
end

local petsTabButton, petsTabStroke = createTabButton("🐾 PETS", 1)
local itemsTabButton, itemsTabStroke = createTabButton("📦 ITEMS", 2)

-- ================= Continut (o ScrollingFrame per tab) =================

local function createContentScroll(name, order)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.LayoutOrder = order
	scroll.BackgroundTransparency = 1
	scroll.Position = UDim2.new(0, 20, 0, 128)
	scroll.Size = UDim2.new(1, -40, 1, -148)
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = ACCENT
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 22
	scroll.Visible = false
	scroll.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 14)
	layout.Parent = scroll

	return scroll
end

local petsScroll = createContentScroll("PetsScroll", 1)
local itemsScroll = createContentScroll("ItemsScroll", 2)

-- ---- Card pentru un item de tranzactionat -- aceeasi abordare ca la
-- pet-uri (createPetEntryCard mai jos): umbra neagra daca nu a fost
-- descoperit niciodata, iar categoria/pretul ascunse pana dai click (si
-- doar daca a fost descoperit -- altfel nu are ce sa arate). ----

local function createEntryCard(parent, order, name, rarity, subtitleText, icon, discovered)
	local color = RARITY_COLORS[rarity] or Color3.fromRGB(255, 255, 255)

	local entry = Instance.new("TextButton")
	entry.Name = name
	entry.LayoutOrder = order
	entry.BackgroundColor3 = CARD_BG
	entry.AutoButtonColor = false
	entry.Text = ""
	entry.ZIndex = 23
	entry.Parent = parent

	Instance.new("UICorner", entry).CornerRadius = UDim.new(0, 10)

	local stroke = Instance.new("UIStroke")
	stroke.Color = discovered and color or Color3.fromRGB(70, 70, 78)
	stroke.Thickness = 2
	stroke.Parent = entry

	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Position = UDim2.new(0, 4, 0, 4)
	image.Size = UDim2.new(1, -8, 0, 96)
	image.Image = icon or ""
	image.ImageColor3 = discovered and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
	image.ScaleType = Enum.ScaleType.Fit
	image.ZIndex = 24
	image.Parent = entry

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 6, 0, 102)
	nameLabel.Size = UDim2.new(1, -12, 0, 22)
	nameLabel.Text = name
	nameLabel.TextColor3 = TEXT_LIGHT
	nameLabel.TextWrapped = true
	nameLabel.Font = FONT_BODY
	nameLabel.TextScaled = true
	nameLabel.ZIndex = 24
	nameLabel.Parent = entry

	-- TextScaled (nu TextSize fix) -- un text fix putea sa nu incapa toate
	-- liniile (2 randuri la iteme/pet-uri cu Source) si sa se taie, aceeasi
	-- greseala gasita si reparata la Stand Upgrade. Ascuns implicit -- se
	-- arata doar la click, si doar daca itemul a fost descoperit.
	local subLabel = Instance.new("TextLabel")
	subLabel.BackgroundTransparency = 1
	subLabel.Position = UDim2.new(0, 6, 0, 124)
	subLabel.Size = UDim2.new(1, -12, 0, 34)
	subLabel.Text = subtitleText
	subLabel.TextColor3 = color
	subLabel.TextWrapped = true
	subLabel.Font = FONT_BODY
	subLabel.TextScaled = true
	subLabel.Visible = false
	subLabel.ZIndex = 24
	subLabel.Parent = entry

	if discovered then
		entry.Activated:Connect(function()
			subLabel.Visible = not subLabel.Visible
		end)
	end

	return entry
end

-- ---- Card special pentru pet-uri: poza (umbra neagra daca nu a fost
-- descoperit niciodata), nume, si bonusurile ascunse pana dai click (si
-- doar daca a fost descoperit -- altfel nu are ce sa arate). ----

local function createPetEntryCard(parent, order, petData, rarity)
	local color = RARITY_COLORS[rarity] or Color3.fromRGB(255, 255, 255)
	local discovered = isPetDiscovered(petData.PetId)

	local entry = Instance.new("TextButton")
	entry.Name = petData.DisplayName
	entry.LayoutOrder = order
	entry.BackgroundColor3 = CARD_BG
	entry.AutoButtonColor = false
	entry.Text = ""
	entry.ZIndex = 23
	entry.Parent = parent

	Instance.new("UICorner", entry).CornerRadius = UDim.new(0, 10)

	local stroke = Instance.new("UIStroke")
	stroke.Color = discovered and color or Color3.fromRGB(70, 70, 78)
	stroke.Thickness = 2
	stroke.Parent = entry

	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Position = UDim2.new(0, 4, 0, 4)
	image.Size = UDim2.new(1, -8, 0, 96)
	image.Image = petData.Image or ""
	image.ImageColor3 = discovered and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0)
	image.ScaleType = Enum.ScaleType.Fit
	image.ZIndex = 24
	image.Parent = entry

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 6, 0, 102)
	nameLabel.Size = UDim2.new(1, -12, 0, 22)
	nameLabel.Text = petData.DisplayName
	nameLabel.TextColor3 = TEXT_LIGHT
	nameLabel.TextWrapped = true
	nameLabel.Font = FONT_BODY
	nameLabel.TextScaled = true
	nameLabel.ZIndex = 24
	nameLabel.Parent = entry

	local stats = "🍀+" .. (petData.Bonuses.NpcLuck or 0)
		.. "%  💰+" .. (petData.Bonuses.SellPrice or 0)
		.. "%  ⚡+" .. (petData.Bonuses.NpcSpeed or 0) .. "%"

	if petData.Source then
		stats = stats .. "\n" .. petData.Source
	end

	local statsLabel = Instance.new("TextLabel")
	statsLabel.BackgroundTransparency = 1
	statsLabel.Position = UDim2.new(0, 6, 0, 124)
	statsLabel.Size = UDim2.new(1, -12, 0, 34)
	statsLabel.Text = stats
	statsLabel.TextColor3 = color
	statsLabel.TextWrapped = true
	statsLabel.Font = FONT_BODY
	statsLabel.TextScaled = true
	statsLabel.Visible = false
	statsLabel.ZIndex = 24
	statsLabel.Parent = entry

	if discovered then
		entry.Activated:Connect(function()
			statsLabel.Visible = not statsLabel.Visible
		end)
	end

	return entry
end

local function createRaritySection(parent, rarity, order)
	local color = RARITY_COLORS[rarity] or Color3.fromRGB(255, 255, 255)

	local section = Instance.new("Frame")
	section.Name = rarity .. "Section"
	section.LayoutOrder = order
	section.BackgroundTransparency = 1
	section.AutomaticSize = Enum.AutomaticSize.Y
	section.Size = UDim2.new(1, 0, 0, 0)
	section.ZIndex = 22
	section.Parent = parent

	local sectionLayout = Instance.new("UIListLayout")
	sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	sectionLayout.Padding = UDim.new(0, 8)
	sectionLayout.Parent = section

	local header = Instance.new("TextLabel")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 26)
	header.Text = rarity:upper()
	header.TextColor3 = color
	header.TextStrokeColor3 = OUTLINE_DARK
	header.TextStrokeTransparency = 0.4
	header.Font = FONT_DISPLAY
	header.TextScaled = true
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.ZIndex = 23
	header.Parent = section

	local gridHolder = Instance.new("Frame")
	gridHolder.Name = "GridHolder"
	gridHolder.LayoutOrder = 2
	gridHolder.BackgroundTransparency = 1
	gridHolder.AutomaticSize = Enum.AutomaticSize.Y
	gridHolder.Size = UDim2.new(1, 0, 0, 0)
	gridHolder.ZIndex = 22
	gridHolder.Parent = section

	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = gridHolder

	return gridHolder, grid
end

local function updateGridColumns(grid, columns, cellHeight)
	local padding = 10
	local totalPaddingScale = (columns - 1) * padding

	grid.CellSize = UDim2.new(1 / columns, -(totalPaddingScale / columns), 0, cellHeight)
	grid.CellPadding = UDim2.new(0, padding, 0, padding)
end

local petGrids = {}
local itemGrids = {}

-- Pastram holder-ul + rarity-ul fiecarei sectiuni de pet-uri, ca sa putem
-- reconstrui cardurile (culoare/umbra) de fiecare data cand se deschide
-- Index-ul -- altfel un pet proaspat descoperit (deschis dintr-un ou dupa ce
-- Index-ul a fost deja construit o data) ramanea umbra pentru tot restul
-- sesiunii, fiindca starea "discovered" era citita o singura data, la
-- pornire.
local petGridHolders = {}
local itemGridHolders = {}
local contentBuilt = false

-- Constructia integrala (~830 Instance.new + ~118 imagini reale) e amanata
-- pana la prima deschidere a Index-ului, nu rulata la pornirea scriptului --
-- rularea ei imediat la join cauza un hitch vizibil in primele secunde de
-- sesiune (toate iconitele noi incep sa se streamuiasca deodata).
local function buildIndexContent()
	if contentBuilt then
		return
	end
	contentBuilt = true

	for order, rarity in ipairs(RARITY_ORDER) do
		if petsByRarity[rarity] then
			local gridHolder, grid = createRaritySection(petsScroll, rarity, order)
			table.insert(petGrids, grid)
			table.insert(petGridHolders, {Holder = gridHolder, Rarity = rarity})

			for petOrder, petData in ipairs(petsByRarity[rarity]) do
				createPetEntryCard(gridHolder, petOrder, petData, rarity)
			end
		end

		if itemsByRarity[rarity] then
			local gridHolder, grid = createRaritySection(itemsScroll, rarity, order)
			table.insert(itemGrids, grid)
			table.insert(itemGridHolders, {Holder = gridHolder, Rarity = rarity})

			for itemOrder, itemData in ipairs(itemsByRarity[rarity]) do
				local subtitleText = itemData.Category .. "\n" .. formatMoney(itemData.MinSell) .. " - " .. formatMoney(Economy.GetMaxSell(itemData.ExpectedValue))
				createEntryCard(gridHolder, itemOrder, itemData.ItemName or itemData.Name, rarity, subtitleText, itemData.Icon, isItemDiscovered(itemData.ItemKey))
			end
		end
	end
end

local function refreshPetCards()
	for _, entry in ipairs(petGridHolders) do
		for _, child in ipairs(entry.Holder:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		for petOrder, petData in ipairs(petsByRarity[entry.Rarity]) do
			createPetEntryCard(entry.Holder, petOrder, petData, entry.Rarity)
		end
	end
end

-- Acelasi motiv ca refreshPetCards -- un item proaspat descoperit (cumparat
-- de la un NPC dupa ce Index-ul a fost deja construit o data) ramanea umbra
-- pentru tot restul sesiunii, fiindca starea "discovered" era citita o
-- singura data, la construire.
local function refreshItemCards()
	for _, entry in ipairs(itemGridHolders) do
		for _, child in ipairs(entry.Holder:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end

		for itemOrder, itemData in ipairs(itemsByRarity[entry.Rarity]) do
			local subtitleText = itemData.Category .. "\n" .. formatMoney(itemData.MinSell) .. " - " .. formatMoney(Economy.GetMaxSell(itemData.ExpectedValue))
			createEntryCard(entry.Holder, itemOrder, itemData.ItemName or itemData.Name, entry.Rarity, subtitleText, itemData.Icon, isItemDiscovered(itemData.ItemKey))
		end
	end
end

local function updateAllGrids()
	local isMobile = computeIsMobile()
	local columns = isMobile and 2 or 4

	for _, grid in ipairs(petGrids) do
		updateGridColumns(grid, columns, 168)
	end

	for _, grid in ipairs(itemGrids) do
		updateGridColumns(grid, columns, 168)
	end
end

-- ================= Footer =================

local footerLabel = Instance.new("TextLabel")
footerLabel.Name = "FooterLabel"
footerLabel.BackgroundTransparency = 1
footerLabel.AnchorPoint = Vector2.new(0.5, 1)
footerLabel.Position = UDim2.new(0.5, 0, 1, -8)
footerLabel.Size = UDim2.new(1, -40, 0, 20)
footerLabel.Text = "🎁 INDEX REWARDS SOON!"
footerLabel.TextColor3 = ACCENT
footerLabel.Font = FONT_DISPLAY
footerLabel.TextScaled = true
footerLabel.ZIndex = 25
footerLabel.Parent = card

-- ================= Comportament taburi =================

local activeTab = "Pets"

local function refreshTabs()
	local petsActive = activeTab == "Pets"

	petsScroll.Visible = petsActive
	itemsScroll.Visible = not petsActive

	petsTabButton.BackgroundColor3 = petsActive and ACCENT or CARD_BG
	itemsTabButton.BackgroundColor3 = (not petsActive) and ACCENT or CARD_BG

	petsTabStroke.Color = petsActive and Color3.fromRGB(255, 255, 255) or OUTLINE_DARK
	itemsTabStroke.Color = (not petsActive) and Color3.fromRGB(255, 255, 255) or OUTLINE_DARK
end

petsTabButton.Activated:Connect(function()
	activeTab = "Pets"
	refreshTabs()
end)

itemsTabButton.Activated:Connect(function()
	activeTab = "Items"
	refreshTabs()
end)

refreshTabs()

-- ================= Coordonare cu celelalte shop-uri =================

local function setShopModalOpen(open)
	player:SetAttribute("ShopModalOpen", open)
end

-- ================= Behaviour =================

local isOpen = false

local function setOpen(open)
	if open == isOpen then
		return
	end
	isOpen = open
	setShopModalOpen(open)

	if open then
		local firstBuild = not contentBuilt
		buildIndexContent()
		card.Size = getMainFrameSize()
		if not firstBuild then
			refreshPetCards()
			refreshItemCards()
		end
		updateAllGrids()
	end

	overlay.Visible = open
end

closeButton.Activated:Connect(function()
	setOpen(false)
end)

openIndexEvent.OnClientEvent:Connect(function()
	setOpen(true)
end)

-- Daca jucatorul roteste telefonul cat timp e deschis, recalculam.
do
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if overlay.Visible then
				card.Size = getMainFrameSize()
				updateAllGrids()
			end
		end)
	end
end
