local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local getPerkBreakdownFunction = remotes:WaitForChild("GetPerkBreakdown")

-- Butonul "PROFILE" e cel fost "SETTINGS" din MainHUD.rbxmx (redenumit +
-- reimaginat acolo direct in XML) -- il gasim extern, fara sa atingem
-- LocalScript-ul deja existent din MainHUD, la fel ca PetEquipSlots.client.luau
-- cu ItemsGui.
-- Timeout explicit (nu WaitForChild simplu) -- la un server proaspat (harta
-- se construieste de la zero la fiecare pornire), replicarea catre client
-- poate depasi cele 5 secunde implicite, umpland consola cu avertismente
-- "Infinite yield possible" degeaba (comportament normal, nu o eroare).
-- Daca totusi lipseste dupa 30s (ceva chiar nu e in regula), iesim curat in
-- loc sa crapam mai jos pe un nil.
local mainHud = playerGui:WaitForChild("MainHUD", 30)
if not mainHud then
	warn("Profile.client.luau: MainHUD nu a aparut in PlayerGui dupa 30s -- panoul de profil nu porneste.")
	return
end

local bottomBar = mainHud:WaitForChild("BottomBar")
local row2 = bottomBar:WaitForChild("Row2")
local profileButton = row2:WaitForChild("SettingsButton")

local FONT_DISPLAY = Enum.Font.Bangers
local FONT_BODY = Enum.Font.FredokaOne

-- Tema distincta (auriu/mov) fata de Settings (albastru) si restul panourilor.
local BG_DARK = Color3.fromRGB(24, 20, 30)
local BG_MID = Color3.fromRGB(44, 36, 56)
local ACCENT = Color3.fromRGB(210, 170, 60)
local OUTLINE_DARK = Color3.fromRGB(14, 12, 18)
local TEXT_LIGHT = Color3.fromRGB(235, 238, 245)
local TEXT_DIM = Color3.fromRGB(170, 165, 180)
local CLOSE_RED = Color3.fromRGB(210, 65, 75)
local ROW_BG = Color3.fromRGB(34, 29, 42)

local function computeIsMobile()
	local UserInputService = game:GetService("UserInputService")
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.X < 700 or viewport.Y < 500
end

local function getMainFrameSize()
	local isMobile = computeIsMobile()

	if not isMobile then
		return UDim2.fromOffset(420, 480)
	end

	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(400, 700)

	local width = math.min(viewport.X * 0.86, viewport.X - 24)
	local height = math.min(viewport.Y * 0.75, viewport.Y - 24)

	return UDim2.fromOffset(width, height)
end

-- ================= ScreenGui =================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ProfileGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local overlay = Instance.new("Frame")
overlay.Name = "ProfileOverlay"
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.35
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.Visible = false
overlay.Active = true
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
closeButton.BackgroundColor3 = CLOSE_RED
closeButton.Text = "×"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Font = FONT_BODY
closeButton.TextSize = 26
closeButton.ZIndex = 25
closeButton.Parent = card

Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 10)

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 20, 0, 18)
titleLabel.Size = UDim2.new(1, -80, 0, 38)
titleLabel.Text = "👤 PROFILE"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextStrokeColor3 = OUTLINE_DARK
titleLabel.TextStrokeTransparency = 0
titleLabel.Font = FONT_DISPLAY
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 22
titleLabel.Parent = card

-- ================= Titlu echipat (sub titlul panoului) =================

local equippedTitleLabel = Instance.new("TextLabel")
equippedTitleLabel.BackgroundTransparency = 1
equippedTitleLabel.Position = UDim2.new(0, 20, 0, 54)
equippedTitleLabel.Size = UDim2.new(1, -80, 0, 24)
equippedTitleLabel.Text = ""
equippedTitleLabel.TextColor3 = TEXT_DIM
equippedTitleLabel.Font = FONT_BODY
equippedTitleLabel.TextScaled = true
equippedTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
equippedTitleLabel.ZIndex = 22
equippedTitleLabel.Parent = card

local function findTokenShopItem(titleId)
	for _, item in ipairs(Economy.TokenShop.Items) do
		if item.Id == titleId then
			return item
		end
	end
	return nil
end

local function refreshEquippedTitle()
	local titleId = player:GetAttribute("EquippedTitle")

	if not titleId or titleId == "" then
		equippedTitleLabel.Text = "No title equipped"
		equippedTitleLabel.TextColor3 = TEXT_DIM
		return
	end

	local item = findTokenShopItem(titleId)

	if item then
		equippedTitleLabel.Text = "Title: " .. item.Name
		equippedTitleLabel.TextColor3 = item.ChatColor or TEXT_DIM
	else
		equippedTitleLabel.Text = "Title: " .. titleId
		equippedTitleLabel.TextColor3 = TEXT_DIM
	end
end

-- ================= Continut (stats read-only) =================
-- ScrollingFrame, nu Frame simplu -- odata cu sectiunea de Perks (numar
-- variabil de randuri, in functie de cate surse contribuie cu ceva > 0),
-- continutul poate depasi usor inaltimea cardului, mai ales pe mobil.

local content = Instance.new("ScrollingFrame")
content.BackgroundTransparency = 1
content.Position = UDim2.new(0, 20, 0, 88)
content.Size = UDim2.new(1, -40, 1, -108)
content.ZIndex = 22
content.BorderSizePixel = 0
content.ScrollBarThickness = 6
content.ScrollBarImageColor3 = ACCENT
content.CanvasSize = UDim2.new(0, 0, 0, 0)
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.Parent = card

local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 10)
contentLayout.Parent = content

-- ---- Rand generic de statistica (eticheta stanga + valoare dreapta) ----

local function createStatRow(order, label)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.BackgroundColor3 = ROW_BG
	row.Size = UDim2.new(1, 0, 0, 40)
	row.ZIndex = 22
	row.Parent = content

	Instance.new("UICorner", row).CornerRadius = UDim.new(0.2, 0)

	local labelText = Instance.new("TextLabel")
	labelText.BackgroundTransparency = 1
	labelText.Position = UDim2.new(0, 14, 0, 0)
	labelText.Size = UDim2.new(0.6, -14, 1, 0)
	labelText.Text = label
	labelText.TextColor3 = TEXT_DIM
	labelText.Font = FONT_BODY
	labelText.TextScaled = true
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.ZIndex = 23
	labelText.Parent = row

	local valueText = Instance.new("TextLabel")
	valueText.BackgroundTransparency = 1
	valueText.AnchorPoint = Vector2.new(1, 0)
	valueText.Position = UDim2.new(1, -14, 0, 0)
	valueText.Size = UDim2.new(0.4, -14, 1, 0)
	valueText.Text = "-"
	valueText.TextColor3 = TEXT_LIGHT
	valueText.Font = FONT_DISPLAY
	valueText.TextScaled = true
	valueText.TextXAlignment = Enum.TextXAlignment.Right
	valueText.ZIndex = 23
	valueText.Parent = row

	local function setValue(text, color)
		valueText.Text = text
		valueText.TextColor3 = color or TEXT_LIGHT
	end

	return row, setValue
end

-- Peste 1 milion, scriem prescurtat -- acelasi tipar ca formatMoney din
-- MainHUD.rbxmx, ca cifrele mari (Cash Earned) sa nu depaseasca randul.
local ABBREVIATIONS = {
	{1e12, "T"},
	{1e9, "B"},
	{1e6, "M"}
}

local function formatMoney(amount)
	amount = math.floor(amount)

	for _, entry in ipairs(ABBREVIATIONS) do
		local threshold, suffix = entry[1], entry[2]

		if amount >= threshold then
			local rounded = math.floor((amount / threshold) * 10) / 10
			local text = (rounded == math.floor(rounded))
				and tostring(math.floor(rounded))
				or string.format("%.1f", rounded)

			return "$" .. text .. suffix
		end
	end

	return "$" .. tostring(amount):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

-- Cash-ul curent (spre deosebire de Cash Earned, care se prescurteaza M/B/T)
-- se arata INTEGRAL, cu punct ca separator de mii (1.100.789) -- cerut
-- explicit, ca jucatorul sa vada suma exacta, nu una rotunjita.
local function formatFullNumber(amount)
	amount = math.floor(amount)
	-- Parantezele trunchiaza la O SINGURA valoare -- string.gsub intoarce
	-- (rezultat, numar_inlocuiri), iar fara paranteze, fiind ULTIMA expresie
	-- din return, AMBELE valori ies din functie. La locul de apel,
	-- setCash(formatFullNumber(...)) trimitea atunci 2 argumente in loc de
	-- unul -- numarul de inlocuiri ajungea in parametrul "color" al lui
	-- setValue (text, color), care apoi incerca sa-l puna in TextColor3
	-- ("Color3 expected, got number").
	return (tostring(amount):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", ""))
end

local function formatMinutes(totalMinutes)
	totalMinutes = totalMinutes or 0
	local hours = math.floor(totalMinutes / 60)
	local minutes = totalMinutes % 60
	return hours .. "h " .. minutes .. "m"
end

local leaderstats = player:WaitForChild("leaderstats")
local moneyValue = leaderstats:WaitForChild("Money")
local cashEarnedValue = leaderstats:WaitForChild("CashEarned")
local rebirthsValue = leaderstats:WaitForChild("Rebirths")
local timePlayedValue = leaderstats:WaitForChild("TimePlayed")

-- RobuxSpent nu mai e in "leaderstats" (mutat in HiddenStats, ca sa nu mai
-- apara in lista default de jucatori a Roblox -- cerut explicit).
local hiddenStats = player:WaitForChild("HiddenStats")
local robuxSpentValue = hiddenStats:WaitForChild("RobuxSpent")

local _, setCash = createStatRow(1, "💰 Cash")
local _, setCashEarned = createStatRow(2, "📈 Cash Earned")
local _, setRebirths = createStatRow(3, "🔁 Rebirths")
local _, setTimePlayed = createStatRow(4, "⏱️ Time Played")
local _, setRobuxSpent = createStatRow(5, "💎 Robux Spent")

local rankRow, setRank = createStatRow(6, "🏆 Cash Rank")
local timeRankRow, setTimeRank = createStatRow(7, "🏆 Time Rank")
local robuxRankRow, setRobuxRank = createStatRow(8, "🏆 Robux Rank")

local function refreshCash()
	setCash(formatFullNumber(moneyValue.Value))
end

local function refreshCashEarned()
	setCashEarned(formatMoney(cashEarnedValue.Value))
end

local function refreshRebirths()
	setRebirths(tostring(rebirthsValue.Value))
end

local function refreshTimePlayed()
	setTimePlayed(formatMinutes(timePlayedValue.Value))
end

local function refreshRobuxSpent()
	setRobuxSpent(tostring(robuxSpentValue.Value) .. " R$")
end

-- Ascundem randul complet daca jucatorul nu e in Top 100 la acel clasament
-- (in loc sa aratam "-", care ar sugera o eroare in loc de "nu esti clasat").
local function refreshRank(row, setValue, attributeName)
	local rank = player:GetAttribute(attributeName)

	if rank then
		row.Visible = true
		setValue("#" .. tostring(rank), ACCENT)
	else
		row.Visible = false
	end
end

local function refreshCashRank()
	refreshRank(rankRow, setRank, "CashRank")
end

local function refreshTimeRank()
	refreshRank(timeRankRow, setTimeRank, "TimeRank")
end

local function refreshRobuxRank()
	refreshRank(robuxRankRow, setRobuxRank, "RobuxRank")
end

refreshCash()
refreshCashEarned()
refreshRebirths()
refreshTimePlayed()
refreshRobuxSpent()
refreshCashRank()
refreshTimeRank()
refreshRobuxRank()
refreshEquippedTitle()

moneyValue:GetPropertyChangedSignal("Value"):Connect(refreshCash)
cashEarnedValue:GetPropertyChangedSignal("Value"):Connect(refreshCashEarned)
rebirthsValue:GetPropertyChangedSignal("Value"):Connect(refreshRebirths)
timePlayedValue:GetPropertyChangedSignal("Value"):Connect(refreshTimePlayed)
robuxSpentValue:GetPropertyChangedSignal("Value"):Connect(refreshRobuxSpent)
player:GetAttributeChangedSignal("CashRank"):Connect(refreshCashRank)
player:GetAttributeChangedSignal("TimeRank"):Connect(refreshTimeRank)
player:GetAttributeChangedSignal("RobuxRank"):Connect(refreshRobuxRank)
player:GetAttributeChangedSignal("EquippedTitle"):Connect(refreshEquippedTitle)

-- ================= Perks (agregat din TOATE sursele) =================
-- Formula reala (Stand/Rebirth/Pets/Cosmetice/VIP/Friend Boost/Speed Pass/
-- Starter Pack/Titluri) traieste DOAR server-side (SellManager/NPCManager,
-- module server-only CosmeticManager/PetManager) -- nu o reimplementam aici
-- (risc de derapaj intre doua copii ale aceleiasi formule). In schimb cerem
-- server-ului rezultatul deja calculat, prin PerkSummary.luau + RemoteFunction
-- GetPerkBreakdown (server/Managers/PerkBreakdownManager.server.luau).

local perksSection = Instance.new("Frame")
perksSection.Name = "PerksSection"
perksSection.LayoutOrder = 50
perksSection.BackgroundTransparency = 1
perksSection.AutomaticSize = Enum.AutomaticSize.Y
perksSection.Size = UDim2.new(1, 0, 0, 0)
perksSection.ZIndex = 22
perksSection.Parent = content

local perksLayout = Instance.new("UIListLayout")
perksLayout.SortOrder = Enum.SortOrder.LayoutOrder
perksLayout.Padding = UDim.new(0, 6)
perksLayout.Parent = perksSection

local perksOrder = 0
local function nextPerkOrder()
	perksOrder += 1
	return perksOrder
end

local function clearPerksSection()
	perksOrder = 0
	for _, child in ipairs(perksSection:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local function addSectionHeader(text)
	local header = Instance.new("TextLabel")
	header.LayoutOrder = nextPerkOrder()
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 30)
	header.Text = text
	header.TextColor3 = ACCENT
	header.TextStrokeColor3 = OUTLINE_DARK
	header.TextStrokeTransparency = 0
	header.Font = FONT_DISPLAY
	header.TextScaled = true
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.ZIndex = 22
	header.Parent = perksSection
end

local function addTotalRow(label, valueText)
	local row = Instance.new("Frame")
	row.LayoutOrder = nextPerkOrder()
	row.BackgroundColor3 = ROW_BG
	row.Size = UDim2.new(1, 0, 0, 34)
	row.ZIndex = 22
	row.Parent = perksSection

	Instance.new("UICorner", row).CornerRadius = UDim.new(0.2, 0)

	local labelLabel = Instance.new("TextLabel")
	labelLabel.BackgroundTransparency = 1
	labelLabel.Position = UDim2.new(0, 12, 0, 0)
	labelLabel.Size = UDim2.new(0.6, -12, 1, 0)
	labelLabel.Text = label
	labelLabel.TextColor3 = TEXT_LIGHT
	labelLabel.Font = FONT_BODY
	labelLabel.TextScaled = true
	labelLabel.TextXAlignment = Enum.TextXAlignment.Left
	labelLabel.ZIndex = 23
	labelLabel.Parent = row

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.AnchorPoint = Vector2.new(1, 0)
	valueLabel.Position = UDim2.new(1, -12, 0, 0)
	valueLabel.Size = UDim2.new(0.4, -12, 1, 0)
	valueLabel.Text = valueText
	valueLabel.TextColor3 = ACCENT
	valueLabel.Font = FONT_DISPLAY
	valueLabel.TextScaled = true
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.ZIndex = 23
	valueLabel.Parent = row
end

local function addSubRow(text)
	local row = Instance.new("TextLabel")
	row.LayoutOrder = nextPerkOrder()
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 22)
	row.Text = "    • " .. text
	row.TextColor3 = TEXT_DIM
	row.Font = FONT_BODY
	row.TextScaled = true
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.ZIndex = 22
	row.Parent = perksSection
end

local function formatPercent(amount)
	amount = amount or 0
	if amount == math.floor(amount) then
		return tostring(math.floor(amount)) .. "%"
	end
	return string.format("%.1f%%", amount)
end

local function formatMultiplier(amount)
	return "x" .. string.format("%.2f", amount or 1)
end

local SELL_SOURCES = {
	{"Stand", "Stand Level"},
	{"Rebirth", "Rebirths"},
	{"Pet", "Pets"},
	{"Cosmetic", "Cosmetics"}
}

local LUCK_SOURCES = {
	{"Stand", "Stand Level"},
	{"Rebirth", "Rebirths"},
	{"Pet", "Pets"},
	{"Cosmetic", "Cosmetics"},
	{"VIP", "VIP"},
	{"StarterPack", "Starter Pack"},
	{"Title", "Titles"}
}

local SPEED_SOURCES = {
	{"Stand", "Stand Level"},
	{"Rebirth", "Rebirths"},
	{"Pet", "Pets"},
	{"Cosmetic", "Cosmetics"},
	{"SpeedPass", "Speed Pass"}
}

-- Randurile per-sursa apar DOAR daca acea sursa contribuie cu ceva (> 0) --
-- altfel cardul s-ar umple cu "Starter Pack: +0%" pentru toti jucatorii care
-- nu-l au, ceea ce nu ajuta cu nimic.
local function addAdditiveCategory(icon, label, values, sources)
	addTotalRow(icon .. " " .. label, "+" .. formatPercent(values.Total))

	for _, source in ipairs(sources) do
		local key, sourceLabel = source[1], source[2]
		local amount = values[key] or 0

		if amount ~= 0 then
			addSubRow(sourceLabel .. ": +" .. formatPercent(amount))
		end
	end
end

local function addMoneyCategory(money)
	addTotalRow("💰 Money Multiplier", formatMultiplier(money.Total))

	if money.VIP and money.VIP > 1 then
		addSubRow("VIP: " .. formatMultiplier(money.VIP))
	end

	if money.Cosmetic and money.Cosmetic > 1 then
		addSubRow("Cosmetics: " .. formatMultiplier(money.Cosmetic))
	end

	if money.FriendBoostPercent and money.FriendBoostPercent > 0 then
		addSubRow("Friend Boost: +" .. formatPercent(money.FriendBoostPercent))
	end
end

local fetchingPerks = false

local function refreshPerks()
	if fetchingPerks then
		return
	end
	fetchingPerks = true

	task.spawn(function()
		local ok, breakdown = pcall(function()
			return getPerkBreakdownFunction:InvokeServer()
		end)

		fetchingPerks = false

		if not ok or typeof(breakdown) ~= "table" then
			return
		end

		clearPerksSection()
		addSectionHeader("✨ PERKS")
		addAdditiveCategory("💵", "Sell Bonus", breakdown.Sell, SELL_SOURCES)
		addAdditiveCategory("🍀", "Luck Bonus", breakdown.Luck, LUCK_SOURCES)
		addAdditiveCategory("⚡", "Speed Bonus", breakdown.Speed, SPEED_SOURCES)
		addMoneyCategory(breakdown.Money)
	end)
end

-- Doar cand panoul e deschis -- fara asta, orice schimbare de perk (echipare
-- pet, VIP cumparat etc) ar declansa un InvokeServer inutil chiar si cu
-- panoul inchis.
local function refreshPerksIfOpen()
	if overlay.Visible then
		refreshPerks()
	end
end

player:GetAttributeChangedSignal("IsVIP"):Connect(refreshPerksIfOpen)
player:GetAttributeChangedSignal("HasSpeedPass"):Connect(refreshPerksIfOpen)
player:GetAttributeChangedSignal("HasStarterPack"):Connect(refreshPerksIfOpen)
player:GetAttributeChangedSignal("FriendBoostPercent"):Connect(refreshPerksIfOpen)
rebirthsValue:GetPropertyChangedSignal("Value"):Connect(refreshPerksIfOpen)

task.spawn(function()
	local equippedPets = player:WaitForChild("EquippedPets", 10)
	if not equippedPets then
		return
	end

	local slot1 = equippedPets:WaitForChild("Slot1", 5)
	if slot1 then
		slot1:GetPropertyChangedSignal("Value"):Connect(refreshPerksIfOpen)
	end

	local slot2 = equippedPets:WaitForChild("Slot2", 5)
	if slot2 then
		slot2:GetPropertyChangedSignal("Value"):Connect(refreshPerksIfOpen)
	end
end)

-- ================= Comportament =================
-- Acelasi flag comun ca Settings/Store/Rebirth/etc -- ascunde tot restul
-- HUD-ului cat timp panoul e deschis (vezi HUDClient in MainHUD.rbxmx).

local function setOpen(open)
	overlay.Visible = open
	player:SetAttribute("ShopModalOpen", open)
	if open then
		card.Size = getMainFrameSize()
		refreshPerks()
	end
end

profileButton.Activated:Connect(function()
	setOpen(true)
end)

closeButton.Activated:Connect(function()
	setOpen(false)
end)

do
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if overlay.Visible then
				card.Size = getMainFrameSize()
			end
		end)
	end
end

player:GetAttributeChangedSignal("ShopModalOpen"):Connect(function()
	local isOpen = player:GetAttribute("ShopModalOpen")
	if not isOpen then
		overlay.Visible = false
	end
end)
