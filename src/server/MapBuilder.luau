-- Hub map generator, wired into Main.server.luau so it runs automatically on
-- every server start -- no manual command needed. Workspace isn't synced by
-- Rojo (only ReplicatedStorage/ServerScriptService/StarterPlayerScripts are,
-- per default.project.json), so this is the only way the map's Parts get
-- created at all.
--
-- Main.server.luau calls MapBuilder.Build() (not BuildIfMissing()) so the
-- map is destroyed and rebuilt from scratch on *every* server start --
-- otherwise a Workspace.Map saved into the place file from a previous
-- session would stick around forever and silently ignore any later changes
-- made here (this bit us: the Potions stand didn't show up in Play mode
-- until the stale saved map was replaced). The map is 100% procedural, so
-- there's nothing hand-tuned in it worth preserving across restarts.
-- BuildIfMissing() is kept around only for callers that explicitly want the
-- old "build once, then leave it alone" behavior.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

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
local PLAZA_TILE_SIZE = 10
local PLAZA_TILE_COLOR_A = Color3.fromRGB(190, 190, 200)
local PLAZA_TILE_COLOR_B = Color3.fromRGB(162, 162, 175)

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

-- Square ice-blue pool surrounding the fountain (a low raised curb + a
-- flat water pane), plus one bench centered on each of its 4 sides --
-- matches the reference's bench-and-pool plaza. Cardinal angles (0/90/
-- 180/270), not diagonal, so each bench faces a flat side of the pool
-- instead of straddling a corner; the N/S/E/W paths start way further out
-- (at PLAZA_DIAMETER/2, radius 50+) so there's no collision this close in.
local POOL_SIZE = 26
local POOL_CURB_HEIGHT = 1.5
local POOL_CURB_THICKNESS = 1.2
local POOL_COLOR = Color3.fromRGB(150, 210, 235)

-- Just past the pool's flat-side outer edge (POOL_SIZE/2 + curb halfwidth
-- = 13.6), close enough to still read as "at the pool" rather than out in
-- the open plaza.
local BENCH_RADIUS = 15.5
local BENCH_ANGLES = { 0, 90, 180, 270 }
local BENCH_WIDTH = 6.5
local BENCH_WOOD_COLOR = Color3.fromRGB(150, 105, 65)
local BENCH_FRAME_COLOR = Color3.fromRGB(35, 35, 42)

-- Single shop kiosk -- Assets and Invest are both categories inside the one
-- ShopPanel, not two separate physical stands. Positioned by exact XZ
-- (walked-to-and-picked-a-spot coordinates), not polar radius/angle.
local STAND_POSITION = Vector2.new(29.34, -32.34)
local STAND_ROOF_COLOR = Color3.fromRGB(90, 60, 200)
local STAND_LABEL = "SHOP"

-- Where players land on join/respawn, by exact XZ (same walked-to-and-
-- picked-a-spot convention as the stands) -- inside the plaza radius, so it
-- sits flush with the cobblestone plaza floor.
local SPAWN_POSITION = Vector2.new(-16.85, -26.25)

-- Separate Potions stand -- temporary Cash-bought boosts, distinct from the
-- Assets/Invest kiosk above, so it gets its own prompt name/panel.
local POTION_STAND_POSITION = Vector2.new(30.08, 35.90)
local POTION_STAND_ROOF_COLOR = Color3.fromRGB(190, 60, 180)
local POTION_STAND_LABEL = "POTIONS"

-- Read-only Index/Catalog stand, right next to the Shop kiosk -- browses
-- every rolled Item/Asset/Investment that exists in the game (no remotes,
-- pure shared-database lookups, see CatalogPanel.luau) rather than trying
-- to physically render 100+ individual items with no models/images.
local INDEX_STAND_POSITION = Vector2.new(STAND_POSITION.X + 11, STAND_POSITION.Y + 4)
local INDEX_STAND_ROOF_COLOR = Color3.fromRGB(80, 170, 190)
local INDEX_STAND_LABEL = "INDEX"

-- 3 boards in a row, centered on this XZ point, all facing the plaza
-- center -- LEADERBOARD_SPACING studs apart along the row.
local LEADERBOARD_CENTER = Vector2.new(-36.95, 24.42)
local LEADERBOARD_SPACING = 6
local LEADERBOARD_LABELS = { "TOP CASH", "TOP NET WORTH", "TOP ROLLS" }

-- Trees sit on a fixed, centered grid (not scattered randomly) so the
-- forest reads as deliberately planted rows, not clutter -- isBlocked still
-- skips any grid point that lands on the plaza or a path.
local TREE_GRID_SPACING = 42
local TREE_EXCLUSION_RADIUS = 57
local GRASS_PLACEMENT_BOUND = 130

-- Puffy blocky clouds (a handful of overlapping Balls per cloud, same
-- "chunky primitive" trick as the trees) floating high above the map, plus
-- a mild Lighting boost -- toned down from the initial pass (which read as
-- too cartoonish) to just a light "pop", not full toon-shaded.
local CLOUD_COUNT = 10
local CLOUD_HEIGHT = 160
local CLOUD_SPREAD = 160
local CLOUD_COLOR = Color3.fromRGB(255, 255, 255)

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
	-- AlwaysOnTop would render this over 2D ScreenGui UI too (e.g. the shop
	-- sign bleeding through AssetShopPanel when open right at the counter),
	-- not just through other 3D parts -- not worth it for a plain label.
	billboard.AlwaysOnTop = false
	billboard.Adornee = adornee
	billboard.Parent = adornee

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, 0, 1, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.TextStrokeTransparency = 0
	textLabel.Font = Enum.Font.LuckiestGuy
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

	-- Checkerboard of square tiles clipped to the plaza's circular footprint
	-- -- same "Bloxy" blocky-square trick buildGround uses for the grass --
	-- instead of one plain cylinder, so the stone floor reads as chunky
	-- square tiles too.
	local radius = PLAZA_DIAMETER / 2
	local tileCount = math.ceil((PLAZA_DIAMETER + PLAZA_TILE_SIZE) / PLAZA_TILE_SIZE)
	local halfSpan = (tileCount * PLAZA_TILE_SIZE) / 2

	for row = 0, tileCount - 1 do
		for col = 0, tileCount - 1 do
			local x = -halfSpan + PLAZA_TILE_SIZE * col + PLAZA_TILE_SIZE / 2
			local z = -halfSpan + PLAZA_TILE_SIZE * row + PLAZA_TILE_SIZE / 2
			if math.sqrt(x * x + z * z) > radius then
				continue
			end

			local isEven = (row + col) % 2 == 0
			local tile = createBlock(
				"PlazaFloorTile",
				Vector3.new(PLAZA_TILE_SIZE, PLAZA_HEIGHT, PLAZA_TILE_SIZE),
				Vector3.new(x, 0, z),
				isEven and PLAZA_TILE_COLOR_A or PLAZA_TILE_COLOR_B,
				Enum.Material.Cobblestone
			)
			tile.Parent = mapFolder
		end
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

-- Invisible, non-collidable pad flush with the plaza's cobblestone top --
-- the plaza floor itself is what players actually stand/collide on, this
-- part only exists to give Roblox a SpawnLocation instance to spawn at.
local SPAWN_PAD_SIZE = Vector3.new(6, 0.2, 6)

local function buildSpawn(mapFolder: Folder)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlayerSpawn"
	spawn.Size = SPAWN_PAD_SIZE
	spawn.CFrame = CFrame.new(SPAWN_POSITION.X, PLAZA_TOP_Y + SPAWN_PAD_SIZE.Y / 2, SPAWN_POSITION.Y)
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = mapFolder
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

local function buildPool(mapFolder: Folder)
	local curbCenterY = PLAZA_TOP_Y + POOL_CURB_HEIGHT / 2
	local half = POOL_SIZE / 2

	local walls = {
		{ name = "PoolCurbNorth", size = Vector3.new(POOL_SIZE, POOL_CURB_HEIGHT, POOL_CURB_THICKNESS), position = Vector3.new(0, curbCenterY, half) },
		{ name = "PoolCurbSouth", size = Vector3.new(POOL_SIZE, POOL_CURB_HEIGHT, POOL_CURB_THICKNESS), position = Vector3.new(0, curbCenterY, -half) },
		{ name = "PoolCurbEast", size = Vector3.new(POOL_CURB_THICKNESS, POOL_CURB_HEIGHT, POOL_SIZE), position = Vector3.new(half, curbCenterY, 0) },
		{ name = "PoolCurbWest", size = Vector3.new(POOL_CURB_THICKNESS, POOL_CURB_HEIGHT, POOL_SIZE), position = Vector3.new(-half, curbCenterY, 0) },
	}
	for _, wall in walls do
		local part = createBlock(wall.name, wall.size, wall.position, POOL_COLOR, Enum.Material.Ice)
		part.Parent = mapFolder
	end

	local waterSize = POOL_SIZE - POOL_CURB_THICKNESS * 2
	local water = createBlock(
		"PoolWater",
		Vector3.new(waterSize, 0.4, waterSize),
		Vector3.new(0, PLAZA_TOP_Y + 0.2, 0),
		FOUNTAIN_WATER_COLOR,
		Enum.Material.Glass
	)
	water.Transparency = 0.3
	water.Parent = mapFolder
end

-- Simple park bench: 2 dark frame legs + a wood seat + a wood backrest.
-- CFrame.lookAt (same convention as stands/leaderboards) points local -Z at
-- the fountain; the extra 180-degree spin flips that so the backrest faces
-- the fountain and the seat faces outward, away from it.
local function buildBench(mapFolder: Folder, angleDegrees: number, index: number)
	local x, z = polarToXZ(BENCH_RADIUS, angleDegrees)
	local benchCF = CFrame.lookAt(Vector3.new(x, PLAZA_TOP_Y, z), Vector3.new(0, PLAZA_TOP_Y, 0)) * CFrame.Angles(0, math.rad(180), 0)

	local function place(name: string, size: Vector3, localOffset: Vector3, color: Color3, material: Enum.Material?): Part
		local part = Instance.new("Part")
		part.Name = "Bench" .. index .. "_" .. name
		part.Size = size
		part.CFrame = benchCF * CFrame.new(localOffset)
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.Anchored = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent = mapFolder
		return part
	end

	local legOffset = BENCH_WIDTH / 2 - 0.6
	place("LegLeft", Vector3.new(0.4, 1.6, 1.8), Vector3.new(-legOffset, 0.8, 0), BENCH_FRAME_COLOR, Enum.Material.Metal)
	place("LegRight", Vector3.new(0.4, 1.6, 1.8), Vector3.new(legOffset, 0.8, 0), BENCH_FRAME_COLOR, Enum.Material.Metal)
	place("Seat", Vector3.new(BENCH_WIDTH, 0.4, 1.8), Vector3.new(0, 1.8, 0), BENCH_WOOD_COLOR, Enum.Material.WoodPlanks)
	place("Backrest", Vector3.new(BENCH_WIDTH, 1.2, 0.3), Vector3.new(0, 2.6, 0.7), BENCH_WOOD_COLOR, Enum.Material.WoodPlanks)
end

local STAND_WIDTH = 7
local STAND_DEPTH = 7
local STAND_WALL_HEIGHT = 6

-- A proper small kiosk instead of a floating table+slab: 4 corner pillars,
-- walls on 3 sides (front stays open over the counter, facing the plaza
-- center), a stepped/tiered "pagoda" roof, and a sign board over the
-- entrance -- reads as an actual shop, not a placeholder table.
local function buildStand(mapFolder: Folder, position: Vector2, index: number, roofColor: Color3, labelText: string, promptName: string)
	local standCF = CFrame.lookAt(Vector3.new(position.X, PLAZA_TOP_Y, position.Y), Vector3.new(0, PLAZA_TOP_Y, 0))

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
	local counter = place("Counter", Vector3.new(STAND_WIDTH - 1, 3, 1.5), Vector3.new(0, 1 + 1.5, -halfDepth + 0.75), Color3.fromRGB(210, 190, 150), Enum.Material.WoodPlanks)

	-- Shop trigger. Named per promptName (e.g. "ShopPrompt", "PotionShopPrompt")
	-- so each stand's client-side panel listener can tell them apart.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = promptName
	prompt.ActionText = "Open Shop"
	prompt.ObjectText = labelText
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = counter

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
local LEADERBOARD_STAND_HEIGHT = 2
local LEADERBOARD_HEADER_HEIGHT = 1
local LEADERBOARD_HEADER_COLORS = { Color3.fromRGB(60, 190, 100), Color3.fromRGB(85, 140, 235), Color3.fromRGB(200, 90, 220) }
local LEADERBOARD_BASE_HEIGHT = 1.2
local LEADERBOARD_FRAME_MARGIN = 0.5

-- Premium trophy-stand look: a wide gold pedestal, two gold side pillars,
-- and a gold backing frame peeking out around the dark screen -- the same
-- FOUNTAIN_GOLD used on the fountain/shop-stand finials, so the boards
-- read as part of the same "wealth" aesthetic instead of a plain
-- scoreboard. Still faces the plaza center (CFrame.lookAt).
local function buildLeaderboard(mapFolder: Folder, offsetIndex: number, labelText: string, index: number)
	local clusterCF = CFrame.lookAt(Vector3.new(LEADERBOARD_CENTER.X, PLAZA_TOP_Y, LEADERBOARD_CENTER.Y), Vector3.new(0, PLAZA_TOP_Y, 0))
	local boardCF = clusterCF * CFrame.new(offsetIndex * LEADERBOARD_SPACING, 0, 0)

	local function place(name: string, size: Vector3, localOffset: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
		local part = Instance.new("Part")
		part.Name = "Leaderboard" .. index .. "_" .. name
		part.Size = size
		part.CFrame = boardCF * CFrame.new(localOffset)
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

	local boardCenterY = LEADERBOARD_STAND_HEIGHT + LEADERBOARD_HEIGHT / 2
	local boardTopY = boardCenterY + LEADERBOARD_HEIGHT / 2

	-- Wide gold pedestal base (replaces the old bare pole's footing).
	place("Base", Vector3.new(LEADERBOARD_WIDTH + 1.5, LEADERBOARD_BASE_HEIGHT, LEADERBOARD_DEPTH + 1.2), Vector3.new(0, LEADERBOARD_BASE_HEIGHT / 2, 0), FOUNTAIN_GOLD, Enum.Material.Metal)

	-- Two gold side pillars, base top to board top -- reads as a trophy
	-- stand holding the screen up, not a single bare pole.
	local pillarHeight = boardTopY - LEADERBOARD_BASE_HEIGHT
	local pillarCenterY = LEADERBOARD_BASE_HEIGHT + pillarHeight / 2
	local pillarX = LEADERBOARD_WIDTH / 2 + 0.35
	place("PillarLeft", Vector3.new(0.5, pillarHeight, 0.5), Vector3.new(-pillarX, pillarCenterY, 0), FOUNTAIN_GOLD, Enum.Material.Metal)
	place("PillarRight", Vector3.new(0.5, pillarHeight, 0.5), Vector3.new(pillarX, pillarCenterY, 0), FOUNTAIN_GOLD, Enum.Material.Metal)

	-- Gold backing frame, set back and larger than the screen so it peeks
	-- out as a border all the way around.
	place(
		"Frame",
		Vector3.new(LEADERBOARD_WIDTH + LEADERBOARD_FRAME_MARGIN * 2, LEADERBOARD_HEIGHT + LEADERBOARD_FRAME_MARGIN * 2, LEADERBOARD_DEPTH * 0.6),
		Vector3.new(0, boardCenterY, LEADERBOARD_DEPTH * 0.35),
		FOUNTAIN_GOLD,
		Enum.Material.Metal
	)

	local board = place("Board", Vector3.new(LEADERBOARD_WIDTH, LEADERBOARD_HEIGHT, LEADERBOARD_DEPTH), Vector3.new(0, boardCenterY, 0), Color3.fromRGB(25, 25, 30), Enum.Material.SmoothPlastic)

	-- Rank rows, painted onto the board's front face. LeaderboardManager finds
	-- this by name ("Display" -> "Rows") and (re)creates one TextLabel row
	-- per ranked entry (up to top 100) on every refresh -- MapBuilder only
	-- builds the empty scrolling container, since a fixed row count can't
	-- fit 100 readable entries on a ~5x6 stud board.
	local displayGui = Instance.new("SurfaceGui")
	displayGui.Name = "Display"
	displayGui.Face = Enum.NormalId.Front
	displayGui.LightInfluence = 0
	displayGui.Parent = board

	local displayPadding = Instance.new("UIPadding")
	displayPadding.PaddingTop = UDim.new(0.05, 0)
	displayPadding.PaddingLeft = UDim.new(0.04, 0)
	displayPadding.PaddingRight = UDim.new(0.04, 0)
	displayPadding.PaddingBottom = UDim.new(0.02, 0)
	displayPadding.Parent = displayGui

	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Rows"
	rows.Size = UDim2.new(1, 0, 1, 0)
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.CanvasSize = UDim2.new(0, 0, 0, 0)
	rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rows.ScrollBarThickness = 10
	rows.ScrollBarImageColor3 = FOUNTAIN_GOLD
	rows.Parent = displayGui

	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Parent = rows

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

	-- Centered, symmetric grid (not an arbitrary corner-anchored one) so the
	-- rows line up evenly on both sides of the plaza.
	local steps = math.floor((2 * GRASS_PLACEMENT_BOUND) / TREE_GRID_SPACING)
	local gridStart = -steps / 2 * TREE_GRID_SPACING

	for row = 0, steps do
		for col = 0, steps do
			local x = gridStart + row * TREE_GRID_SPACING
			local z = gridStart + col * TREE_GRID_SPACING
			if isBlocked(x, z) then
				continue
			end

			-- Position is strictly on-grid; only size gets slight variation
			-- so the rows still read as uniform, not identical toy soldiers.
			local scale = random:NextNumber(0.9, 1.1)
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
		end
	end
end

local function buildClouds(mapFolder: Folder)
	local cloudsFolder = Instance.new("Folder")
	cloudsFolder.Name = "Clouds"
	cloudsFolder.Parent = mapFolder

	for i = 1, CLOUD_COUNT do
		local cx = random:NextNumber(-CLOUD_SPREAD, CLOUD_SPREAD)
		local cz = random:NextNumber(-CLOUD_SPREAD, CLOUD_SPREAD)
		local cy = CLOUD_HEIGHT + random:NextNumber(-15, 15)
		local puffCount = random:NextInteger(3, 5)

		for p = 1, puffCount do
			local puffDiameter = random:NextNumber(10, 18)
			local offsetX = (p - 1) * random:NextNumber(6, 10) - (puffCount - 1) * 4
			local offsetY = random:NextNumber(-2, 2)
			local offsetZ = random:NextNumber(-4, 4)

			local puff = Instance.new("Part")
			puff.Name = "CloudPuff"
			puff.Shape = Enum.PartType.Ball
			puff.Size = Vector3.new(puffDiameter, puffDiameter, puffDiameter)
			puff.CFrame = CFrame.new(cx + offsetX, cy + offsetY, cz + offsetZ)
			puff.Color = CLOUD_COLOR
			puff.Material = Enum.Material.SmoothPlastic
			puff.Anchored = true
			puff.CanCollide = false
			puff.Parent = cloudsFolder
		end
	end
end

-- Brighter/more saturated Lighting + a mild ColorCorrection boost --
-- Roblox's default look is fairly flat/realistic; this is the cheap,
-- asset-free way to push it toward a cartoon "pop" instead.
local function applyCartoonLighting()
	Lighting.Brightness = 2.4
	Lighting.ClockTime = 14
	Lighting.Ambient = Color3.fromRGB(140, 140, 150)
	Lighting.OutdoorAmbient = Color3.fromRGB(175, 175, 190)
	Lighting.FogEnd = 100000

	local colorCorrection = Lighting:FindFirstChild("WealthRNG_ColorCorrection")
	if not colorCorrection then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Name = "WealthRNG_ColorCorrection"
		colorCorrection.Parent = Lighting
	end
	colorCorrection.Saturation = 0.15
	colorCorrection.Contrast = 0.08
	colorCorrection.Brightness = 0.02
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

	-- Clear any stray SpawnLocation left directly under Workspace (e.g. from
	-- the old pre-pivot game) so ours -- built inside mapFolder below -- is
	-- the only one Roblox can pick for player spawns.
	for _, child in Workspace:GetChildren() do
		if child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end

	local mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"

	buildGround(mapFolder)
	buildPlaza(mapFolder)
	buildPaths(mapFolder)
	buildSpawn(mapFolder)
	buildFountain(mapFolder)
	buildPool(mapFolder)
	for index, angle in BENCH_ANGLES do
		buildBench(mapFolder, angle, index)
	end

	buildStand(mapFolder, STAND_POSITION, 1, STAND_ROOF_COLOR, STAND_LABEL, "ShopPrompt")
	buildStand(mapFolder, POTION_STAND_POSITION, 2, POTION_STAND_ROOF_COLOR, POTION_STAND_LABEL, "PotionShopPrompt")
	buildStand(mapFolder, INDEX_STAND_POSITION, 3, INDEX_STAND_ROOF_COLOR, INDEX_STAND_LABEL, "CatalogPrompt")

	for index, labelText in LEADERBOARD_LABELS do
		local offsetIndex = index - 2 -- 3 boards -> -1, 0, 1
		buildLeaderboard(mapFolder, offsetIndex, labelText, index)
	end

	buildTrees(mapFolder)
	buildClouds(mapFolder)
	applyCartoonLighting()

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
