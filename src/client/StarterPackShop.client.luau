local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

local STARTER_PACK_PASS_ID = Economy.StarterPack.GamePassId
local ROBUX_PRICE_TEXT = Economy.StarterPack.RobuxPrice .. " Robux"

-- Font "impact" pentru titluri/butoane, font cartoonish rotunjit pentru text mai mic.
local FONT_DISPLAY = Enum.Font.Bangers
local FONT_BODY = Enum.Font.FredokaOne

local GOLD_LIGHT = Color3.fromRGB(255, 226, 130)
local GOLD_MID = Color3.fromRGB(255, 191, 60)
local GOLD_DEEP = Color3.fromRGB(198, 138, 18)
local BRONZE_OUTLINE = Color3.fromRGB(107, 66, 10)
local TEXT_DARK = Color3.fromRGB(64, 38, 8)

-- ================= ScreenGui =================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StarterPackShop"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ================= Toggle button (right side, gold) =================

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "StarterPackButton"
toggleButton.AnchorPoint = Vector2.new(1, 0.5)
toggleButton.Position = UDim2.new(1, -16, 0.5, 0)
toggleButton.Size = UDim2.new(0, 168, 0, 72)
toggleButton.BackgroundColor3 = GOLD_MID
toggleButton.AutoButtonColor = false
toggleButton.ClipsDescendants = true
toggleButton.Text = ""
toggleButton.ZIndex = 10
toggleButton.Parent = screenGui

Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0.22, 0)

local toggleGradient = Instance.new("UIGradient")
toggleGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, GOLD_LIGHT),
	ColorSequenceKeypoint.new(0.35, GOLD_MID),
	ColorSequenceKeypoint.new(1, GOLD_DEEP),
})
toggleGradient.Rotation = 90
toggleGradient.Parent = toggleButton

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = BRONZE_OUTLINE
toggleStroke.Thickness = 3
toggleStroke.Parent = toggleButton

-- Banda "LIMITED EDITION", diagonala in coltul din dreapta-sus, ca o funda de cadou
-- (mica, proportionala cu butonul, nu il depaseste).
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
toggleTitle.TextStrokeColor3 = BRONZE_OUTLINE
toggleTitle.TextStrokeTransparency = 0
toggleTitle.Font = FONT_DISPLAY
toggleTitle.TextScaled = true
toggleTitle.ZIndex = 11
toggleTitle.Parent = toggleButton

local togglePrice = Instance.new("TextLabel")
togglePrice.BackgroundTransparency = 1
togglePrice.Position = UDim2.new(0, 10, 0, 42)
togglePrice.Size = UDim2.new(1, -20, 0, 24)
togglePrice.Text = ROBUX_PRICE_TEXT
togglePrice.TextColor3 = Color3.fromRGB(0, 0, 0)
togglePrice.Font = FONT_DISPLAY
togglePrice.TextScaled = true
togglePrice.ZIndex = 11
togglePrice.Parent = toggleButton

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
card.BackgroundColor3 = GOLD_MID
card.ClipsDescendants = true
card.ZIndex = 21
card.Parent = overlay

Instance.new("UICorner", card).CornerRadius = UDim.new(0, 22)

local cardStroke = Instance.new("UIStroke")
cardStroke.Color = BRONZE_OUTLINE
cardStroke.Thickness = 5
cardStroke.Parent = card

local cardGradient = Instance.new("UIGradient")
cardGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, GOLD_LIGHT),
	ColorSequenceKeypoint.new(0.18, Color3.fromRGB(255, 244, 200)), -- luciu, ca o reflexie
	ColorSequenceKeypoint.new(0.4, GOLD_MID),
	ColorSequenceKeypoint.new(1, GOLD_DEEP),
})
cardGradient.Rotation = 90
cardGradient.Parent = card

-- ---- "LIMITED PACK" ribbon (top-left corner, rosu pe fundal auriu) ----

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

-- ---- Close (X) button, top-right ----

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -12, 0, 12)
closeButton.Size = UDim2.new(0, 32, 0, 32)
closeButton.BackgroundColor3 = BRONZE_OUTLINE
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
titleLabel.TextStrokeColor3 = BRONZE_OUTLINE
titleLabel.TextStrokeTransparency = 0
titleLabel.Font = FONT_DISPLAY
titleLabel.TextScaled = true
titleLabel.ZIndex = 22
titleLabel.Parent = card

-- ---- Perks list ----

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

local function createPerkRow(icon, text, order, color)
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
	textLabel.TextColor3 = color or TEXT_DARK
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.Font = FONT_BODY
	textLabel.TextScaled = true
	textLabel.ZIndex = 22
	textLabel.Parent = row

	return row
end

createPerkRow("💵", "$" .. Economy.StarterPack.Money .. " Cash", 1)
createPerkRow("🐾", "+1 Free Pet", 2)
createPerkRow(
	"🍀",
	"+" .. Economy.StarterPack.LuckBonus .. "% Luck (Forever)",
	3,
	Color3.fromRGB(20, 130, 55)
)

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

-- "Robux logo" stand-in badge (fara un asset id verificat, vezi nota din chat).
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
priceText.Text = ROBUX_PRICE_TEXT
priceText.TextColor3 = Color3.fromRGB(0, 0, 0)
priceText.Font = FONT_DISPLAY
priceText.TextScaled = true
priceText.LayoutOrder = 2
priceText.ZIndex = 22
priceText.Parent = priceRow

-- ---- Buy button (verde) ----

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
-- Pe ecrane mici (telefon), micsoram proportional butonul si cardul,
-- ca sa nu ocupe prea mult ecran si sa ramana usor de citit/apasat.

local toggleScale = Instance.new("UIScale")
toggleScale.Parent = toggleButton

local cardScale = Instance.new("UIScale")
cardScale.Parent = card

local BASE_VIEWPORT_WIDTH = 1200
local MIN_UI_SCALE = 0.75 -- nu coboram mai mult, ca butoanele sa ramana usor de apasat pe telefon

local function updateUIScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local scale = math.clamp(camera.ViewportSize.X / BASE_VIEWPORT_WIDTH, MIN_UI_SCALE, 1)
	toggleScale.Scale = scale
	cardScale.Scale = scale
end

local function bindCamera()
	updateUIScale()

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateUIScale)
	end
end

bindCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCamera)

-- ================= Behaviour =================

local isOpen = false

local function setOpen(open)
	if open == isOpen then
		return
	end
	isOpen = open

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

toggleButton.Activated:Connect(function()
	setOpen(not isOpen)
end)

closeButton.Activated:Connect(function()
	setOpen(false)
end)

buyButton.Activated:Connect(function()
	MarketplaceService:PromptGamePassPurchase(player, STARTER_PACK_PASS_ID)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(purchasedPlayer, gamePassId, wasPurchased)
	if purchasedPlayer ~= player or gamePassId ~= STARTER_PACK_PASS_ID then
		return
	end

	if wasPurchased then
		setOpen(false)
	end
end)
