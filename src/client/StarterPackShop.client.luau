-- UN SINGUR slot (buton + card), care trece prin 3 trepte in ACELASI loc pe
-- ecran -- Starter Pack -> Medium Pack -> Elite Pack -- ca la jocurile mari:
-- cumperi Starter, in acelasi loc apare Medium; cumperi Medium, apare Elite;
-- cumperi Elite, slotul dispare de tot (nu mai ramane nimic acolo). Cerut
-- explicit: NU 3 butoane separate stivuite (asa a fost implementat initial,
-- in MediumPackShop.client.luau/ElitePackShop.client.luau -- ambele sterse,
-- inlocuite complet de acest script unic).

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

-- Font "impact" pentru titluri/butoane, font cartoonish rotunjit pentru text mai mic.
local FONT_DISPLAY = Enum.Font.Bangers
local FONT_BODY = Enum.Font.FredokaOne

-- ================= Treptele (Starter -> Medium -> Elite) =================
-- OwnedAttribute = setat de StarterPackManager/MediumPackManager/
-- ElitePackManager.server.luau (HasStarterPack/HasMediumPack/HasElitePack).
-- Prima treapta din lista pentru care jucatorul NU are attribute-ul e cea
-- activa -- daca le are pe toate, slotul intreg se ascunde.
local TIERS = {
	{
		Key = "Starter",
		OwnedAttribute = "HasStarterPack",
		GamePassId = Economy.StarterPack.GamePassId,
		Title = "STARTER PACK",
		ToggleRibbon = "LIMITED EDITION",
		CardRibbon = "LIMITED PACK",
		BuyText = "GET STARTER PACK",
		AccentLight = Color3.fromRGB(255, 226, 130),
		AccentMid = Color3.fromRGB(255, 191, 60),
		AccentDeep = Color3.fromRGB(198, 138, 18),
		Outline = Color3.fromRGB(107, 66, 10),
		TextDark = Color3.fromRGB(64, 38, 8),
		Perks = {
			{Icon = "💵", Text = "$" .. Economy.StarterPack.Money .. " Cash"},
			{Icon = "🐾", Text = "+1 Free Pet"},
			{
				Icon = "🍀",
				Text = "+" .. Economy.StarterPack.LuckBonus .. "% Luck (Forever)",
				Color = Color3.fromRGB(20, 130, 55)
			}
		}
	},
	{
		Key = "Medium",
		OwnedAttribute = "HasMediumPack",
		GamePassId = Economy.MediumPack.GamePassId,
		Title = "MEDIUM PACK",
		ToggleRibbon = "UPGRADE",
		CardRibbon = "UPGRADE PACK",
		BuyText = "GET MEDIUM PACK",
		AccentLight = Color3.fromRGB(160, 200, 245),
		AccentMid = Color3.fromRGB(40, 120, 220),
		AccentDeep = Color3.fromRGB(15, 60, 130),
		Outline = Color3.fromRGB(10, 30, 65),
		TextDark = Color3.fromRGB(15, 25, 45),
		Perks = {
			{Icon = "💵", Text = "$" .. Economy.MediumPack.Money .. " Cash"},
			{Icon = "🐾", Text = "+1 Free Pet (Rare Egg)"},
			{
				Icon = "🍀",
				Text = "+" .. Economy.MediumPack.LuckBonus .. "% Luck (Forever)",
				Color = Color3.fromRGB(20, 90, 170)
			}
		}
	},
	{
		Key = "Elite",
		OwnedAttribute = "HasElitePack",
		GamePassId = Economy.ElitePack.GamePassId,
		Title = "ELITE PACK",
		ToggleRibbon = "UPGRADE",
		CardRibbon = "FINAL PACK",
		BuyText = "GET ELITE PACK",
		AccentLight = Color3.fromRGB(250, 170, 170),
		AccentMid = Color3.fromRGB(210, 45, 45),
		AccentDeep = Color3.fromRGB(120, 15, 15),
		Outline = Color3.fromRGB(60, 8, 8),
		TextDark = Color3.fromRGB(45, 12, 12),
		Perks = {
			{Icon = "💵", Text = "$" .. Economy.ElitePack.Money .. " Cash"},
			{Icon = "🐾", Text = "+1 Free Pet (Epic Egg)"},
			{
				Icon = "🍀",
				Text = "+" .. Economy.ElitePack.LuckBonus .. "% Luck (Forever)",
				Color = Color3.fromRGB(150, 20, 20)
			}
		}
	}
}

local function getActiveTier()
	for _, tier in ipairs(TIERS) do
		if player:GetAttribute(tier.OwnedAttribute) ~= true then
			return tier
		end
	end
	return nil
end

local function getPassPriceText(passId)
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
	end)

	if ok and info and info.PriceInRobux then
		return info.PriceInRobux .. " Robux"
	end

	return "BUY"
end

-- ================= ScreenGui =================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StarterPackShop"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ================= Toggle button (right side, aceeasi pozitie pentru toate treptele) =================

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "StarterPackButton"
toggleButton.AnchorPoint = Vector2.new(1, 0.5)
toggleButton.Position = UDim2.new(1, -16, 0.5, 0)
toggleButton.Size = UDim2.new(0, 168, 0, 72)
toggleButton.AutoButtonColor = false
toggleButton.ClipsDescendants = true
toggleButton.Text = ""
toggleButton.ZIndex = 10
toggleButton.Parent = screenGui

Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0.22, 0)

local toggleGradient = Instance.new("UIGradient")
toggleGradient.Rotation = 90
toggleGradient.Parent = toggleButton

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Thickness = 3
toggleStroke.Parent = toggleButton

local toggleRibbon = Instance.new("TextLabel")
toggleRibbon.Name = "LimitedRibbon"
toggleRibbon.AnchorPoint = Vector2.new(0.5, 0.5)
toggleRibbon.Position = UDim2.new(1, -6, 0, 12)
toggleRibbon.Size = UDim2.new(0, 78, 0, 13)
toggleRibbon.Rotation = 45
toggleRibbon.BackgroundColor3 = Color3.fromRGB(206, 40, 55)
toggleRibbon.BorderSizePixel = 0
toggleRibbon.Text = "LIMITED EDITION"
toggleRibbon.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleRibbon.Font = FONT_DISPLAY
toggleRibbon.TextScaled = true
toggleRibbon.ZIndex = 13
toggleRibbon.Parent = toggleButton

local toggleRibbonPadding = Instance.new("UIPadding")
toggleRibbonPadding.PaddingLeft = UDim.new(0, 4)
toggleRibbonPadding.PaddingRight = UDim.new(0, 4)
toggleRibbonPadding.Parent = toggleRibbon

local toggleRibbonStroke = Instance.new("UIStroke")
toggleRibbonStroke.Color = Color3.fromRGB(100, 12, 20)
toggleRibbonStroke.Thickness = 1
toggleRibbonStroke.Parent = toggleRibbon

local toggleTitle = Instance.new("TextLabel")
toggleTitle.BackgroundTransparency = 1
toggleTitle.Position = UDim2.new(0, 10, 0, 10)
toggleTitle.Size = UDim2.new(1, -20, 0, 32)
toggleTitle.Text = "STARTER PACK"
toggleTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleTitle.TextStrokeTransparency = 0
toggleTitle.Font = FONT_DISPLAY
toggleTitle.TextScaled = true
toggleTitle.ZIndex = 11
toggleTitle.Parent = toggleButton

local togglePrice = Instance.new("TextLabel")
togglePrice.BackgroundTransparency = 1
togglePrice.Position = UDim2.new(0, 10, 0, 42)
togglePrice.Size = UDim2.new(1, -20, 0, 24)
togglePrice.Text = "..."
togglePrice.TextColor3 = Color3.fromRGB(0, 0, 0)
togglePrice.Font = FONT_DISPLAY
togglePrice.TextScaled = true
togglePrice.ZIndex = 11
togglePrice.Parent = toggleButton

-- Pe mobil, butonul e mult mai mic -- textele de mai sus (pozitionate in
-- pixeli ficsi, gandite pentru butonul de PC) s-ar suprapune daca doar am
-- micsora containerul. Pe mobil le ascundem si aratam o eticheta simpla,
-- centrata, care umple tot butonul compact.
local mobileLabel = Instance.new("TextLabel")
mobileLabel.Name = "MobileLabel"
mobileLabel.BackgroundTransparency = 1
mobileLabel.Size = UDim2.new(1, -10, 1, -10)
mobileLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
mobileLabel.AnchorPoint = Vector2.new(0.5, 0.5)
mobileLabel.Text = "STARTER PACK"
mobileLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
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
overlay.Name = "StarterPackOverlay"
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
card.Size = UDim2.new(0, 340, 0, 440)
card.ClipsDescendants = true
card.ZIndex = 21
card.Parent = overlay

Instance.new("UICorner", card).CornerRadius = UDim.new(0, 22)

local cardStroke = Instance.new("UIStroke")
cardStroke.Thickness = 5
cardStroke.Parent = card

local cardGradient = Instance.new("UIGradient")
cardGradient.Rotation = 90
cardGradient.Parent = card

-- ---- Ribbon (top-left corner) ----

local ribbon = Instance.new("TextLabel")
ribbon.Name = "LimitedRibbon"
ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
ribbon.Position = UDim2.new(0, 6, 0, 34)
ribbon.Size = UDim2.new(0, 190, 0, 32)
ribbon.Rotation = -45
ribbon.BackgroundColor3 = Color3.fromRGB(206, 40, 55)
ribbon.BorderSizePixel = 0
ribbon.Text = "LIMITED PACK"
ribbon.TextColor3 = Color3.fromRGB(255, 255, 255)
ribbon.Font = FONT_DISPLAY
ribbon.TextSize = 18
ribbon.ZIndex = 24
ribbon.Parent = card

local ribbonStroke = Instance.new("UIStroke")
ribbonStroke.Color = Color3.fromRGB(100, 12, 20)
ribbonStroke.Thickness = 2
ribbonStroke.Parent = ribbon

-- ---- Close (X) button ----

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -12, 0, 12)
closeButton.Size = UDim2.new(0, 32, 0, 32)
closeButton.Text = "✕"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Font = FONT_DISPLAY
closeButton.TextScaled = true
closeButton.ZIndex = 25
closeButton.Parent = card

Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0.5, 0)

-- ---- Title ----

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 0, 0, 52)
titleLabel.Size = UDim2.new(1, 0, 0, 48)
titleLabel.Text = "STARTER PACK"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextStrokeTransparency = 0
titleLabel.Font = FONT_DISPLAY
titleLabel.TextScaled = true
titleLabel.ZIndex = 22
titleLabel.Parent = card

-- ---- Perks list (rebuilt la fiecare schimbare de treapta) ----

local perksFrame = Instance.new("Frame")
perksFrame.BackgroundTransparency = 1
perksFrame.Position = UDim2.new(0, 24, 0, 112)
perksFrame.Size = UDim2.new(1, -48, 0, 180)
perksFrame.ZIndex = 22
perksFrame.Parent = card

local perksLayout = Instance.new("UIListLayout")
perksLayout.Padding = UDim.new(0, 14)
perksLayout.SortOrder = Enum.SortOrder.LayoutOrder
perksLayout.Parent = perksFrame

local function createPerkRow(icon, text, order, color, textDark)
	local row = Instance.new("Frame")
	row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	row.BackgroundTransparency = 0.75
	row.Size = UDim2.new(1, 0, 0, 42)
	row.LayoutOrder = order
	row.ZIndex = 22
	row.Parent = perksFrame

	Instance.new("UICorner", row).CornerRadius = UDim.new(0.3, 0)

	local iconLabel = Instance.new("TextLabel")
	iconLabel.BackgroundTransparency = 1
	iconLabel.Size = UDim2.new(0, 36, 1, 0)
	iconLabel.Position = UDim2.new(0, 6, 0, 0)
	iconLabel.Text = icon
	iconLabel.TextScaled = true
	iconLabel.ZIndex = 22
	iconLabel.Parent = row

	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Position = UDim2.new(0, 48, 0, 0)
	textLabel.Size = UDim2.new(1, -54, 1, 0)
	textLabel.Text = text
	textLabel.TextColor3 = color or textDark
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.Font = FONT_BODY
	textLabel.TextScaled = true
	textLabel.ZIndex = 22
	textLabel.Parent = row

	return row
end

-- ---- Robux price row (above the Buy button) ----

local priceRow = Instance.new("Frame")
priceRow.BackgroundTransparency = 1
priceRow.AnchorPoint = Vector2.new(0.5, 1)
priceRow.Position = UDim2.new(0.5, 0, 1, -88)
priceRow.Size = UDim2.new(0, 140, 0, 34)
priceRow.ZIndex = 22
priceRow.Parent = card

local priceLayout = Instance.new("UIListLayout")
priceLayout.FillDirection = Enum.FillDirection.Horizontal
priceLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
priceLayout.VerticalAlignment = Enum.VerticalAlignment.Center
priceLayout.Padding = UDim.new(0, 8)
priceLayout.SortOrder = Enum.SortOrder.LayoutOrder
priceLayout.Parent = priceRow

local robuxBadge = Instance.new("Frame")
robuxBadge.Size = UDim2.new(0, 30, 0, 30)
robuxBadge.BackgroundColor3 = Color3.fromRGB(50, 190, 90)
robuxBadge.LayoutOrder = 1
robuxBadge.ZIndex = 22
robuxBadge.Parent = priceRow

Instance.new("UICorner", robuxBadge).CornerRadius = UDim.new(0.3, 0)

local robuxBadgeText = Instance.new("TextLabel")
robuxBadgeText.BackgroundTransparency = 1
robuxBadgeText.Size = UDim2.new(1, 0, 1, 0)
robuxBadgeText.Text = "R$"
robuxBadgeText.TextColor3 = Color3.fromRGB(255, 255, 255)
robuxBadgeText.Font = FONT_DISPLAY
robuxBadgeText.TextScaled = true
robuxBadgeText.ZIndex = 23
robuxBadgeText.Parent = robuxBadge

local priceText = Instance.new("TextLabel")
priceText.BackgroundTransparency = 1
priceText.Size = UDim2.new(0, 90, 1, 0)
priceText.Text = "..."
priceText.TextColor3 = Color3.fromRGB(0, 0, 0)
priceText.Font = FONT_DISPLAY
priceText.TextScaled = true
priceText.LayoutOrder = 2
priceText.ZIndex = 22
priceText.Parent = priceRow

-- ---- Buy button (verde, acelasi pentru toate treptele) ----

local buyButton = Instance.new("TextButton")
buyButton.Name = "BuyButton"
buyButton.AnchorPoint = Vector2.new(0.5, 1)
buyButton.Position = UDim2.new(0.5, 0, 1, -24)
buyButton.Size = UDim2.new(1, -48, 0, 54)
buyButton.BackgroundColor3 = Color3.fromRGB(60, 200, 95)
buyButton.AutoButtonColor = false
buyButton.Text = "GET STARTER PACK"
buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
buyButton.Font = FONT_DISPLAY
buyButton.TextScaled = true
buyButton.ZIndex = 22
buyButton.Parent = card

Instance.new("UICorner", buyButton).CornerRadius = UDim.new(0.3, 0)

local buyGradient = Instance.new("UIGradient")
buyGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(110, 230, 140)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 165, 75)),
})
buyGradient.Rotation = 90
buyGradient.Parent = buyButton

local buyStroke = Instance.new("UIStroke")
buyStroke.Color = Color3.fromRGB(18, 100, 45)
buyStroke.Thickness = 3
buyStroke.Parent = buyButton

local buyPadding = Instance.new("UIPadding")
buyPadding.PaddingLeft = UDim.new(0, 8)
buyPadding.PaddingRight = UDim.new(0, 8)
buyPadding.Parent = buyButton

addHoverPop(buyButton)
addHoverPop(toggleButton)

-- ================= Scalare responsive (mobil) =================
-- Pe ecrane mici (telefon), micsoram proportional cardul, ca sa nu ocupe
-- prea mult ecran si sa ramana usor de citit/apasat.

local cardScale = Instance.new("UIScale")
cardScale.Parent = card

local BASE_VIEWPORT_WIDTH = 1200
local MIN_UI_SCALE = 0.75

local function computeIsMobile()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.X < 700 or viewport.Y < 500
end

local function updateResponsiveLayout()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local isMobile = computeIsMobile()

	if isMobile then
		toggleButton.AnchorPoint = Vector2.new(1, 0)
		toggleButton.Position = UDim2.new(1, -8, 0, 48)
		toggleButton.Size = UDim2.new(0, 112, 0, 42)

		local fitScale = math.min(
			(camera.ViewportSize.X * 0.78) / 340,
			(camera.ViewportSize.Y * 0.70) / 440
		)
		cardScale.Scale = math.min(MIN_UI_SCALE, fitScale)

		toggleRibbon.Size = UDim2.new(0, 52, 0, 10)
		toggleRibbon.Position = UDim2.new(1, -2, 0, 8)
	else
		toggleButton.AnchorPoint = Vector2.new(1, 0.5)
		toggleButton.Position = UDim2.new(1, -16, 0.5, 0)
		toggleButton.Size = UDim2.new(0, 168, 0, 72)
		cardScale.Scale = math.clamp(camera.ViewportSize.X / BASE_VIEWPORT_WIDTH, MIN_UI_SCALE, 1)
	end

	toggleTitle.Visible = not isMobile
	togglePrice.Visible = not isMobile
	mobileLabel.Visible = isMobile
end

local viewportConnection = nil

local function bindCamera()
	updateResponsiveLayout()

	if viewportConnection then
		viewportConnection:Disconnect()
		viewportConnection = nil
	end

	local camera = workspace.CurrentCamera
	if camera then
		viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout)
	end
end

bindCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

-- ================= Constructia cardului/butonului pentru treapta activa =================

local currentTierKey = nil
local currentPassId = nil
local priceRequestId = 0

local function rebuildForTier(tier)
	currentPassId = tier.GamePassId

	toggleButton.BackgroundColor3 = tier.AccentMid
	toggleGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, tier.AccentLight),
		ColorSequenceKeypoint.new(0.35, tier.AccentMid),
		ColorSequenceKeypoint.new(1, tier.AccentDeep),
	})
	toggleStroke.Color = tier.Outline
	toggleRibbon.Text = tier.ToggleRibbon
	toggleTitle.Text = tier.Title
	toggleTitle.TextStrokeColor3 = tier.Outline
	mobileLabel.Text = tier.Title
	mobileLabel.TextStrokeColor3 = tier.Outline

	card.BackgroundColor3 = tier.AccentMid
	cardGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, tier.AccentLight),
		ColorSequenceKeypoint.new(0.18, Color3.fromRGB(255, 244, 200)),
		ColorSequenceKeypoint.new(0.4, tier.AccentMid),
		ColorSequenceKeypoint.new(1, tier.AccentDeep),
	})
	cardStroke.Color = tier.Outline

	ribbon.Text = tier.CardRibbon

	closeButton.BackgroundColor3 = tier.Outline

	titleLabel.Text = tier.Title
	titleLabel.TextStrokeColor3 = tier.Outline

	for _, child in ipairs(perksFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for order, perk in ipairs(tier.Perks) do
		createPerkRow(perk.Icon, perk.Text, order, perk.Color, tier.TextDark)
	end

	buyButton.Text = tier.BuyText

	togglePrice.Text = "..."
	priceText.Text = "..."

	priceRequestId += 1
	local requestId = priceRequestId

	task.spawn(function()
		local priceLabelText = getPassPriceText(tier.GamePassId)

		if requestId ~= priceRequestId then
			return
		end

		togglePrice.Text = priceLabelText
		priceText.Text = priceLabelText
	end)
end

-- ================= Coordonare cu celelalte shop-uri =================
-- Un singur flag comun pe player -- cand se deschide ORICE panou (Starter/
-- Medium/Elite Pack, Rebirth, Daily Rewards, Token Shop), toate butoanele
-- astea de pe ecran se ascund.
local function setShopModalOpen(open)
	player:SetAttribute("ShopModalOpen", open)
end

local isOpen = false

local function setOpen(open)
	if open == isOpen then
		return
	end
	isOpen = open
	setShopModalOpen(open)

	if open then
		overlay.Visible = true
		card.Size = UDim2.new(0, 280, 0, 360)
		TweenService:Create(
			card,
			TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Size = UDim2.new(0, 340, 0, 440)}
		):Play()
	else
		overlay.Visible = false
	end
end

-- SideStackCollapsed -- comutatorul "<"/">" din SideStackToggle.client.luau.
local function updateToggleVisibility()
	toggleButton.Visible = currentTierKey ~= nil
		and not player:GetAttribute("ShopModalOpen")
		and not player:GetAttribute("SideStackCollapsed")
end

-- Recalculeaza treapta activa (Starter/Medium/Elite/niciuna) -- apelat la
-- start si de fiecare data cand se schimba HasStarterPack/HasMediumPack/
-- HasElitePack (adica live, in aceeasi sesiune, imediat dupa o achizitie).
local function refreshTier()
	local tier = getActiveTier()

	if not tier then
		currentTierKey = nil
		if isOpen then
			setOpen(false)
		end
		updateToggleVisibility()
		return
	end

	if tier.Key ~= currentTierKey then
		currentTierKey = tier.Key
		rebuildForTier(tier)

		-- Daca panoul era deschis si tocmai s-a schimbat treapta pe fundal
		-- (achizitia s-a terminat cat cardul era deschis), il inchidem --
		-- continutul de dedesubt tocmai s-a schimbat sub jucator.
		if isOpen then
			setOpen(false)
		end
	end

	updateToggleVisibility()
end

refreshTier()

for _, tier in ipairs(TIERS) do
	player:GetAttributeChangedSignal(tier.OwnedAttribute):Connect(refreshTier)
end

player:GetAttributeChangedSignal("ShopModalOpen"):Connect(updateToggleVisibility)
player:GetAttributeChangedSignal("SideStackCollapsed"):Connect(updateToggleVisibility)

-- ================= Behaviour =================

toggleButton.Activated:Connect(function()
	setOpen(not isOpen)
end)

closeButton.Activated:Connect(function()
	setOpen(false)
end)

buyButton.Activated:Connect(function()
	if currentPassId then
		MarketplaceService:PromptGamePassPurchase(player, currentPassId)
	end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchasedPlayer, gamePassId, wasPurchased)
	if purchasedPlayer ~= player or gamePassId ~= currentPassId then
		return
	end

	if wasPurchased then
		setOpen(false)
	end
end)
