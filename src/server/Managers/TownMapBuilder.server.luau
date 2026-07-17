local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local MarketManager = require(modulesFolder:WaitForChild("MarketManager"))

-- Harta noua: doar strada + trotuare + iarba, cu Material=Plastic (grid-ul
-- fin cerut de jucator, exact ca in poza de referinta -- 3 fasii: gri inchis,
-- alb, verde). Fara cladiri, fara felinare -- doar solul.
--
-- IMPORTANT: NU sterge harta veche -- nu avem vizibilitate asupra
-- numelor/structurii ei exacte din Studio, deci stergerea automata ar risca
-- sa distruga ceva construit manual (sau standurile facute separat: Token
-- Shop, Egg Shop, Index). Harta noua e construita intr-un Folder separat,
-- clar identificabil ("TownMap"), intr-o zona goala -- dupa ce o vezi in
-- Studio, stergi manual ce nu mai vrei din harta veche (sau imi spui exact ce
-- sa sterg).
local STREET_LENGTH = 400
local STREET_WIDTH = 32
local SIDEWALK_WIDTH = 8

-- Pozitie provizorie -- o zona goala, departe de standurile deja construite
-- (Token Shop ~Z=-318, Egg Shop ~Z=-319, Index ~Z=90). Spune-mi daca se
-- suprapune cu ceva din harta ta veche si o mut.
local STREET_START_Z = 200

-- Ridicata clar deasupra nivelului 0 -- daca solul vechi al hartii e undeva
-- aproape de Y=0, orice piesa noua aproape coplanara cu el pâlpâie
-- (z-fighting) la miscarea camerei. La 5 studs deasupra, nu se mai poate
-- suprapune cu nimic din harta veche.
local GROUND_Y = 5

-- Textura "bloxy" cu patratele in relief, identificata de jucator (ID de
-- asset Roblox) -- Material=Plastic singur NU produce grid-ul asta in
-- randarea moderna (confirmat vizual: piesele ies complet plate). Grid-ul e
-- o imagine reala, aplicata ca Texture pe fata de sus a fiecarei piese, colorata
-- diferit per fasie (strada/trotuar/iarba) via Texture.Color3 -- aceeasi
-- imagine, doar tentata, exact ca in poza de referinta.
local GRID_TEXTURE_ID = "rbxassetid://6372755229"
local TEXTURE_TILE_STUDS = 4

local mapFolder = Workspace:FindFirstChild("TownMap")
if mapFolder then
	mapFolder:Destroy()
end

mapFolder = Instance.new("Folder")
mapFolder.Name = "TownMap"
mapFolder.Parent = Workspace

local streetCenterZ = STREET_START_Z + STREET_LENGTH / 2

local function createPart(name, size, cframe, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Plastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = mapFolder

	local topTexture = Instance.new("Texture")
	topTexture.Name = "GridTexture"
	topTexture.Face = Enum.NormalId.Top
	topTexture.Texture = GRID_TEXTURE_ID
	topTexture.Color3 = color
	topTexture.StudsPerTileU = TEXTURE_TILE_STUDS
	topTexture.StudsPerTileV = TEXTURE_TILE_STUDS
	topTexture.Parent = part

	return part
end

local MAP_SIZE = 400

-- Iarba, o zona mare in jurul strazii.
createPart(
	"Grass",
	Vector3.new(MAP_SIZE, 0.8, MAP_SIZE),
	CFrame.new(0, GROUND_Y - 0.5, streetCenterZ),
	Color3.fromRGB(30, 200, 40)
)

-- Strada.
createPart(
	"Street",
	Vector3.new(STREET_WIDTH, 1, STREET_LENGTH),
	CFrame.new(0, GROUND_Y, streetCenterZ),
	Color3.fromRGB(60, 60, 65)
)

-- Linie galbena intrerupta pe mijlocul strazii, cu aceeasi textura (tentata
-- galben) -- putin mai inalta decat strada, ca sa iasa vizibil deasupra ei
-- fara sa palpaie (z-fighting) cu suprafata strazii.
local DASH_LENGTH = 6
local DASH_GAP = 6
local dashZ = STREET_START_Z

while dashZ < STREET_START_Z + STREET_LENGTH do
	createPart(
		"Dash",
		Vector3.new(1.2, 1.1, DASH_LENGTH),
		CFrame.new(0, GROUND_Y, dashZ + DASH_LENGTH / 2),
		Color3.fromRGB(255, 220, 60)
	)
	dashZ += DASH_LENGTH + DASH_GAP
end

-- Trotuare, stanga si dreapta.
local sidewalkOffsetX = STREET_WIDTH / 2 + SIDEWALK_WIDTH / 2

createPart(
	"SidewalkLeft",
	Vector3.new(SIDEWALK_WIDTH, 1.2, STREET_LENGTH),
	CFrame.new(-sidewalkOffsetX, GROUND_Y, streetCenterZ),
	Color3.fromRGB(235, 235, 235)
)

createPart(
	"SidewalkRight",
	Vector3.new(SIDEWALK_WIDTH, 1.2, STREET_LENGTH),
	CFrame.new(sidewalkOffsetX, GROUND_Y, streetCenterZ),
	Color3.fromRGB(235, 235, 235)
)

-- Pereti inalti pe marginea hartii, ca la Steal a Brainrot -- delimiteaza
-- zona de joc, jucatorii nu pot iesi/cadea de pe marginea hartii.
local WALL_HEIGHT = 35
local WALL_THICKNESS = 4
local WALL_GRAY = Color3.fromRGB(140, 140, 145)
local mapHalfSize = MAP_SIZE / 2
local wallCenterY = GROUND_Y + WALL_HEIGHT / 2

local function createWall(name, size, cframe)
	local wall = Instance.new("Part")
	wall.Name = name
	wall.Anchored = true
	wall.Size = size
	wall.CFrame = cframe
	wall.Material = Enum.Material.Plastic
	wall.Color = WALL_GRAY
	wall.Parent = mapFolder

	for _, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back}) do
		local texture = Instance.new("Texture")
		texture.Name = "GridTexture"
		texture.Face = face
		texture.Texture = GRID_TEXTURE_ID
		texture.Color3 = WALL_GRAY
		texture.StudsPerTileU = TEXTURE_TILE_STUDS
		texture.StudsPerTileV = TEXTURE_TILE_STUDS
		texture.Parent = wall
	end

	return wall
end

-- Latimea coridorului de trecere prin portal -- strada + ambele trotuare,
-- ca jucatorul sa poata iesi mergand normal pe strada, nu doar printr-un gol
-- ingust. Calculata o singura data, folosita si de gol-ul din zid, si de
-- portalul decorativ (rama aurie), ca sa ramana perfect aliniate.
local corridorWidth = STREET_WIDTH + SIDEWALK_WIDTH * 2

-- Inaltimea reala pe unde poate trece jucatorul (cat rama aurie a
-- portalului) -- deasupra ei, zidul ramane plin (o "grinda" ca la o poarta
-- reala), nu gol pana sus.
local PORTAL_OPENING_HEIGHT = 28

-- Zid cu GOL real la mijloc (nu un singur bloc plin) -- doi stalpi laterali,
-- lasand liber coridorul strazii, ca jucatorul sa poata trece efectiv prin
-- portal, nu doar sa vada decorul lui. Deasupra golului ramane o grinda de
-- zid (nu e deschis pana in varf, ca o poarta reala).
local function createWallWithOpening(name, wallZ)
	local outerHalfWidth = MAP_SIZE / 2 + WALL_THICKNESS
	local openingHalfWidth = corridorWidth / 2
	local segmentWidth = outerHalfWidth - openingHalfWidth
	local segmentCenterX = openingHalfWidth + segmentWidth / 2

	createWall(
		name .. "Left",
		Vector3.new(segmentWidth, WALL_HEIGHT, WALL_THICKNESS),
		CFrame.new(-segmentCenterX, wallCenterY, wallZ)
	)

	createWall(
		name .. "Right",
		Vector3.new(segmentWidth, WALL_HEIGHT, WALL_THICKNESS),
		CFrame.new(segmentCenterX, wallCenterY, wallZ)
	)

	local headerHeight = WALL_HEIGHT - PORTAL_OPENING_HEIGHT
	local headerCenterY = GROUND_Y + PORTAL_OPENING_HEIGHT + headerHeight / 2

	createWall(
		name .. "Top",
		Vector3.new(corridorWidth, headerHeight, WALL_THICKNESS),
		CFrame.new(0, headerCenterY, wallZ)
	)
end

-- Peretii de Nord/Sud sunt putin mai lungi decat harta, ca sa acopere si
-- coltul unde s-ar intalni cu peretii de Est/Vest (fara gol la colturi).
-- WallNorth are gol real (portal deschis, extindere de harta) -- WallSouth
-- ramane plin (portalul de acolo e doar decor deocamdata).
createWallWithOpening("WallNorth", streetCenterZ + mapHalfSize)

createWall(
	"WallSouth",
	Vector3.new(MAP_SIZE + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS),
	CFrame.new(0, wallCenterY, streetCenterZ - mapHalfSize)
)

createWall(
	"WallEast",
	Vector3.new(WALL_THICKNESS, WALL_HEIGHT, MAP_SIZE),
	CFrame.new(mapHalfSize, wallCenterY, streetCenterZ)
)

createWall(
	"WallWest",
	Vector3.new(WALL_THICKNESS, WALL_HEIGHT, MAP_SIZE),
	CFrame.new(-mapHalfSize, wallCenterY, streetCenterZ)
)

-- Portal decorativ SUBTIRE (nu volum gros), montat direct pe fata zidului --
-- un panou negru plat + un contur Neon auriu in jur. La ambele capete ale
-- strazii acum (Nord si Sud). NPCManager foloseste specific "PortalNorth" ca
-- punct de plecare pentru NPC-uri -- cel de Sud e doar decor, deocamdata.
--
-- makePassable: cand e true (PortalNorth, zidul cu gol de mai sus), panoul
-- negru devine INVIZIBIL (nu sters -- NPCManager cauta piesa dupa nume ca sa-i
-- ia .Position ca punct de plecare) -- ramane doar rama aurie, ca un portal
-- deschis, prin care jucatorul chiar poate trece (zidul din spate are gol).
local function createPortal(name, wallZ, innerDirection, makePassable)
	local openingHeight = PORTAL_OPENING_HEIGHT
	local borderWidth = 4
	local decorDepth = 1

	-- Chiar in fata zidului (spre strada), nu suprapus peste el.
	-- innerDirection = -1 pentru Nord (strada e spre Z mai mic),
	-- +1 pentru Sud (strada e spre Z mai mare).
	local decorZ = wallZ + innerDirection * (WALL_THICKNESS / 2 + 0.6)
	local decorCenterY = GROUND_Y + openingHeight / 2

	-- Neon (nu SmoothPlastic) -- randeaza mereu ca negru "plat", neafectat de
	-- lumina scenei. MapMaterialManager converteste automat orice piesa
	-- SmoothPlastic din harta in Plastic, iar negrul in Plastic, sub lumina
	-- puternica de amiaza, iese gri-inchis, nu negru real -- se pierdea pe
	-- fondul zidului gri (asta parea sa fie cauza reala a "nu se vede").
	local panel = Instance.new("Part")
	panel.Name = name
	panel.Anchored = true
	panel.CanCollide = false
	panel.Size = Vector3.new(corridorWidth, openingHeight, decorDepth)
	panel.CFrame = CFrame.new(0, decorCenterY, decorZ)
	panel.Color = Color3.fromRGB(0, 0, 0)
	panel.Material = Enum.Material.Neon
	panel.Transparency = makePassable and 1 or 0
	panel.Parent = mapFolder

	-- Contur Neon auriu, stralucitor -- imposibil de ratat, chiar daca
	-- piatra texturata tot se pierde vizual de la distanta.
	local glowColor = Color3.fromRGB(255, 200, 60)

	local function glowStrip(stripName, size, cframe)
		local part = Instance.new("Part")
		part.Name = stripName
		part.Anchored = true
		part.CanCollide = false
		part.Size = size
		part.CFrame = cframe
		part.Color = glowColor
		part.Material = Enum.Material.Neon
		part.Parent = mapFolder
		return part
	end

	glowStrip(
		name .. "BorderLeft",
		Vector3.new(borderWidth, openingHeight + borderWidth, decorDepth + 0.4),
		CFrame.new(-corridorWidth / 2 - borderWidth / 2, decorCenterY, decorZ)
	)

	glowStrip(
		name .. "BorderRight",
		Vector3.new(borderWidth, openingHeight + borderWidth, decorDepth + 0.4),
		CFrame.new(corridorWidth / 2 + borderWidth / 2, decorCenterY, decorZ)
	)

	glowStrip(
		name .. "BorderTop",
		Vector3.new(corridorWidth + borderWidth * 2, borderWidth, decorDepth + 0.4),
		CFrame.new(0, GROUND_Y + openingHeight + borderWidth / 2, decorZ)
	)
end

createPortal("PortalNorth", streetCenterZ + mapHalfSize, -1, true)
createPortal("PortalSouth", streetCenterZ - mapHalfSize, 1, false)

-- Countdown pana la urmatorul eveniment de piata (Golden Hour sau Market
-- Crash), scris pe panoul negru inchis al tunelului de Sud. Foloseste
-- MarketManager.GetEventCountdown() DIRECT -- aceeasi functie, acelasi calcul
-- trimis si catre MarketGui (client) -- ca sa arate mereu EXACT acelasi
-- numar, nu doua calcule separate care se pot desincroniza.
local nextMarketEventPanel = mapFolder:FindFirstChild("PortalSouth")

if nextMarketEventPanel then
	local function formatCountdown(totalSeconds)
		local hours = math.floor(totalSeconds / 3600)
		local minutes = math.floor((totalSeconds % 3600) / 60)
		local seconds = totalSeconds % 60
		return string.format("%02dh %02dm %02ds", hours, minutes, seconds)
	end

	-- Cand NU e activ niciun eveniment, text generic (NU numeste tipul) --
	-- "NEXT MARKET SPECIAL EVENT IN:". Cand UNUL e activ chiar acum, spune
	-- exact care si cand se termina -- acelasi text/numar trimis si catre
	-- MarketGui (client), ca sa fie sincronizate perfect.
	local function getMarketEventText()
		local countdown = MarketManager.GetEventCountdown()
		local timeText = formatCountdown(countdown.SecondsLeft)

		if countdown.Active and countdown.Type == "GoldenHour" then
			return "GOLDEN HOUR\nACTIVE!\nENDS IN:\n" .. timeText
		elseif countdown.Active and countdown.Type == "MarketCrash" then
			return "MARKET CRASH\nACTIVE!\nENDS IN:\n" .. timeText
		end

		return "NEXT MARKET\nSPECIAL EVENT\nIN:\n" .. timeText
	end

	local function addMarketSurface(face)
		local surfaceGui = Instance.new("SurfaceGui")
		surfaceGui.Name = "NextMarketEventSurface" .. face.Name
		surfaceGui.Face = face
		surfaceGui.Adornee = nextMarketEventPanel
		surfaceGui.AlwaysOnTop = true
		surfaceGui.LightInfluence = 0
		surfaceGui.PixelsPerStud = 36
		surfaceGui.Parent = nextMarketEventPanel

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0.08, 0)
		padding.PaddingBottom = UDim.new(0.08, 0)
		padding.PaddingLeft = UDim.new(0.06, 0)
		padding.PaddingRight = UDim.new(0.06, 0)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(255, 220, 60)
		label.TextStrokeColor3 = Color3.fromRGB(20, 14, 8)
		label.TextStrokeTransparency = 0.1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextWrapped = true
		label.Parent = surfaceGui
		padding.Parent = label

		return label
	end

	local marketLabelFront = addMarketSurface(Enum.NormalId.Front)
	local marketLabelBack = addMarketSurface(Enum.NormalId.Back)

	task.spawn(function()
		while nextMarketEventPanel.Parent do
			local text = getMarketEventText()
			marketLabelFront.Text = text
			marketLabelBack.Text = text
			task.wait(1)
		end
	end)
end

-- ================= Extindere harta, dincolo de PortalNorth =================
-- Continuare directa a strazii/trotuarelor/ierbii, EXACT acelasi stil
-- (aceleasi texturi, culori, dimensiuni de piesa) -- doar mai departe spre
-- Nord, dupa poarta. WallNorth (poarta) ramane exact unde era, ca prag intre
-- orasul vechi si zona noua -- doar zidul de la capatul de departe se muta.
local EXTENSION_LENGTH = 200
local extensionCenterZ = streetCenterZ + mapHalfSize + EXTENSION_LENGTH / 2
local extensionFarZ = streetCenterZ + mapHalfSize + EXTENSION_LENGTH

createPart(
	"GrassExtension",
	Vector3.new(MAP_SIZE, 0.8, EXTENSION_LENGTH),
	CFrame.new(0, GROUND_Y - 0.5, extensionCenterZ),
	Color3.fromRGB(30, 200, 40)
)

createPart(
	"StreetExtension",
	Vector3.new(STREET_WIDTH, 1, EXTENSION_LENGTH),
	CFrame.new(0, GROUND_Y, extensionCenterZ),
	Color3.fromRGB(60, 60, 65)
)

-- Continuam linia galbena intrerupta de pe mijlocul strazii, fara pauza la
-- trecerea prin poarta -- acelasi ritm (DASH_LENGTH/DASH_GAP) ca pe strada
-- veche.
local extensionDashZ = streetCenterZ + mapHalfSize

while extensionDashZ < extensionFarZ do
	createPart(
		"Dash",
		Vector3.new(1.2, 1.1, DASH_LENGTH),
		CFrame.new(0, GROUND_Y, extensionDashZ + DASH_LENGTH / 2),
		Color3.fromRGB(255, 220, 60)
	)
	extensionDashZ += DASH_LENGTH + DASH_GAP
end

createPart(
	"SidewalkLeftExtension",
	Vector3.new(SIDEWALK_WIDTH, 1.2, EXTENSION_LENGTH),
	CFrame.new(-sidewalkOffsetX, GROUND_Y, extensionCenterZ),
	Color3.fromRGB(235, 235, 235)
)

createPart(
	"SidewalkRightExtension",
	Vector3.new(SIDEWALK_WIDTH, 1.2, EXTENSION_LENGTH),
	CFrame.new(sidewalkOffsetX, GROUND_Y, extensionCenterZ),
	Color3.fromRGB(235, 235, 235)
)

-- Pereti laterali (Est/Vest) pentru zona noua -- acelasi stil ca cei vechi --
-- altfel jucatorul ar putea iesi pe lateral din extindere, pe langa iarba.
createWall(
	"WallEastExtension",
	Vector3.new(WALL_THICKNESS, WALL_HEIGHT, EXTENSION_LENGTH),
	CFrame.new(mapHalfSize, wallCenterY, extensionCenterZ)
)

createWall(
	"WallWestExtension",
	Vector3.new(WALL_THICKNESS, WALL_HEIGHT, EXTENSION_LENGTH),
	CFrame.new(-mapHalfSize, wallCenterY, extensionCenterZ)
)

-- Zid plin (nu gol real) la capatul de departe al extinderii -- acelasi
-- tratament ca WallSouth/PortalSouth: doar decor (portal cu panoul negru
-- INCHIS + rama aurie), jucatorul NU poate trece pe acolo.
createWall(
	"WallFarNorth",
	Vector3.new(MAP_SIZE + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS),
	CFrame.new(0, wallCenterY, extensionFarZ)
)
createPortal("PortalFarNorth", extensionFarZ, -1, false)

-- Drum ingust suplimentar, langa Bank/Egg Shop -- de la pozitia de start data
-- de jucator, pana la a doua pozitie data (spre Est, langa Bank). Orientat
-- exact pe linia dintre cele doua puncte (nu neaparat perfect Est-Vest), ca
-- sa se lipeasca precis de amandoua capetele. Acelasi stil/textura (asfalt
-- gri, ca strada normala).
local SIDE_STREET_WIDTH = 8
local sideStreetStart = Vector3.new(24.624576568603516, GROUND_Y, 689.3706665039062)
local sideStreetEnd = Vector3.new(156.24317932128906, GROUND_Y, 687.2850341796875)
local sideStreetVector = sideStreetEnd - sideStreetStart
local sideStreetLength = sideStreetVector.Magnitude
local sideStreetCenter = sideStreetStart + sideStreetVector / 2

createPart(
	"SideStreetToFarWall",
	Vector3.new(SIDE_STREET_WIDTH, 1, sideStreetLength),
	CFrame.new(sideStreetCenter, sideStreetCenter + sideStreetVector),
	Color3.fromRGB(200, 40, 40)
)

-- Patrat rosu pe podea, care cuprinde toate cele 3 standuri de leaderboard
-- (Cash/Time Played/Robux Spent) si podiumurile lor -- doar decorativ,
-- marcheaza vizual "zona leaderboard-urilor". Calculat sa acopere generos
-- toate coordonatele lor (standuri + podiumuri), cu marja.
local LEADERBOARD_ZONE_CENTER_X = 176.175
local LEADERBOARD_ZONE_CENTER_Z = 687.705
local LEADERBOARD_ZONE_WIDTH = 48
local LEADERBOARD_ZONE_LENGTH = 38

createPart(
	"LeaderboardZoneMarker",
	Vector3.new(LEADERBOARD_ZONE_WIDTH, 1, LEADERBOARD_ZONE_LENGTH),
	CFrame.new(LEADERBOARD_ZONE_CENTER_X, GROUND_Y, LEADERBOARD_ZONE_CENTER_Z),
	Color3.fromRGB(200, 40, 40)
)

-- Countdown pana la urmatorul update, scris pe panoul negru inchis --
-- userul lanseaza de obicei update-urile sambata la ora 19:00. Recalculat
-- direct din ziua/ora curenta (nu memorat), ca sa functioneze corect
-- indiferent cand porneste serverul.
local nextUpdatePanel = mapFolder:FindFirstChild("PortalFarNorth")

if nextUpdatePanel then
	local UPDATE_HOUR = 19 -- 19:00 (7 seara)

	local function secondsUntilNextUpdate()
		local now = os.date("!*t")
		local secondsToday = now.hour * 3600 + now.min * 60 + now.sec
		local targetSecondsOfDay = UPDATE_HOUR * 3600

		-- wday: 1=Duminica ... 7=Sambata.
		local daysUntilSaturday = (7 - now.wday) % 7
		local secondsUntil = daysUntilSaturday * 86400 + (targetSecondsOfDay - secondsToday)

		if secondsUntil <= 0 then
			secondsUntil += 7 * 86400
		end

		return secondsUntil
	end

	local function formatCountdown(totalSeconds)
		local days = math.floor(totalSeconds / 86400)
		local hours = math.floor((totalSeconds % 86400) / 3600)
		local minutes = math.floor((totalSeconds % 3600) / 60)
		local seconds = totalSeconds % 60
		return string.format("%dz %02dh %02dm %02ds", days, hours, minutes, seconds)
	end

	-- SurfaceGui, nu BillboardGui -- textul se lipeste EXACT pe fata panoului
	-- negru (dimensiunea lui reala), nu plutește într-un cadru separat, mai
	-- mare, care iese in afara marginilor panoului. Pus pe ambele fete
	-- (Front/Back), ca sa se vada indiferent din ce parte se apropie jucatorul.
	local function addUpdateSurface(face)
		local surfaceGui = Instance.new("SurfaceGui")
		surfaceGui.Name = "NextUpdateSurface" .. face.Name
		surfaceGui.Face = face
		surfaceGui.Adornee = nextUpdatePanel
		surfaceGui.AlwaysOnTop = true
		surfaceGui.LightInfluence = 0
		surfaceGui.PixelsPerStud = 36
		surfaceGui.Parent = nextUpdatePanel

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0.08, 0)
		padding.PaddingBottom = UDim.new(0.08, 0)
		padding.PaddingLeft = UDim.new(0.06, 0)
		padding.PaddingRight = UDim.new(0.06, 0)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(255, 220, 60)
		label.TextStrokeColor3 = Color3.fromRGB(20, 14, 8)
		label.TextStrokeTransparency = 0.1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextWrapped = true
		label.Parent = surfaceGui
		padding.Parent = label

		return label
	end

	local labelFront = addUpdateSurface(Enum.NormalId.Front)
	local labelBack = addUpdateSurface(Enum.NormalId.Back)

	task.spawn(function()
		while nextUpdatePanel.Parent do
			local text = "NEXT UPDATE\nIN:\n" .. formatCountdown(secondsUntilNextUpdate())
			labelFront.Text = text
			labelBack.Text = text
			task.wait(1)
		end
	end)
end

-- Spawn point pe strada noua (coordonate date de jucator via
-- HumanoidRootPart.Position). Invizibila (Transparency=1) ca sa nu se vada
-- un patrat peste asfalt -- strada de dedesubt ramane vizibila normal,
-- SpawnLocation doar marcheaza unde apar jucatorii.
--
-- Nota: daca mai exista alt SpawnLocation in harta veche, Roblox alege la
-- intamplare intre toate cele active la fiecare respawn -- spune-mi daca vrei
-- sa fie singurul spawn si il dezactivez pe cel vechi (am nevoie sa stiu unde
-- e, nu am vizibilitate asupra hartii vechi).
local spawn = Instance.new("SpawnLocation")
spawn.Name = "TownMapSpawn"
spawn.Anchored = true
spawn.CanCollide = false
spawn.Neutral = true
spawn.Transparency = 1
spawn.Size = Vector3.new(6, 1, 6)
spawn.CFrame = CFrame.new(22.171461, GROUND_Y, 397.950958)
spawn.Parent = mapFolder

-- Stergem orice alt SpawnLocation din harta veche -- doar cel nou trebuie sa
-- functioneze. Doar dezactivarea (Enabled=false) tot lasa ocazional
-- jucatori sa aterizeze acolo (race condition la primul spawn, inainte ca
-- scriptul asta sa apuce sa ruleze) -- stergerea completa elimina orice sansa.
local disabledCount = 0

for _, instance in ipairs(Workspace:GetDescendants()) do
	if instance:IsA("SpawnLocation") and instance ~= spawn then
		print("TownMapBuilder: sterg SpawnLocation vechi -- " .. instance:GetFullName())
		instance:Destroy()
		disabledCount += 1
	end
end

if disabledCount > 0 then
	print("TownMapBuilder: " .. disabledCount .. " SpawnLocation vechi sterse.")
end

-- Teleportam manual fiecare jucator la noua pozitie -- garantat, indiferent
-- ce SpawnLocation ar alege Roblox altfel (rezolva si cazul in care
-- personajul apare inainte ca scriptul asta sa apuce sa dezactiveze
-- spawn-ul vechi la pornirea serverului).
local townSpawnCFrame = spawn.CFrame + Vector3.new(0, 3, 0)

local function teleportToTownSpawn(character)
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
	if humanoidRootPart then
		humanoidRootPart.CFrame = townSpawnCFrame
	end
end

-- Player.RespawnLocation ii spune direct lui Roblox unde sa puna jucatorul
-- la orice respawn viitor -- functioneaza indiferent ce alt SpawnLocation ar
-- mai exista si indiferent cat de repede se creeaza personajul (nu mai
-- depinde de ordinea de rulare a scripturilor la pornirea serverului).
local function assignTownSpawn(player)
	player.RespawnLocation = spawn
end

Players.PlayerAdded:Connect(function(player)
	assignTownSpawn(player)
	player.CharacterAdded:Connect(teleportToTownSpawn)
end)

for _, player in ipairs(Players:GetPlayers()) do
	assignTownSpawn(player)
	if player.Character then
		teleportToTownSpawn(player.Character)
	end
	player.CharacterAdded:Connect(teleportToTownSpawn)
end

-- ================= Decor: copaci si tufe =================
-- Copaci "bloxy" (blocuri, nu forme rotunde -- acelasi stil ca restul
-- hartii), mai mari decat prima varianta, cu marime/culoare usor variate per
-- copac (nu clone identice) -- plus tufe mici, imprastiate printre ei, ca
-- decor suplimentar. Evitam strada/trotuarele si toate standurile/cladirile
-- deja construite, printr-o lista de zone "interzise" (cercuri) + o fasie
-- pentru strada, si NU lasam decorurile sa se suprapuna intre ele.
local DECOR_GRID_TEXTURE_ID = "rbxassetid://6372755229"

local function addGridTextureToPart(part, color)
	local texture = Instance.new("Texture")
	texture.Name = "GridTexture"
	texture.Face = Enum.NormalId.Top
	texture.Texture = DECOR_GRID_TEXTURE_ID
	texture.Color3 = color
	texture.StudsPerTileU = 3
	texture.StudsPerTileV = 3
	texture.Parent = part
end

local function createTree(position, scale, hueShift)
	scale = scale or 1
	hueShift = hueShift or 0

	-- BUG gasit la testare: YOffset-urile foliajului includeau deja
	-- trunkHeight (care e la randul ei inmultita cu scale), si apoi erau
	-- inmultite CU scale INCA O DATA mai jos -- scalare dubla, care facea ca
	-- trunchiul sa para "plutind" sub coroana la copacii mai mari/mici decat
	-- scale=1. Acum totul se calculeaza dintr-un singur punct de referinta
	-- (varful trunchiului), cu un singur nivel de scalare.
	local groundY = position.Y
	local trunkHeight = 7.5 * scale

	-- Trunchiul e ingropat usor sub sol (0.4 studs) -- garanteaza ca nu
	-- ramane niciodata un gol vizibil intre baza lui si iarba.
	local trunk = Instance.new("Part")
	trunk.Name = "TreeTrunk"
	trunk.Anchored = true
	trunk.Size = Vector3.new(1.8 * scale, trunkHeight + 0.4, 1.8 * scale)
	trunk.Material = Enum.Material.Wood
	trunk.Color = Color3.fromRGB(92, 64, 40)
	trunk.Position = Vector3.new(position.X, groundY - 0.4 + (trunkHeight + 0.4) / 2, position.Z)
	trunk.Parent = mapFolder
	addGridTextureToPart(trunk, trunk.Color)

	-- Verde usor diferit per copac (hueShift), ca sa nu arate ca niste
	-- clone perfecte -- variatie organica, discreta.
	local foliageColor = Color3.fromRGB(
		math.clamp(38 + hueShift, 25, 70),
		math.clamp(148 + hueShift, 120, 175),
		math.clamp(58 + hueShift, 40, 85)
	)

	local trunkTopY = groundY + trunkHeight
	local foliageLayers = {
		{Size = Vector3.new(8, 4.4, 8), Gap = -1.0},
		{Size = Vector3.new(5.8, 3.8, 5.8), Gap = 1.8},
		{Size = Vector3.new(3.6, 3, 3.6), Gap = 4.2}
	}

	for i, layer in ipairs(foliageLayers) do
		local foliage = Instance.new("Part")
		foliage.Name = "TreeFoliage" .. i
		foliage.Anchored = true
		foliage.Size = layer.Size * scale
		foliage.Material = Enum.Material.Grass
		foliage.Color = foliageColor
		foliage.Position = Vector3.new(position.X, trunkTopY + layer.Gap * scale, position.Z)
		foliage.Parent = mapFolder
		addGridTextureToPart(foliage, foliageColor)
	end
end

local function createBush(position, scale, hueShift)
	scale = scale or 1
	hueShift = hueShift or 0

	local bushColor = Color3.fromRGB(
		math.clamp(45 + hueShift, 30, 75),
		math.clamp(130 + hueShift, 100, 160),
		math.clamp(55 + hueShift, 35, 80)
	)

	-- Primul strat ingropat usor sub sol (0.4 studs), acelasi motiv ca la
	-- trunchiul copacilor -- fara gol vizibil dedesubt.
	local layers = {
		{Size = Vector3.new(3.2, 2.2, 3.2), YOffset = 0.7},
		{Size = Vector3.new(2.1, 1.4, 2.1), YOffset = 1.9}
	}

	for i, layer in ipairs(layers) do
		local bush = Instance.new("Part")
		bush.Name = "Bush" .. i
		bush.Anchored = true
		bush.Size = layer.Size * scale
		bush.Material = Enum.Material.Grass
		bush.Color = bushColor
		bush.Position = Vector3.new(position.X, position.Y + layer.YOffset * scale, position.Z)
		bush.Parent = mapFolder
		addGridTextureToPart(bush, bushColor)
	end
end

-- Zone interzise (cercuri) -- standuri/cladiri deja construite in extindere.
local TREE_KEEPOUT_CIRCLES = {
	{X = 36.57196807861328, Z = 649.1923828125, Radius = 18}, -- Egg Shop
	{X = -36.116424560546875, Z = 683.343505859375, Radius = 18}, -- Token Shop
	{X = 45.847381591796875, Z = 737.329345703125, Radius = 24}, -- Bank
	{X = 104.87107849121094, Z = 676.2765502929688, Radius = 12}, -- Index
	{X = 176.175, Z = 687.705, Radius = 32} -- Zona leaderboard-urilor
}

local TREE_CORRIDOR_HALF_WIDTH = 26 -- strada + trotuare, in extindere
local DECOR_MIN_Z = streetCenterZ + mapHalfSize + 6
local DECOR_MAX_Z = extensionFarZ - 12
local DECOR_MAX_X = mapHalfSize - 6

local function isInsideTreeKeepout(x, z)
	if math.abs(x) < TREE_CORRIDOR_HALF_WIDTH then
		return true
	end

	-- Drumul rosu diagonal (SideStreetToFarWall), bounding box generos.
	if x > 15 and x < 165 and z > 680 and z < 696 then
		return true
	end

	for _, circle in ipairs(TREE_KEEPOUT_CIRCLES) do
		local dx = x - circle.X
		local dz = z - circle.Z
		if (dx * dx + dz * dz) <= circle.Radius * circle.Radius then
			return true
		end
	end

	return false
end

-- Seed fix -- decorurile raman in ACELASI loc la fiecare repornire a
-- serverului, nu se reamesteca aleator de fiecare data.
local decorRandom = Random.new(12345)
local placedDecor = {} -- {X=, Z=, Radius=} -- ca sa nu se suprapuna intre ele

local function tryPlaceDecor(minSpacing)
	local x = decorRandom:NextNumber(-DECOR_MAX_X, DECOR_MAX_X)
	local z = decorRandom:NextNumber(DECOR_MIN_Z, DECOR_MAX_Z)

	if isInsideTreeKeepout(x, z) then
		return nil
	end

	for _, other in ipairs(placedDecor) do
		local dx = x - other.X
		local dz = z - other.Z
		local minDist = minSpacing + other.Radius
		if (dx * dx + dz * dz) < (minDist * minDist) then
			return nil
		end
	end

	return x, z
end

local TREE_COUNT = 22
local BUSH_COUNT = 14
local treesPlaced = 0
local attempts = 0

while treesPlaced < TREE_COUNT and attempts < TREE_COUNT * 25 do
	attempts += 1

	local x, z = tryPlaceDecor(5.5)
	if x then
		local scale = decorRandom:NextNumber(0.9, 1.5)
		local hueShift = decorRandom:NextInteger(-14, 14)
		createTree(Vector3.new(x, GROUND_Y, z), scale, hueShift)
		table.insert(placedDecor, {X = x, Z = z, Radius = 4.5 * scale})
		treesPlaced += 1
	end
end

local bushesPlaced = 0
attempts = 0

while bushesPlaced < BUSH_COUNT and attempts < BUSH_COUNT * 25 do
	attempts += 1

	local x, z = tryPlaceDecor(2.2)
	if x then
		local scale = decorRandom:NextNumber(0.8, 1.3)
		local hueShift = decorRandom:NextInteger(-12, 12)
		createBush(Vector3.new(x, GROUND_Y, z), scale, hueShift)
		table.insert(placedDecor, {X = x, Z = z, Radius = 1.8 * scale})
		bushesPlaced += 1
	end
end

-- ================= Decor: copaci si tufe (harta principala) =================
-- Acelasi tratament, dar pe harta veche (cea cu cele 6 standuri FIXE ale
-- jucatorilor -- vezi StandManager.server.luau: X=+-45, Z in {331.155,
-- 421.155, 511.155}). Egg Shop/Token Shop/Bank NU mai sunt aici -- au fost
-- mutate in extindere mai devreme in sesiunea asta, deci harta veche e
-- libera in afara de strada si cele 6 standuri.
local MAIN_MAP_STAND_KEEPOUTS = {
	{X = 45, Z = 331.155, Radius = 20},
	{X = -45, Z = 331.155, Radius = 20},
	{X = -45, Z = 421.155, Radius = 20},
	{X = 45, Z = 421.155, Radius = 20},
	{X = -45, Z = 511.155, Radius = 20},
	{X = 45, Z = 511.155, Radius = 20},
	{X = 22.171461, Z = 397.950958, Radius = 10}, -- punctul de spawn
	{X = 33.349586486816406, Z = 383.71649169921875, Radius = 6} -- copac scos, la cererea jucatorului
}

local MAIN_MAP_CORRIDOR_HALF_WIDTH = 26
local MAIN_MAP_MIN_Z = STREET_START_Z + 6
local MAIN_MAP_MAX_Z = streetCenterZ + mapHalfSize - 6
local MAIN_MAP_MAX_X = mapHalfSize - 6

local function isInsideMainMapKeepout(x, z)
	if math.abs(x) < MAIN_MAP_CORRIDOR_HALF_WIDTH then
		return true
	end

	for _, circle in ipairs(MAIN_MAP_STAND_KEEPOUTS) do
		local dx = x - circle.X
		local dz = z - circle.Z
		if (dx * dx + dz * dz) <= circle.Radius * circle.Radius then
			return true
		end
	end

	return false
end

local function tryPlaceMainMapDecor(minSpacing)
	local x = decorRandom:NextNumber(-MAIN_MAP_MAX_X, MAIN_MAP_MAX_X)
	local z = decorRandom:NextNumber(MAIN_MAP_MIN_Z, MAIN_MAP_MAX_Z)

	if isInsideMainMapKeepout(x, z) then
		return nil
	end

	for _, other in ipairs(placedDecor) do
		local dx = x - other.X
		local dz = z - other.Z
		local minDist = minSpacing + other.Radius
		if (dx * dx + dz * dz) < (minDist * minDist) then
			return nil
		end
	end

	return x, z
end

local MAIN_MAP_TREE_COUNT = 26
local MAIN_MAP_BUSH_COUNT = 16
local mainTreesPlaced = 0
attempts = 0

while mainTreesPlaced < MAIN_MAP_TREE_COUNT and attempts < MAIN_MAP_TREE_COUNT * 25 do
	attempts += 1

	local x, z = tryPlaceMainMapDecor(5.5)
	if x then
		local scale = decorRandom:NextNumber(0.9, 1.5)
		local hueShift = decorRandom:NextInteger(-14, 14)
		createTree(Vector3.new(x, GROUND_Y, z), scale, hueShift)
		table.insert(placedDecor, {X = x, Z = z, Radius = 4.5 * scale})
		mainTreesPlaced += 1
	end
end

local mainBushesPlaced = 0
attempts = 0

while mainBushesPlaced < MAIN_MAP_BUSH_COUNT and attempts < MAIN_MAP_BUSH_COUNT * 25 do
	attempts += 1

	local x, z = tryPlaceMainMapDecor(2.2)
	if x then
		local scale = decorRandom:NextNumber(0.8, 1.3)
		local hueShift = decorRandom:NextInteger(-12, 12)
		createBush(Vector3.new(x, GROUND_Y, z), scale, hueShift)
		table.insert(placedDecor, {X = x, Z = z, Radius = 1.8 * scale})
		mainBushesPlaced += 1
	end
end

-- Grup suplimentar de copaci/tufe, cerut manual de jucator intr-o zona
-- anume -- imprastiate RANDOM intr-un cerc in jurul punctului dat (nu toate
-- lipite exact la coordonata), cu aceeasi verificare de spatiere ca restul
-- decorurilor (nu se suprapun intre ele si nici cu ce era deja pus).
local EXTRA_ZONE_CENTER_X = -124.76773071289062
local EXTRA_ZONE_CENTER_Z = 329.99029541015625
local EXTRA_ZONE_RADIUS = 75

local function tryPlaceInExtraZone(minSpacing)
	local angle = decorRandom:NextNumber(0, math.pi * 2)
	-- sqrt() -- ca sa fie DISTRIBUIT UNIFORM pe suprafata cercului, nu
	-- aglomerat spre centru (o distanta aleasa liniar favorizeaza centrul,
	-- pentru ca acolo "aria" per unitate de distanta e mai mica -- exact
	-- bug-ul care facea copacii sa iasa toti gramada intr-un colt).
	local dist = math.sqrt(decorRandom:NextNumber(0, 1)) * EXTRA_ZONE_RADIUS
	local x = EXTRA_ZONE_CENTER_X + math.cos(angle) * dist
	local z = EXTRA_ZONE_CENTER_Z + math.sin(angle) * dist

	if isInsideMainMapKeepout(x, z) then
		return nil
	end

	for _, other in ipairs(placedDecor) do
		local dx = x - other.X
		local dz = z - other.Z
		local minDist = minSpacing + other.Radius
		if (dx * dx + dz * dz) < (minDist * minDist) then
			return nil
		end
	end

	return x, z
end

local EXTRA_TREE_COUNT = 12
local EXTRA_BUSH_COUNT = 8
local extraTreesPlaced = 0
attempts = 0

while extraTreesPlaced < EXTRA_TREE_COUNT and attempts < EXTRA_TREE_COUNT * 25 do
	attempts += 1

	local x, z = tryPlaceInExtraZone(5.5)
	if x then
		local scale = decorRandom:NextNumber(0.9, 1.4)
		local hueShift = decorRandom:NextInteger(-12, 12)
		createTree(Vector3.new(x, GROUND_Y, z), scale, hueShift)
		table.insert(placedDecor, {X = x, Z = z, Radius = 4.5 * scale})
		extraTreesPlaced += 1
	end
end

local extraBushesPlaced = 0
attempts = 0

while extraBushesPlaced < EXTRA_BUSH_COUNT and attempts < EXTRA_BUSH_COUNT * 25 do
	attempts += 1

	local x, z = tryPlaceInExtraZone(2.2)
	if x then
		local scale = decorRandom:NextNumber(0.8, 1.2)
		local hueShift = decorRandom:NextInteger(-10, 10)
		createBush(Vector3.new(x, GROUND_Y, z), scale, hueShift)
		table.insert(placedDecor, {X = x, Z = z, Radius = 1.8 * scale})
		extraBushesPlaced += 1
	end
end

-- ================= Zone de viteza =================
-- Mai multe zone, fiecare cu boost-ul ei -- trotuarul ALB din stanga da
-- viteza mare (dublu), drumul ROSU (SideStreetToFarWall, langa Bank/Egg
-- Shop) da doar "oleaca" viteza (mai putin decat trotuarul). Revine automat
-- la viteza normala cand jucatorul pleaca de pe orice zona.
local SPEED_ZONES = {
	{Names = {"SidewalkLeft", "SidewalkLeftExtension"}, BoostSpeed = 32},
	{Names = {"SideStreetToFarWall"}, BoostSpeed = 22}
}
local NORMAL_WALK_SPEED = 16
local SPEED_ZONE_CHECK_INTERVAL = 0.25

local resolvedSpeedZones = {}
for _, zone in ipairs(SPEED_ZONES) do
	local parts = {}
	for _, name in ipairs(zone.Names) do
		local part = mapFolder:FindFirstChild(name)
		if part then
			table.insert(parts, part)
		end
	end
	if #parts > 0 then
		table.insert(resolvedSpeedZones, {Parts = parts, BoostSpeed = zone.BoostSpeed})
	end
end

if #resolvedSpeedZones > 0 then
	local playerSpeedState = {}
	local speedZoneTimer = 0

	local function isPointOnPart(point, part)
		local relative = part.CFrame:PointToObjectSpace(point)
		return math.abs(relative.X) <= part.Size.X / 2 and math.abs(relative.Z) <= part.Size.Z / 2
	end

	RunService.Heartbeat:Connect(function(dt)
		speedZoneTimer += dt
		if speedZoneTimer < SPEED_ZONE_CHECK_INTERVAL then
			return
		end
		speedZoneTimer = 0

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")

			if rootPart and humanoid then
				-- Daca e in mai multe zone deodata (suprapunere), castiga
				-- cea cu boost-ul mai mare.
				local bestBoost = nil

				for _, zone in ipairs(resolvedSpeedZones) do
					for _, part in ipairs(zone.Parts) do
						if isPointOnPart(rootPart.Position, part) then
							if not bestBoost or zone.BoostSpeed > bestBoost then
								bestBoost = zone.BoostSpeed
							end
							break
						end
					end
				end

				local targetSpeed = bestBoost or NORMAL_WALK_SPEED

				if playerSpeedState[player] ~= targetSpeed then
					playerSpeedState[player] = targetSpeed
					humanoid.WalkSpeed = targetSpeed
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		playerSpeedState[player] = nil
	end)
end

print("TownMapBuilder: harta noua construita in Workspace.TownMap (strada + trotuare + iarba, "
	.. STREET_LENGTH .. " studs lungime).")
