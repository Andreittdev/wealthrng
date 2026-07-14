local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

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

-- Peretii de Nord/Sud sunt putin mai lungi decat harta, ca sa acopere si
-- coltul unde s-ar intalni cu peretii de Est/Vest (fara gol la colturi).
createWall(
	"WallNorth",
	Vector3.new(MAP_SIZE + WALL_THICKNESS * 2, WALL_HEIGHT, WALL_THICKNESS),
	CFrame.new(0, wallCenterY, streetCenterZ + mapHalfSize)
)

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
local function createPortal(name, wallZ, innerDirection)
	local corridorWidth = STREET_WIDTH + SIDEWALK_WIDTH * 2
	local openingHeight = 28
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

createPortal("PortalNorth", streetCenterZ + mapHalfSize, -1)
createPortal("PortalSouth", streetCenterZ - mapHalfSize, 1)

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

print("TownMapBuilder: harta noua construita in Workspace.TownMap (strada + trotuare + iarba, "
	.. STREET_LENGTH .. " studs lungime).")
