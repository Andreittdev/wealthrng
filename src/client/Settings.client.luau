local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local updateSettingsEvent = remotes:WaitForChild("UpdateSettings")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EconomyConfig"))

local FONT_DISPLAY = Enum.Font.Bangers
local FONT_BODY = Enum.Font.FredokaOne

-- Tema "settings/gri-albastru", distincta de restul panourilor.
local BG_DARK = Color3.fromRGB(22, 24, 28)
local BG_MID = Color3.fromRGB(38, 42, 50)
local CARD_BG = Color3.fromRGB(32, 35, 42)
local ACCENT = Color3.fromRGB(90, 160, 255)
local OUTLINE_DARK = Color3.fromRGB(14, 16, 20)
local TEXT_LIGHT = Color3.fromRGB(235, 238, 245)
local TEXT_DIM = Color3.fromRGB(165, 172, 185)
local GREEN_ON = Color3.fromRGB(90, 230, 130)
local RED_OFF = Color3.fromRGB(210, 75, 85)
local CLOSE_RED = Color3.fromRGB(210, 65, 75)

-- SoundGroup-uri pentru volum -- creare CENTRALIZATA (vezi SoundGroups.luau),
-- ca sa nu existe risc de cursa intre scripturi separate care creeaza fiecare
-- propriul grup.
local SoundGroups = require(script.Parent:WaitForChild("SoundGroups"))
local musicGroup = SoundGroups.Music
local sfxGroup = SoundGroups.SFX

local function computeIsMobile()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.X < 700 or viewport.Y < 500
end

local function getMainFrameSize()
	local isMobile = computeIsMobile()

	if not isMobile then
		return UDim2.fromOffset(420, 420)
	end

	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(400, 700)

	local width = math.min(viewport.X * 0.86, viewport.X - 24)
	local height = math.min(viewport.Y * 0.65, viewport.Y - 24)

	return UDim2.fromOffset(width, height)
end

-- ================= ScreenGui =================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SettingsGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ================= Buton de deschidere, stivuit sub Daily Rewards =================
-- Mutat din coltul sus-dreapta -- continua stiva verticala existenta
-- (Starter Pack Y=0, Rebirth Y=81, Daily Rewards Y=162, fiecare +81 fata de
-- precedentul pe desktop) -- Settings e urmatorul, la Y=243. Patrat (nu
-- buton lat cu text, ca restul stivei) -- ramane doar iconita, dar aliniat
-- pe aceeasi margine dreapta si cu aceeasi inaltime (66/40) ca sa se
-- potriveasca vizual in stiva.

local gearButton = Instance.new("TextButton")
gearButton.Name = "SettingsButton"
gearButton.AnchorPoint = Vector2.new(1, 0.5)
gearButton.Position = UDim2.new(1, -16, 0.5, 243)
gearButton.Size = UDim2.new(0, 66, 0, 66)
gearButton.BackgroundColor3 = BG_MID
gearButton.AutoButtonColor = false
gearButton.Text = "⚙️"
gearButton.TextScaled = true
gearButton.Font = FONT_BODY
gearButton.ZIndex = 10
gearButton.Parent = screenGui

Instance.new("UICorner", gearButton).CornerRadius = UDim.new(0.3, 0)

local gearStroke = Instance.new("UIStroke")
gearStroke.Color = ACCENT
gearStroke.Thickness = 2
gearStroke.Parent = gearButton

-- Pozitia/dimensiunea difera pe mobil, la fel ca restul stivei (StarterPack/
-- Rebirth/DailyRewards) -- Y=188 continua stiva mobila (DailyRewards
-- termina la 138+44=182, +6 gol = 188).
local function updateGearButtonLayout()
	local isMobile = computeIsMobile()

	if isMobile then
		gearButton.AnchorPoint = Vector2.new(1, 0)
		gearButton.Position = UDim2.new(1, -8, 0, 188)
		gearButton.Size = UDim2.new(0, 40, 0, 40)
	else
		gearButton.AnchorPoint = Vector2.new(1, 0.5)
		gearButton.Position = UDim2.new(1, -16, 0.5, 243)
		gearButton.Size = UDim2.new(0, 66, 0, 66)
	end
end

updateGearButtonLayout()

do
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateGearButtonLayout)
	end
end

-- ================= Overlay + Card =================

local overlay = Instance.new("Frame")
overlay.Name = "SettingsOverlay"
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
titleLabel.Text = "⚙️ SETTINGS"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextStrokeColor3 = OUTLINE_DARK
titleLabel.TextStrokeTransparency = 0
titleLabel.Font = FONT_DISPLAY
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 22
titleLabel.Parent = card

-- ================= Continut =================
-- ScrollingFrame, nu Frame simplu -- cu filtrele de Auto Buy (4 randuri in
-- plus, doar pentru cine detine pass-ul), continutul poate depasi usor
-- inaltimea cardului, mai ales pe mobil.

local content = Instance.new("ScrollingFrame")
content.BackgroundTransparency = 1
content.Position = UDim2.new(0, 20, 0, 70)
content.Size = UDim2.new(1, -40, 1, -90)
content.ZIndex = 22
content.BorderSizePixel = 0
content.ScrollBarThickness = 6
content.ScrollBarImageColor3 = ACCENT
content.CanvasSize = UDim2.new(0, 0, 0, 0)
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.Parent = card

local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 18)
contentLayout.Parent = content

-- ---- Toggle generic (parent optional -- implicit "content", dar folosit si
-- pentru randurile indentate din interiorul unui childrenContainer, vezi
-- createExpandableToggle mai jos) ----

local function createToggle(order, label, initialValue, onChanged, parent)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 40)
	row.Parent = parent or content

	local labelText = Instance.new("TextLabel")
	labelText.BackgroundTransparency = 1
	labelText.Size = UDim2.new(0.62, 0, 1, 0)
	labelText.Text = label
	labelText.TextColor3 = TEXT_LIGHT
	labelText.Font = FONT_BODY
	labelText.TextScaled = true
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.ZIndex = 23
	labelText.Parent = row

	local toggleButton = Instance.new("TextButton")
	toggleButton.AnchorPoint = Vector2.new(1, 0.5)
	toggleButton.Position = UDim2.new(1, 0, 0.5, 0)
	toggleButton.Size = UDim2.new(0, 76, 0, 34)
	toggleButton.AutoButtonColor = false
	toggleButton.Text = initialValue and "ON" or "OFF"
	toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	toggleButton.BackgroundColor3 = initialValue and GREEN_ON or RED_OFF
	toggleButton.Font = FONT_DISPLAY
	toggleButton.TextScaled = true
	toggleButton.ZIndex = 23
	toggleButton.Parent = row

	Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0.3, 0)

	local state = initialValue

	local function setVisual(value)
		state = value
		toggleButton.Text = value and "ON" or "OFF"
		toggleButton.BackgroundColor3 = value and GREEN_ON or RED_OFF
	end

	toggleButton.Activated:Connect(function()
		setVisual(not state)
		onChanged(state)
	end)

	return row, setVisual
end

-- ---- Toggle EXPANDABIL (Auto Buy Pass/Auto Sell Pass) -- ON/OFF master in
-- dreapta, ca la orice alt toggle, DAR eticheta din stanga e clickabila
-- separat (cu triunghi ▲/▼, varf in sus cand e colapsat, varf in jos cand e
-- extins) si extinde/ascunde un container cu sub-optiuni
-- (filtrele pe raritate) -- exact tiparul "ca la jocurile mari" cerut
-- explicit: dai click pe Auto Buy, iti apar dedesubt Auto Buy: Common/Rare/
-- Epic/Legendary. Containerul e Visible=false implicit (colapsat) --
-- UIListLayout-ul parintelui ignora automat copiii invizibili la asezare,
-- deci nu ramane un gol cand e inchis.
local function createExpandableToggle(order, label, initialValue, onChanged)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 40)
	row.Parent = content

	local labelButton = Instance.new("TextButton")
	labelButton.BackgroundTransparency = 1
	labelButton.Size = UDim2.new(0.62, 0, 1, 0)
	labelButton.Text = "▲ " .. label
	labelButton.TextColor3 = TEXT_LIGHT
	labelButton.Font = FONT_BODY
	labelButton.TextScaled = true
	labelButton.TextXAlignment = Enum.TextXAlignment.Left
	labelButton.AutoButtonColor = false
	labelButton.ZIndex = 23
	labelButton.Parent = row

	local toggleButton = Instance.new("TextButton")
	toggleButton.AnchorPoint = Vector2.new(1, 0.5)
	toggleButton.Position = UDim2.new(1, 0, 0.5, 0)
	toggleButton.Size = UDim2.new(0, 76, 0, 34)
	toggleButton.AutoButtonColor = false
	toggleButton.Text = initialValue and "ON" or "OFF"
	toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	toggleButton.BackgroundColor3 = initialValue and GREEN_ON or RED_OFF
	toggleButton.Font = FONT_DISPLAY
	toggleButton.TextScaled = true
	toggleButton.ZIndex = 23
	toggleButton.Parent = row

	Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0.3, 0)

	local state = initialValue

	local function setVisual(value)
		state = value
		toggleButton.Text = value and "ON" or "OFF"
		toggleButton.BackgroundColor3 = value and GREEN_ON or RED_OFF
	end

	toggleButton.Activated:Connect(function()
		setVisual(not state)
		onChanged(state)
	end)

	local childrenContainer = Instance.new("Frame")
	childrenContainer.LayoutOrder = order + 1
	childrenContainer.BackgroundTransparency = 1
	childrenContainer.AutomaticSize = Enum.AutomaticSize.Y
	childrenContainer.Size = UDim2.new(1, 0, 0, 0)
	childrenContainer.Visible = false
	childrenContainer.Parent = content

	local childrenLayout = Instance.new("UIListLayout")
	childrenLayout.SortOrder = Enum.SortOrder.LayoutOrder
	childrenLayout.Padding = UDim.new(0, 8)
	childrenLayout.Parent = childrenContainer

	local expanded = false

	labelButton.Activated:Connect(function()
		expanded = not expanded
		childrenContainer.Visible = expanded
		labelButton.Text = (expanded and "▼ " or "▲ ") .. label
	end)

	return row, setVisual, childrenContainer
end

-- ---- Slider generic (0-1), construit din Frame-uri -- Roblox nu are un
-- GuiObject de slider nativ. Track + fill + drag prin UserInputService.
local function createSlider(order, label, initialValue, onChanged)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 54)
	row.Parent = content

	local labelText = Instance.new("TextLabel")
	labelText.BackgroundTransparency = 1
	labelText.Size = UDim2.new(1, 0, 0, 22)
	labelText.Text = label
	labelText.TextColor3 = TEXT_LIGHT
	labelText.Font = FONT_BODY
	labelText.TextScaled = true
	labelText.TextXAlignment = Enum.TextXAlignment.Left
	labelText.ZIndex = 23
	labelText.Parent = row

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 0, 0, 28)
	track.Size = UDim2.new(1, 0, 0, 26)
	track.BackgroundColor3 = Color3.fromRGB(50, 54, 62)
	track.ZIndex = 23
	track.Parent = row

	Instance.new("UICorner", track).CornerRadius = UDim.new(0.5, 0)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = ACCENT
	fill.Size = UDim2.new(math.clamp(initialValue, 0, 1), 0, 1, 0)
	fill.BorderSizePixel = 0
	fill.ZIndex = 24
	fill.Parent = track

	Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)

	local dragging = false

	local function setFromInput(input)
		local relativeX = (input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X
		relativeX = math.clamp(relativeX, 0, 1)
		fill.Size = UDim2.new(relativeX, 0, 1, 0)
		onChanged(relativeX)
	end

	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromInput(input)
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromInput(input)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	local function setVisual(value)
		fill.Size = UDim2.new(math.clamp(value, 0, 1), 0, 1, 0)
	end

	return row, setVisual
end

-- ================= Grafica redusa (Low Graphics Mode) =================
-- Ascunde local copacii/tufele (~700 de piese, TownMapBuilder.server.luau)
-- -- doar pentru clientul curent (LocalTransparencyModifier: schimba ce vede
-- ACEST client, fara sa afecteze harta reala sau ce vad ceilalti jucatori).
-- Identificate dupa nume (TreeTrunk/TreeFoliage#/Bush#) -- singurul mod de a
-- le distinge de restul hartii, fiindca toate impart acelasi folder
-- Workspace.TownMap, alaturi de ziduri/drumuri/standuri.
local function isDecorationPart(part)
	return part.Name == "TreeTrunk" or part.Name:match("^TreeFoliage") or part.Name:match("^Bush")
end

local lowGraphicsMode = false

local function applyDecorationVisibility(part)
	if part:IsA("BasePart") and isDecorationPart(part) then
		part.LocalTransparencyModifier = lowGraphicsMode and 1 or 0
	end
end

local townMap = workspace:WaitForChild("TownMap", 10)
if townMap then
	for _, part in ipairs(townMap:GetChildren()) do
		applyDecorationVisibility(part)
	end
	-- Copacii/tufele se construiesc treptat la pornirea serverului (yield la
	-- fiecare 6) -- ChildAdded prinde si piesele care apar dupa ce am facut
	-- deja prima trecere, indiferent de cursa cu constructia hartii.
	townMap.ChildAdded:Connect(applyDecorationVisibility)
end

local function setLowGraphicsMode(enabled)
	lowGraphicsMode = enabled
	if not townMap then
		return
	end
	for _, part in ipairs(townMap:GetChildren()) do
		applyDecorationVisibility(part)
	end
end

-- ================= Trimitere schimbari catre server =================
-- Trimitem intreaga stare curenta la fiecare schimbare (nu doar campul
-- modificat) -- SettingsManager.server.luau accepta oricum un tabel partial,
-- dar e mai simplu de urmarit aici avand mereu toate valorile la zi.

local currentSettings = {
	NotificationsEnabled = player:GetAttribute("NotificationsEnabled") ~= false,
	LowGraphicsMode = player:GetAttribute("LowGraphicsMode") == true,
	MusicVolume = player:GetAttribute("MusicVolume") or 0.5,
	SFXVolume = player:GetAttribute("SFXVolume") or 0.5,
	AutoRebirthEnabled = player:GetAttribute("AutoRebirthEnabled") ~= false,
	SellDuplicatesEnabled = player:GetAttribute("SellDuplicatesEnabled") ~= false
}

musicGroup.Volume = currentSettings.MusicVolume
sfxGroup.Volume = currentSettings.SFXVolume
setLowGraphicsMode(currentSettings.LowGraphicsMode)

local function pushSettings()
	updateSettingsEvent:FireServer(currentSettings)
end

local _, setNotifVisual = createToggle(1, "Notifications", currentSettings.NotificationsEnabled, function(value)
	currentSettings.NotificationsEnabled = value
	pushSettings()
end)

local _, setLowGraphicsVisual = createToggle(2, "Low Graphics Mode", currentSettings.LowGraphicsMode, function(value)
	currentSettings.LowGraphicsMode = value
	setLowGraphicsMode(value)
	pushSettings()
end)

local _, setMusicVisual = createSlider(3, "Music Volume", currentSettings.MusicVolume, function(value)
	currentSettings.MusicVolume = value
	musicGroup.Volume = value
	pushSettings()
end)

local _, setSFXVisual = createSlider(4, "SFX Volume", currentSettings.SFXVolume, function(value)
	currentSettings.SFXVolume = value
	sfxGroup.Volume = value
	pushSettings()
end)

-- Randul asta apare DOAR daca detii Auto Rebirth Pass -- pentru restul
-- jucatorilor, toggle-ul n-ar avea niciun efect (RebirthManager.server.luau
-- verifica HasAutoRebirthPass inainte de orice), deci l-am ascunde ca sa nu
-- creeze confuzie ("de ce nu face nimic butonul asta").
local autoRebirthRow, setAutoRebirthVisual = createToggle(5, "Auto Rebirth", currentSettings.AutoRebirthEnabled, function(value)
	currentSettings.AutoRebirthEnabled = value
	pushSettings()
end)

local function refreshAutoRebirthRowVisibility()
	autoRebirthRow.Visible = player:GetAttribute("HasAutoRebirthPass") == true
end

refreshAutoRebirthRowVisibility()
player:GetAttributeChangedSignal("HasAutoRebirthPass"):Connect(refreshAutoRebirthRowVisibility)

-- Auto Buy Pass si Auto Sell Pass -- randuri EXPANDABILE ("ca la jocurile
-- mari"): master ON/OFF in dreapta + click pe eticheta extinde dedesubt
-- filtrele pe raritate (Common/Rare/Epic/Legendary). Auto Rebirth NU are
-- filtre pe raritate (n-are sens, rebirth-ul nu tine de raritatea unui item),
-- deci ramane randul simplu de mai sus.
local function buildAutoPassSection(order, label, masterEnabledKey, ownershipAttribute, filterPrefix, filterOptions)
	local masterRow, setMasterVisual, childrenContainer = createExpandableToggle(
		order,
		label,
		currentSettings[masterEnabledKey],
		function(value)
			currentSettings[masterEnabledKey] = value
			pushSettings()
		end
	)

	for i, option in ipairs(filterOptions) do
		local settingKey = filterPrefix .. option
		currentSettings[settingKey] = player:GetAttribute(settingKey) ~= false

		local _, setVisual = createToggle(i, "  " .. option, currentSettings[settingKey], function(value)
			currentSettings[settingKey] = value
			pushSettings()
		end, childrenContainer)

		player:GetAttributeChangedSignal(settingKey):Connect(function()
			local value = player:GetAttribute(settingKey) ~= false
			currentSettings[settingKey] = value
			setVisual(value)
		end)
	end

	local function refreshVisibility()
		local visible = player:GetAttribute(ownershipAttribute) == true
		masterRow.Visible = visible
		if not visible then
			childrenContainer.Visible = false
		end
	end

	refreshVisibility()
	player:GetAttributeChangedSignal(ownershipAttribute):Connect(refreshVisibility)

	player:GetAttributeChangedSignal(masterEnabledKey):Connect(function()
		local value = player:GetAttribute(masterEnabledKey) ~= false
		currentSettings[masterEnabledKey] = value
		setMasterVisual(value)
	end)
end

-- Auto Buy filtreaza pe RARITATE (Common/Rare/Epic/Legendary/Mythic).
currentSettings.AutoBuyPassEnabled = player:GetAttribute("AutoBuyPassEnabled") ~= false
buildAutoPassSection(6, "Auto Buy Pass", "AutoBuyPassEnabled", "HasAutoBuyPass", "AutoBuyFilter", Economy.ItemRarities)

-- Auto Sell filtreaza pe CATEGORIE (Clothing/Shoes/Electronics/Luxury/
-- Collectibles), NU pe raritate -- cerut explicit: vinde automat un item
-- doar daca piata categoriei lui e chiar pe plus (>= +1%), verificat server-
-- side in NPCManager.server.luau, nu doar pe baza raritatii lui.
currentSettings.AutoSellPassEnabled = player:GetAttribute("AutoSellPassEnabled") ~= false
buildAutoPassSection(8, "Auto Sell Pass", "AutoSellPassEnabled", "OwnsAutoSellPass", "AutoSellFilter", Economy.ItemCategories)

-- Cand e oprit, duplicatele de peturi din oua NU se mai vand automat pentru
-- cash -- raman in inventar (util pentru cine strange duplicate pentru un
-- viitor sistem de fuziune/Golden-Rainbow Pets). Implicit true (comportamentul
-- de dinainte, neschimbat pentru cine nu atinge setarea asta).
local _, setSellDuplicatesVisual = createToggle(9, "Sell Duplicates", currentSettings.SellDuplicatesEnabled, function(value)
	currentSettings.SellDuplicatesEnabled = value
	pushSettings()
end)

-- Corectie de cursa: acest script poate rula/citi atributele INAINTE ca
-- DataManager.ApplyData (alt script, fara ordine garantata fata de acesta)
-- sa fi apucat sa le seteze din salvarea reala -- fara asta, UI-ul pornea cu
-- valorile implicite chiar daca jucatorul avea altceva salvat, iar orice alta
-- interactiune ar fi retrimis (si suprascris) preferinta reala cu implicitul
-- gresit. Ascultam schimbarile si resincronizam UI-ul + starea locala oricand
-- atributul se seteaza, indiferent cand anume se intampla asta.
player:GetAttributeChangedSignal("NotificationsEnabled"):Connect(function()
	local value = player:GetAttribute("NotificationsEnabled") ~= false
	currentSettings.NotificationsEnabled = value
	setNotifVisual(value)
end)

player:GetAttributeChangedSignal("LowGraphicsMode"):Connect(function()
	local value = player:GetAttribute("LowGraphicsMode") == true
	currentSettings.LowGraphicsMode = value
	setLowGraphicsMode(value)
	setLowGraphicsVisual(value)
end)

player:GetAttributeChangedSignal("SellDuplicatesEnabled"):Connect(function()
	local value = player:GetAttribute("SellDuplicatesEnabled") ~= false
	currentSettings.SellDuplicatesEnabled = value
	setSellDuplicatesVisual(value)
end)

player:GetAttributeChangedSignal("MusicVolume"):Connect(function()
	local value = player:GetAttribute("MusicVolume") or 0.5
	currentSettings.MusicVolume = value
	musicGroup.Volume = value
	setMusicVisual(value)
end)

player:GetAttributeChangedSignal("SFXVolume"):Connect(function()
	local value = player:GetAttribute("SFXVolume") or 0.5
	currentSettings.SFXVolume = value
	sfxGroup.Volume = value
	setSFXVisual(value)
end)

player:GetAttributeChangedSignal("AutoRebirthEnabled"):Connect(function()
	local value = player:GetAttribute("AutoRebirthEnabled") ~= false
	currentSettings.AutoRebirthEnabled = value
	setAutoRebirthVisual(value)
end)

-- ================= Comportament =================

local function setOpen(open)
	overlay.Visible = open
	player:SetAttribute("ShopModalOpen", open)
	if open then
		card.Size = getMainFrameSize()
	end
end

gearButton.Activated:Connect(function()
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

-- Ascuns cat timp orice alt panou modal e deschis (acelasi flag comun ca
-- Starter Pack/Rebirth/Daily Rewards/Token Shop/Store/Index/Pets).
-- SideStackCollapsed -- comutatorul "<"/">" din SideStackToggle.client.luau,
-- ascunde/arata TOATA stiva (Starter Pack/Rebirth/Daily Rewards/Settings)
-- deodata, ca la jocurile mari. Se combina cu ShopModalOpen (nu doar il
-- inlocuieste) -- butonul ramane ascuns daca ORICARE din cele doua e activ.
local function updateGearVisibility()
	gearButton.Visible = not player:GetAttribute("ShopModalOpen") and not player:GetAttribute("SideStackCollapsed")
end

player:GetAttributeChangedSignal("ShopModalOpen"):Connect(updateGearVisibility)
player:GetAttributeChangedSignal("SideStackCollapsed"):Connect(updateGearVisibility)
