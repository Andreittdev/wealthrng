local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestPurchaseEvent = remotes:WaitForChild("RequestTokenPurchase")
local purchaseResultEvent = remotes:WaitForChild("TokenPurchaseResult")
local openTokenShopEvent = remotes:WaitForChild("OpenTokenShop")
local equipTitleEvent = remotes:WaitForChild("EquipTitle")

local FONT_DISPLAY = Enum.Font.Bangers
local FONT_BODY = Enum.Font.FredokaOne

-- Tema "premium dark shop", diferita de auriul Starter Pack si movul Rebirth,
-- dar construita dupa acelasi limbaj vizual ca EggShopGui (fundal inchis,
-- rotunjiri mari, contur gros colorat, titlu mare cu emoji, carduri clare).
local BG_DARK = Color3.fromRGB(24, 17, 15)
local BG_MID = Color3.fromRGB(46, 28, 20)
local CARD_BG = Color3.fromRGB(38, 27, 22)
local FIRE_ORANGE = Color3.fromRGB(255, 140, 45)
local GOLD_ACCENT = Color3.fromRGB(255, 205, 95)
local PET_PURPLE = Color3.fromRGB(210, 130, 255)
local OUTLINE_DARK = Color3.fromRGB(70, 34, 16)
local TEXT_LIGHT = Color3.fromRGB(245, 232, 220)
local TEXT_DIM = Color3.fromRGB(190, 170, 158)
local GREEN_OK = Color3.fromRGB(90, 230, 130)
local RED_MISSING = Color3.fromRGB(255, 110, 110)
local CLOSE_RED = Color3.fromRGB(210, 65, 75)

local CATEGORY_COLOR = {
	Titles = GOLD_ACCENT,
	Pets = PET_PURPLE
}

local CATEGORY_LABEL = {
	Titles = "TITLE",
	Pets = "PET"
}

-- ================= Date live ale jucatorului =================

local tokensValue = player:WaitForChild("RebirthTokens", 10)

local function getTokens()
	return tokensValue and tokensValue.Value or 0
end

-- ================= Responsive sizing (acelasi limbaj ca EggShopGui) =================

local function computeIsMobile()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.X < 700 or viewport.Y < 500
end

local function getMainFrameSize(scaleFactor)
	scaleFactor = scaleFactor or 1
	local isMobile = computeIsMobile()

	if not isMobile then
		return UDim2.fromOffset(600 * scaleFactor, 640 * scaleFactor)
	end

	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(400, 700)

	local width = math.min(viewport.X * 0.9, viewport.X - 30) * scaleFactor
	local height = math.min(viewport.Y * 0.82, viewport.Y - 30) * scaleFactor

	return UDim2.fromOffset(width, height)
end

-- ================= ScreenGui =================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TokenShop"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ================= Overlay + Main frame =================
-- Fara buton pe ecran -- panoul se deschide doar de la standul fizic
-- din lume (TokenShopStall), prin ProximityPrompt -> remote OpenTokenShop.

local overlay = Instance.new("Frame")
overlay.Name = "TokenShopOverlay"
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.35
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.Visible = false
overlay.ZIndex = 20
overlay.Parent = screenGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.Size = getMainFrameSize()
mainFrame.BackgroundColor3 = BG_DARK
mainFrame.ClipsDescendants = true
mainFrame.ZIndex = 21
mainFrame.Parent = overlay

Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 18)

local mainStroke = Instance.new("UIStroke")
mainStroke.Color = FIRE_ORANGE
mainStroke.Thickness = 3
mainStroke.Parent = mainFrame

local mainGradient = Instance.new("UIGradient")
mainGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, BG_MID),
	ColorSequenceKeypoint.new(1, BG_DARK),
})
mainGradient.Rotation = 90
mainGradient.Parent = mainFrame

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
closeButton.Parent = mainFrame

Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 10)

local titleLabel = Instance.new("TextLabel")
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 20, 0, 14)
titleLabel.Size = UDim2.new(1, -80, 0, 40)
titleLabel.Text = "REBIRTH TOKEN SHOP"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextStrokeColor3 = OUTLINE_DARK
titleLabel.TextStrokeTransparency = 0
titleLabel.Font = FONT_DISPLAY
titleLabel.TextScaled = true
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 22
titleLabel.Parent = mainFrame

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Position = UDim2.new(0, 20, 0, 52)
subtitleLabel.Size = UDim2.new(1, -80, 0, 20)
subtitleLabel.Text = "Spend Rebirth Tokens on exclusive permanent rewards"
subtitleLabel.TextColor3 = TEXT_DIM
subtitleLabel.Font = FONT_BODY
subtitleLabel.TextSize = 14
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.ZIndex = 22
subtitleLabel.Parent = mainFrame

-- ---- Balanta de tokens, vizibila permanent sus, stil "badge premium" ----

local balanceFrame = Instance.new("Frame")
balanceFrame.BackgroundColor3 = BG_DARK
balanceFrame.Position = UDim2.new(0, 20, 0, 82)
balanceFrame.Size = UDim2.new(1, -40, 0, 46)
balanceFrame.ZIndex = 22
balanceFrame.Parent = mainFrame

Instance.new("UICorner", balanceFrame).CornerRadius = UDim.new(0, 12)

local balanceStroke = Instance.new("UIStroke")
balanceStroke.Color = GOLD_ACCENT
balanceStroke.Thickness = 2
balanceStroke.Transparency = 0.2
balanceStroke.Parent = balanceFrame

-- Grup orizontal (text + iconita, in ordinea asta) -- UIListLayout centreaza
-- grupul ca intreg in balanceFrame, iar AutomaticSize.X pe label face ca
-- iconita sa se lipeasca mereu chiar dupa numar, indiferent cate cifre are
-- (4 vs 400) -- nu o pozitie fixa, care ar lasa un gol sau s-ar suprapune.
local balanceContent = Instance.new("Frame")
balanceContent.BackgroundTransparency = 1
balanceContent.Size = UDim2.new(1, 0, 1, 0)
balanceContent.ZIndex = 22
balanceContent.Parent = balanceFrame

local balanceContentLayout = Instance.new("UIListLayout")
balanceContentLayout.FillDirection = Enum.FillDirection.Horizontal
balanceContentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
balanceContentLayout.VerticalAlignment = Enum.VerticalAlignment.Center
balanceContentLayout.Padding = UDim.new(0, 2)
balanceContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
balanceContentLayout.Parent = balanceContent

local balanceLabel = Instance.new("TextLabel")
balanceLabel.BackgroundTransparency = 1
balanceLabel.AutomaticSize = Enum.AutomaticSize.X
balanceLabel.Size = UDim2.new(0, 0, 1, 0)
balanceLabel.LayoutOrder = 1
balanceLabel.Text = "Your Rebirth Tokens: 0"
balanceLabel.TextColor3 = GOLD_ACCENT
balanceLabel.Font = FONT_DISPLAY
balanceLabel.TextSize = 24
balanceLabel.ZIndex = 22
balanceLabel.Parent = balanceContent

local balanceIcon = Instance.new("ImageLabel")
balanceIcon.BackgroundTransparency = 1
balanceIcon.Size = UDim2.new(0, 28, 0, 28)
balanceIcon.LayoutOrder = 2
balanceIcon.Image = "rbxassetid://73268562302125"
balanceIcon.ZIndex = 22
balanceIcon.Parent = balanceContent

-- ---- Grila de iteme (data-driven, din Economy.TokenShop.Items) ----

local itemsScroll = Instance.new("ScrollingFrame")
itemsScroll.Name = "ItemsScroll"
itemsScroll.BackgroundTransparency = 1
itemsScroll.Position = UDim2.new(0, 20, 0, 140)
itemsScroll.Size = UDim2.new(1, -40, 1, -190)
itemsScroll.ScrollBarThickness = 6
itemsScroll.ScrollBarImageColor3 = FIRE_ORANGE
itemsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
itemsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
itemsScroll.ZIndex = 22
itemsScroll.Parent = mainFrame

local itemsGrid = Instance.new("UIGridLayout")
itemsGrid.SortOrder = Enum.SortOrder.LayoutOrder
itemsGrid.Parent = itemsScroll

local function updateGridLayout()
	if computeIsMobile() then
		itemsGrid.CellSize = UDim2.new(1, 0, 0, 190)
		itemsGrid.CellPadding = UDim2.new(0, 0, 0, 12)
	else
		itemsGrid.CellSize = UDim2.new(0.5, -10, 0, 195)
		itemsGrid.CellPadding = UDim2.new(0, 20, 0, 16)
	end
end

updateGridLayout()

local emptyLabel = Instance.new("TextLabel")
emptyLabel.Name = "EmptyLabel"
emptyLabel.BackgroundTransparency = 1
emptyLabel.Size = UDim2.new(1, 0, 0, 120)
emptyLabel.Text = "🚧 Rewards coming soon!"
emptyLabel.TextColor3 = TEXT_LIGHT
emptyLabel.Font = FONT_BODY
emptyLabel.TextScaled = true
emptyLabel.ZIndex = 22
emptyLabel.Visible = false
emptyLabel.Parent = mainFrame

-- ---- Bottom bar cu explicatie ----

local footerLabel = Instance.new("TextLabel")
footerLabel.BackgroundTransparency = 1
footerLabel.AnchorPoint = Vector2.new(0.5, 1)
footerLabel.Position = UDim2.new(0.5, 0, 1, -14)
footerLabel.Size = UDim2.new(1, -48, 0, 30)
footerLabel.Text = "Earn Rebirth Tokens by doing Rebirths"
footerLabel.TextColor3 = TEXT_DIM
footerLabel.Font = FONT_BODY
footerLabel.TextSize = 13
footerLabel.ZIndex = 22
footerLabel.Parent = mainFrame

-- ================= Iconite premium (2D, fara emoji) =================
-- Construite din Frame-uri cu gradient/glow, la fel ca preview-urile de oua
-- din EggShopGui, in loc de un caracter emoji static. Fiecare item are
-- SILUETA LUI PROPRIE (nu doar aceeasi forma re-colorata) -- un tag pentru
-- Trader, o servieta pentru Merchant, o coroana pentru Tycoon, o vulpe
-- pentru Sprite, un lup pentru Guardian.

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

-- 🏷️ Trader Title -> un tag de pret rotit, cu o "gaura" perforata.
local function buildTagIcon(container, color)
	local tag = iconShape(container, 34, 24, 0, 0, color, 23, 0.22)
	tag.Rotation = -35
	iconOutline(tag, Color3.fromRGB(255, 255, 255), 1.5, 0.4)

	local hole = iconShape(tag, 7, 7, -9, -3, CARD_BG, 24, 0.5)
end

-- 💼 Merchant Title -> o servieta cu maner.
local function buildBriefcaseIcon(container, color)
	iconShape(container, 16, 14, 0, -14, Color3.fromRGB(255, 255, 255), 22, 0.5)

	local body = iconShape(container, 38, 26, 0, 6, color, 23, 0.22)
	iconOutline(body, Color3.fromRGB(255, 255, 255), 1.5, 0.4)

	local clasp = iconShape(body, 10, 7, 0, -3, Color3.fromRGB(255, 255, 255), 24, 0.3)
	clasp.BackgroundTransparency = 0.25
end

-- 💲 Millionaire -> o moneda cu semnul dolarului.
local function buildDollarIcon(container, color)
	local coin = iconShape(container, 42, 42, 0, 0, color, 23, 0.5)
	iconOutline(coin, Color3.fromRGB(255, 255, 255), 2, 0.25)

	-- Font drept (nu FONT_DISPLAY/Bangers, care e inclinat/comic) -- Bangers
	-- facea semnul "$" sa para deplasat intr-o parte, desi caseta lui e
	-- perfect centrata matematic.
	local sign = Instance.new("TextLabel")
	sign.AnchorPoint = Vector2.new(0.5, 0.5)
	sign.Position = UDim2.fromScale(0.5, 0.5)
	sign.Size = UDim2.fromScale(0.7, 0.7)
	sign.BackgroundTransparency = 1
	sign.Text = "$"
	sign.TextColor3 = Color3.fromRGB(255, 255, 255)
	sign.Font = Enum.Font.GothamBlack
	sign.TextScaled = true
	sign.ZIndex = 24
	sign.Parent = coin
end

-- 💎 Diamant clasic (ca in poza de referinta): lat si plat sus (crown),
-- ingustandu-se DOAR in jos, pana la un varf ascutit (pavilion) -- nu un
-- patrat rotit simplu (ala se ingusteaza si sus si jos, iese ca o bomboana).
--
-- Trucul: un patrat rotit 45° (pavilion) centrat EXACT pe linia unde se
-- opreste crown-ul (girdle) -- jumatatea lui de SUS (care s-ar ingusta spre
-- un varf, nedorit) e acoperita complet de crown (ZIndex mai mare), deci
-- ramane vizibila doar jumatatea de JOS, care se ingusteaza natural spre
-- punctul ascutit.
-- Fallback pe baza de Frame-uri (folosit doar daca EditableImage nu merge pe
-- acest Roblox -- vezi buildDiamondIcon mai jos). Aproximare imperfecta, dar
-- functionala, ca sa nu ramana iconita complet goala daca API-ul nou pica.
local function buildDiamondIconFallback(container, color)
	local highlight = color:Lerp(Color3.fromRGB(255, 255, 255), 0.35)
	local girdleY = -6

	local pavilion = iconShape(container, 26, 26, 0, girdleY, color, 22, 0.04)
	pavilion.Rotation = 45
	iconOutline(pavilion, Color3.fromRGB(255, 255, 255), 1.5, 0.3)

	local crown = iconShape(container, 40, 16, 0, girdleY - 8, highlight, 23, 0.15)
	iconOutline(crown, Color3.fromRGB(255, 255, 255), 1.5, 0.3)

	for _, angle in ipairs({32, -32}) do
		local facetLine = iconShape(container, 2, 18, angle > 0 and 5 or -5, girdleY + 9, Color3.fromRGB(255, 255, 255), 24, 0.5)
		facetLine.Rotation = angle
		facetLine.BackgroundTransparency = 0.35
	end
end

-- 💎 Diamant clasic (ca in poza de referinta), desenat pixel-cu-pixel intr-un
-- EditableImage -- un Frame+UICorner rotit nu poate face o forma de
-- pentagon (plat sus, ascutit jos), doar dreptunghiuri/patrate. Desenam
-- silueta exacta prin test "punct in poligon", cu 5 varfuri (2 sus, 2 in
-- lateral la latimea maxima -- girdle, 1 jos, ascutit -- varf).
--
-- Invelit in pcall: EditableImage e o functie mai noua din Roblox -- daca nu
-- e suportata pe versiunea curenta, cadem sigur pe varianta cu Frame-uri, in
-- loc sa crape tot magazinul de tokens (exact ce a patit fontul Cinzel).
local function buildDiamondIcon(container, color)
	local ok = pcall(function()
		local SIZE = 48

		local vertices = {
			Vector2.new(15, 6),
			Vector2.new(33, 6),
			Vector2.new(44, 18),
			Vector2.new(24, 44),
			Vector2.new(4, 18)
		}

		local function pointInPolygon(px, py)
			local inside = false
			local j = #vertices
			for i = 1, #vertices do
				local xi, yi = vertices[i].X, vertices[i].Y
				local xj, yj = vertices[j].X, vertices[j].Y
				if (yi > py) ~= (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi then
					inside = not inside
				end
				j = i
			end
			return inside
		end

		local editable = Instance.new("EditableImage")
		editable.Size = Vector2.new(SIZE, SIZE)

		local pixels = table.create(SIZE * SIZE * 4, 0)

		for y = 0, SIZE - 1 do
			for x = 0, SIZE - 1 do
				local index = (y * SIZE + x) * 4
				if pointInPolygon(x + 0.5, y + 0.5) then
					-- Reflexie simpla: mai deschis spre stanga-sus, mai
					-- inchis spre dreapta-jos -- da un aspect de "fatetat",
					-- nu o culoare plata, uniforma.
					local shade = 1 - math.clamp((x + y) / (SIZE * 2), 0, 1) * 0.4
					pixels[index + 1] = math.clamp(color.R * shade + 0.15, 0, 1)
					pixels[index + 2] = math.clamp(color.G * shade + 0.15, 0, 1)
					pixels[index + 3] = math.clamp(color.B * shade + 0.15, 0, 1)
					pixels[index + 4] = 1
				else
					pixels[index + 4] = 0
				end
			end
		end

		editable:WritePixels(Vector2.new(0, 0), Vector2.new(SIZE, SIZE), pixels)

		local imageLabel = Instance.new("ImageLabel")
		imageLabel.Name = "DiamondShape"
		imageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		imageLabel.Position = UDim2.fromScale(0.5, 0.5)
		imageLabel.Size = UDim2.fromOffset(44, 44)
		imageLabel.BackgroundTransparency = 1
		imageLabel.ImageContent = Content.fromObject(editable)
		imageLabel.ZIndex = 23
		imageLabel.Parent = container
	end)

	if not ok then
		buildDiamondIconFallback(container, color)
	end
end

-- 👑 Tycoon Title -> o coroana cu trei varfuri si o gema in centru.
local function buildCrownIcon(container, color)
	local band = iconShape(container, 34, 12, 0, 10, color, 23, 0.3)
	iconOutline(band, Color3.fromRGB(255, 255, 255), 1.5, 0.4)

	for _, spikeOffset in ipairs({-11, 0, 11}) do
		local spike = iconShape(container, 12, 12, spikeOffset, spikeOffset == 0 and -13 or -9, color, 23, 0.15)
		spike.Rotation = 45
	end

	iconShape(band, 8, 8, 0, 0, Color3.fromRGB(255, 255, 255), 24, 0.5)
end

-- Fallback generic (diamond pentru Title, cerc pentru Pet), folosit doar
-- daca se adauga un item nou in Economy.TokenShop.Items fara iconita dedicata.
local function buildGenericIcon(container, color, item)
	local isTitle = item.Type == "Title"
	local body = iconShape(container, 40, 40, 0, 0, color, 23, isTitle and 0.2 or 0.5)
	body.Rotation = isTitle and 45 or 0
	iconOutline(body, Color3.fromRGB(255, 255, 255), 1.5, 0.4)
end

local ICON_BUILDERS = {
	TraderTitle = buildTagIcon,
	MillionaireTitle = buildDollarIcon,
	BillionaireTitle = buildDiamondIcon
}

local function createPremiumIcon(parent, item)
	local categoryColor = CATEGORY_COLOR[item.Category] or FIRE_ORANGE

	local container = Instance.new("Frame")
	container.Name = "IconPreview"
	container.BackgroundTransparency = 1
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0, 20)
	container.Size = UDim2.fromOffset(58, 58)
	container.ZIndex = 22
	container.Parent = parent

	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromOffset(68, 68)
	glow.BackgroundColor3 = categoryColor
	glow.BackgroundTransparency = 0.6
	glow.BorderSizePixel = 0
	glow.ZIndex = 22
	glow.Parent = container
	Instance.new("UICorner", glow).CornerRadius = UDim.new(0.5, 0)

	-- Pet-urile arata poza reala a pet-ului (avem deja ID-urile), nu o
	-- iconita vectoriala abstracta -- mult mai clar ce primesti.
	if item.Type == "Pet" and item.Pet and item.Pet.Image and item.Pet.Image ~= "" then
		-- Continutul din asset-ul Rebirth Guardian nu e centrat in canvas-ul
		-- lui propriu (modelul in sine sta deplasat spre dreapta) -- nu putem
		-- edita imaginea deja urcata, doar compensam vizual cu un offset.
		local imageOffsetX = (item.Pet.PetId == "RebirthGuardian") and 2 or 0

		local petImage = Instance.new("ImageLabel")
		petImage.Name = "PetImage"
		petImage.BackgroundTransparency = 1
		petImage.AnchorPoint = Vector2.new(0.5, 0.5)
		petImage.Position = UDim2.new(0.5, imageOffsetX, 0.5, 0)
		petImage.Size = UDim2.fromOffset(52, 52)
		petImage.Image = item.Pet.Image
		petImage.ScaleType = Enum.ScaleType.Fit
		petImage.ZIndex = 23
		petImage.Parent = container

		return container
	end

	local builder = ICON_BUILDERS[item.Id]
	if builder then
		builder(container, categoryColor)
	else
		buildGenericIcon(container, categoryColor, item)
	end

	return container
end

-- ================= Randare iteme din Economy.TokenShop.Items =================

local function createItemCard(item, order)
	local categoryColor = CATEGORY_COLOR[item.Category] or FIRE_ORANGE
	local categoryTag = CATEGORY_LABEL[item.Category] or item.Type or ""

	local card = Instance.new("Frame")
	card.Name = item.Id
	card.BackgroundColor3 = CARD_BG
	card.LayoutOrder = order
	card.ZIndex = 22
	card.Parent = itemsScroll

	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = categoryColor
	cardStroke.Thickness = 2
	cardStroke.Parent = card

	-- Badge de categorie, sus in stanga, ca jucatorul sa inteleaga instant
	-- daca e un Titlu (bonus permanent de Luck) sau un Pet exclusiv.
	local tagFrame = Instance.new("Frame")
	tagFrame.BackgroundColor3 = categoryColor
	tagFrame.Position = UDim2.new(0, 10, 0, 10)
	tagFrame.Size = UDim2.new(0, 54, 0, 20)
	tagFrame.ZIndex = 23
	tagFrame.Parent = card

	Instance.new("UICorner", tagFrame).CornerRadius = UDim.new(0, 6)

	local tagLabel = Instance.new("TextLabel")
	tagLabel.BackgroundTransparency = 1
	tagLabel.Size = UDim2.new(1, 0, 1, 0)
	tagLabel.Text = categoryTag
	tagLabel.TextColor3 = BG_DARK
	tagLabel.Font = FONT_BODY
	tagLabel.TextScaled = true
	tagLabel.ZIndex = 24
	tagLabel.Parent = tagFrame

	local costFrame = Instance.new("Frame")
	costFrame.BackgroundColor3 = BG_DARK
	costFrame.AnchorPoint = Vector2.new(1, 0)
	costFrame.Position = UDim2.new(1, -10, 0, 10)
	costFrame.Size = UDim2.new(0, 64, 0, 20)
	costFrame.ZIndex = 23
	costFrame.Parent = card

	Instance.new("UICorner", costFrame).CornerRadius = UDim.new(0, 6)

	local costLayout = Instance.new("UIListLayout")
	costLayout.FillDirection = Enum.FillDirection.Horizontal
	costLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	costLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	costLayout.Padding = UDim.new(0, 1)
	costLayout.SortOrder = Enum.SortOrder.LayoutOrder
	costLayout.Parent = costFrame

	local costLabel = Instance.new("TextLabel")
	costLabel.BackgroundTransparency = 1
	costLabel.Size = UDim2.new(0, 30, 1, 0)
	costLabel.LayoutOrder = 1
	costLabel.Text = tostring(item.Cost)
	costLabel.TextColor3 = GOLD_ACCENT
	costLabel.Font = FONT_BODY
	costLabel.TextScaled = true
	costLabel.ZIndex = 24
	costLabel.Parent = costFrame

	local costIcon = Instance.new("ImageLabel")
	costIcon.BackgroundTransparency = 1
	costIcon.Size = UDim2.new(0, 16, 0, 16)
	costIcon.Image = "rbxassetid://73268562302125"
	costIcon.LayoutOrder = 2
	costIcon.ZIndex = 24
	costIcon.Parent = costFrame

	createPremiumIcon(card, item)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 10, 0, 82)
	nameLabel.Size = UDim2.new(1, -20, 0, 22)
	nameLabel.Text = item.Name
	nameLabel.TextColor3 = TEXT_LIGHT
	nameLabel.Font = FONT_DISPLAY
	nameLabel.TextScaled = true
	nameLabel.ZIndex = 22
	nameLabel.Parent = card

	local descLabel = Instance.new("TextLabel")
	descLabel.BackgroundTransparency = 1
	descLabel.Position = UDim2.new(0, 10, 0, 106)
	descLabel.Size = UDim2.new(1, -20, 0, 36)
	descLabel.Text = item.Description or ""
	descLabel.TextColor3 = TEXT_DIM
	descLabel.TextWrapped = true
	descLabel.Font = FONT_BODY
	descLabel.TextSize = 13
	descLabel.ZIndex = 22
	descLabel.Parent = card

	local buyButton = Instance.new("TextButton")
	buyButton.AnchorPoint = Vector2.new(0.5, 1)
	buyButton.Position = UDim2.new(0.5, 0, 1, -10)
	buyButton.Size = UDim2.new(1, -20, 0, 32)
	buyButton.AutoButtonColor = false
	buyButton.Text = ""
	buyButton.ZIndex = 22
	buyButton.Parent = card

	Instance.new("UICorner", buyButton).CornerRadius = UDim.new(0, 8)

	-- Text-ul butonului nu mai e proprietatea .Text (RichText cu <img> nu se
	-- randa corect, incercat si respins -- vezi captura primita de la user).
	-- In loc, iconita e un ImageLabel REAL, separat, aratat DOAR pentru
	-- starile BUY/NEED (unde chiar apare costul in tokens) -- textul se muta
	-- la dreapta cand iconita e vizibila, ca sa nu se suprapuna.
	-- Grup orizontal (text + iconita, in ordinea asta) -- UIListLayout
	-- centreaza grupul ca intreg in buton, iar AutomaticSize.X pe label face
	-- ca iconita sa se lipeasca mereu chiar dupa numar. Iconita e ascunsa
	-- (Visible=false) pentru starile fara cost (EQUIP/EQUIPPED/OWNED) --
	-- UIListLayout ignora automat copiii invizibili, deci textul se
	-- recentreaza singur, fara sa mai umblam manual la Size/Position.
	local buyContent = Instance.new("Frame")
	buyContent.BackgroundTransparency = 1
	buyContent.Size = UDim2.new(1, 0, 1, 0)
	buyContent.ZIndex = 23
	buyContent.Parent = buyButton

	local buyContentLayout = Instance.new("UIListLayout")
	buyContentLayout.FillDirection = Enum.FillDirection.Horizontal
	buyContentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	buyContentLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	buyContentLayout.Padding = UDim.new(0, 2)
	buyContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	buyContentLayout.Parent = buyContent

	local buyTextLabel = Instance.new("TextLabel")
	buyTextLabel.BackgroundTransparency = 1
	buyTextLabel.AutomaticSize = Enum.AutomaticSize.X
	buyTextLabel.Size = UDim2.new(0, 0, 1, 0)
	buyTextLabel.LayoutOrder = 1
	buyTextLabel.Text = "BUY"
	buyTextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyTextLabel.Font = FONT_DISPLAY
	buyTextLabel.TextSize = 18
	buyTextLabel.ZIndex = 23
	buyTextLabel.Parent = buyContent

	local buyIcon = Instance.new("ImageLabel")
	buyIcon.BackgroundTransparency = 1
	buyIcon.Size = UDim2.new(0, 20, 0, 20)
	buyIcon.LayoutOrder = 2
	buyIcon.Image = "rbxassetid://73268562302125"
	buyIcon.Visible = false
	buyIcon.ZIndex = 23
	buyIcon.Parent = buyContent

	local isTitleItem = item.Type == "Title"

	local function refreshButton()
		local owned = item.OneTime and player:GetAttribute("TokenShopBought_" .. item.Id) == true

		if owned and isTitleItem then
			-- Titlurile cumparate raman active (nu inerte ca "✔ OWNED") --
			-- butonul devine EQUIP/UNEQUIP, ca sa poti alege care sa fie cel
			-- afisat in chat (poti purta un singur titlu deodata).
			local equipped = player:GetAttribute("EquippedTitle") == item.Id

			if equipped then
				buyButton.BackgroundColor3 = GOLD_ACCENT
				buyIcon.Visible = false
				buyTextLabel.Text = "✔ EQUIPPED"
			else
				buyButton.BackgroundColor3 = GREEN_OK
				buyIcon.Visible = false
				buyTextLabel.Text = "EQUIP"
			end

			buyButton.Active = true
			cardStroke.Transparency = 0
		elseif owned then
			buyButton.BackgroundColor3 = BG_DARK
			buyIcon.Visible = false
			buyTextLabel.Text = "✔ OWNED"
			buyButton.Active = false
			cardStroke.Transparency = 0.5
		elseif getTokens() >= item.Cost then
			buyButton.BackgroundColor3 = GREEN_OK
			buyIcon.Visible = true
			buyTextLabel.Text = "BUY — " .. item.Cost
			buyButton.Active = true
			cardStroke.Transparency = 0
		else
			buyButton.BackgroundColor3 = RED_MISSING
			buyIcon.Visible = true
			buyTextLabel.Text = "NEED " .. item.Cost
			buyButton.Active = true
			cardStroke.Transparency = 0
		end
	end

	refreshButton()

	buyButton.Activated:Connect(function()
		local owned = item.OneTime and player:GetAttribute("TokenShopBought_" .. item.Id) == true

		if owned and isTitleItem then
			local equipped = player:GetAttribute("EquippedTitle") == item.Id
			equipTitleEvent:FireServer(equipped and "" or item.Id)
			return
		end

		if owned or getTokens() < item.Cost then
			return
		end

		requestPurchaseEvent:FireServer(item.Id)
	end)

	if tokensValue then
		tokensValue:GetPropertyChangedSignal("Value"):Connect(refreshButton)
	end
	player:GetAttributeChangedSignal("TokenShopBought_" .. item.Id):Connect(refreshButton)

	if isTitleItem then
		player:GetAttributeChangedSignal("EquippedTitle"):Connect(refreshButton)
	end

	return card
end

local function buildShop()
	local items = Economy.TokenShop.Items

	if #items == 0 then
		emptyLabel.Visible = true
		return
	end

	emptyLabel.Visible = false

	for index, item in ipairs(items) do
		createItemCard(item, index)
	end
end

buildShop()

-- ================= Actualizare live a balantei =================

local function refreshBalance()
	local tokens = getTokens()
	balanceLabel.Text = "Your Rebirth Tokens: " .. tokens
end

refreshBalance()

if tokensValue then
	tokensValue:GetPropertyChangedSignal("Value"):Connect(refreshBalance)
end

-- ================= Coordonare cu celelalte shop-uri =================
-- Token Shop nu are propriul buton pe ecran (se deschide doar de la standul
-- fizic), dar tot trebuie sa ascunda butoanele Starter Pack/Rebirth/Daily
-- Rewards cat timp e deschis -- acelasi flag comun ca la celelalte.
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
		refreshBalance()
		updateGridLayout()
		overlay.Visible = true
		mainFrame.Size = getMainFrameSize(0.88)

		local targetSize = getMainFrameSize()

		TweenService:Create(
			mainFrame,
			TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{Size = targetSize}
		):Play()
	else
		overlay.Visible = false
	end
end

closeButton.Activated:Connect(function()
	setOpen(false)
end)

openTokenShopEvent.OnClientEvent:Connect(function()
	setOpen(true)
end)

purchaseResultEvent.OnClientEvent:Connect(function(data)
	refreshBalance()
end)

-- Daca jucatorul roteste telefonul cat timp shop-ul e deschis, recalculam.
do
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if overlay.Visible then
				updateGridLayout()
				mainFrame.Size = getMainFrameSize()
			end
		end)
	end
end
