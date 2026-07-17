local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CashLeaderboardStore = require(script.Parent:WaitForChild("CashLeaderboardStore"))

-- Pancarda fizica de Leaderboards, stil "gard de lemn + tabla neagra" (cerut
-- explicit de jucator, dupa o poza de referinta din alt joc). Jucatorii apar
-- DIRECT pe tabla (Top 500, cu scroll cu rotita/degetul) -- NU intr-un popup
-- separat, deschis cu "E" (userul a respins explicit varianta cu prompt).
-- Datele vin din CashLeaderboardStore (OrderedDataStore separat, populat de
-- DataManager la fiecare crestere de Money).
local BOARD_X = 191.9238739013672
local BOARD_Z = 686.7409057617188
local GROUND_Y = 5
local WOOD_LIGHT = Color3.fromRGB(196, 154, 108)
local WOOD_DARK = Color3.fromRGB(120, 82, 52)
local DARK_PANEL = Color3.fromRGB(46, 32, 48)
local ROWS_REFRESH_INTERVAL = 30
local FULL_LIST_COUNT = 500
local RANK_SEARCH_LIMIT = 1000

local groundPosition = Vector3.new(BOARD_X, GROUND_Y, BOARD_Z)

-- Cache de nume (UserId -> username), valabil pe durata serverului -- daca
-- se refac randurile de mai multe ori, nu mai interogam de fiecare data
-- GetNameFromUserIdAsync pentru acelasi UserId (evita rate-limit-ul).
local nameCache = {}

local function resolveName(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end

	local name = "Player" .. tostring(userId)

	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)

	if ok and result then
		name = result
	end

	nameCache[userId] = name
	return name
end

-- ================= Remote-uri =================
-- Doar pentru placuta personala ("Your Rank") -- lista mare (Top 500) e
-- construita direct pe tabla, de server, aceeasi pentru toata lumea, fara
-- remote-uri.
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local getMyRankFunction = remotes:FindFirstChild("GetMyCashRank")
if not getMyRankFunction then
	getMyRankFunction = Instance.new("RemoteFunction")
	getMyRankFunction.Name = "GetMyCashRank"
	getMyRankFunction.Parent = remotes
end

getMyRankFunction.OnServerInvoke = function(player)
	local _, rank, score = CashLeaderboardStore.GetLeaderboard(0, player.UserId, RANK_SEARCH_LIMIT)
	return rank, score
end

-- ================= Structura fizica =================

-- Reconstruim intotdeauna de la zero la pornirea serverului, ca sa nu ramana
-- versiuni vechi (acelasi tratament ca la standurile de Token/Egg Shop).
local existing = Workspace:FindFirstChild("LeaderboardStand")
if existing then
	existing:Destroy()
end

local stand = Instance.new("Model")
stand.Name = "LeaderboardStand"
stand.Parent = Workspace

local function part(name, size, position, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.Material = material or Enum.Material.WoodPlanks
	p.Color = color
	p.Position = position
	p.Parent = stand
	return p
end

-- SurfaceGui, NU BillboardGui -- textul se lipeste EXACT pe fata piesei
-- (dimensiunea ei reala), nu plutește separat, mai mare, in afara marginilor
-- modelului.
local function addSurface(targetPart, face)
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "Surface" .. face.Name
	surfaceGui.Face = face
	surfaceGui.Adornee = targetPart
	-- AlwaysOnTop=false -- cu true, textul se vedea PRIN pereti/alte piese
	-- din fata lui (randat mereu deasupra, ignorand adancimea reala din
	-- scena) -- bug real, gasit la testare pe podium.
	surfaceGui.AlwaysOnTop = false
	surfaceGui.LightInfluence = 0
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 50
	surfaceGui.Parent = targetPart

	return surfaceGui
end

-- UIPadding NU functioneaza pus direct pe un SurfaceGui (nu e GuiObject) --
-- trebuie un Frame intermediar, adevarat GuiObject, care sa "tina"
-- padding-ul si continutul.
local function addPadding(guiObject, top, bottom, left, right)
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(top, 0)
	padding.PaddingBottom = UDim.new(bottom, 0)
	padding.PaddingLeft = UDim.new(left, 0)
	padding.PaddingRight = UDim.new(right, 0)
	padding.Parent = guiObject
	return padding
end

local POST_HEIGHT = 13

-- Doi stalpi laterali de lemn, cu baza EXACT pe sol (GROUND_Y).
part("PostLeft", Vector3.new(1, POST_HEIGHT, 1), groundPosition + Vector3.new(-4.5, POST_HEIGHT / 2, 0), WOOD_DARK)
part("PostRight", Vector3.new(1, POST_HEIGHT, 1), groundPosition + Vector3.new(4.5, POST_HEIGHT / 2, 0), WOOD_DARK)

-- Placuta mica de jos, pentru "Your Rank" (personalizata per jucator, de un
-- LocalScript separat -- LeaderboardRankDisplay.client.luau).
local rankPlacard = part("RankPlacard", Vector3.new(8, 1.6, 0.4), groundPosition + Vector3.new(0, 1.1, 0), WOOD_DARK)

-- Panoul negru central (tabla), cu chenar de lemn deschis in jur. Panel
-- iese PUTIN in afara chenarului pe AMBELE fete (Z simetric, nu doar in
-- fata) -- altfel, vazut din spate, chenarul de lemn acoperea complet tabla
-- neagra si textul de pe ea (bug real, gasit la testare).
part("PanelFrame", Vector3.new(10.4, 8.0, 0.5), groundPosition + Vector3.new(0, 6.1, 0), WOOD_LIGHT)
local panel = part("Panel", Vector3.new(9.6, 7.2, 0.6), groundPosition + Vector3.new(0, 6.1, 0), DARK_PANEL, Enum.Material.SmoothPlastic)

-- Firma de sus (categoria), usor inclinata ca un indicator de drum.
local header = part("Header", Vector3.new(11.5, 2.6, 0.6), groundPosition + Vector3.new(0, 11.6, 0), WOOD_DARK)
header.CFrame = CFrame.new(header.Position) * CFrame.Angles(math.rad(-8), 0, 0)

stand.PrimaryPart = panel

-- Pancarda e langa zidul de Est (X mare, aproape de WallEastExtension) --
-- aceeasi rotatie (90) folosita si la Egg Shop/Bank o pune cu fata spre
-- Vest, catre strada.
stand:PivotTo(CFrame.new(panel.Position) * CFrame.Angles(0, math.rad(90), 0))

-- ================= Podium Top 3 =================
-- Locul 1 la mijloc (cel mai inalt, auriu), locul 2 in STANGA jucatorului
-- (mai jos, argintiu), locul 3 in DREAPTA jucatorului (mai jos, bronz) --
-- "stanga/dreapta" calculat din perspectiva cuiva care se apropie dinspre
-- strada (Vest) si se uita spre pancarda (spre Est, +X) -- in Roblox, cu
-- fata spre +X, stanga vazatorului e -Z si dreapta e +Z.
-- Centrul podiumurilor (locul 1, la mijloc) -- coordonate date de jucator.
-- Y-ul NU se ia de acolo (e inaltimea personajului stand in picioare, nu
-- solul) -- se calculeaza mai jos, din GROUND_Y + inaltimea piedestalului.
local PODIUM_CENTER_X = 190.92147827148438
local PODIUM_CENTER_Z = 697.102294921875
local PODIUM_SPACING_Z = 3.6
local PODIUM_SIZE_XZ = 3.4

local podiumConfig = {
	{Rank = 1, Height = 3.4, Color = Color3.fromRGB(255, 205, 60), ZOffset = 0},
	{Rank = 2, Height = 2.4, Color = Color3.fromRGB(200, 200, 205), ZOffset = -PODIUM_SPACING_Z},
	{Rank = 3, Height = 1.6, Color = Color3.fromRGB(180, 110, 60), ZOffset = PODIUM_SPACING_Z}
}

local podiumLabels = {}

for _, config in ipairs(podiumConfig) do
	local podiumPart = part(
		"Podium" .. config.Rank,
		Vector3.new(PODIUM_SIZE_XZ, config.Height, PODIUM_SIZE_XZ),
		Vector3.new(PODIUM_CENTER_X, GROUND_Y + config.Height / 2, PODIUM_CENTER_Z + config.ZOffset),
		config.Color,
		Enum.Material.Marble
	)

	-- Text DIRECT pe piedestal (SurfaceGui), nu plutind deasupra
	-- (BillboardGui) -- cerut explicit. Pe toate cele 4 fete laterale --
	-- garantat vizibil indiferent din ce directie te apropii.
	local rankLabelsForFace = {}

	for _, face in ipairs({Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Front, Enum.NormalId.Back}) do
		local surfaceGui = addSurface(podiumPart, face)

		local contentFrame = Instance.new("Frame")
		contentFrame.Name = "Content"
		contentFrame.Size = UDim2.new(1, 0, 1, 0)
		contentFrame.BackgroundTransparency = 1
		contentFrame.Parent = surfaceGui
		addPadding(contentFrame, 0.05, 0.05, 0.08, 0.08)

		local rankLabel = Instance.new("TextLabel")
		rankLabel.Size = UDim2.new(1, 0, 0.4, 0)
		rankLabel.BackgroundTransparency = 1
		rankLabel.Text = "#" .. config.Rank
		rankLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		rankLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		rankLabel.TextStrokeTransparency = 0.3
		rankLabel.Font = Enum.Font.FredokaOne
		rankLabel.TextScaled = true
		rankLabel.Parent = contentFrame

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, 0, 0.6, 0)
		nameLabel.Position = UDim2.new(0, 0, 0.4, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = "..."
		nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		nameLabel.TextStrokeTransparency = 0.3
		nameLabel.Font = Enum.Font.FredokaOne
		nameLabel.TextScaled = true
		nameLabel.Parent = contentFrame

		table.insert(rankLabelsForFace, {Name = nameLabel})
	end

	podiumLabels[config.Rank] = rankLabelsForFace
end

-- Titlul, direct pe firma de sus -- FARA emoji.
for _, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back}) do
	local surfaceGui = addSurface(header, face)

	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, 0, 1, 0)
	contentFrame.BackgroundTransparency = 1
	contentFrame.Parent = surfaceGui
	addPadding(contentFrame, 0.08, 0.08, 0.06, 0.06)

	local headerLabel = Instance.new("TextLabel")
	headerLabel.Size = UDim2.new(1, 0, 1, 0)
	headerLabel.BackgroundTransparency = 1
	headerLabel.Text = "MOST CASH EARNED"
	headerLabel.TextColor3 = Color3.fromRGB(255, 240, 210)
	headerLabel.TextStrokeColor3 = Color3.fromRGB(40, 25, 10)
	headerLabel.TextStrokeTransparency = 0.1
	headerLabel.Font = Enum.Font.FredokaOne
	-- TextScaled se comporta imprevizibil pe firma asta (aspect ratio extrem
	-- de lat/scund, plus rotatia de -8 grade) -- de doua ori a dat text
	-- minuscul. TextSize fix, calculat sa incapa titlul pe un rand, cu marja
	-- de siguranta (60 iesea taiat pe margini).
	headerLabel.TextScaled = false
	headerLabel.TextSize = 38
	headerLabel.TextWrapped = false
	headerLabel.TextXAlignment = Enum.TextXAlignment.Center
	headerLabel.TextYAlignment = Enum.TextYAlignment.Center
	headerLabel.Parent = contentFrame
end

-- Randurile (Top 500), DIRECT pe tabla neagra, intr-un ScrollingFrame real --
-- jucatorul da scroll cu rotita/degetul, chiar pe model, fara niciun popup.
-- Cate un ScrollingFrame separat per fata (Front/Back), populate impreuna.
local rowScrolls = {}

for _, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back}) do
	local surfaceGui = addSurface(panel, face)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "RowsScroll"
	scroll.Size = UDim2.new(1, 0, 1, 0)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = Color3.fromRGB(212, 175, 55)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = surfaceGui

	addPadding(scroll, 0.03, 0.03, 0.14, 0.05)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = scroll

	table.insert(rowScrolls, scroll)
end

local function clearRows(scroll)
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("TextLabel") or child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function buildRow(scroll, i, text, isFirst)
	local label = Instance.new("TextLabel")
	label.Name = "Row" .. i
	label.LayoutOrder = i
	label.Size = UDim2.new(1, 0, 0, 40)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = isFirst and Color3.fromRGB(255, 215, 90) or Color3.fromRGB(235, 235, 240)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = scroll
end

local function setRows(lines)
	for _, scroll in ipairs(rowScrolls) do
		clearRows(scroll)

		for i, line in ipairs(lines) do
			buildRow(scroll, i, line, i == 1)
		end
	end
end

setRows({"Loading data..."})

-- Podiumurile Top 3 folosesc primele 3 intrari din ACELASI fetch de mai jos
-- (nu mai interogam separat DataStore-ul doar pentru ele).
local function updatePodiums(top)
	for rank, faceLabels in pairs(podiumLabels) do
		local entry = top[rank]

		for _, labels in ipairs(faceLabels) do
			labels.Name.Text = entry and resolveName(entry.UserId) or "-"
		end
	end
end

local function refreshRows()
	local top = CashLeaderboardStore.GetTop(FULL_LIST_COUNT)

	updatePodiums(top)

	if #top == 0 then
		setRows({"No data yet..."})
		return
	end

	local lines = {}
	for i, entry in ipairs(top) do
		table.insert(lines, i .. ". " .. resolveName(entry.UserId) .. " - $" .. tostring(entry.Score))
	end

	setRows(lines)
end

task.spawn(function()
	while stand.Parent do
		refreshRows()
		task.wait(ROWS_REFRESH_INTERVAL)
	end
end)
