local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestStatusEvent = remotes:WaitForChild("RequestDailyStatus")
local statusResultEvent = remotes:WaitForChild("DailyStatusResult")
local requestClaimEvent = remotes:WaitForChild("RequestDailyClaim")
local claimResultEvent = remotes:WaitForChild("DailyClaimResult")

local FONT_DISPLAY = Enum.Font.Bangers
local FONT_BODY = Enum.Font.FredokaOne

-- Tema "calendar/albastru", diferita de auriul Starter Pack, movul Rebirth
-- si portocaliul Token Shop.
local BG_DARK = Color3.fromRGB(14, 24, 32)
local BG_MID = Color3.fromRGB(22, 46, 58)
local CARD_BG = Color3.fromRGB(24, 42, 52)
local CYAN_ACCENT = Color3.fromRGB(90, 210, 255)
local OUTLINE_DARK = Color3.fromRGB(12, 30, 38)
local TEXT_LIGHT = Color3.fromRGB(232, 244, 248)
local TEXT_DIM = Color3.fromRGB(160, 190, 200)
local GREEN_OK = Color3.fromRGB(90, 230, 130)
local GRAY_LOCKED = Color3.fromRGB(46, 58, 64)

-- Asteptam un marker sigur ca datele au fost aplicate de DataManager
-- (acelasi truc folosit si de RebirthShop.client.luau) -- evita o cursa cu
-- scripturile de server care initializeaza datele jucatorului.
player:WaitForChild("RebirthTokens", 10)

-- ================= Responsive sizing (acelasi limbaj ca EggShopGui/TokenShop) ====

local function computeIsMobile()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.X < 700 or viewport.Y < 500
end

local function getMainFrameSize(scaleFactor)
	scaleFactor = scaleFactor or 1
	local isMobile = computeIsMobile()

	if not isMobile then
		-- Pe PC cele 7 zile incap intotdeauna pe un singur rand. Latimea (760)
		-- lasa loc de rezerva sigur pentru cele 7 carduri, vezi setUniformGrid.
		-- Inaltimea a crescut fata de 300 -- butonul de revendicare s-a
		-- micsorat, iar spatiul eliberat s-a dus la carduri (mai mari).
		return UDim2.fromOffset(760 * scaleFactor, 270 * scaleFactor)
	end

	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(400, 700)

	-- Pe mobil, cele 7 zile se resfira pe mai multe randuri -- lasam loc
	-- rezonabil, nu aproape tot ecranul; daca tot nu incape, ScrollingFrame-ul
	-- de mai jos preia diferenta in loc sa taie/suprapuna continutul.
	local width = math.min(viewport.X * 0.85, viewport.X - 24) * scaleFactor
	local height = math.min(viewport.Y * 0.75, viewport.Y - 24) * scaleFactor

	return UDim2.fromOffset(width, height)
end

-- ================= ScreenGui =================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DailyRewards"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ================= Buton pe ecran, stivuit sub Rebirth =================

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "DailyRewardsButton"
toggleButton.AnchorPoint = Vector2.new(1, 0.5)
toggleButton.Position = UDim2.new(1, -16, 0.5, 162)
toggleButton.Size = UDim2.new(0, 156, 0, 66)
toggleButton.BackgroundColor3 = BG_MID
toggleButton.AutoButtonColor = false
toggleButton.Text = ""
toggleButton.ZIndex = 10
toggleButton.Parent = screenGui

Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0.22, 0)

local toggleGradient = Instance.new("UIGradient")
toggleGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, BG_MID),
	ColorSequenceKeypoint.new(1, BG_DARK),
})
toggleGradient.Rotation = 90
toggleGradient.Parent = toggleButton

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = CYAN_ACCENT
toggleStroke.Thickness = 3
toggleStroke.Parent = toggleButton

local toggleTitle = Instance.new("TextLabel")
toggleTitle.BackgroundTransparency = 1
toggleTitle.Position = UDim2.new(0, 10, 0, 8)
toggleTitle.Size = UDim2.new(1, -20, 0, 28)
toggleTitle.Text = "🎁 DAILY REWARDS"
toggleTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleTitle.Font = FONT_DISPLAY
toggleTitle.TextScaled = true
toggleTitle.TextXAlignment = Enum.TextXAlignment.Left
toggleTitle.ZIndex = 11
toggleTitle.Parent = toggleButton

local toggleSubtitle = Instance.new("TextLabel")
toggleSubtitle.BackgroundTransparency = 1
toggleSubtitle.Position = UDim2.new(0, 10, 0, 38)
toggleSubtitle.Size = UDim2.new(1, -20, 0, 20)
toggleSubtitle.Text = "..."
toggleSubtitle.TextColor3 = TEXT_DIM
toggleSubtitle.Font = FONT_BODY
toggleSubtitle.TextScaled = true
toggleSubtitle.TextXAlignment = Enum.TextXAlignment.Left
toggleSubtitle.ZIndex = 11
toggleSubtitle.Parent = toggleButton

-- Pe mobil, butonul e mult mai mic -- titlul+subtitlul (pixeli ficsi,
-- gandite pentru butonul de PC) s-ar suprapune. Doua etichete mici, fara
-- emoji: "DAILY REWARDS" sus, timer/READY jos (tot actualizat live, vezi
-- refreshToggleSubtitle).
local mobileTitle = Instance.new("TextLabel")
mobileTitle.Name = "MobileTitle"
mobileTitle.BackgroundTransparency = 1
mobileTitle.Position = UDim2.new(0, 6, 0, 3)
mobileTitle.Size = UDim2.new(1, -12, 0, 18)
mobileTitle.Text = "DAILY REWARDS"
mobileTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
mobileTitle.Font = FONT_DISPLAY
mobileTitle.TextScaled = true
mobileTitle.Visible = false
mobileTitle.ZIndex = 11
mobileTitle.Parent = toggleButton

local mobileStatus = Instance.new("TextLabel")
mobileStatus.Name = "MobileStatus"
mobileStatus.BackgroundTransparency = 1
mobileStatus.Position = UDim2.new(0, 6, 0, 22)
mobileStatus.Size = UDim2.new(1, -12, 0, 16)
mobileStatus.Text = "..."
mobileStatus.TextColor3 = TEXT_DIM
mobileStatus.Font = FONT_BODY
mobileStatus.TextScaled = true
mobileStatus.Visible = false
mobileStatus.ZIndex = 11
mobileStatus.Parent = toggleButton

local function addHoverPop(button)
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), {Size = button.Size + UDim2.new(0, 6, 0, 4)}):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), {Size = button.Size - UDim2.new(0, 6, 0, 4)}):Play()
	end)
end

addHoverPop(toggleButton)

-- Pe telefon (ecran landscape, scund), stiva Starter Pack/Rebirth/Daily
-- Rewards din mijlocul ecranului putea iesi de pe ecran/peste joystick --
-- pe mobil, butonul de Daily Rewards se muta sub cele doua de mai sus,
-- sus-dreapta, compact.
local function updateToggleLayout()
	local isMobile = computeIsMobile()

	if isMobile then
		-- Sub Rebirth (96 + 36 inaltime + 6 gol) -- pornea prea sus inainte (92).
		-- Inaltimea a crescut la 44 (de la 36) ca sa incapa doua randuri de
		-- text (titlu + status), fara sa se suprapuna.
		toggleButton.AnchorPoint = Vector2.new(1, 0)
		toggleButton.Position = UDim2.new(1, -8, 0, 138)
		toggleButton.Size = UDim2.new(0, 102, 0, 44)
	else
		toggleButton.AnchorPoint = Vector2.new(1, 0.5)
		toggleButton.Position = UDim2.new(1, -16, 0.5, 162)
		toggleButton.Size = UDim2.new(0, 156, 0, 66)
	end

	toggleTitle.Visible = not isMobile
	toggleSubtitle.Visible = not isMobile
	mobileTitle.Visible = isMobile
	mobileStatus.Visible = isMobile
end

updateToggleLayout()

do
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateToggleLayout)
	end
end

-- ================= Overlay + Card =================

local overlay = Instance.new("Frame")
overlay.Name = "DailyRewardsOverlay"
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.4
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

Instance.new("UICorner", card).CornerRadius = UDim.new(0, 20)

local cardStroke = Instance.new("UIStroke")
cardStroke.Color = CYAN_ACCENT
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
closeButton.ZIndex = 25
closeButton.Parent = card

Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 10)

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 20, 0, 16)
titleLabel.Size = UDim2.new(1, -80, 0, 38)
titleLabel.Text = "🎁 DAILY REWARDS"
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
subtitleLabel.Position = UDim2.new(0, 20, 0, 54)
subtitleLabel.Size = UDim2.new(1, -80, 0, 20)
subtitleLabel.Text = "Log in every day for a streak of rewards"
subtitleLabel.TextColor3 = TEXT_DIM
subtitleLabel.Font = FONT_BODY
subtitleLabel.TextSize = 14
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.ZIndex = 22
subtitleLabel.Parent = card

-- ---- Iconite premium (2D, fara emoji) -- acelasi limbaj vizual (glow +
-- gradient + shine) ca la Token Shop, cu o forma distincta per tip de reward.

local GOLD_ICON = Color3.fromRGB(255, 205, 95)
local PET_PURPLE = Color3.fromRGB(210, 130, 255)
local FIRE_ORANGE = Color3.fromRGB(255, 140, 45)
local BRONZE_LIGHT = Color3.fromRGB(224, 155, 90)
local BRONZE_DARK = Color3.fromRGB(100, 56, 26)
local SILVER_LIGHT = Color3.fromRGB(235, 240, 245)
local SILVER_DARK = Color3.fromRGB(110, 128, 145)

local function iconShape(parent, sizeX, sizeY, offsetX, offsetY, color, zIndex, cornerScale)
	local shape = Instance.new("Frame")
	shape.AnchorPoint = Vector2.new(0.5, 0.5)
	shape.Position = UDim2.new(0.5, offsetX, 0.5, offsetY)
	shape.Size = UDim2.fromOffset(sizeX, sizeY)
	shape.BackgroundColor3 = color
	shape.BorderSizePixel = 0
	shape.ZIndex = zIndex
	shape.Parent = parent
	Instance.new("UICorner", shape).CornerRadius = UDim.new(cornerScale or 0.5, 0)
	return shape
end

local function iconOutline(instance, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency or 0
	stroke.Parent = instance
	return stroke
end

local function iconGlow(container, color)
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromOffset(44, 44)
	glow.BackgroundColor3 = color
	glow.BackgroundTransparency = 0.65
	glow.BorderSizePixel = 0
	glow.ZIndex = 22
	glow.Parent = container
	Instance.new("UICorner", glow).CornerRadius = UDim.new(0.5, 0)
end

-- Fundal metalic static (bronz/argintiu) -- fara curcubeu, doar un gradient
-- pe doua tonuri, pentru Day 2 si Day 4 (un pas sub aura "exclusiva" de
-- la Day 7, dar tot vizibil mai special decat restul zilelor).
local function metallicGlow(container, lightColor, darkColor)
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromOffset(44, 44)
	glow.BackgroundColor3 = lightColor
	glow.BackgroundTransparency = 0.15
	glow.BorderSizePixel = 0
	glow.ZIndex = 22
	glow.Parent = container
	Instance.new("UICorner", glow).CornerRadius = UDim.new(0.5, 0)

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, lightColor),
		ColorSequenceKeypoint.new(1, darkColor)
	})
	gradient.Rotation = 90
	gradient.Parent = glow
end

-- Aura curcubeu, animata (se roteste incet la nesfarsit) -- doar pentru
-- Day 7, ca sa dea un aspect vizibil "exclusiv/legendar", diferit de restul.
local function rainbowGlow(container)
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromOffset(48, 48)
	glow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	glow.BackgroundTransparency = 0.35
	glow.BorderSizePixel = 0
	glow.ZIndex = 22
	glow.Parent = container
	Instance.new("UICorner", glow).CornerRadius = UDim.new(0.5, 0)

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 90, 90)),
		ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 205, 90)),
		ColorSequenceKeypoint.new(0.34, Color3.fromRGB(140, 255, 110)),
		ColorSequenceKeypoint.new(0.50, Color3.fromRGB(90, 220, 255)),
		ColorSequenceKeypoint.new(0.67, Color3.fromRGB(150, 130, 255)),
		ColorSequenceKeypoint.new(0.84, Color3.fromRGB(255, 110, 220)),
		ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 90, 90))
	})
	gradient.Parent = glow

	task.spawn(function()
		while glow.Parent do
			gradient.Rotation = (gradient.Rotation + 1.5) % 360
			RunService.Heartbeat:Wait()
		end
	end)
end

-- Coloreaza CARDUL intreg (nu doar cercul din spatele iconitei) pentru Day 2
-- (bronz), Day 4 (argintiu) si Day 7 (curcubeu, animat). IMPORTANT: UIGradient
-- inmulteste culorile cu BackgroundColor3 al parintelui -- pus direct pe
-- `cell` (aproape negru), culorile erau practic strivite la negru (de-aia
-- se vedea doar cercul din spatele iconitei, care are fundal alb). Fix:
-- un frame separat cu fundal ALB (gradientul iese la culorile lui reale),
-- plus un overlay semi-transparent inchis DEASUPRA lui, doar ca sa ramana
-- textul lizibil -- cardul tot arata viu colorat, nu spalacit.
local function applyCellRewardTint(cell, dayConfig)
	local colorSequence
	local accentColor
	local animated = false

	if dayConfig.Type == "RandomPet" then
		colorSequence = ColorSequence.new({
			ColorSequenceKeypoint.new(0, BRONZE_LIGHT),
			ColorSequenceKeypoint.new(1, BRONZE_DARK)
		})
		accentColor = BRONZE_LIGHT
	elseif dayConfig.Type == "RebirthTokens" then
		colorSequence = ColorSequence.new({
			ColorSequenceKeypoint.new(0, SILVER_LIGHT),
			ColorSequenceKeypoint.new(1, SILVER_DARK)
		})
		accentColor = SILVER_LIGHT
	elseif dayConfig.Type == "SpecificPet" then
		colorSequence = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 90, 90)),
			ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 205, 90)),
			ColorSequenceKeypoint.new(0.34, Color3.fromRGB(140, 255, 110)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(90, 220, 255)),
			ColorSequenceKeypoint.new(0.67, Color3.fromRGB(150, 130, 255)),
			ColorSequenceKeypoint.new(0.84, Color3.fromRGB(255, 110, 220)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 90, 90))
		})
		accentColor = Color3.fromRGB(255, 255, 255)
		animated = true
	else
		return
	end

	local tintBg = Instance.new("Frame")
	tintBg.Name = "RewardTint"
	tintBg.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	tintBg.BorderSizePixel = 0
	tintBg.Size = UDim2.new(1, 0, 1, 0)
	tintBg.ZIndex = 22
	tintBg.Parent = cell
	Instance.new("UICorner", tintBg).CornerRadius = UDim.new(0, 10)

	local gradient = Instance.new("UIGradient")
	gradient.Color = colorSequence
	gradient.Rotation = 90
	gradient.Parent = tintBg

	-- Contur colorat, in plus fata de conturul functional (verde/cyan/gri de
	-- stare) care se adauga peste -- accentueaza tema fara sa strice semnalul
	-- de "poti revendica azi".
	local accentStroke = Instance.new("UIStroke")
	accentStroke.Color = accentColor
	accentStroke.Thickness = 2
	accentStroke.Transparency = 0.15
	accentStroke.Parent = tintBg

	-- Overlay mult mai subtire decat inainte (0.32 -> 0.55 transparenta) --
	-- doar cat sa ramana textul lizibil, fara sa spele culorile.
	local overlay = Instance.new("Frame")
	overlay.Name = "RewardTintOverlay"
	overlay.BackgroundColor3 = CARD_BG
	overlay.BackgroundTransparency = 0.55
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Parent = tintBg
	Instance.new("UICorner", overlay).CornerRadius = UDim.new(0, 10)

	if animated then
		task.spawn(function()
			while gradient.Parent do
				gradient.Rotation = (gradient.Rotation + 1) % 360
				RunService.Heartbeat:Wait()
			end
		end)
	end
end

-- 💰 Money -> sac cu bani, cu semnul $ deasupra (caracter tipografic, nu emoji).
local function buildMoneyIcon(container)
	local bag = iconShape(container, 30, 24, 0, 4, GOLD_ICON, 23, 0.35)
	iconOutline(bag, Color3.fromRGB(255, 255, 255), 1.5, 0.4)

	iconShape(container, 12, 7, 0, -11, GOLD_ICON, 23, 0.3)

	local sign = Instance.new("TextLabel")
	sign.AnchorPoint = Vector2.new(0.5, 0.5)
	sign.Position = UDim2.new(0.5, 0, 0.5, 5)
	sign.Size = UDim2.fromOffset(16, 16)
	sign.BackgroundTransparency = 1
	sign.Text = "$"
	sign.TextColor3 = Color3.fromRGB(90, 60, 10)
	sign.Font = Enum.Font.FredokaOne
	sign.TextScaled = true
	sign.ZIndex = 24
	sign.Parent = container
end

-- Fata de creatura (urechi + cap + botic) -- se "insinueaza pet" mult mai
-- clar decat o forma abstracta. Refolosita pentru Day 2 (simpla) si Day 7
-- (cu urechi ascutite + accent premium).
local function buildPetFaceIcon(container, color, pointyEars)
	local earColor = color:Lerp(Color3.fromRGB(255, 255, 255), 0.15)

	for _, earOffset in ipairs({-11, 11}) do
		local ear = iconShape(container, 13, 15, earOffset, -12, earColor, 23, pointyEars and 0.15 or 0.4)
		if pointyEars then
			ear.Rotation = earOffset < 0 and -18 or 18
		end
	end

	local head = iconShape(container, 30, 26, 0, 6, color, 23, 0.4)
	iconOutline(head, Color3.fromRGB(255, 255, 255), 1.5, 0.4)

	local snout = iconShape(head, 12, 8, 0, 7, Color3.fromRGB(255, 255, 255), 24, 0.4)
	iconShape(snout, 4, 4, 0, 1, Color3.fromRGB(40, 30, 25), 25, 0.5)
end

-- 🐾 Random Pet -> fata de creatura obisnuita, urechi rotunjite.
local function buildRandomPetIcon(container)
	buildPetFaceIcon(container, PET_PURPLE, false)
end

-- 🔥 Rebirth Token -> moneda cu inel interior si o scanteie sus.
local function buildTokenIcon(container)
	local coin = iconShape(container, 30, 30, 0, 2, FIRE_ORANGE, 23, 0.5)
	iconOutline(coin, Color3.fromRGB(255, 255, 255), 1.5, 0.4)

	local ring = iconShape(coin, 18, 18, 0, 0, FIRE_ORANGE, 24, 0.5)
	ring.BackgroundTransparency = 1
	iconOutline(ring, Color3.fromRGB(255, 255, 255), 1.5, 0.5)

	local spark = iconShape(container, 9, 9, 0, -16, Color3.fromRGB(255, 255, 255), 24, 0.15)
	spark.Rotation = 45
end

-- 👑 Exclusive Epic Pet -> aceeasi fata de creatura (ca sa se inteleaga tot
-- ca e un pet), dar aurie, cu urechi ascutite si o gema mica intre urechi --
-- accentul "premium", fara sa mai fie doar o coroana abstracta (ambigua,
-- putea parea un Titlu, nu un Pet).
local function buildExclusivePetIcon(container)
	buildPetFaceIcon(container, GOLD_ICON, true)

	local gem = iconShape(container, 9, 9, 0, -16, Color3.fromRGB(255, 255, 255), 24, 0.15)
	gem.Rotation = 45
	iconOutline(gem, GOLD_ICON, 1.5, 0.1)

	iconShape(gem, 4, 4, 0, 0, GOLD_ICON, 25, 0.15)
end

local ICON_BUILDERS = {
	Money = buildMoneyIcon,
	RandomPet = buildRandomPetIcon,
	RebirthTokens = buildTokenIcon,
	SpecificPet = buildExclusivePetIcon
}

local function createDayIcon(parent, dayConfig)
	-- UIScale aici a fost o greseala -- scaleaza containerul din coltul lui
	-- stanga-sus (nu din centru), asa ca iconita se muta vizibil spre dreapta
	-- fata de textul de sub ea (nescalat, ramane centrat normal). Eliminat --
	-- iconitele raman la marimea lor naturala, aliniate corect cu textul.
	local container = Instance.new("Frame")
	container.Name = "IconPreview"
	container.BackgroundTransparency = 1
	container.Position = UDim2.new(0, 0, 0, 18)
	container.Size = UDim2.new(1, 0, 0, 48)
	container.ZIndex = 23
	container.Parent = parent

	-- Fundaluri speciale: Day 2 (bronz), Day 4 (argintiu), Day 7 (curcubeu,
	-- singurul animat) -- ca sa se vada o progresie de raritate intre zile,
	-- fara sa fie toate identice.
	if dayConfig.Type == "SpecificPet" then
		rainbowGlow(container)
	elseif dayConfig.Type == "RandomPet" then
		metallicGlow(container, BRONZE_LIGHT, BRONZE_DARK)
	elseif dayConfig.Type == "RebirthTokens" then
		metallicGlow(container, SILVER_LIGHT, SILVER_DARK)
	else
		iconGlow(container, GOLD_ICON)
	end

	local builder = ICON_BUILDERS[dayConfig.Type]
	if builder then
		builder(container)
	end

	return container
end

-- ---- Grila cu cele 7 zile ----
-- ScrollingFrame + AutomaticCanvasSize (nu Frame fix) -- ca sa functioneze
-- indiferent daca celulele incap intr-un singur rand (PC) sau se resfira pe
-- mai multe randuri (mobil, coloane mai putine) fara sa se taie/suprapuna.

local daysHolder = Instance.new("ScrollingFrame")
daysHolder.Name = "DaysScroll"
daysHolder.BackgroundTransparency = 1
daysHolder.Position = UDim2.new(0, 20, 0, 82)
daysHolder.Size = UDim2.new(1, -40, 1, -130)
daysHolder.ScrollBarThickness = 6
daysHolder.ScrollBarImageColor3 = CYAN_ACCENT
daysHolder.CanvasSize = UDim2.new(0, 0, 0, 0)
daysHolder.AutomaticCanvasSize = Enum.AutomaticSize.Y
daysHolder.ZIndex = 22
daysHolder.Parent = card

-- Fara padding, primul rand de carduri incepe EXACT la marginea de sus a
-- ScrollingFrame-ului -- jumatatea de sus a conturului de accent (bronz/
-- argintiu/curcubeu) se taia acolo, cu 0 rezerva. Un pic de padding sus
-- rezolva -- cardurile "coboara" putin, iar linia de sus ramane intreaga.
local daysPadding = Instance.new("UIPadding")
daysPadding.PaddingTop = UDim.new(0, 6)
daysPadding.PaddingBottom = UDim.new(0, 4)
daysPadding.Parent = daysHolder

local daysGrid = Instance.new("UIGridLayout")
daysGrid.SortOrder = Enum.SortOrder.LayoutOrder
daysGrid.Parent = daysHolder

-- Calculam latimea celulei in pixeli ficsi, din latimea CUNOSCUTA a cardului
-- (cea intoarsa de getMainFrameSize -- nu AbsoluteSize, care poate fi 0/stale
-- in exact momentul in care rulam asta, inainte de primul randare). Scazand
-- si o marja de siguranta explicita (nu doar "exact cat incape"), cele 7
-- carduri nu mai sar niciodata pe un rand nou din cauza rotunjirii sau a
-- ScrollBar-ului -- inainte calculul se potrivea EXACT, cu 0 rezerva reala.
local SAFETY_MARGIN_PX = 32

local function setUniformGrid(columns, cellHeight, padding, containerWidth)
	local usableWidth = containerWidth - SAFETY_MARGIN_PX
	local totalPadding = (columns - 1) * padding
	local cellWidth = math.floor((usableWidth - totalPadding) / columns)

	daysGrid.CellSize = UDim2.new(0, cellWidth, 0, cellHeight)
	daysGrid.CellPadding = UDim2.new(0, padding, 0, padding)
end

-- Butonul de revendicare s-a micsorat -- spatiul eliberat s-a dus la carduri
-- (124, nu 96).
local function updateDaysGridLayout()
	local cardSize = getMainFrameSize()
	local containerWidth = cardSize.X.Offset - 40 -- cele 20px de margine din fiecare parte

	-- Putin mai mici (124 -> 108) -- cardurile ajungeau prea aproape de
	-- marginea de jos a ScrollingFrame-ului, taind linia/conturul cardurilor
	-- speciale. Iconita si textul raman la aceeasi marime, doar spatiile
	-- goale din jurul lor s-au strans.
	if computeIsMobile() then
		setUniformGrid(4, 108, 8, containerWidth)
	else
		setUniformGrid(7, 108, 10, containerWidth)
	end
end

updateDaysGridLayout()

local dayCells = {}

for dayNumber = 1, Economy.DailyRewards.CycleLength do
	local dayConfig = Economy.DailyRewards.Days[dayNumber]

	local cell = Instance.new("Frame")
	cell.Name = "Day" .. dayNumber
	cell.BackgroundColor3 = CARD_BG
	cell.LayoutOrder = dayNumber
	cell.ZIndex = 22
	cell.Parent = daysHolder

	Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 10)
	applyCellRewardTint(cell, dayConfig)

	local cellStroke = Instance.new("UIStroke")
	cellStroke.Color = GRAY_LOCKED
	cellStroke.Thickness = 2
	cellStroke.Parent = cell

	local dayLabel = Instance.new("TextLabel")
	dayLabel.BackgroundTransparency = 1
	dayLabel.Position = UDim2.new(0, 0, 0, 2)
	dayLabel.Size = UDim2.new(1, 0, 0, 16)
	dayLabel.Text = "DAY " .. dayNumber
	dayLabel.TextColor3 = TEXT_DIM
	dayLabel.Font = FONT_BODY
	dayLabel.TextScaled = true
	dayLabel.ZIndex = 23
	dayLabel.Parent = cell

	createDayIcon(cell, dayConfig)

	local descLabel = Instance.new("TextLabel")
	descLabel.BackgroundTransparency = 1
	descLabel.Position = UDim2.new(0, 4, 0, 68)
	descLabel.Size = UDim2.new(1, -8, 0, 36)
	descLabel.Text = dayConfig.Description or ""
	descLabel.TextColor3 = TEXT_LIGHT
	descLabel.TextWrapped = true
	descLabel.Font = FONT_BODY
	descLabel.TextSize = 14
	descLabel.ZIndex = 23
	descLabel.Parent = cell

	-- Semn de "revendicat" -- acopera tot cardul, nu doar un colt: un overlay
	-- semi-transparent inchis peste tot cardul (estompeaza reward-ul de
	-- dedesubt) plus o bifa verde mare, centrata, cat mai evidenta dintr-o
	-- privire -- ca in jocurile mari.
	local checkmark = Instance.new("Frame")
	checkmark.Name = "ClaimedOverlay"
	checkmark.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	checkmark.BackgroundTransparency = 0.45
	checkmark.BorderSizePixel = 0
	checkmark.Size = UDim2.new(1, 0, 1, 0)
	checkmark.Visible = false
	checkmark.ZIndex = 25
	checkmark.Parent = cell

	Instance.new("UICorner", checkmark).CornerRadius = UDim.new(0, 10)

	-- Caracterul "✔" cade mereu pe un glif de rezerva cenusiu in Roblox,
	-- indiferent de font -- ignora TextColor3 complet. Construim bifa din
	-- doua dreptunghiuri rotite (aceeasi tehnica ca la iconitele din carduri
	-- mai sus), ca sa avem control garantat asupra culorii.
	--
	-- IMPORTANT: Rotation in Roblox se roteste in jurul CENTRULUI obiectului,
	-- NU in jurul AnchorPoint -- ancorarea ambelor linii in acelasi punct
	-- (0.5,1) si rotirea lor separat NU le face sa se intalneasca intr-un
	-- varf comun (fiecare se roteste in jurul propriului mijloc, deci ies
	-- din pozitie -- de-aia arata ca o singura linie stramba). Fix: pozitia
	-- fiecarei linii e MIJLOCUL segmentului ei (nu un capat), cu AnchorPoint
	-- (0.5,0.5), calculat geometric intre cele 3 puncte ale bifei.
	-- Mai mare (60px, nu 44) si mutat putin mai sus in card (offset -8), nu
	-- exact in centru. Bratele sunt si putin mai lungi decat distanta stricta
	-- dintre puncte, ca sa se suprapuna clar la varf (nu doar sa se atinga) --
	-- altfel putea sa para "incompleta", cu un gol vizibil la imbinare.
	local checkContainer = Instance.new("Frame")
	checkContainer.Name = "CheckShape"
	checkContainer.BackgroundTransparency = 1
	checkContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	checkContainer.Position = UDim2.new(0.5, 0, 0.5, -8)
	checkContainer.Size = UDim2.new(0, 60, 0, 60)
	checkContainer.ZIndex = 26
	checkContainer.Parent = checkmark

	-- Punctele bifei (in interiorul containerului de 60x60):
	-- A = (14,30) varful bratului scurt, V = (25,44) varful de jos,
	-- B = (49,14) varful bratului lung. Rotation=θ (sensul acelor de
	-- ceasornic) roteste directia "in jos" (0,1) catre (-sinθ, cosθ).
	local shortLine = Instance.new("Frame")
	shortLine.AnchorPoint = Vector2.new(0.5, 0.5)
	shortLine.Position = UDim2.new(0, 20, 0, 37)
	shortLine.Size = UDim2.new(0, 10, 0, 20)
	shortLine.Rotation = -38
	shortLine.BackgroundColor3 = GREEN_OK
	shortLine.BorderSizePixel = 0
	shortLine.ZIndex = 26
	shortLine.Parent = checkContainer
	Instance.new("UICorner", shortLine).CornerRadius = UDim.new(0.5, 0)

	local longLine = Instance.new("Frame")
	longLine.AnchorPoint = Vector2.new(0.5, 0.5)
	longLine.Position = UDim2.new(0, 37, 0, 29)
	longLine.Size = UDim2.new(0, 10, 0, 44)
	longLine.Rotation = -141
	longLine.BackgroundColor3 = GREEN_OK
	longLine.BorderSizePixel = 0
	longLine.ZIndex = 26
	longLine.Parent = checkContainer
	Instance.new("UICorner", longLine).CornerRadius = UDim.new(0.5, 0)

	dayCells[dayNumber] = {Cell = cell, Stroke = cellStroke, Checkmark = checkmark}
end

-- ---- Buton de revendicare ----

-- Mai mic decat inainte (era prea dominant, "maricel") -- TextSize fix in
-- loc de TextScaled, ca sa nu creasca odata cu butonul daca il marim.
local claimButton = Instance.new("TextButton")
claimButton.AnchorPoint = Vector2.new(0.5, 1)
claimButton.Position = UDim2.new(0.5, 0, 1, -14)
claimButton.Size = UDim2.new(0, 200, 0, 34)
claimButton.AutoButtonColor = false
claimButton.Text = "..."
claimButton.TextColor3 = Color3.fromRGB(255, 255, 255)
claimButton.Font = FONT_DISPLAY
claimButton.TextSize = 18
claimButton.ZIndex = 22
claimButton.Parent = card

Instance.new("UICorner", claimButton).CornerRadius = UDim.new(0.2, 0)

-- ================= Coordonare cu celelalte shop-uri =================
-- Un singur flag comun pe player -- cand se deschide ORICE panou (Starter
-- Pack, Rebirth, Daily Rewards, Token Shop), toate butoanele astea de pe
-- ecran se ascund, ca sa nu ramana unul peste altul/langa cardul deschis
-- (asta era exact problema din screenshot).
local function setShopModalOpen(open)
	player:SetAttribute("ShopModalOpen", open)
end

player:GetAttributeChangedSignal("ShopModalOpen"):Connect(function()
	toggleButton.Visible = not player:GetAttribute("ShopModalOpen")
end)

-- ================= Behaviour (declarat aici ca sa fie vizibil din applyState) ====

local isOpen = false

local function setOpen(open)
	if open == isOpen then
		return
	end
	isOpen = open
	setShopModalOpen(open)

	if open then
		updateDaysGridLayout()
		card.Size = getMainFrameSize()
	end

	overlay.Visible = open
end

-- Daca jucatorul roteste telefonul cat timp panoul e deschis, recalculam.
do
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if overlay.Visible then
				updateDaysGridLayout()
				card.Size = getMainFrameSize()
			end
		end)
	end
end

-- ================= Stare live =================

local latestState = {CanClaim = false, NextDay = 1, SecondsRemaining = 0, StreakDay = 0}
local countdownEndClock = nil
local hasAutoPopped = false

local function formatCountdown(seconds)
	seconds = math.max(0, math.floor(seconds))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60
	return string.format("%02d:%02d:%02d", hours, minutes, secs)
end

local function refreshDayCells()
	for dayNumber, refs in ipairs(dayCells) do
		if dayNumber < latestState.NextDay then
			refs.Stroke.Color = GREEN_OK
			refs.Cell.BackgroundColor3 = CARD_BG
			refs.Checkmark.Visible = true
		elseif dayNumber == latestState.NextDay then
			refs.Stroke.Color = latestState.CanClaim and GREEN_OK or CYAN_ACCENT
			refs.Cell.BackgroundColor3 = BG_MID
			refs.Checkmark.Visible = false
		else
			refs.Stroke.Color = GRAY_LOCKED
			refs.Cell.BackgroundColor3 = CARD_BG
			refs.Checkmark.Visible = false
		end
	end
end

local function refreshClaimButton()
	if latestState.CanClaim then
		claimButton.BackgroundColor3 = GREEN_OK
		claimButton.Text = "CLAIM DAY " .. latestState.NextDay
		claimButton.Active = true
	else
		claimButton.BackgroundColor3 = GRAY_LOCKED
		claimButton.Text = "NEXT IN " .. formatCountdown(latestState.SecondsRemaining)
		claimButton.Active = false
	end
end

local function refreshToggleSubtitle()
	mobileStatus.Text = latestState.CanClaim and "READY!" or formatCountdown(latestState.SecondsRemaining)
	mobileStatus.TextColor3 = latestState.CanClaim and GREEN_OK or TEXT_DIM

	if latestState.CanClaim then
		toggleSubtitle.Text = "Day " .. latestState.NextDay .. " ready!"
	else
		toggleSubtitle.Text = "Next in " .. formatCountdown(latestState.SecondsRemaining)
	end
end

local function applyState(state)
	latestState = state

	if state.CanClaim then
		countdownEndClock = nil
	else
		countdownEndClock = os.clock() + state.SecondsRemaining
	end

	refreshDayCells()
	refreshClaimButton()
	refreshToggleSubtitle()

	if state.CanClaim and not hasAutoPopped then
		hasAutoPopped = true
		setOpen(true)
	end
end

statusResultEvent.OnClientEvent:Connect(applyState)

claimResultEvent.OnClientEvent:Connect(function(data)
	if data and data.Success then
		requestStatusEvent:FireServer()
	end
end)

-- Countdown-ul local se actualizeaza in fiecare secunda, fara sa bata
-- serverul la fiecare tick -- doar cand ajunge la 0 cerem statusul din nou.
task.spawn(function()
	while true do
		task.wait(1)

		if countdownEndClock then
			local remaining = countdownEndClock - os.clock()

			if remaining <= 0 then
				countdownEndClock = nil
				requestStatusEvent:FireServer()
			else
				latestState.SecondsRemaining = remaining
				refreshClaimButton()
				refreshToggleSubtitle()
			end
		end
	end
end)

requestStatusEvent:FireServer()

-- ================= Conectare butoane =================

toggleButton.Activated:Connect(function()
	setOpen(true)
end)

closeButton.Activated:Connect(function()
	setOpen(false)
end)

claimButton.Activated:Connect(function()
	if latestState.CanClaim then
		requestClaimEvent:FireServer()
	end
end)
