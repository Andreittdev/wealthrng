local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- BUG gasit (audit): pornit aici (inainte de orice WaitForChild care poate
-- dura -- MainHUD se poate construi/replica pana la 10s pe un server
-- proaspat), nu dupa ce tot HUD-ul s-a incarcat -- altfel countdown-ul de
-- pe client ramanea in urma fata de task.delay-urile reale de pe server
-- (PlayerAdded), putand arata timp ramas chiar si dupa ce recompensa a
-- fost deja acordata.
local sessionStart = os.clock()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EconomyConfig"))

local FONT_DISPLAY = Enum.Font.FredokaOne
local FONT_BODY = Enum.Font.FredokaOne
local ACCENT = Color3.fromRGB(255, 199, 79)
local BG_DARK = Color3.fromRGB(24, 20, 16)

-- Paleta de tile-uri (gradient), rotita per milestone -- acelasi limbaj
-- vizual ca poza de referinta (portocaliu/mov/roz), fara textura de
-- "caramida Lego" (ar cere un asset de imagine pe care nu-l avem).
local TILE_PALETTE = {
	{Color3.fromRGB(255, 170, 60), Color3.fromRGB(230, 120, 20)},
	{Color3.fromRGB(190, 110, 255), Color3.fromRGB(140, 60, 210)},
	{Color3.fromRGB(255, 110, 170), Color3.fromRGB(210, 60, 130)},
}

local function computeIsMobile()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.X < 700 or viewport.Y < 500
end

-- Pe un telefon cu ecran scund (ex: landscape), 420px ficsi puteau depasi
-- ecranul real, facand panoul sa para "pe tot ecranul". Plafonam la
-- inaltimea reala disponibila -- grila deruleaza oricum (ScrollingFrame),
-- deci continutul ramane accesibil chiar daca panoul e mai mic.
local function getMobilePanelHeight()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(400, 700)
	return math.min(320, viewport.Y - 60)
end

-- Calculat O SINGURA DATA, refolosit peste tot mai jos -- pe Desktop
-- ramane 100% neschimbat (toate valorile "or"); pe mobil, panoul/header/
-- butonul de close/tile-urile sunt acum mai mici, ca sa nu mai domine tot
-- ecranul (cerut explicit).
local isMobile = computeIsMobile()

local mainHud = playerGui:WaitForChild("MainHUD", 30)
if not mainHud then
	warn("PlaytimeRewardsDisplay.client.luau: MainHUD nu a aparut in PlayerGui dupa 30s.")
	return
end

local bottomBar = mainHud:WaitForChild("BottomBar", 30)
local row3 = bottomBar and bottomBar:WaitForChild("Row3", 30)
local storeButton = row3 and row3:WaitForChild("StoreButton", 30)

if not storeButton then
	warn("PlaytimeRewardsDisplay.client.luau: StoreButton nu a aparut dupa 30s.")
	return
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlaytimeRewardsDisplay"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ================= Butonul mic, in mijlocul ecranului =================

-- Aceeasi forma patrata compacta pe mobil SI pe PC -- doar cadoul + timerul,
-- fara niciun text de titlu. Singura diferenta: pe PC are un fundal (chenar)
-- in spate; pe mobil ramane transparent, ca inainte.
local toggleButton = Instance.new("TextButton")
toggleButton.Name = "PlaytimeRewardsButton"
toggleButton.BackgroundColor3 = BG_DARK
toggleButton.BackgroundTransparency = isMobile and 1 or 0.1
toggleButton.Text = ""
toggleButton.AutoButtonColor = false
toggleButton.ClipsDescendants = false
toggleButton.Parent = screenGui

if not isMobile then
	Instance.new("UICorner", toggleButton).CornerRadius = UDim.new(0.2, 0)

	local toggleStroke = Instance.new("UIStroke")
	toggleStroke.Color = ACCENT
	toggleStroke.Thickness = 2
	toggleStroke.Transparency = 0.3
	toggleStroke.Parent = toggleButton
end

-- BUG gasit: UIAspectRatioConstraint cu Size initial de latime 0 -- cu
-- AspectType implicit (FitWithinMaxSize), incadrarea intr-o cutie de latime
-- 0 dadea tot 0 -- imaginea disparea complet. Fix simplu: parintele
-- (toggleButton) e garantat patrat (vezi repositionToggle), deci Scale egal
-- pe X si Y produce direct un patrat, fara nicio constrangere.
local badgeIcon = Instance.new("ImageLabel")
badgeIcon.BackgroundTransparency = 1
badgeIcon.Size = UDim2.new(0.72, 0, 0.72, 0)
badgeIcon.Position = UDim2.new(0.5, 0, 0, 0)
badgeIcon.AnchorPoint = Vector2.new(0.5, 0)
badgeIcon.Image = "rbxassetid://116174166971152"
badgeIcon.ZIndex = 2
badgeIcon.Parent = toggleButton

local toggleCountdownLabel = Instance.new("TextLabel")
toggleCountdownLabel.BackgroundTransparency = 1
toggleCountdownLabel.Size = UDim2.new(1, 0, 0.24, 0)
toggleCountdownLabel.Position = UDim2.new(0.5, 0, 1, 0)
toggleCountdownLabel.AnchorPoint = Vector2.new(0.5, 1)
toggleCountdownLabel.Text = "--:--"
toggleCountdownLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleCountdownLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
toggleCountdownLabel.TextStrokeTransparency = 0
toggleCountdownLabel.Font = FONT_DISPLAY
toggleCountdownLabel.TextScaled = true
toggleCountdownLabel.ZIndex = 2
toggleCountdownLabel.Parent = toggleButton

-- Cerut: sus, in mijlocul ecranului (centrat orizontal, aproape de partea de
-- sus, nu chiar in centrul ecranului).
local function repositionToggle()
	local absSize = storeButton.AbsoluteSize
	local side = absSize.Y

	toggleButton.AnchorPoint = Vector2.new(0.5, 0)
	toggleButton.Size = UDim2.new(0, side, 0, side)
	toggleButton.Position = UDim2.new(0.5, 0, 0, isMobile and 2 or 0)
end

repositionToggle()
storeButton:GetPropertyChangedSignal("AbsolutePosition"):Connect(repositionToggle)
storeButton:GetPropertyChangedSignal("AbsoluteSize"):Connect(repositionToggle)

-- ================= Panoul (grila de tile-uri) =================

-- TextButton (nu Frame) -- ca sa poata prinde click-ul de "inchide daca dai
-- click in afara panoului" prin Activated (Frame nu are acest eveniment).
local dimmer = Instance.new("TextButton")
dimmer.Name = "Dimmer"
dimmer.Text = ""
dimmer.AutoButtonColor = false
dimmer.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
dimmer.BackgroundTransparency = 0.45
dimmer.Size = UDim2.new(1, 0, 1, 0)
dimmer.Visible = false
dimmer.ZIndex = 60
dimmer.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "PlaytimeRewardsPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = isMobile and UDim2.new(0.72, 0, 0, getMobilePanelHeight()) or UDim2.new(0, 560, 0, 360)
panel.BackgroundColor3 = BG_DARK
panel.Visible = false
panel.ZIndex = 61
panel.Parent = screenGui

Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = ACCENT
panelStroke.Thickness = 2
panelStroke.Parent = panel

-- Header -- gradient albastru, gift + titlu + X, ca in poza de referinta.
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, isMobile and 42 or 56)
header.BackgroundColor3 = Color3.fromRGB(70, 190, 235)
header.ZIndex = 62
header.Parent = panel

Instance.new("UICorner", header).CornerRadius = UDim.new(0, 18)

local headerGradient = Instance.new("UIGradient")
headerGradient.Color = ColorSequence.new(Color3.fromRGB(90, 210, 255), Color3.fromRGB(40, 150, 200))
headerGradient.Rotation = 90
headerGradient.Parent = header

-- Colturile de jos ale header-ului raman drepte (nu rotunjite), ca sa se
-- lipeasca de restul panoului -- un Frame mic peste jumatatea de jos a
-- UICorner-ului, aceeasi culoare.
local headerMask = Instance.new("Frame")
headerMask.BackgroundColor3 = Color3.fromRGB(70, 190, 235)
headerMask.BorderSizePixel = 0
headerMask.Size = UDim2.new(1, 0, 0, 18)
headerMask.Position = UDim2.new(0, 0, 1, -18)
headerMask.ZIndex = 62
headerMask.Parent = header
local headerMaskGradient = Instance.new("UIGradient")
headerMaskGradient.Color = ColorSequence.new(Color3.fromRGB(90, 210, 255), Color3.fromRGB(40, 150, 200))
headerMaskGradient.Rotation = 90
headerMaskGradient.Parent = headerMask

local headerTitleContainer = Instance.new("Frame")
headerTitleContainer.BackgroundTransparency = 1
headerTitleContainer.Size = UDim2.new(1, isMobile and -85 or -110, 1, -12)
headerTitleContainer.Position = UDim2.new(0, isMobile and 44 or 60, 0, 6)
headerTitleContainer.ZIndex = 63
headerTitleContainer.Parent = header

local headerTitleLayout = Instance.new("UIListLayout")
headerTitleLayout.FillDirection = Enum.FillDirection.Horizontal
headerTitleLayout.VerticalAlignment = Enum.VerticalAlignment.Center
headerTitleLayout.Padding = UDim.new(0, 8)
headerTitleLayout.SortOrder = Enum.SortOrder.LayoutOrder
headerTitleLayout.Parent = headerTitleContainer

local headerIcon = Instance.new("ImageLabel")
headerIcon.BackgroundTransparency = 1
headerIcon.Size = UDim2.new(0, isMobile and 24 or 36, 0, isMobile and 24 or 36)
headerIcon.Image = "rbxassetid://116174166971152"
headerIcon.LayoutOrder = 1
headerIcon.ZIndex = 63
headerIcon.Parent = headerTitleContainer

local headerTitle = Instance.new("TextLabel")
headerTitle.BackgroundTransparency = 1
headerTitle.Size = UDim2.new(1, -44, 1, 0)
headerTitle.Text = "Playtime Rewards"
headerTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
headerTitle.TextStrokeColor3 = Color3.fromRGB(20, 60, 80)
headerTitle.TextStrokeTransparency = 0.3
headerTitle.Font = FONT_DISPLAY
headerTitle.TextScaled = true
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.LayoutOrder = 2
headerTitle.ZIndex = 63
headerTitle.Parent = headerTitleContainer

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, isMobile and 30 or 40, 0, isMobile and 30 or 40)
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, isMobile and -6 or -8, 0.5, 0)
closeButton.BackgroundColor3 = Color3.fromRGB(230, 70, 70)
closeButton.Text = "✕"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Font = FONT_DISPLAY
closeButton.TextScaled = true
closeButton.ZIndex = 63
closeButton.Parent = header

Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 10)

-- Grila de tile-uri.
local grid = Instance.new("ScrollingFrame")
grid.Name = "Grid"
grid.BackgroundTransparency = 1
grid.Position = UDim2.new(0, 12, 0, 66)
grid.Size = UDim2.new(1, -24, 1, -78)
grid.CanvasSize = UDim2.new(0, 0, 0, 0)
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.ScrollBarThickness = 6
grid.ScrollBarImageColor3 = ACCENT
grid.ZIndex = 62
grid.Parent = panel

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.new(0, isMobile and 100 or 140, 0, isMobile and 100 or 140)
gridLayout.CellPadding = UDim2.new(0, isMobile and 6 or 10, 0, isMobile and 6 or 10)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = grid

local function rewardIconAndText(milestone)
	if milestone.Type == "Money" then
		return "💰", "+$" .. milestone.Money
	elseif milestone.Type == "Pet" then
		return "🐾", milestone.Pet.DisplayName
	end
	return "🎁", ""
end

local tiles = {}

for i, milestone in ipairs(Economy.PlaytimeRewards.Milestones) do
	local palette = TILE_PALETTE[((i - 1) % #TILE_PALETTE) + 1]

	local tile = Instance.new("Frame")
	tile.Name = "Tile" .. i
	tile.LayoutOrder = i
	tile.BackgroundColor3 = palette[1]
	tile.ZIndex = 62
	tile.Parent = grid

	Instance.new("UICorner", tile).CornerRadius = UDim.new(0, 12)

	local tileGradient = Instance.new("UIGradient")
	tileGradient.Color = ColorSequence.new(palette[1], palette[2])
	tileGradient.Rotation = 90
	tileGradient.Parent = tile

	local tileStroke = Instance.new("UIStroke")
	tileStroke.Color = Color3.fromRGB(20, 15, 10)
	tileStroke.Thickness = 2
	tileStroke.Parent = tile

	local icon, rewardText = rewardIconAndText(milestone)

	-- Peturile exclusive (Chronos Pup/Timekeeper) au acum imagine reala --
	-- o folosim in loc de emoji-ul generic "🐾" cand exista.
	local petImage = milestone.Type == "Pet" and milestone.Pet.Image
	if petImage and petImage ~= "" then
		local iconImage = Instance.new("ImageLabel")
		iconImage.BackgroundTransparency = 1
		iconImage.Size = UDim2.new(0, isMobile and 56 or 78, 0, isMobile and 56 or 78)
		iconImage.Position = UDim2.new(0.5, 0, 0, isMobile and 4 or 6)
		iconImage.AnchorPoint = Vector2.new(0.5, 0)
		iconImage.Image = petImage
		iconImage.ZIndex = 63
		iconImage.Parent = tile
	else
		local iconLabel = Instance.new("TextLabel")
		iconLabel.BackgroundTransparency = 1
		iconLabel.Size = UDim2.new(1, 0, 0, isMobile and 43 or 60)
		iconLabel.Position = UDim2.new(0, 0, 0, isMobile and 4 or 6)
		iconLabel.Text = icon
		iconLabel.Font = FONT_DISPLAY
		iconLabel.TextScaled = true
		iconLabel.ZIndex = 63
		iconLabel.Parent = tile
	end

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Size = UDim2.new(1, -8, 0, isMobile and 16 or 22)
	rewardLabel.Position = UDim2.new(0, 4, 0, isMobile and 61 or 86)
	rewardLabel.Text = rewardText
	rewardLabel.TextColor3 = Color3.fromRGB(255, 240, 120)
	rewardLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	rewardLabel.TextStrokeTransparency = 0.2
	rewardLabel.Font = FONT_DISPLAY
	rewardLabel.TextScaled = true
	rewardLabel.ZIndex = 63
	rewardLabel.Parent = tile

	local statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Size = UDim2.new(1, -8, 0, isMobile and 19 or 26)
	statusLabel.Position = UDim2.new(0, 4, 1, isMobile and -22 or -30)
	statusLabel.Text = "--:--"
	statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	statusLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	statusLabel.TextStrokeTransparency = 0.2
	statusLabel.Font = FONT_DISPLAY
	statusLabel.TextScaled = true
	statusLabel.ZIndex = 63
	statusLabel.Parent = tile

	table.insert(tiles, {Milestone = milestone, StatusLabel = statusLabel, Tile = tile})
end

-- ================= Deschidere/inchidere =================
-- Continua sa se ascunda cand orice alt panou e deschis (ShopModalOpen), ca
-- sa nu se suprapuna peste el -- dar, cerut explicit, NU mai dispare cand
-- jucatorul restrange stiva din dreapta cu "<" (SideStackCollapsed). Playtime
-- Rewards ramane vizibil mereu, indiferent de starea comutatorului.
local function setShopModalOpen(open)
	player:SetAttribute("ShopModalOpen", open)
end

local function updateToggleVisibility()
	toggleButton.Visible = not player:GetAttribute("ShopModalOpen")
end

player:GetAttributeChangedSignal("ShopModalOpen"):Connect(updateToggleVisibility)
updateToggleVisibility()

local function setOpen(open)
	dimmer.Visible = open
	panel.Visible = open
	setShopModalOpen(open)
end

toggleButton.Activated:Connect(function()
	setOpen(true)
end)

closeButton.Activated:Connect(function()
	setOpen(false)
end)

dimmer.Activated:Connect(function()
	setOpen(false)
end)

-- ================= Countdown (buton mic + tile-urile din panou) =================
-- Auto-grant, la fel ca inainte -- serverul acorda recompensa singur, fara
-- click; panoul/butonul doar AFISEAZA countdown-ul, cu bifa cand pragul a
-- fost deja atins in sesiunea asta. sessionStart e declarat la INCEPUTUL
-- fisierului (vezi comentariul de acolo), nu aici.
local milestones = Economy.PlaytimeRewards.Milestones

local function formatCountdown(seconds)
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%d:%02d", minutes, secs)
end

local function updateDisplay()
	local elapsed = os.clock() - sessionStart

	local nextText = "All claimed!"
	local foundNext = false

	for _, entry in ipairs(tiles) do
		local remaining = entry.Milestone.Seconds - elapsed

		if remaining <= 0 then
			entry.StatusLabel.Text = "✅ Claimed"
		else
			entry.StatusLabel.Text = formatCountdown(remaining)

			if not foundNext then
				foundNext = true
				nextText = formatCountdown(remaining)
			end
		end
	end

	toggleCountdownLabel.Text = nextText
end

updateDisplay()

task.spawn(function()
	while true do
		task.wait(1)
		updateDisplay()
	end
end)
