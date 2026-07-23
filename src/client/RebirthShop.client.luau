local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestRebirthEvent = remotes:WaitForChild("RequestRebirth")
local rebirthResultEvent = remotes:WaitForChild("RebirthResult")

local REQUIRED_LEVEL = Economy.Rebirth.RequiredStandLevel

local FONT_DISPLAY = Enum.Font.LuckiestGuy
local FONT_BODY = Enum.Font.FredokaOne

local PURPLE_LIGHT = Color3.fromRGB(196, 140, 255)
local PURPLE_MID = Color3.fromRGB(147, 51, 234)
local PURPLE_DEEP = Color3.fromRGB(76, 20, 130)
local OUTLINE_DARK = Color3.fromRGB(45, 10, 80)
local TEXT_LIGHT = Color3.fromRGB(240, 230, 255)
local GREEN_OK = Color3.fromRGB(90, 230, 130)
local RED_MISSING = Color3.fromRGB(255, 110, 110)

local function formatMoney(amount)
	local s = tostring(math.floor(amount))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return "$" .. formatted
end

-- ================= Date live ale jucatorului =================

local standLevelValue = player:WaitForChild("StandLevel", 10)
local leaderstats = player:WaitForChild("leaderstats")
local moneyValue = leaderstats:WaitForChild("Money")
local rebirthsValue = leaderstats:WaitForChild("Rebirths")
local tokensValue = player:WaitForChild("RebirthTokens", 10)

local function getStandLevel()
	return standLevelValue and standLevelValue.Value or 1
end

-- ================= ScreenGui =================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RebirthShop"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ================= Toggle button (dreapta, sub Starter Pack, mov) =================

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "RebirthButton"
toggleButton.AnchorPoint = Vector2.new(1, 0.5)
toggleButton.Position = UDim2.new(1, -16, 0.5, 81)
toggleButton.Size = UDim2.new(0, 156, 0, 66)
toggleButton.BackgroundColor3 = PURPLE_MID
toggleButton.AutoButtonColor = false
toggleButton.Text = ""
toggleButton.ZIndex = 10
toggleButton.Parent = screenGui

Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0.22, 0)

local toggleGradient = Instance.new("UIGradient")
toggleGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, PURPLE_LIGHT),
	ColorSequenceKeypoint.new(0.35, PURPLE_MID),
	ColorSequenceKeypoint.new(1, PURPLE_DEEP),
})
toggleGradient.Rotation = 90
toggleGradient.Parent = toggleButton

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = OUTLINE_DARK
toggleStroke.Thickness = 3
toggleStroke.Parent = toggleButton

local toggleTitle = Instance.new("TextLabel")
toggleTitle.BackgroundTransparency = 1
toggleTitle.Position = UDim2.new(0, 10, 0, 10)
toggleTitle.Size = UDim2.new(1, -20, 0, 26)
toggleTitle.Text = "REBIRTH"
toggleTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleTitle.TextStrokeColor3 = OUTLINE_DARK
toggleTitle.TextStrokeTransparency = 0
toggleTitle.Font = FONT_DISPLAY
toggleTitle.TextScaled = true
toggleTitle.ZIndex = 11
toggleTitle.Parent = toggleButton

local toggleSubtitle = Instance.new("TextLabel")
toggleSubtitle.BackgroundTransparency = 1
toggleSubtitle.Position = UDim2.new(0, 10, 0, 40)
toggleSubtitle.Size = UDim2.new(1, -20, 0, 16)
toggleSubtitle.Text = "Rebirths: 0"
toggleSubtitle.TextColor3 = TEXT_LIGHT
toggleSubtitle.Font = FONT_DISPLAY
toggleSubtitle.TextScaled = true
toggleSubtitle.ZIndex = 11
toggleSubtitle.Parent = toggleButton

-- Pe mobil, butonul e mult mai mic -- titlul+subtitlul (pixeli ficsi,
-- gandite pentru butonul de PC) s-ar suprapune. O eticheta simpla in loc,
-- tot actualizata live cu numarul de rebirth-uri.
local mobileLabel = Instance.new("TextLabel")
mobileLabel.Name = "MobileLabel"
mobileLabel.BackgroundTransparency = 1
mobileLabel.AnchorPoint = Vector2.new(0.5, 0.5)
mobileLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
mobileLabel.Size = UDim2.new(1, -10, 1, -10)
mobileLabel.Text = "REBIRTH"
mobileLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
mobileLabel.TextStrokeColor3 = OUTLINE_DARK
mobileLabel.TextStrokeTransparency = 0
mobileLabel.Font = FONT_DISPLAY
mobileLabel.TextScaled = true
mobileLabel.TextWrapped = true
mobileLabel.Visible = false
mobileLabel.ZIndex = 11
mobileLabel.Parent = toggleButton

local function addHoverPop(button)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), {Size = button.Size + UDim2.new(0, 6, 0, 6)}):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), {Size = button.Size - UDim2.new(0, 6, 0, 6)}):Play()
	end)
end

-- ================= Overlay + Card =================

local overlay = Instance.new("Frame")
overlay.Name = "RebirthOverlay"
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.45
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.Visible = false
overlay.ZIndex = 20
overlay.Parent = screenGui

local card = Instance.new("Frame")
card.Name = "Card"
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.new(0.5, 0, 0.5, 0)
card.Size = UDim2.new(0, 340, 0, 548)
card.BackgroundColor3 = PURPLE_MID
card.ClipsDescendants = true
card.ZIndex = 21
card.Parent = overlay

Instance.new("UICorner", card).CornerRadius = UDim.new(0, 22)

local cardStroke = Instance.new("UIStroke")
cardStroke.Color = OUTLINE_DARK
cardStroke.Thickness = 5
cardStroke.Parent = card

local cardGradient = Instance.new("UIGradient")
cardGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, PURPLE_LIGHT),
	ColorSequenceKeypoint.new(0.18, Color3.fromRGB(230, 210, 255)),
	ColorSequenceKeypoint.new(0.4, PURPLE_MID),
	ColorSequenceKeypoint.new(1, PURPLE_DEEP),
})
cardGradient.Rotation = 90
cardGradient.Parent = card

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -12, 0, 12)
closeButton.Size = UDim2.new(0, 32, 0, 32)
closeButton.BackgroundColor3 = OUTLINE_DARK
closeButton.Text = "✕"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Font = FONT_DISPLAY
closeButton.TextScaled = true
closeButton.ZIndex = 25
closeButton.Parent = card

Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0.5, 0)

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 0, 0, 18)
titleLabel.Size = UDim2.new(1, 0, 0, 48)
titleLabel.Text = "✨ REBIRTH"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextStrokeColor3 = OUTLINE_DARK
titleLabel.TextStrokeTransparency = 0
titleLabel.Font = FONT_DISPLAY
titleLabel.TextScaled = true
titleLabel.ZIndex = 22
titleLabel.Parent = card

local rebirthCountLabel = Instance.new("TextLabel")
rebirthCountLabel.BackgroundTransparency = 1
rebirthCountLabel.Position = UDim2.new(0, 0, 0, 70)
rebirthCountLabel.Size = UDim2.new(1, 0, 0, 24)
rebirthCountLabel.Text = "You have rebirthed 0 times"
rebirthCountLabel.TextColor3 = TEXT_LIGHT
rebirthCountLabel.Font = FONT_BODY
rebirthCountLabel.TextScaled = true
rebirthCountLabel.ZIndex = 22
rebirthCountLabel.Parent = card

-- ---- Cerinte (checklist) ----

local requirementsFrame = Instance.new("Frame")
requirementsFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
requirementsFrame.BackgroundTransparency = 0.85
requirementsFrame.Position = UDim2.new(0, 24, 0, 100)
requirementsFrame.Size = UDim2.new(1, -48, 0, 96)
requirementsFrame.ZIndex = 22
requirementsFrame.Parent = card

Instance.new("UICorner", requirementsFrame).CornerRadius = UDim.new(0.12, 0)

local reqLayout = Instance.new("UIListLayout")
reqLayout.Padding = UDim.new(0, 6)
reqLayout.SortOrder = Enum.SortOrder.LayoutOrder
reqLayout.Parent = requirementsFrame

local reqPadding = Instance.new("UIPadding")
reqPadding.PaddingTop = UDim.new(0, 8)
reqPadding.PaddingLeft = UDim.new(0, 12)
reqPadding.PaddingRight = UDim.new(0, 12)
reqPadding.Parent = requirementsFrame

local function createRequirementRow(order)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 34)
	row.LayoutOrder = order
	row.ZIndex = 22
	row.Parent = requirementsFrame

	local check = Instance.new("TextLabel")
	check.Name = "Check"
	check.BackgroundTransparency = 1
	check.Size = UDim2.new(0, 28, 1, 0)
	check.Text = "❌"
	check.TextScaled = true
	check.ZIndex = 22
	check.Parent = row

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 34, 0, 0)
	label.Size = UDim2.new(1, -34, 1, 0)
	label.TextColor3 = TEXT_LIGHT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = FONT_BODY
	label.TextScaled = true
	label.ZIndex = 22
	label.Parent = row

	return row, check, label
end

local levelRow, levelCheck, levelLabel = createRequirementRow(1)
local moneyRow, moneyCheck, moneyLabel = createRequirementRow(2)

-- ---- Perks-urile pentru URMATORUL rebirth (nu cumulate, nu pet-ul) ----

local perksTitle = Instance.new("TextLabel")
perksTitle.BackgroundTransparency = 1
perksTitle.Position = UDim2.new(0, 24, 0, 204)
perksTitle.Size = UDim2.new(1, -48, 0, 26)
perksTitle.Text = "Next Rebirth Perks:"
perksTitle.TextColor3 = Color3.fromRGB(255, 215, 90)
perksTitle.Font = FONT_DISPLAY
perksTitle.TextScaled = true
perksTitle.ZIndex = 22
perksTitle.Parent = card

local perksLabel = Instance.new("TextLabel")
perksLabel.BackgroundTransparency = 1
perksLabel.Position = UDim2.new(0, 24, 0, 230)
perksLabel.Size = UDim2.new(1, -48, 0, 46)
perksLabel.Text = "+0% Sell   +0% Luck   +0% Speed"
perksLabel.TextColor3 = GREEN_OK
perksLabel.TextWrapped = true
perksLabel.Font = FONT_BODY
perksLabel.TextScaled = true
perksLabel.ZIndex = 22
perksLabel.Parent = card

-- ---- Perks-urile CURENTE (cumulate din toate rebirth-urile facute pana acum) ----

local currentPerksTitle = Instance.new("TextLabel")
currentPerksTitle.BackgroundTransparency = 1
currentPerksTitle.Position = UDim2.new(0, 24, 0, 282)
currentPerksTitle.Size = UDim2.new(1, -48, 0, 26)
currentPerksTitle.Text = "Current Perks:"
currentPerksTitle.TextColor3 = GREEN_OK
currentPerksTitle.Font = FONT_DISPLAY
currentPerksTitle.TextScaled = true
currentPerksTitle.ZIndex = 22
currentPerksTitle.Parent = card

local currentPerksLabel = Instance.new("TextLabel")
currentPerksLabel.BackgroundTransparency = 1
currentPerksLabel.Position = UDim2.new(0, 24, 0, 308)
currentPerksLabel.Size = UDim2.new(1, -48, 0, 46)
currentPerksLabel.Text = "+0% Sell   +0% Luck   +0% Speed"
currentPerksLabel.TextColor3 = TEXT_LIGHT
currentPerksLabel.TextWrapped = true
currentPerksLabel.Font = FONT_BODY
currentPerksLabel.TextScaled = true
currentPerksLabel.ZIndex = 22
currentPerksLabel.Parent = card

local resetInfoLabel = Instance.new("TextLabel")
resetInfoLabel.BackgroundTransparency = 1
resetInfoLabel.Position = UDim2.new(0, 24, 0, 360)
resetInfoLabel.Size = UDim2.new(1, -48, 0, 40)
resetInfoLabel.Text = "Resets: Money & Stand Level  |  Keeps: Pets & Upgrades"
resetInfoLabel.TextColor3 = TEXT_LIGHT
resetInfoLabel.TextWrapped = true
resetInfoLabel.Font = FONT_BODY
resetInfoLabel.TextSize = 14
resetInfoLabel.ZIndex = 22
resetInfoLabel.Parent = card

-- Grup orizontal (text + iconita, in ordinea asta) -- UIListLayout centreaza
-- grupul ca intreg, iar AutomaticSize.X pe label face ca iconita sa se
-- lipeasca mereu chiar dupa numar, indiferent cate cifre are.
local tokenRow = Instance.new("Frame")
tokenRow.BackgroundTransparency = 1
tokenRow.Position = UDim2.new(0, 24, 0, 406)
tokenRow.Size = UDim2.new(1, -48, 0, 26)
tokenRow.ZIndex = 22
tokenRow.Parent = card

local tokenRowLayout = Instance.new("UIListLayout")
tokenRowLayout.FillDirection = Enum.FillDirection.Horizontal
tokenRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
tokenRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tokenRowLayout.Padding = UDim.new(0, 2)
tokenRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
tokenRowLayout.Parent = tokenRow

local tokenLabel = Instance.new("TextLabel")
tokenLabel.BackgroundTransparency = 1
tokenLabel.AutomaticSize = Enum.AutomaticSize.X
tokenLabel.Size = UDim2.new(0, 0, 1, 0)
tokenLabel.LayoutOrder = 1
tokenLabel.Text = "Rebirth Tokens: 0"
tokenLabel.TextColor3 = TEXT_LIGHT
tokenLabel.Font = FONT_BODY
tokenLabel.TextSize = 20
tokenLabel.ZIndex = 22
tokenLabel.Parent = tokenRow

local tokenIcon = Instance.new("ImageLabel")
tokenIcon.BackgroundTransparency = 1
tokenIcon.Size = UDim2.new(0, 22, 0, 22)
tokenIcon.LayoutOrder = 2
tokenIcon.Image = "rbxassetid://73268562302125"
tokenIcon.ZIndex = 22
tokenIcon.Parent = tokenRow

-- ---- Buton Rebirth ----

local rebirthButton = Instance.new("TextButton")
rebirthButton.Name = "RebirthConfirmButton"
rebirthButton.AnchorPoint = Vector2.new(0.5, 1)
rebirthButton.Position = UDim2.new(0.5, 0, 1, -24)
rebirthButton.Size = UDim2.new(1, -48, 0, 54)
rebirthButton.BackgroundColor3 = RED_MISSING
rebirthButton.AutoButtonColor = false
rebirthButton.Text = "REBIRTH"
rebirthButton.TextColor3 = Color3.fromRGB(255, 255, 255)
rebirthButton.Font = FONT_DISPLAY
rebirthButton.TextScaled = true
rebirthButton.ZIndex = 22
rebirthButton.Parent = card

Instance.new("UICorner", rebirthButton).CornerRadius = UDim.new(0.3, 0)

local rebirthButtonStroke = Instance.new("UIStroke")
rebirthButtonStroke.Color = OUTLINE_DARK
rebirthButtonStroke.Thickness = 3
rebirthButtonStroke.Parent = rebirthButton

-- Fara padding, TextScaled calculeaza fontul dupa latimea INTREAGA a
-- butonului -- textul "REBIRTH NOW" ajungea sa atinga/depaseasca vizual
-- coltul rotunjit (UICorner). Padding-ul lasa margine reala, deci fontul
-- calculat de TextScaled iese automat mai mic si incape sigur in buton.
local rebirthButtonPadding = Instance.new("UIPadding")
rebirthButtonPadding.PaddingLeft = UDim.new(0, 20)
rebirthButtonPadding.PaddingRight = UDim.new(0, 20)
rebirthButtonPadding.PaddingTop = UDim.new(0, 10)
rebirthButtonPadding.PaddingBottom = UDim.new(0, 2)
rebirthButtonPadding.Parent = rebirthButton

-- ================= Actualizare live a starii =================

local isEligible = false

-- Retinute la nivel de modul (nu doar locale in refreshState) -- butonul are
-- nevoie de ele cand jucatorul apasa desi nu e eligibil, ca sa stie EXACT ce
-- ii lipseste (Stand Level sau bani), nu doar ca "nu poate".
local missingLevel = false
local missingMoney = false

local function refreshState()
	local level = getStandLevel()
	local money = moneyValue.Value
	local rebirths = rebirthsValue.Value
	local tokens = tokensValue and tokensValue.Value or 0

	local requiredMoney = Economy.Rebirth.GetRequiredMoney(rebirths + 1)

	local hasLevel = level >= REQUIRED_LEVEL
	local hasMoney = money >= requiredMoney

	missingLevel = not hasLevel
	missingMoney = not hasMoney

	levelCheck.Text = hasLevel and "✅" or "❌"
	levelLabel.Text = "Stand Level " .. level .. " / " .. REQUIRED_LEVEL
	levelLabel.TextColor3 = hasLevel and GREEN_OK or RED_MISSING

	moneyCheck.Text = hasMoney and "✅" or "❌"
	moneyLabel.Text = formatMoney(money) .. " / " .. formatMoney(requiredMoney)
	moneyLabel.TextColor3 = hasMoney and GREEN_OK or RED_MISSING

	rebirthCountLabel.Text = "You have rebirthed " .. rebirths .. " time" .. (rebirths == 1 and "" or "s")

	local nextPerks = Economy.Rebirth.GetPerks(rebirths + 1)
	perksLabel.Text = "+" .. nextPerks.Sell .. "% Sell   +" .. nextPerks.Luck .. "% Luck   +" .. nextPerks.Speed .. "% Speed"

	-- Bonusul TOTAL, cumulat din toate rebirth-urile facute pana acum (activ
	-- chiar acum, permanent) -- nu doar cel pe care il aduce urmatorul rebirth.
	local currentBonuses = Economy.Rebirth.GetCumulativeBonuses(rebirths)
	currentPerksLabel.Text = "+" .. currentBonuses.Sell .. "% Sell   +" .. currentBonuses.Luck .. "% Luck   +" .. currentBonuses.Speed .. "% Speed"

	tokenLabel.Text = "Rebirth Tokens: " .. tokens

	toggleSubtitle.Text = "Rebirths: " .. rebirths

	isEligible = hasLevel and hasMoney

	if isEligible then
		rebirthButton.BackgroundColor3 = GREEN_OK
		rebirthButton.Text = "REBIRTH NOW"
	else
		rebirthButton.BackgroundColor3 = RED_MISSING
		rebirthButton.Text = "LOCKED"
	end
end

refreshState()

moneyValue:GetPropertyChangedSignal("Value"):Connect(refreshState)
rebirthsValue:GetPropertyChangedSignal("Value"):Connect(refreshState)
if standLevelValue then
	standLevelValue:GetPropertyChangedSignal("Value"):Connect(refreshState)
end
if tokensValue then
	tokensValue:GetPropertyChangedSignal("Value"):Connect(refreshState)
end

-- ================= Scalare responsive (mobil) =================

local cardScale = Instance.new("UIScale")
cardScale.Parent = card

local BASE_VIEWPORT_WIDTH = 1200
local MIN_UI_SCALE = 0.75

-- TouchEnabled singur nu e de incredere -- verificam si dimensiunea reala a
-- ecranului (acelasi fix aplicat si la EggShopGui/TokenShop/StoreGui).
local function computeIsMobile()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.X < 700 or viewport.Y < 500
end

-- Pe telefon (ecran landscape, scund), stiva Starter Pack/Rebirth/Daily
-- Rewards din mijlocul ecranului putea iesi de pe ecran/peste joystick --
-- pe mobil, butonul de Rebirth se muta sub cel de Starter Pack, sus-dreapta,
-- compact, in loc sa creasca in jos de la centrul ecranului.
local function updateUIScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local isMobile = computeIsMobile()

	if isMobile then
		-- Sub Starter Pack (48 + 42 inaltime + 6 gol) -- pornea prea sus
		-- inainte (52), lipit aproape de primul buton.
		toggleButton.AnchorPoint = Vector2.new(1, 0)
		toggleButton.Position = UDim2.new(1, -8, 0, 96)
		toggleButton.Size = UDim2.new(0, 102, 0, 36)

		-- MIN_UI_SCALE (0.75) era un scale FIX -- cardul de baza (340x548px)
		-- la 0.75 ramane 255x411px, mai mare decat inaltimea disponibila pe
		-- un telefon landscape (ecran lat-dar-scund), deci iesea pe sub
		-- marginea ecranului. Calculam scale-ul din dimensiunea REALA a
		-- ecranului, ca sa incapa garantat, indiferent cat de mic e telefonul.
		local fitScale = math.min(
			(camera.ViewportSize.X * 0.78) / 340,
			(camera.ViewportSize.Y * 0.70) / 548
		)
		cardScale.Scale = math.min(MIN_UI_SCALE, fitScale)
	else
		toggleButton.AnchorPoint = Vector2.new(1, 0.5)
		toggleButton.Position = UDim2.new(1, -16, 0.5, 81)
		toggleButton.Size = UDim2.new(0, 156, 0, 66)
		cardScale.Scale = math.clamp(camera.ViewportSize.X / BASE_VIEWPORT_WIDTH, MIN_UI_SCALE, 1)
	end

	toggleTitle.Visible = not isMobile
	toggleSubtitle.Visible = not isMobile
	mobileLabel.Visible = isMobile
end

local viewportConnection = nil

local function bindCamera()
	updateUIScale()

	-- Deconectam handler-ul vechi inainte sa conectam unul nou -- altfel
	-- fiecare schimbare de CurrentCamera adauga inca o conexiune, fara sa o
	-- scoata pe cea veche pe niciun teren.
	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end

	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateUIScale)
	end
end

bindCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

-- ================= Coordonare cu celelalte shop-uri =================
-- Un singur flag comun pe player -- cand se deschide ORICE panou (Starter
-- Pack, Rebirth, Daily Rewards, Token Shop), toate butoanele astea de pe
-- ecran se ascund, ca sa nu ramana unul peste altul/langa cardul deschis.
local function setShopModalOpen(open)
	player:SetAttribute("ShopModalOpen", open)
end

-- SideStackCollapsed -- comutatorul "<"/">" din SideStackToggle.client.luau,
-- ascunde/arata TOATA stiva (Starter Pack/Rebirth/Daily Rewards/Settings)
-- deodata, ca la jocurile mari. Se combina cu ShopModalOpen (nu doar il
-- inlocuieste) -- butonul ramane ascuns daca ORICARE din cele doua e activ.
local function updateToggleVisibility()
	toggleButton.Visible = not player:GetAttribute("ShopModalOpen") and not player:GetAttribute("SideStackCollapsed")
end

player:GetAttributeChangedSignal("ShopModalOpen"):Connect(updateToggleVisibility)
player:GetAttributeChangedSignal("SideStackCollapsed"):Connect(updateToggleVisibility)

-- ================= Behaviour =================

local isOpen = false

local function setOpen(open)
	if open == isOpen then
		return
	end
	isOpen = open
	setShopModalOpen(open)

	if open then
		refreshState()
		overlay.Visible = true
		card.Size = UDim2.new(0, 280, 0, 390)
		TweenService:Create(
			card,
			TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Size = UDim2.new(0, 340, 0, 548)}
		):Play()
	else
		overlay.Visible = false
	end
end

toggleButton.Activated:Connect(function()
	setOpen(not isOpen)
end)

closeButton.Activated:Connect(function()
	setOpen(false)
end)

addHoverPop(toggleButton)

-- Cand jucatorul apasa desi butonul e "LOCKED", nu se intampla nimic vizibil
-- inainte -- acum arata explicit ce lipseste (Stand Level, apoi bani, in
-- aceeasi ordine ca verificarea serverului) direct pe buton, cateva secunde,
-- inainte sa revina la "LOCKED". showMissingReasonUntil evita sa se suprapuna
-- doua mesaje daca jucatorul apasa repetat.
local showMissingReasonUntil = 0

-- Rebirth-ul reseteaza Money/Stand Level/Inventory, deci un click gresit e
-- costisitor -- aratam MEREU o confirmare Da/Anuleaza inainte de FireServer
-- (nu mai e optionala din Settings -- cerut explicit).
local function showRebirthConfirmation(onConfirm)
	local confirmOverlay = Instance.new("Frame")
	confirmOverlay.Name = "RebirthConfirmOverlay"
	confirmOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	confirmOverlay.BackgroundTransparency = 0.4
	confirmOverlay.Size = UDim2.new(1, 0, 1, 0)
	confirmOverlay.ZIndex = 50
	-- Active=true -- un Frame simplu NU blocheaza click-urile catre ce e in
	-- spate implicit (doar butoanele fac asta), deci fara asta butonul X al
	-- panoului principal ramanea clickabil PRIN acest overlay.
	confirmOverlay.Active = true
	-- Parentat in "overlay" (nu in screenGui direct) -- ca sa dispara automat
	-- cand panoul principal se inchide (overlay.Visible = false in setOpen).
	-- Inainte era frate cu panoul, nu copil, deci ramanea pe ecran, clickabil,
	-- chiar si dupa ce jucatorul "inchidea" Rebirth Shop-ul.
	confirmOverlay.Parent = overlay

	local confirmCard = Instance.new("Frame")
	confirmCard.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmCard.Position = UDim2.new(0.5, 0, 0.5, 0)
	confirmCard.Size = UDim2.new(0, 340, 0, 180)
	confirmCard.BackgroundColor3 = PURPLE_DEEP
	confirmCard.ZIndex = 51
	confirmCard.Parent = confirmOverlay

	Instance.new("UICorner", confirmCard).CornerRadius = UDim.new(0, 16)

	local confirmStroke = Instance.new("UIStroke")
	confirmStroke.Color = PURPLE_LIGHT
	confirmStroke.Thickness = 3
	confirmStroke.Parent = confirmCard

	local confirmText = Instance.new("TextLabel")
	confirmText.BackgroundTransparency = 1
	confirmText.Position = UDim2.new(0, 16, 0, 16)
	confirmText.Size = UDim2.new(1, -32, 0, 90)
	confirmText.Text = "Rebirth resets your Money, Stand Level, and Inventory. Are you sure?"
	confirmText.TextColor3 = TEXT_LIGHT
	confirmText.TextWrapped = true
	confirmText.Font = FONT_BODY
	confirmText.TextScaled = true
	confirmText.ZIndex = 52
	confirmText.Parent = confirmCard

	local yesButton = Instance.new("TextButton")
	yesButton.AnchorPoint = Vector2.new(0, 1)
	yesButton.Position = UDim2.new(0, 16, 1, -16)
	yesButton.Size = UDim2.new(0.45, -8, 0, 44)
	yesButton.AutoButtonColor = false
	yesButton.BackgroundColor3 = GREEN_OK
	yesButton.Text = "Yes, Rebirth"
	yesButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	yesButton.Font = FONT_DISPLAY
	yesButton.TextScaled = true
	yesButton.ZIndex = 52
	yesButton.Parent = confirmCard
	Instance.new("UICorner", yesButton).CornerRadius = UDim.new(0.2, 0)

	local noButton = Instance.new("TextButton")
	noButton.AnchorPoint = Vector2.new(1, 1)
	noButton.Position = UDim2.new(1, -16, 1, -16)
	noButton.Size = UDim2.new(0.45, -8, 0, 44)
	noButton.AutoButtonColor = false
	noButton.BackgroundColor3 = RED_MISSING
	noButton.Text = "Cancel"
	noButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	noButton.Font = FONT_DISPLAY
	noButton.TextScaled = true
	noButton.ZIndex = 52
	noButton.Parent = confirmCard
	Instance.new("UICorner", noButton).CornerRadius = UDim.new(0.2, 0)

	yesButton.Activated:Connect(function()
		confirmOverlay:Destroy()
		onConfirm()
	end)

	noButton.Activated:Connect(function()
		confirmOverlay:Destroy()
	end)
end

rebirthButton.Activated:Connect(function()
	if not isEligible then
		rebirthButton.Text = missingLevel and "Not enough Stand Level" or "Not enough Money"

		local myClickTime = os.clock()
		showMissingReasonUntil = myClickTime

		task.delay(1.5, function()
			if showMissingReasonUntil == myClickTime and not isEligible then
				rebirthButton.Text = "LOCKED"
			end
		end)

		return
	end

	-- Confirmarea e OBLIGATORIE, nu mai e optionala din Settings -- cerut
	-- explicit, rebirth-ul trebuie sa ceara mereu confirmare, indiferent de
	-- orice.
	showRebirthConfirmation(function()
		requestRebirthEvent:FireServer()
	end)
end)

rebirthResultEvent.OnClientEvent:Connect(function(data)
	if data and data.Success then
		setOpen(false)
	end
	refreshState()
end)
