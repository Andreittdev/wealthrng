-- Hub map generator, wired into Main.server.luau so it runs automatically on
-- every server start -- no manual command needed. Workspace isn't synced by
-- Rojo (only ReplicatedStorage/ServerScriptService/StarterPlayerScripts are,
-- per default.project.json), so this is the only way the map's Parts get
-- created at all.
--
-- MapBuilder.BuildIfMissing() (what Main.server.luau calls) only builds when
-- Workspace.Map doesn't exist yet -- so the *first* server start creates it,
-- and any hand-tuning done afterward in Studio survives future restarts.
-- MapBuilder.Build() (unconditional, always clears + rebuilds) is still
-- available for a deliberate full reset -- call it manually from the Command
-- Bar (`require(game.ServerScriptService.MapBuilder).Build()`) when you
-- actually want to throw away manual edits and start over.

local Workspace = game:GetService("Workspace")

local MapBuilder = {}

-- Chunky/toy proportions throughout (thick slabs, stubby trees, bulky
-- stands) is the point of the "Bloxy" simulator look -- thin, realistic
-- proportions read as generic greybox, not stylized.

local GROUND_SIZE = 300
local GROUND_THICKNESS = 4
local GRASS_TILE_SIZE = 15
local GRASS_TILE_COLOR_A = Color3.fromRGB(72, 201, 60)
local GRASS_TILE_COLOR_B = Color3.fromRGB(56, 176, 46)

local PLAZA_DIAMETER = 100
local PLAZA_HEIGHT = 3
local RIM_DIAMETER = 110
local RIM_HEIGHT = 2
local ACCENT_COUNT = 18
local ACCENT_RADIUS = 52
local ACCENT_SIZE = 2

local PATH_WIDTH = 16
local PATH_LENGTH = 100
local PATH_HEIGHT = 2

-- Smaller footprint than a flat pool, but taller/more detailed: two tiered
-- basins on a gold stem, capped with a glowing gem -- reads as a premium
-- centerpiece instead of a big flat puddle.
local FOUNTAIN_GOLD = Color3.fromRGB(212, 175, 55)
local FOUNTAIN_WATER_COLOR = Color3.fromRGB(120, 200, 255)

local FOUNTAIN_BASE_DIAMETER = 16
local FOUNTAIN_BASE_HEIGHT = 1.5
local FOUNTAIN_BASE_WATER_DIAMETER = 14
local FOUNTAIN_BASE_WATER_HEIGHT = 0.4

local FOUNTAIN_STEM1_DIAMETER = 2
local FOUNTAIN_STEM1_HEIGHT = 3

local FOUNTAIN_TOP_DIAMETER = 8
local FOUNTAIN_TOP_HEIGHT = 1
local FOUNTAIN_TOP_WATER_DIAMETER = 6.5
local FOUNTAIN_TOP_WATER_HEIGHT = 0.3

local FOUNTAIN_STEM2_DIAMETER = 1
local FOUNTAIN_STEM2_HEIGHT = 1.8
local FOUNTAIN_GEM_DIAMETER = 2.5

local STAND_RADIUS = 38
local STAND_ANGLES = { 200, 340 }
local STAND_ROOF_COLORS = { Color3.fromRGB(225, 45, 45), Color3.fromRGB(60, 130, 220) }
local STAND_LABELS = { "SHOP", "SHOP" }

local LEADERBOARD_RADIUS = 42
local LEADERBOARD_ANGLES = { 75, 90, 105 }
local LEADERBOARD_LABELS = { "TOP CASH", "TOP NET WORTH", "TOP ROLLS" }

local TREE_COUNT = 45
local TREE_EXCLUSION_RADIUS = 57
local GRASS_PLACEMENT_BOUND = 130
local TREE_PLACEMENT_ATTEMPTS = 20

local random = Random.new()

-- Vertical cylinder (axis along world Y): `height` runs vertically,
-- `diameter` is the circular cross-section. Reused for the plaza floor,
-- its rim, the fountain, and tree trunks -- only the aspect ratio differs.
local function createCylinder(name: string, diameter: number, height: number, centerPosition: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(height, diameter, diameter)
	part.CFrame = CFrame.new(centerPosition) * CFrame.Angles(0, 0, math.rad(90))
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function createBlock(name: string, size: Vector3, centerPosition: Vector3, color: Color3, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(centerPosition)
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function addLabel(adornee: BasePart, text: string, studsUp: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.new(0, 140, 0, 36)
	billboard.StudsOffset = Vector3.new(0, studsUp, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = adornee
	billboard.Parent = adornee

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, 0, 1, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.TextStrokeTransparency = 0
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextScaled = true
	textLabel.Text = text
	textLabel.Parent = billboard
end

local function polarToXZ(radius: number, angleDegrees: number): (number, number)
	local angleRadians = math.rad(angleDegrees)
	return radius * math.cos(angleRadians), radius * math.sin(angleRadians)
end

local PLAZA_TOP_Y = PLAZA_HEIGHT / 2

-- Built as a checkerboard grid of square tiles (not one big slab) so the
-- grass visibly reads as squares, like the reference image, instead of a
-- single flat plane.
local function buildGround(mapFolder: Folder)
	local groundFolder = Instance.new("Folder")
	groundFolder.Name = "Ground"
	groundFolder.Parent = mapFolder

	local tileCount = math.floor(GROUND_SIZE / GRASS_TILE_SIZE)
	local halfSpan = (tileCount * GRASS_TILE_SIZE) / 2

	for row = 0, tileCount - 1 do
		for col = 0, tileCount - 1 do
			local x = -halfSpan + GRASS_TILE_SIZE * col + GRASS_TILE_SIZE / 2
			local z = -halfSpan + GRASS_TILE_SIZE * row + GRASS_TILE_SIZE / 2
			local isEven = (row + col) % 2 == 0

			local tile = createBlock(
				"GrassTile",
				Vector3.new(GRASS_TILE_SIZE, GROUND_THICKNESS, GRASS_TILE_SIZE),
				Vector3.new(x, -GROUND_THICKNESS / 2, z),
				isEven and GRASS_TILE_COLOR_A or GRASS_TILE_COLOR_B,
				Enum.Material.Grass
			)
			tile.Parent = groundFolder
		end
	end
end

local function buildPlaza(mapFolder: Folder)
	local rim = createCylinder(
		"PlazaRim",
		RIM_DIAMETER,
		RIM_HEIGHT,
		Vector3.new(0, 0, 0),
		Color3.fromRGB(100, 215, 90),
		Enum.Material.Grass
	)
	rim.Parent = mapFolder

	local floor = createCylinder(
		"PlazaFloor",
		PLAZA_DIAMETER,
		PLAZA_HEIGHT,
		Vector3.new(0, 0, 0),
		Color3.fromRGB(175, 175, 185),
		Enum.Material.Cobblestone
	)
	floor.Parent = mapFolder

	local rimTopY = RIM_HEIGHT / 2
	for i = 1, ACCENT_COUNT do
		local angle = (360 / ACCENT_COUNT) * i
		local x, z = polarToXZ(ACCENT_RADIUS, angle)
		local accent = createBlock(
			"RimAccent",
			Vector3.new(ACCENT_SIZE, ACCENT_SIZE, ACCENT_SIZE),
			Vector3.new(x, rimTopY + ACCENT_SIZE / 2, z),
			Color3.fromRGB(235, 40, 55)
		)
		accent.Parent = mapFolder
	end
end

local function buildPaths(mapFolder: Folder)
	local offset = PLAZA_DIAMETER / 2 + PATH_LENGTH / 2
	local centerY = PLAZA_HEIGHT / 2 - PATH_HEIGHT / 2 -- flush with the plaza's top surface

	local directions = {
		{ name = "PathEast", position = Vector3.new(offset, centerY, 0), size = Vector3.new(PATH_LENGTH, PATH_HEIGHT, PATH_WIDTH) },
		{ name = "PathWest", position = Vector3.new(-offset, centerY, 0), size = Vector3.new(PATH_LENGTH, PATH_HEIGHT, PATH_WIDTH) },
		{ name = "PathNorth", position = Vector3.new(0, centerY, offset), size = Vector3.new(PATH_WIDTH, PATH_HEIGHT, PATH_LENGTH) },
		{ name = "PathSouth", position = Vector3.new(0, centerY, -offset), size = Vector3.new(PATH_WIDTH, PATH_HEIGHT, PATH_LENGTH) },
	}

	for _, data in directions do
		local path = createBlock(data.name, data.size, data.position, Color3.fromRGB(175, 175, 185), Enum.Material.Cobblestone)
		path.Parent = mapFolder
	end
end

local function buildFountain(mapFolder: Folder)
	-- Base basin, gold-rimmed (base tier is wider than its water, so the
	-- gold peeks out as a rim -- same trick as the plaza's rim accents).
	local baseCenterY = PLAZA_TOP_Y + FOUNTAIN_BASE_HEIGHT / 2
	local base = createCylinder("FountainBase", FOUNTAIN_BASE_DIAMETER, FOUNTAIN_BASE_HEIGHT, Vector3.new(0, baseCenterY, 0), FOUNTAIN_GOLD, Enum.Material.Metal)
	base.Parent = mapFolder

	local baseTopY = baseCenterY + FOUNTAIN_BASE_HEIGHT / 2
	local baseWater = createCylinder(
		"FountainBaseWater",
		FOUNTAIN_BASE_WATER_DIAMETER,
		FOUNTAIN_BASE_WATER_HEIGHT,
		Vector3.new(0, baseTopY + FOUNTAIN_BASE_WATER_HEIGHT / 2 - 0.1, 0),
		FOUNTAIN_WATER_COLOR,
		Enum.Material.Glass
	)
	baseWater.Transparency = 0.3
	baseWater.Parent = mapFolder

	-- Gold stem up to the smaller top basin
	local stem1CenterY = baseTopY + FOUNTAIN_STEM1_HEIGHT / 2
	local stem1 = createCylinder("FountainStem1", FOUNTAIN_STEM1_DIAMETER, FOUNTAIN_STEM1_HEIGHT, Vector3.new(0, stem1CenterY, 0), FOUNTAIN_GOLD, Enum.Material.Metal)
	stem1.Parent = mapFolder

	local stem1TopY = stem1CenterY + FOUNTAIN_STEM1_HEIGHT / 2
	local topBasinCenterY = stem1TopY + FOUNTAIN_TOP_HEIGHT / 2
	local topBasin = createCylinder("FountainTopBasin", FOUNTAIN_TOP_DIAMETER, FOUNTAIN_TOP_HEIGHT, Vector3.new(0, topBasinCenterY, 0), FOUNTAIN_GOLD, Enum.Material.Metal)
	topBasin.Parent = mapFolder

	local topBasinTopY = topBasinCenterY + FOUNTAIN_TOP_HEIGHT / 2
	local topWater = createCylinder(
		"FountainTopWater",
		FOUNTAIN_TOP_WATER_DIAMETER,
		FOUNTAIN_TOP_WATER_HEIGHT,
		Vector3.new(0, topBasinTopY + FOUNTAIN_TOP_WATER_HEIGHT / 2 - 0.08, 0),
		FOUNTAIN_WATER_COLOR,
		Enum.Material.Glass
	)
	topWater.Transparency = 0.3
	topWater.Parent = mapFolder

	-- Thin gold spire capped with a glowing gem -- the "premium" crown piece
	local stem2CenterY = topBasinTopY + FOUNTAIN_STEM2_HEIGHT / 2
	local stem2 = createCylinder("FountainStem2", FOUNTAIN_STEM2_DIAMETER, FOUNTAIN_STEM2_HEIGHT, Vector3.new(0, stem2CenterY, 0), FOUNTAIN_GOLD, Enum.Material.Metal)
	stem2.Parent = mapFolder

	local stem2TopY = stem2CenterY + FOUNTAIN_STEM2_HEIGHT / 2
	local gem = Instance.new("Part")
	gem.Name = "FountainGem"
	gem.Shape = Enum.PartType.Ball
	gem.Size = Vector3.new(FOUNTAIN_GEM_DIAMETER, FOUNTAIN_GEM_DIAMETER, FOUNTAIN_GEM_DIAMETER)
	gem.CFrame = CFrame.new(0, stem2TopY + FOUNTAIN_GEM_DIAMETER / 2, 0)
	gem.Color = Color3.fromRGB(255, 221, 120)
	gem.Material = Enum.Material.Neon
	gem.Anchored = true
	gem.Parent = mapFolder
end

local STAND_WIDTH = 7
local STAND_DEPTH = 7
local STAND_WALL_HEIGHT = 6

-- A proper small kiosk instead of a floating table+slab: 4 corner pillars,
-- walls on 3 sides (front stays open over the counter, facing the plaza
-- center), a stepped/tiered "pagoda" roof, and a sign board over the
-- entrance -- reads as an actual shop, not a placeholder table.
local function buildStand(mapFolder: Folder, angleDegrees: number, index: number, roofColor: Color3, labelText: string)
	local x, z = polarToXZ(STAND_RADIUS, angleDegrees)
	local standCF = CFrame.lookAt(Vector3.new(x, PLAZA_TOP_Y, z), Vector3.new(0, PLAZA_TOP_Y, 0))

	local halfWidth = STAND_WIDTH / 2
	local halfDepth = STAND_DEPTH / 2

	local function place(name: string, size: Vector3, localOffset: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
		local part = Instance.new("Part")
		part.Name = "Stand" .. index .. "_" .. name
		part.Size = size
		part.CFrame = standCF * CFrame.new(localOffset)
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		if shape then
			part.Shape = shape
		end
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = mapFolder
		return part
	end

	-- Floor (local Y 0 to 1)
	place("Floor", Vector3.new(STAND_WIDTH + 1, 1, STAND_DEPTH + 1), Vector3.new(0, 0.5, 0), Color3.fromRGB(150, 110, 70), Enum.Material.WoodPlanks)

	-- 4 corner pillars (local Y 1 to 1+WALL_HEIGHT), -Z side is the front (faces plaza center, per CFrame.lookAt)
	local pillarCenterY = 1 + STAND_WALL_HEIGHT / 2
	local pillarPositions = {
		Vector3.new(-halfWidth, pillarCenterY, -halfDepth),
		Vector3.new(halfWidth, pillarCenterY, -halfDepth),
		Vector3.new(-halfWidth, pillarCenterY, halfDepth),
		Vector3.new(halfWidth, pillarCenterY, halfDepth),
	}
	for _, localPos in pillarPositions do
		place("Pillar", Vector3.new(1.2, STAND_WALL_HEIGHT, 1.2), localPos, Color3.fromRGB(120, 85, 60), Enum.Material.Wood)
	end

	-- Back + side walls; front (-Z) stays open above the counter
	place("BackWall", Vector3.new(STAND_WIDTH, STAND_WALL_HEIGHT, 0.8), Vector3.new(0, pillarCenterY, halfDepth), Color3.fromRGB(235, 225, 210), Enum.Material.WoodPlanks)
	place("LeftWall", Vector3.new(0.8, STAND_WALL_HEIGHT, STAND_DEPTH), Vector3.new(-halfWidth, pillarCenterY, 0), Color3.fromRGB(235, 225, 210), Enum.Material.WoodPlanks)
	place("RightWall", Vector3.new(0.8, STAND_WALL_HEIGHT, STAND_DEPTH), Vector3.new(halfWidth, pillarCenterY, 0), Color3.fromRGB(235, 225, 210), Enum.Material.WoodPlanks)

	-- Counter across the open front
	place("Counter", Vector3.new(STAND_WIDTH - 1, 3, 1.5), Vector3.new(0, 1 + 1.5, -halfDepth + 0.75), Color3.fromRGB(210, 190, 150), Enum.Material.WoodPlanks)

	-- Sign board over the entrance
	local sign = place("Sign", Vector3.new(STAND_WIDTH - 1, 1.4, 0.4), Vector3.new(0, 1 + STAND_WALL_HEIGHT + 0.7, -halfDepth + 0.2), roofColor, Enum.Material.Fabric)
	addLabel(sign, labelText, 0)

	-- Stepped "pagoda" roof, each tier flush on the one below, tapering up
	local roofBaseY = 1 + STAND_WALL_HEIGHT
	place("RoofTier1", Vector3.new(STAND_WIDTH + 2, 1, STAND_DEPTH + 2), Vector3.new(0, roofBaseY + 0.5, 0), roofColor, Enum.Material.Fabric)
	place("RoofTier2", Vector3.new(STAND_WIDTH - 1, 1, STAND_DEPTH - 1), Vector3.new(0, roofBaseY + 1.5, 0), roofColor, Enum.Material.Fabric)
	place("RoofTier3", Vector3.new(STAND_WIDTH - 4, 1, STAND_DEPTH - 4), Vector3.new(0, roofBaseY + 2.5, 0), roofColor, Enum.Material.Fabric)
	place("Finial", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, roofBaseY + 3.6, 0), Color3.fromRGB(255, 215, 90), Enum.Material.Neon, Enum.PartType.Ball)
end

local LEADERBOARD_WIDTH = 5
local LEADERBOARD_HEIGHT = 6
local LEADERBOARD_DEPTH = 0.6
local LEADERBOARD_POLE_HEIGHT = 2
local LEADERBOARD_HEADER_HEIGHT = 1
local LEADERBOARD_HEADER_COLORS = { Color3.fromRGB(60, 190, 100), Color3.fromRGB(85, 140, 235), Color3.fromRGB(200, 90, 220) }

-- Plain scoreboard, like a standard simulator-game leaderboard: a pole, a
-- flat dark screen, and a colored header strip with the title -- no gold,
-- no ornamentation. Still faces the plaza center (CFrame.lookAt).
local function buildLeaderboard(mapFolder: Folder, angleDegrees: number, labelText: string, index: number)
	local x, z = polarToXZ(LEADERBOARD_RADIUS, angleDegrees)
	local boardCF = CFrame.lookAt(Vector3.new(x, PLAZA_TOP_Y, z), Vector3.new(0, PLAZA_TOP_Y, 0))

	local function place(name: string, size: Vector3, localOffset: Vector3, color: Color3, material: Enum.Material?): Part
		local part = Instance.new("Part")
		part.Name = "Leaderboard" .. index .. "_" .. name
		part.Size = size
		part.CFrame = boardCF * CFrame.new(localOffset)
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = mapFolder
		return part
	end

	local poleCenterY = LEADERBOARD_POLE_HEIGHT / 2
	place("Pole", Vector3.new(1, LEADERBOARD_POLE_HEIGHT, 1), Vector3.new(0, poleCenterY, 0), Color3.fromRGB(90, 90, 95), Enum.Material.Metal)

	local boardCenterY = LEADERBOARD_POLE_HEIGHT + LEADERBOARD_HEIGHT / 2
	local board = place("Board", Vector3.new(LEADERBOARD_WIDTH, LEADERBOARD_HEIGHT, LEADERBOARD_DEPTH), Vector3.new(0, boardCenterY, 0), Color3.fromRGB(25, 25, 30), Enum.Material.SmoothPlastic)

	local headerCenterY = boardCenterY + LEADERBOARD_HEIGHT / 2 - LEADERBOARD_HEADER_HEIGHT / 2
	local header = place(
		"Header",
		Vector3.new(LEADERBOARD_WIDTH, LEADERBOARD_HEADER_HEIGHT, LEADERBOARD_DEPTH + 0.05),
		Vector3.new(0, headerCenterY, 0),
		LEADERBOARD_HEADER_COLORS[index],
		Enum.Material.SmoothPlastic
	)

	addLabel(header, labelText, 0)
end

local function isNearPath(x: number, z: number): boolean
	local halfWidth = PATH_WIDTH / 2 + 1
	local reach = PLAZA_DIAMETER / 2 + PATH_LENGTH

	if math.abs(z) <= halfWidth and math.abs(x) <= reach then
		return true
	end
	if math.abs(x) <= halfWidth and math.abs(z) <= reach then
		return true
	end
	return false
end

local function isBlocked(x: number, z: number): boolean
	if math.sqrt(x * x + z * z) <= TREE_EXCLUSION_RADIUS then
		return true
	end
	return isNearPath(x, z)
end

local function buildTrees(mapFolder: Folder)
	local treesFolder = Instance.new("Folder")
	treesFolder.Name = "Trees"
	treesFolder.Parent = mapFolder

	local placed = 0
	local index = 0
	while placed < TREE_COUNT and index < TREE_COUNT * TREE_PLACEMENT_ATTEMPTS do
		index += 1

		local x = random:NextNumber(-GRASS_PLACEMENT_BOUND, GRASS_PLACEMENT_BOUND)
		local z = random:NextNumber(-GRASS_PLACEMENT_BOUND, GRASS_PLACEMENT_BOUND)
		if isBlocked(x, z) then
			continue
		end

		local scale = random:NextNumber(0.8, 1.3)
		local trunkHeight = 4.5 * scale
		local foliageDiameter = 9 * scale

		local trunk = createCylinder(
			"TreeTrunk",
			3 * scale,
			trunkHeight,
			Vector3.new(x, trunkHeight / 2, z),
			Color3.fromRGB(110, 75, 45),
			Enum.Material.Wood
		)
		trunk.Parent = treesFolder

		local foliage = Instance.new("Part")
		foliage.Name = "TreeFoliage"
		foliage.Shape = Enum.PartType.Ball
		foliage.Size = Vector3.new(foliageDiameter, foliageDiameter, foliageDiameter)
		foliage.CFrame = CFrame.new(x, trunkHeight + foliageDiameter / 2.5, z)
		foliage.Color = Color3.fromRGB(45, 150, 60)
		foliage.Material = Enum.Material.Grass
		foliage.Anchored = true
		foliage.CanCollide = false
		foliage.Parent = treesFolder

		placed += 1
	end
end

function MapBuilder.Build()
	local existing = Workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end

	local defaultBaseplate = Workspace:FindFirstChild("Baseplate")
	if defaultBaseplate and defaultBaseplate:IsA("BasePart") then
		defaultBaseplate:Destroy()
	end

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"

	buildGround(mapFolder)
	buildPlaza(mapFolder)
	buildPaths(mapFolder)
	buildFountain(mapFolder)

	for index, angle in STAND_ANGLES do
		buildStand(mapFolder, angle, index, STAND_ROOF_COLORS[index], STAND_LABELS[index])
	end

	for index, angle in LEADERBOARD_ANGLES do
		buildLeaderboard(mapFolder, angle, LEADERBOARD_LABELS[index], index)
	end

	buildTrees(mapFolder)

	mapFolder.Parent = Workspace

	print("[MapBuilder] Hub map built under Workspace.Map")
end

function MapBuilder.BuildIfMissing()
	if Workspace:FindFirstChild("Map") then
		return
	end
	MapBuilder.Build()
end

return MapBuilder
