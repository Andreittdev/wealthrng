-- Panou "Premium Shop" -- Premium Egg + Cash Packs, cumparabile ORICAND cu
-- Robux (Developer Products, nu gamepass-uri -- vezi PremiumPurchaseManager
-- .server.luau si Economy.PremiumEgg / Economy.CashPacks in EconomyConfig).
--
-- IMPORTANT: ProductId = 0 in EconomyConfig inseamna ca Developer Product-ul
-- inca nu a fost creat in Creator Dashboard -- butoanele de Buy raman
-- vizibile, dar apasarea lor nu face nimic (PromptProductPurchase cu
-- productId=0 e ignorat de Roblox) pana nu sunt puse ID-urile reale.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

local FONT_DISPLAY = Enum.Font.Bangers
local FONT_BODY = Enum.Font.FredokaOne

local PURPLE = Color3.fromRGB(170, 120, 255)
local PURPLE_DARK = Color3.fromRGB(90, 55, 160)
local GREEN = Color3.fromRGB(90, 220, 130)
local GREEN_DARK = Color3.fromRGB(30, 110, 60)
local PANEL_BG = Color3.fromRGB(26, 22, 34)
local CARD_BG = Color3.fromRGB(38, 32, 48)

local function computeIsMobile()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.X < 700 or viewport.Y < 500
end

-- ================= ScreenGui + toggle button =================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PremiumShopGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "PremiumShopButton"
toggleButton.AnchorPoint = Vector2.new(1, 1)
toggleButton.Position = UDim2.new(1, -16, 1, -100)
toggleButton.Size = UDim2.new(0, 140, 0, 56)
toggleButton.BackgroundColor3 = PURPLE
toggleButton.AutoButtonColor = false
toggleButton.Text = ""
toggleButton.ZIndex = 10
toggleButton.Parent = screenGui

Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0.2, 0)

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = PURPLE_DARK
toggleStroke.Thickness = 3
toggleStroke.Parent = toggleButton

local toggleLabel = Instance.new("TextLabel")
toggleLabel.BackgroundTransparency = 1
toggleLabel.Size = UDim2.new(1, -10, 1, -10)
toggleLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
toggleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
toggleLabel.Text = "PREMIUM\nSHOP"
toggleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleLabel.TextStrokeColor3 = PURPLE_DARK
toggleLabel.TextStrokeTransparency = 0
toggleLabel.Font = FONT_DISPLAY
toggleLabel.TextScaled = true
toggleLabel.TextWrapped = true
toggleLabel.ZIndex = 11
toggleLabel.Parent = toggleButton

-- ================= Overlay + panel =================

local overlay = Instance.new("Frame")
overlay.Name = "PremiumShopOverlay"
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.45
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.Visible = false
overlay.ZIndex = 20
overlay.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = PANEL_BG
panel.ZIndex = 21
panel.Parent = overlay

Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 20)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = PURPLE
panelStroke.Thickness = 3
panelStroke.Parent = panel

local function applyLayout()
	if computeIsMobile() then
		panel.Size = UDim2.new(0.9, 0, 0.82, 0)
	else
		panel.Size = UDim2.new(0, 420, 0, 560)
	end
end

applyLayout()

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.Position = UDim2.new(1, -12, 0, 12)
closeButton.Size = UDim2.new(0, 34, 0, 34)
closeButton.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Font = FONT_DISPLAY
closeButton.TextScaled = true
closeButton.ZIndex = 23
closeButton.Parent = panel

Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0.3, 0)

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 16, 0, 10)
titleLabel.Size = UDim2.new(1, -70, 0, 44)
titleLabel.Text = "PREMIUM SHOP"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextStrokeColor3 = PURPLE_DARK
titleLabel.TextStrokeTransparency = 0
titleLabel.Font = FONT_DISPLAY
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 22
titleLabel.Parent = panel

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "CardsScroll"
scroll.Position = UDim2.new(0, 14, 0, 62)
scroll.Size = UDim2.new(1, -28, 1, -76)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ZIndex = 21
scroll.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 12)
listLayout.Parent = scroll

-- ================= Carduri =================

local function buildCard(config)
	local card = Instance.new("Frame")
	card.Name = config.Name
	card.LayoutOrder = config.LayoutOrder
	card.Size = UDim2.new(1, 0, 0, config.Height or 120)
	card.BackgroundColor3 = CARD_BG
	card.ZIndex = 22
	card.Parent = scroll

	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = config.AccentColor
	cardStroke.Thickness = 2
	cardStroke.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 14, 0, 10)
	nameLabel.Size = UDim2.new(1, -28, 0, 30)
	nameLabel.Text = config.Title
	nameLabel.TextColor3 = config.AccentColor
	nameLabel.Font = FONT_DISPLAY
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 23
	nameLabel.Parent = card

	local descLabel = Instance.new("TextLabel")
	descLabel.BackgroundTransparency = 1
	descLabel.Position = UDim2.new(0, 14, 0, 42)
	descLabel.Size = UDim2.new(1, -28, 0, (config.Height or 120) - 92)
	descLabel.Text = config.Description
	descLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
	descLabel.Font = FONT_BODY
	descLabel.TextSize = 14
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.ZIndex = 23
	descLabel.Parent = card

	local buyButton = Instance.new("TextButton")
	buyButton.Name = "BuyButton"
	buyButton.AnchorPoint = Vector2.new(1, 1)
	buyButton.Position = UDim2.new(1, -12, 1, -10)
	buyButton.Size = UDim2.new(0, 130, 0, 32)
	buyButton.BackgroundColor3 = config.AccentColor
	buyButton.Text = config.PriceText
	buyButton.TextColor3 = Color3.fromRGB(20, 15, 10)
	buyButton.Font = FONT_DISPLAY
	buyButton.TextScaled = true
	buyButton.ZIndex = 23
	buyButton.Parent = card

	Instance.new("UICorner", buyButton).CornerRadius = UDim.new(0.25, 0)

	buyButton.Activated:Connect(function()
		if config.ProductId == 0 then
			return
		end
		MarketplaceService:PromptProductPurchase(player, config.ProductId)
	end)

	return card
end

-- Premium Egg -- descriere din Economy.PremiumEgg.RarityChances, ca sansele
-- afisate sa fie mereu corecte (nu hardcodate separat).
local rarityLines = {}
for _, entry in ipairs(Economy.PremiumEgg.RarityChances) do
	table.insert(rarityLines, entry.Rarity .. ": " .. entry.Chance .. "%")
end

buildCard({
	Name = "PremiumEggCard",
	LayoutOrder = 1,
	Height = 150,
	Title = "PREMIUM EGG",
	Description = "Much better odds than normal eggs!\n" .. table.concat(rarityLines, "  |  "),
	AccentColor = PURPLE,
	PriceText = Economy.PremiumEgg.RobuxPrice .. " R$",
	ProductId = Economy.PremiumEgg.ProductId
})

for i, pack in ipairs(Economy.CashPacks) do
	buildCard({
		Name = pack.Id,
		LayoutOrder = i + 1,
		Height = 110,
		Title = "CASH PACK",
		Description = "Instantly get $" .. pack.Money .. " added to your balance.",
		AccentColor = GREEN,
		PriceText = pack.RobuxPrice .. " R$",
		ProductId = pack.ProductId
	})
end

-- ================= Comportament =================

local isOpen = false

local function setOpen(open)
	if open == isOpen then
		return
	end
	isOpen = open
	overlay.Visible = open

	if open then
		applyLayout()
	end
end

toggleButton.Activated:Connect(function()
	setOpen(not isOpen)
end)

closeButton.Activated:Connect(function()
	setOpen(false)
end)
