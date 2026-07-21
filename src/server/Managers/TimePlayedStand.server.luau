local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TimePlayedStore = require(script.Parent:WaitForChild("TimePlayedStore"))
local PodiumAvatars = require(script.Parent:WaitForChild("PodiumAvatars"))

-- Al doilea stand de leaderboard, langa cel de "Most Cash Earned"
-- (LeaderboardStand.server.luau) -- acelasi stil (gard de lemn + tabla
-- neagra), dar pentru "Most Time Played". Scorul e in MINUTE (vezi
-- DataManager.luau -- se incrementeaza automat, +1 la fiecare 60 secunde
-- petrecute in joc).
--
-- Pozitie exacta, data de jucator.
local BOARD_X = 172.0379638671875
local BOARD_Z = 672.2557373046875
local GROUND_Y = 5
local WOOD_LIGHT = Color3.fromRGB(196, 154, 108)
local WOOD_DARK = Color3.fromRGB(120, 82, 52)
local DARK_PANEL = Color3.fromRGB(46, 32, 48)
local ROWS_REFRESH_INTERVAL = 30
local FULL_LIST_COUNT = 500
local RANK_SEARCH_LIMIT = 1000

local groundPosition = Vector3.new(BOARD_X, GROUND_Y, BOARD_Z)

local function formatMinutes(totalMinutes)
	totalMinutes = totalMinutes or 0
	local hours = math.floor(totalMinutes / 60)
	local minutes = totalMinutes % 60
	return hours .. "h " .. minutes .. "m"
end

-- Cache de nume (UserId -> username), valabil pe durata serverului.
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
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local getMyRankFunction = remotes:FindFirstChild("GetMyTimeRank")
if not getMyRankFunction then
	getMyRankFunction = Instance.new("RemoteFunction")
	getMyRankFunction.Name = "GetMyTimeRank"
	getMyRankFunction.Parent = remotes
end

getMyRankFunction.OnServerInvoke = function(player)
	local _, rank, score = TimePlayedStore.GetLeaderboard(0, player.UserId, RANK_SEARCH_LIMIT)
	return rank, score
end

-- ================= Structura fizica =================

local existing = Workspace:FindFirstChild("TimePlayedStand")
if existing then
	existing:Destroy()
end

local stand = Instance.new("Model")
stand.Name = "TimePlayedStand"
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

part("PostLeft", Vector3.new(1, POST_HEIGHT, 1), groundPosition + Vector3.new(-4.5, POST_HEIGHT / 2, 0), WOOD_DARK)
part("PostRight", Vector3.new(1, POST_HEIGHT, 1), groundPosition + Vector3.new(4.5, POST_HEIGHT / 2, 0), WOOD_DARK)

local rankPlacard = part("RankPlacard", Vector3.new(8, 1.6, 0.4), groundPosition + Vector3.new(0, 1.1, 0), WOOD_DARK)

part("PanelFrame", Vector3.new(10.4, 8.0, 0.5), groundPosition + Vector3.new(0, 6.1, 0), WOOD_LIGHT)
local panel = part("Panel", Vector3.new(9.6, 7.2, 0.6), groundPosition + Vector3.new(0, 6.1, 0), DARK_PANEL, Enum.Material.SmoothPlastic)

local header = part("Header", Vector3.new(11.5, 2.6, 0.6), groundPosition + Vector3.new(0, 11.6, 0), WOOD_DARK)
header.CFrame = CFrame.new(header.Position) * CFrame.Angles(math.rad(-8), 0, 0)

stand.PrimaryPart = panel

-- Rotit inca 90 spre dreapta fata de cum era (270 -> 180).
stand:PivotTo(CFrame.new(panel.Position) * CFrame.Angles(0, math.rad(180), 0))

-- ================= Podium Top 3 =================
-- Pozitie exacta, data de jucator -- rotit CU ACELASI unghi ca standul
-- (180), in jurul acestui punct. Aranjamentul (1/2/3) e definit ca offset
-- LOCAL pe X (aceeasi conventie ca stalpii standului, inainte de rotatie),
-- transformat apoi in coordonate lumii prin acelasi CFrame de rotatie.
local PODIUM_CENTER_X = 157.69676208496094 + 5
local PODIUM_CENTER_Z = 675.0775756835938
local PODIUM_ROTATION_DEGREES = 180
local PODIUM_SPACING = 3.6
local PODIUM_SIZE_XZ = 3.4

local podiumRootCFrame = CFrame.new(PODIUM_CENTER_X, 0, PODIUM_CENTER_Z) * CFrame.Angles(0, math.rad(PODIUM_ROTATION_DEGREES), 0)

local podiumConfig = {
	{Rank = 1, Height = 3.4, Color = Color3.fromRGB(255, 205, 60), LocalXOffset = 0},
	{Rank = 2, Height = 2.4, Color = Color3.fromRGB(200, 200, 205), LocalXOffset = -PODIUM_SPACING},
	{Rank = 3, Height = 1.6, Color = Color3.fromRGB(180, 110, 60), LocalXOffset = PODIUM_SPACING}
}

local podiumLabels = {}
local podiumAvatars = {}

for _, config in ipairs(podiumConfig) do
	local worldPos = podiumRootCFrame:PointToWorldSpace(Vector3.new(config.LocalXOffset, 0, 0))

	local podiumPart = part(
		"Podium" .. config.Rank,
		Vector3.new(PODIUM_SIZE_XZ, config.Height, PODIUM_SIZE_XZ),
		Vector3.new(worldPos.X, GROUND_Y + config.Height / 2, worldPos.Z),
		config.Color,
		Enum.Material.Marble
	)

	podiumPart.CFrame = CFrame.new(podiumPart.Position) * CFrame.Angles(0, math.rad(PODIUM_ROTATION_DEGREES), 0)

	podiumAvatars[config.Rank] = PodiumAvatars.Attach(podiumPart, config.Height, panel.Position)

	local rankLabelsForFace = {}

	-- Pe toate cele 4 fete laterale (nu doar Stanga/Dreapta) -- garantat
	-- vizibil indiferent din ce directie te apropii de podium.
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
	headerLabel.Text = "MOST TIME PLAYED"
	headerLabel.TextColor3 = Color3.fromRGB(255, 240, 210)
	headerLabel.TextStrokeColor3 = Color3.fromRGB(40, 25, 10)
	headerLabel.TextStrokeTransparency = 0.1
	headerLabel.Font = Enum.Font.FredokaOne
	-- TextScaled se comporta imprevizibil pe firma asta (aspect ratio extrem
	-- de lat/scund, plus rotatia de -8 grade) -- de doua ori a dat text
	-- minuscul. TextSize fix, calculat sa incapa "MOST TIME PLAYED" pe un
	-- rand, cu marja de siguranta (60 iesea taiat pe margini).
	headerLabel.TextScaled = false
	headerLabel.TextSize = 38
	headerLabel.TextWrapped = false
	headerLabel.TextXAlignment = Enum.TextXAlignment.Center
	headerLabel.TextYAlignment = Enum.TextYAlignment.Center
	headerLabel.Parent = contentFrame
end

-- Randurile (Top 500), DIRECT pe tabla neagra, intr-un ScrollingFrame real.
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

-- Pool de randuri, REFOLOSITE intre refresh-uri (nu mai stergem/recreem
-- pana la 500 TextLabel-uri x2 fete la fiecare 30s -- bug real de
-- performanta, gasit la audit). Doar textul/culoarea se schimba; randurile
-- in plus fata de lista noua raman create dar ascunse.
local rowPools = {}

local function getOrCreateRow(scroll, i)
	local pool = rowPools[scroll]
	if not pool then
		pool = {}
		rowPools[scroll] = pool
	end

	local label = pool[i]
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "Row" .. i
		label.LayoutOrder = i
		label.Size = UDim2.new(1, 0, 0, 40)
		label.BackgroundTransparency = 1
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextStrokeTransparency = 0.3
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = scroll
		pool[i] = label
	end

	return label
end

local function setRows(lines)
	for _, scroll in ipairs(rowScrolls) do
		local pool = rowPools[scroll] or {}
		rowPools[scroll] = pool

		for i, line in ipairs(lines) do
			local label = getOrCreateRow(scroll, i)
			label.Text = line
			label.TextColor3 = (i == 1) and Color3.fromRGB(255, 215, 90) or Color3.fromRGB(235, 235, 240)
			label.Visible = true
		end

		for i = #lines + 1, #pool do
			pool[i].Visible = false
		end
	end
end

setRows({"Loading data..."})

local function updatePodiums(top)
	for rank, faceLabels in pairs(podiumLabels) do
		local entry = top[rank]

		for _, labels in ipairs(faceLabels) do
			labels.Name.Text = entry and resolveName(entry.UserId) or "-"
		end

		PodiumAvatars.SetAvatar(podiumAvatars[rank], entry and entry.UserId)
	end
end

local function refreshRows()
	local top = TimePlayedStore.GetTop(FULL_LIST_COUNT)

	updatePodiums(top)

	if #top == 0 then
		setRows({"No data yet..."})
		return
	end

	local lines = {}
	for i, entry in ipairs(top) do
		table.insert(lines, i .. ". " .. resolveName(entry.UserId) .. " - " .. formatMinutes(entry.Score))
	end

	setRows(lines)
end

task.spawn(function()
	while stand.Parent do
		refreshRows()
		task.wait(ROWS_REFRESH_INTERVAL)
	end
end)
