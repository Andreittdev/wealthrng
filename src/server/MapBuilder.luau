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
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StadiumOfferConfig = require(ReplicatedStorage.Modules.StadiumOfferConfig)

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
local PATH_LENGTH = 50
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
-- Pulled in closer to the fountain per explicit request (was 15.5, from
-- back when there was a square water pool here that this needed to clear).
local BENCH_RADIUS = 10.5
-- Down to 2 (was 4, opposite sides of the fountain) per explicit request.
local BENCH_ANGLES = { 0, 180 }
local BENCH_WIDTH = 6.5
local BENCH_WOOD_COLOR = Color3.fromRGB(150, 105, 65)
local BENCH_FRAME_COLOR = Color3.fromRGB(35, 35, 42)

-- Lamp posts flanking each of the 4 paths, 1 per side per path (8 total) --
-- fills in the previously bare stretches between the plaza and the map's
-- edge without crowding the paths, and doubles as light sources for a
-- dusk/night ClockTime later without any extra work.
local LAMP_POST_HEIGHT = 6
local LAMP_POST_ABS_DISTANCES = { 75 } -- along-path distance from world origin (path midpoint)
local LAMP_POST_OFFSET = PATH_WIDTH / 2 + 2.5 -- perpendicular offset from the path's centerline
local LAMP_POLE_COLOR = Color3.fromRGB(40, 40, 45)
local LAMP_GLOW_COLOR = Color3.fromRGB(255, 225, 150)

-- Small flower planters dotted just outside the plaza rim (on the grass,
-- not the cobblestone -- PLANTER_RADIUS used to be inside the plaza's
-- concrete floor, which is wrong), 8 evenly spaced but offset from the 4
-- cardinal path angles (0/90/180/270) so they never sit right where a
-- path opens onto the plaza.
local PLANTER_RADIUS = RIM_DIAMETER / 2 + 8
local PLANTER_ANGLES = { 22.5, 67.5, 112.5, 157.5, 202.5, 247.5, 292.5, 337.5 }
local PLANTER_BOX_COLOR = Color3.fromRGB(120, 85, 60)
local FLOWER_COLORS = {
	Color3.fromRGB(235, 80, 100),
	Color3.fromRGB(255, 210, 90),
	Color3.fromRGB(230, 230, 240),
}

-- Faint gold sparkles drifting up out of the plaza floor -- purely
-- atmospheric ("wealth in the air"), ties the whole plaza back to the same
-- gold-accent theme as the fountain/leaderboards/stand finials.
local AMBIENT_SPARKLE_COUNT = 10
local AMBIENT_SPARKLE_RADIUS = 40

-- Single shop kiosk -- Assets and Invest are both categories inside the one
-- ShopPanel, not two separate physical stands. Positioned by exact XZ
-- (walked-to-and-picked-a-spot coordinates), not polar radius/angle.
local STAND_POSITION = Vector2.new(29.34, -32.34)
local STAND_ROOF_COLOR = Color3.fromRGB(90, 60, 200)
local STAND_LABEL = "SHOP"

-- Where players land on join/respawn, by exact XZ (same walked-to-and-
-- picked-a-spot convention as the stands) -- inside the plaza radius, so it
-- sits flush with the cobblestone plaza floor.
local SPAWN_POSITION = Vector2.new(-9.200676918029785, 26.894458770751953)

-- Separate Potions stand -- temporary Cash-bought boosts, distinct from the
-- Assets/Invest kiosk above, so it gets its own prompt name/panel.
local POTION_STAND_POSITION = Vector2.new(30.08, 35.90)
local POTION_STAND_ROOF_COLOR = Color3.fromRGB(190, 60, 180)
local POTION_STAND_LABEL = "POTIONS"

-- Read-only Index/Catalog stand -- browses every rolled Item/Asset/
-- Investment that exists in the game (no remotes, pure shared-database
-- lookups, see CatalogPanel.luau) rather than trying to physically render
-- 100+ individual items with no models/images. Deliberately NOT another
-- copy of the Shop/Potions kiosk (see buildIndexPedestal) -- a small
-- marble pedestal + angled lectern instead, so it reads as its own
-- distinct "premium" prop rather than a third identical house.
local INDEX_STAND_POSITION = Vector2.new(42.69997787475586, -23.43633460998535)
local INDEX_STAND_LABEL = "INDEX"
local INDEX_MARBLE_COLOR = Color3.fromRGB(235, 230, 225)

-- Flat glowing circle on the plaza floor marking where to stand to open
-- the VIP gamepass purchase panel (ShopPanel.luau) -- no physical
-- kiosk/building, just a marker + floating label + trigger, since VIP is a
-- Robux purchase (a menu, not a haggled-over shop stand like Assets/Invest).
local VIP_MARKER_POSITION = Vector2.new(11.02, 37.4)
local VIP_MARKER_COLOR = Color3.fromRGB(255, 215, 0)
local VIP_MARKER_LABEL = "VIP"

-- Same flat-circle marker convention as VIP, out on the open grass (not
-- the plaza) -- claim panel is GroupRewardsProximityPanel.luau (client) +
-- GroupRewardsManager.luau (server).
local GROUP_REWARDS_MARKER_POSITION = Vector2.new(-0.32, 72.79)
local GROUP_REWARDS_MARKER_COLOR = Color3.fromRGB(70, 130, 255)
local GROUP_REWARDS_MARKER_LABEL = "Group Rewards"

-- Same convention again, red this time -- claim panel is
-- DailyRewardsProximityPanel.luau (client) + DailyRewardsManager.luau
-- (server).
local DAILY_REWARDS_MARKER_POSITION = Vector2.new(-0.66, -71.2)
local DAILY_REWARDS_MARKER_COLOR = Color3.fromRGB(230, 60, 60)
local DAILY_REWARDS_MARKER_LABEL = "Daily Rewards"

-- Same spot the old Playtime Rewards marker used to sit at -- just the
-- usual glowing disk, no extra 3D geometry on top -- claim panel is
-- LuckyRollProximityPanel.luau (client), which also owns the floating
-- dice-icon/timer/Claim billboard above this marker (reuses the same dice
-- image RollPanel's ROLL button uses, no custom 3D dice model needed), and
-- no static "Lucky Roll" title label here since that billboard already
-- covers it. Server side lives in RollManager.luau (Lucky is just another
-- SpecialRollConfig tier, see its own comments).
local LUCKY_ROLL_MARKER_POSITION = Vector2.new(72.16, -1.23)
local LUCKY_ROLL_MARKER_COLOR = Color3.fromRGB(180, 100, 255)

-- LARP Battles marker (BattleManager.luau owns the actual queue/matchmaking
-- server-side) -- same spot the old Next Update countdown board used to
-- stand.
local BATTLE_MARKER_POSITION = Vector2.new(-69.96, -0.25)

-- Same flat-circle marker convention as VIP -- inside the plaza (matches
-- VIP's PLAZA_TOP_Y, no beam needed since there's no grass clutter to poke
-- above here), client-provided position (HumanoidRootPart.Position while
-- standing there). Claim panel is CodesProximityPanel.luau (client) +
-- CodesManager.luau (server).
local CODES_MARKER_POSITION = Vector2.new(41.372745513916016, 24.04339599609375)
local CODES_MARKER_COLOR = Color3.fromRGB(80, 220, 160)
local CODES_MARKER_LABEL = "Codes"

-- Every out-on-the-grass floor marker's position, so isBlocked can keep
-- ALL of them clear of trees/bushes/grass decor (see MARKER_EXCLUSION_RADIUS
-- below) without hardcoding each one by name -- VIP's marker doesn't need
-- to be here since it already sits inside TREE_EXCLUSION_RADIUS, on the
-- protected plaza.
local GRASS_MARKER_POSITIONS =
	{ GROUP_REWARDS_MARKER_POSITION, DAILY_REWARDS_MARKER_POSITION, LUCKY_ROLL_MARKER_POSITION, BATTLE_MARKER_POSITION }

-- 4 boards in a row, centered on this XZ point, all facing the plaza
-- center -- LEADERBOARD_SPACING studs apart along the row.
local LEADERBOARD_CENTER = Vector2.new(-36.95, 24.42)
local LEADERBOARD_SPACING = 7.5 -- must clear LEADERBOARD_WIDTH (6.5) or the boards overlap
-- "TOP POINTS" (LARP Battles' weekly leaderboard) is built separately, next
-- to the battle line, not as a 4th slot in this row -- see Build().
local LEADERBOARD_LABELS = { "TOP TIME", "TOP NET WORTH", "TOP ROLLS" }

-- Trees sit on a fixed, centered grid (not scattered randomly) so the
-- forest reads as deliberately planted rows, not clutter -- isBlocked still
-- skips any grid point that lands on the plaza or a path.
-- Tighter than the original 42 -- more trees overall, per explicit request
-- (after switching to the much-smaller-scaled "F Tree" model, more of them
-- packed closer together reads right instead of sparse).
local TREE_GRID_SPACING = 28
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

local DEFAULT_LABEL_MAX_DISTANCE = 40
-- Group Rewards/Daily Rewards/Lucky Roll's markers are out on the open
-- grass, further from the plaza than everything else -- readable from
-- twice the usual distance so they don't just disappear the moment you
-- leave the plaza itself.
local LARGE_LABEL_MAX_DISTANCE = 80

local function addLabel(adornee: BasePart, text: string, studsUp: number, size: UDim2?, textColor: Color3?, alwaysOnTop: boolean?, maxDistance: number?)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = size or UDim2.new(0, 100, 0, 26)
	billboard.StudsOffset = Vector3.new(0, studsUp, 0)
	-- AlwaysOnTop would render this over 2D ScreenGui UI too (e.g. the shop
	-- sign bleeding through AssetShopPanel when open right at the counter),
	-- not just through other 3D parts -- not worth it for a plain label by
	-- default. Callers with something like a glowing beam sitting right
	-- behind/around their label (buildFloorMarker's withBeam) opt in
	-- instead, so the text draws in front of the glow instead of washing
	-- out into it.
	billboard.AlwaysOnTop = alwaysOnTop or false
	-- Unset, this defaults to effectively unlimited -- every floor
	-- marker/stand/board label was readable from clear across the map,
	-- all piled up on screen at once from the plaza. Fades out (Roblox's
	-- own built-in behavior) once the camera is farther than this instead.
	-- Callers can opt into a bigger radius (e.g. Daily/Group Rewards, meant
	-- to stay noticeable from farther across the grass) via `maxDistance`.
	billboard.MaxDistance = maxDistance or DEFAULT_LABEL_MAX_DISTANCE
	billboard.Adornee = adornee
	billboard.Parent = adornee

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, 0, 1, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = textColor or Color3.fromRGB(255, 255, 255)
	textLabel.TextStrokeTransparency = 0
	textLabel.Font = Enum.Font.LuckiestGuy
	textLabel.TextScaled = true
	textLabel.Text = text
	textLabel.Parent = billboard
end

-- Continuous slow rotation (not a TweenService loop back to the same
-- CFrame every 360 degrees, which is a visual no-op) -- used on gold
-- accents (fountain gem, stand finials) so they visibly catch the light
-- and read as "alive" instead of static props. Disconnects itself via
-- Destroying so a future MapBuilder.Build() call (BuildIfMissing/manual
-- rebuild) can't pile up dangling Heartbeat connections on destroyed parts.
local function addContinuousSpin(part: BasePart, degreesPerSecond: number)
	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function(deltaTime: number)
		part.CFrame = part.CFrame * CFrame.Angles(0, math.rad(degreesPerSecond * deltaTime), 0)
	end)
	part.Destroying:Connect(function()
		connection:Disconnect()
	end)
end

-- Small twinkling glow -- reused on the fountain gem and every stand's
-- finial so the map's gold accents feel like they're catching light
-- instead of sitting flat, matching the "premium/wealth" theme.
local function addSparkle(part: BasePart, color: Color3, rate: number?)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.8, 1.4)
	emitter.Rate = rate or 10
	emitter.Speed = NumberRange.new(1, 2)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 1
	emitter.Parent = part
end

-- Upward drifting mist -- used on the fountain's water panes so the water
-- reads as moving/misting instead of a flat glass slab.
local function addWaterMist(part: BasePart)
	local mist = Instance.new("ParticleEmitter")
	mist.Color = ColorSequence.new(FOUNTAIN_WATER_COLOR)
	mist.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 1.6),
	})
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.Lifetime = NumberRange.new(1, 1.8)
	mist.Rate = 18
	mist.Speed = NumberRange.new(2, 4)
	mist.SpreadAngle = Vector2.new(15, 15)
	mist.Parent = part
end

local function polarToXZ(radius: number, angleDegrees: number): (number, number)
	local angleRadians = math.rad(angleDegrees)
	return radius * math.cos(angleRadians), radius * math.sin(angleRadians)
end

local PLAZA_TOP_Y = PLAZA_HEIGHT / 2
-- Top surface of the flat checkerboard grass (buildGround's tiles are
-- centered at -GROUND_THICKNESS/2, so their top face is exactly Y=0) --
-- the plaza/rim/paths sit elevated above this on their own raised dais, so
-- anything placed beyond RIM_DIAMETER/2 (out on the open grass, not on the
-- plaza) needs to use this instead of PLAZA_TOP_Y or it floats.
local GROUND_TOP_Y = 0

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
	addWaterMist(baseWater)

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
	addWaterMist(topWater)

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
	addContinuousSpin(gem, 40)
	addSparkle(gem, Color3.fromRGB(255, 240, 180), 14)
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
	addLabel(sign, labelText, 3)

	-- Stepped "pagoda" roof, each tier flush on the one below, tapering up
	local roofBaseY = 1 + STAND_WALL_HEIGHT
	place("RoofTier1", Vector3.new(STAND_WIDTH + 2, 1, STAND_DEPTH + 2), Vector3.new(0, roofBaseY + 0.5, 0), roofColor, Enum.Material.Fabric)
	place("RoofTier2", Vector3.new(STAND_WIDTH - 1, 1, STAND_DEPTH - 1), Vector3.new(0, roofBaseY + 1.5, 0), roofColor, Enum.Material.Fabric)
	place("RoofTier3", Vector3.new(STAND_WIDTH - 4, 1, STAND_DEPTH - 4), Vector3.new(0, roofBaseY + 2.5, 0), roofColor, Enum.Material.Fabric)
	local finial = place("Finial", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, roofBaseY + 3.6, 0), Color3.fromRGB(255, 215, 90), Enum.Material.Neon, Enum.PartType.Ball)
	addContinuousSpin(finial, 50)
	addSparkle(finial, Color3.fromRGB(255, 225, 140), 8)
end

-- Small marble pedestal + angled lectern -- the Index/Catalog stand's own
-- distinct look (not a scaled-down copy of buildStand's wood kiosk), ~4.5
-- studs across vs. the Shop/Potions kiosks' 7x7 footprint, so it visibly
-- reads as a different, smaller kind of prop while still matching the
-- map's gold/marble "premium" accents (same trick as the fountain/
-- leaderboards: gold trim + a spinning, sparkling gold gem).
local function buildIndexPedestal(mapFolder: Folder, position: Vector2, labelText: string, promptName: string)
	local pedestalCF = CFrame.lookAt(Vector3.new(position.X, PLAZA_TOP_Y, position.Y), Vector3.new(0, PLAZA_TOP_Y, 0))

	-- Wide marble base + gold trim ring peeking out under it (same "wider
	-- base than the tier above" rim trick the fountain uses). Round tiers
	-- are rotationally symmetric, so they're placed by plain world
	-- position via createCylinder (which already handles standing a
	-- Cylinder-shaped Part upright) rather than through pedestalCF.
	local baseHeight = 1
	local baseCenterY = baseHeight / 2
	local trim = createCylinder("IndexPedestal_GoldTrim", 4.8, 0.3, Vector3.new(position.X, PLAZA_TOP_Y + 0.15, position.Y), FOUNTAIN_GOLD, Enum.Material.Metal)
	trim.Parent = mapFolder
	local base = createCylinder("IndexPedestal_Base", 4.2, baseHeight, Vector3.new(position.X, PLAZA_TOP_Y + baseCenterY + 0.15, position.Y), INDEX_MARBLE_COLOR, Enum.Material.Marble)
	base.Parent = mapFolder

	-- Narrower riser tier
	local riserHeight = 0.7
	local riserCenterY = baseHeight + 0.3 + riserHeight / 2
	local riser = createCylinder("IndexPedestal_Riser", 2.8, riserHeight, Vector3.new(position.X, PLAZA_TOP_Y + riserCenterY, position.Y), INDEX_MARBLE_COLOR, Enum.Material.Marble)
	riser.Parent = mapFolder

	-- Angled lectern top -- a slanted slab (rotated about local X) reading
	-- as a book stand/index podium, with a thin "book" resting on it.
	local lecternTopY = riserCenterY + riserHeight / 2
	local lecternPart = Instance.new("Part")
	lecternPart.Name = "IndexPedestal_Lectern"
	lecternPart.Size = Vector3.new(3, 0.3, 2.2)
	lecternPart.CFrame = pedestalCF * CFrame.new(0, lecternTopY + 0.6, 0.3) * CFrame.Angles(math.rad(-28), 0, 0)
	lecternPart.Color = FOUNTAIN_GOLD
	lecternPart.Material = Enum.Material.Metal
	lecternPart.Anchored = true
	lecternPart.TopSurface = Enum.SurfaceType.Smooth
	lecternPart.BottomSurface = Enum.SurfaceType.Smooth
	lecternPart.Parent = mapFolder

	local standPart = Instance.new("Part")
	standPart.Name = "IndexPedestal_LecternStand"
	standPart.Size = Vector3.new(0.6, 1.2, 0.6)
	standPart.CFrame = pedestalCF * CFrame.new(0, riserCenterY + riserHeight / 2 + 0.5, 0)
	standPart.Color = FOUNTAIN_GOLD
	standPart.Material = Enum.Material.Metal
	standPart.Anchored = true
	standPart.TopSurface = Enum.SurfaceType.Smooth
	standPart.BottomSurface = Enum.SurfaceType.Smooth
	standPart.Parent = mapFolder

	-- Closed book resting on the lectern -- a dark cover slab with a
	-- lighter "pages" slab sandwiched just inside it, same layered trick
	-- used for a stylized/chunky prop instead of a single flat block.
	local bookCover = Instance.new("Part")
	bookCover.Name = "IndexPedestal_BookCover"
	bookCover.Size = Vector3.new(2, 0.4, 1.6)
	bookCover.CFrame = lecternPart.CFrame * CFrame.new(0, 0.3, 0)
	bookCover.Color = Color3.fromRGB(90, 25, 35)
	bookCover.Material = Enum.Material.SmoothPlastic
	bookCover.Anchored = true
	bookCover.CanCollide = false
	bookCover.Parent = mapFolder

	local bookPages = Instance.new("Part")
	bookPages.Name = "IndexPedestal_BookPages"
	bookPages.Size = Vector3.new(1.8, 0.28, 1.4)
	bookPages.CFrame = bookCover.CFrame * CFrame.new(0, 0.05, 0)
	bookPages.Color = Color3.fromRGB(245, 238, 220)
	bookPages.Material = Enum.Material.SmoothPlastic
	bookPages.Anchored = true
	bookPages.CanCollide = false
	bookPages.Parent = mapFolder

	-- Trigger + floating label
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = promptName
	prompt.ActionText = "Browse Index"
	prompt.ObjectText = labelText
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = standPart

	addLabel(bookCover, labelText, 2.5)
end

-- Flat glowing circle on the floor + floating label -- see
-- VIP_MARKER_POSITION's comment for why this is a marker, not a kiosk. No
-- ProximityPrompt on purpose -- that always draws Roblox's own "Press E"
-- prompt UI the instant a player is in range, which isn't wanted for VIP's
-- version of this; other callers are free to add their own trigger.
-- `diskName` must be unique per marker (client scripts find a specific
-- marker by name, e.g. VIPProximityPanel.luau looks up "VIPMarker_Disk").
-- `baseY` is the ground level to sit flush on -- PLAZA_TOP_Y for markers on
-- the paved plaza, GROUND_TOP_Y for ones out on the open grass (using the
-- wrong one floats the disk 1.5 studs above the actual surface -- see
-- buildLampPost's/buildPlanter's identical fix). `withBeam` adds a tall
-- thin glowing column above the disk, tall enough to poke up over nearby
-- trees/bushes/grass clutter and read as a marker from across the map --
-- VIP's marker sits in the open plaza (no clutter) so it doesn't need one,
-- but markers out on the grass do.
local function buildFloorMarker(
	mapFolder: Folder,
	diskName: string,
	position: Vector2,
	baseY: number,
	color: Color3,
	labelText: string,
	textColor: Color3,
	withBeam: boolean?,
	labelMaxDistance: number?
): Part
	local diskY = baseY + 0.05
	local disk = createCylinder(diskName, 6, 0.15, Vector3.new(position.X, diskY, position.Y), color, Enum.Material.Neon)
	disk.CanCollide = false
	disk.Parent = mapFolder

	if withBeam then
		local beamHeight = 20
		local beam = createCylinder(diskName .. "_Beam", 1.5, beamHeight, Vector3.new(position.X, diskY + beamHeight / 2, position.Y), color, Enum.Material.Neon)
		beam.CanCollide = false
		beam.Transparency = 0.55
		beam.Parent = mapFolder
	end

	-- Stays low near the disk either way -- AlwaysOnTop (only when there's
	-- a beam) is what keeps the text readable in front of the glow, not
	-- moving the label up and out of it. Empty labelText skips the label
	-- entirely -- Lucky Roll's marker uses this since its own billboard
	-- (LuckyRollProximityPanel.luau's "Nx Roll!"/"Claim in..." callout)
	-- already covers that space, and a static "Lucky Roll" title floating
	-- right underneath it just doubled up.
	if labelText ~= "" then
		addLabel(disk, labelText, 7, UDim2.new(0, 75, 0, 22), textColor, withBeam, labelMaxDistance)
	end
	return disk
end

local BATTLE_LINE_LENGTH = 8
local BATTLE_LINE_WIDTH = 0.6
local BATTLE_MARKER_COLOR = Color3.fromRGB(255, 140, 80)
-- "TOP POINTS" (LARP Battles' own weekly board) -- explicit world position
-- (client-provided, via HumanoidRootPart.Position while standing there),
-- facing the plaza center like every other board (no extra rotation --
-- see buildLeaderboard's call site for why that broke the board's visibility).
local LEADERBOARD_POINTS_POSITION = Vector2.new(-55.436, -6.461)

-- Red carpet under the LARP Battles line -- a flat black line + floating
-- text label alone used to read as "some random spot on the grass" from a
-- distance; a real patch of red carpet (with a gold trim border, same
-- premium-accent language as everywhere else on the map) makes the zone
-- read as special ground worth walking onto, without needing a big
-- structure looming over it.
local CARPET_COLOR = Color3.fromRGB(160, 20, 20)
local CARPET_TRIM_COLOR = Color3.fromRGB(212, 175, 55)
local CARPET_DEPTH = 10
local CARPET_TRIM_WIDTH = 0.4

-- Built with raw Parts (not createBlock) -- createBlock only ever applies
-- a plain CFrame.new(position) with IDENTITY rotation, silently dropping
-- facingCF's rotation component (which the previous version fed it via
-- `(facingCF * offset).Position`, discarding the rotation half of that
-- CFrame entirely). Harmless when the marker happens to sit near-aligned
-- with world axes, but the real bug was thickness: 0.1-0.3 studs sitting
-- barely 0.2 studs above the ground is well within typical terrain/part
-- z-fighting range and reads as "not there" from a normal camera angle.
-- Genuinely thick and clearly elevated now.
local function buildBattleCarpet(mapFolder: Folder, facingCF: CFrame)
	local carpetLength = BATTLE_LINE_LENGTH + 3
	local carpetHeight = 1

	local carpet = Instance.new("Part")
	carpet.Name = "BattleGate_Carpet"
	carpet.Size = Vector3.new(carpetLength, carpetHeight, CARPET_DEPTH)
	carpet.CFrame = facingCF * CFrame.new(0, carpetHeight / 2, 0)
	carpet.Color = CARPET_COLOR
	carpet.Material = Enum.Material.Fabric
	carpet.Anchored = true
	carpet.CanCollide = false
	carpet.Parent = mapFolder

	-- Gold trim along both long edges, same premium-accent color used
	-- everywhere else (fountain rim, stand finials) -- raised to sit right
	-- on top of the carpet's own top surface, not floating separately.
	for _, zOffset in { -CARPET_DEPTH / 2, CARPET_DEPTH / 2 } do
		local trim = Instance.new("Part")
		trim.Name = "BattleGate_CarpetTrim"
		trim.Size = Vector3.new(carpetLength, 0.3, CARPET_TRIM_WIDTH)
		trim.CFrame = facingCF * CFrame.new(0, carpetHeight + 0.15, zOffset)
		trim.Color = CARPET_TRIM_COLOR
		trim.Material = Enum.Material.Metal
		trim.Anchored = true
		trim.CanCollide = false
		trim.Parent = mapFolder
	end
end

-- Just the flat black line painted on the ground, players face off across
-- it -- no ProximityPrompt. BattlePanel.luau (client) shows its own 3-card
-- menu automatically while in range (plain distance check against this
-- part, same pattern as VIPProximityPanel.luau), and BattleManager.luau
-- (server) owns the actual queue/matchmaking once a card is picked.
local function buildBattleMarker(mapFolder: Folder, position: Vector2)
	-- PLAZA_TOP_Y, not GROUND_TOP_Y -- this marker's position sits inside
	-- PathWest's footprint (a solid, elevated stone slab flush with the
	-- plaza, not open grass), so anything built at grass-level Y here was
	-- rendering embedded INSIDE that solid path part -- completely hidden,
	-- not just hard to see. The line itself was invisible this whole
	-- time too, just nobody noticed since its floating label (16 studs up,
	-- well above the path) is all that was ever actually visible.
	local baseY = PLAZA_TOP_Y
	local facingCF = CFrame.lookAt(Vector3.new(position.X, baseY, position.Y), Vector3.new(0, baseY, 0))

	local line = Instance.new("Part")
	line.Name = "BattleMarker_Line"
	line.Size = Vector3.new(BATTLE_LINE_LENGTH, 0.1, BATTLE_LINE_WIDTH)
	line.CFrame = facingCF * CFrame.new(0, 0.05, 0)
	line.Color = Color3.fromRGB(15, 15, 18)
	line.Material = Enum.Material.SmoothPlastic
	line.Anchored = true
	line.CanCollide = false
	line.TopSurface = Enum.SurfaceType.Smooth
	line.BottomSurface = Enum.SurfaceType.Smooth
	line.Parent = mapFolder

	-- Floating world-space title above the line -- same BillboardGui
	-- convention every other marker's label uses (addLabel), not a flat
	-- 2D screen element.
	addLabel(line, "LARP Battles", 16, UDim2.new(0, 180, 0, 32), BATTLE_MARKER_COLOR, false, LARGE_LABEL_MAX_DISTANCE)

	buildBattleCarpet(mapFolder, facingCF)
end

-- Small standalone signboard -- a post + gold-trimmed board with a 2-line
-- SurfaceGui (title + live countdown). NextUpdateCountdown.luau (client)
-- finds it by these exact names ("NextUpdateBoard_Board" -> "Display" ->
-- "CountdownLabel") and fills in/ticks the actual countdown -- this only
-- builds the empty board with placeholder text, same split every other
-- physical board/marker in this file uses.
local NEXT_UPDATE_BOARD_POSITION = Vector2.new(0.2770043909549713, 8.67017650604248)

local function buildNextUpdateBoard(mapFolder: Folder)
	local boardCF = CFrame.lookAt(Vector3.new(NEXT_UPDATE_BOARD_POSITION.X, PLAZA_TOP_Y, NEXT_UPDATE_BOARD_POSITION.Y), Vector3.new(0, PLAZA_TOP_Y, 0))
		* CFrame.Angles(0, math.rad(180), 0)

	local function place(name: string, size: Vector3, localOffset: Vector3, color: Color3, material: Enum.Material?): Part
		local part = Instance.new("Part")
		part.Name = "NextUpdateBoard_" .. name
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

	-- Frame has to sit BEHIND the board (positive local Z, away from the
	-- direction CFrame.lookAt's -Z front face points) so it reads as a
	-- backing border peeking out around the edges -- had this backwards
	-- (Frame in front of Board) originally, which made the solid Frame
	-- part physically block the board's own front face, hiding the
	-- SurfaceGui/text behind it entirely.
	place("Post", Vector3.new(0.6, 5, 0.6), Vector3.new(0, 2.5, 0), Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
	place("Frame", Vector3.new(6.6, 3.6, 0.5), Vector3.new(0, 6, 0.2), FOUNTAIN_GOLD, Enum.Material.Metal)
	local board = place("Board", Vector3.new(6, 3, 0.3), Vector3.new(0, 6, 0), Color3.fromRGB(20, 20, 26), Enum.Material.SmoothPlastic)

	local displayGui = Instance.new("SurfaceGui")
	displayGui.Name = "Display"
	displayGui.Face = Enum.NormalId.Front
	displayGui.LightInfluence = 0
	displayGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	displayGui.PixelsPerStud = 100
	displayGui.Parent = board

	local displayPadding = Instance.new("UIPadding")
	displayPadding.PaddingTop = UDim.new(0.1, 0)
	displayPadding.PaddingBottom = UDim.new(0.1, 0)
	displayPadding.PaddingLeft = UDim.new(0.05, 0)
	displayPadding.PaddingRight = UDim.new(0.05, 0)
	displayPadding.Parent = displayGui

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0.4, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.LuckiestGuy
	titleLabel.TextScaled = true
	titleLabel.Text = "NEXT UPDATE IN:"
	titleLabel.TextColor3 = FOUNTAIN_GOLD
	titleLabel.TextStrokeTransparency = 0
	titleLabel.Parent = displayGui

	-- Placeholder only -- NextUpdateCountdown.luau overwrites this every
	-- second with the live countdown.
	local countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name = "CountdownLabel"
	countdownLabel.Size = UDim2.new(1, 0, 0.5, 0)
	countdownLabel.Position = UDim2.new(0, 0, 0.45, 0)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Font = Enum.Font.LuckiestGuy
	countdownLabel.TextScaled = true
	countdownLabel.Text = "..."
	countdownLabel.TextColor3 = Color3.new(1, 1, 1)
	countdownLabel.TextStrokeTransparency = 0
	countdownLabel.Parent = displayGui
end

-- Bigger than before (was 5x6) -- text on a small board has a hard physical
-- ceiling on how large it can render no matter the font/wrap settings;
-- growing the board itself was the actually-reliable fix after several
-- font/wrap tweaks weren't enough on their own.
local LEADERBOARD_WIDTH = 6.5
local LEADERBOARD_HEIGHT = 7.5
local LEADERBOARD_DEPTH = 0.6
local LEADERBOARD_STAND_HEIGHT = 2
local LEADERBOARD_HEADER_HEIGHT = 1.3
local LEADERBOARD_HEADER_COLORS =
	{ Color3.fromRGB(60, 190, 100), Color3.fromRGB(85, 140, 235), Color3.fromRGB(200, 90, 220), Color3.fromRGB(230, 170, 60) }
local LEADERBOARD_BASE_HEIGHT = 1.2
local LEADERBOARD_FRAME_MARGIN = 0.5

-- Premium trophy-stand look: a wide gold pedestal, two gold side pillars,
-- and a gold backing frame peeking out around the dark screen -- the same
-- FOUNTAIN_GOLD used on the fountain/shop-stand finials, so the boards
-- read as part of the same "wealth" aesthetic instead of a plain
-- scoreboard. Still faces the plaza center (CFrame.lookAt).
-- Takes the board's final CFrame directly (not a cluster offsetIndex) --
-- the 3 general boards (Time/NetWorth/Rolls) still live in the row around
-- LEADERBOARD_CENTER (see Build()), but the 4th (Points, LARP Battles'
-- weekly leaderboard) stands next to the battle line instead, so it needs
-- its own independent placement, not another slot in that row.
-- `premium` (Points only) swaps the gold trim for icy diamond-white
-- (Glass material) and adds a spinning, sparkling diamond-shaped finial on
-- top -- same "catches the light, reads as alive" trick as the fountain
-- gem/stand finials -- so this one board visibly stands out from the other
-- 3's plainer gold trophy-stand look, matching how much more went into
-- LARP Battles as a feature.
local function buildLeaderboard(mapFolder: Folder, boardCF: CFrame, labelText: string, index: number, premium: boolean?)
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

	-- Icy diamond-white trim for the premium (Points) board instead of the
	-- other 3's gold, so the whole stand reads as diamond-themed, not just
	-- the small finial on top.
	local trimColor = premium and Color3.fromRGB(190, 235, 255) or FOUNTAIN_GOLD
	local trimMaterial = premium and Enum.Material.Glass or Enum.Material.Metal

	-- Wide pedestal base (replaces the old bare pole's footing).
	place("Base", Vector3.new(LEADERBOARD_WIDTH + 1.5, LEADERBOARD_BASE_HEIGHT, LEADERBOARD_DEPTH + 1.2), Vector3.new(0, LEADERBOARD_BASE_HEIGHT / 2, 0), trimColor, trimMaterial)

	-- Two side pillars, base top to board top -- reads as a trophy stand
	-- holding the screen up, not a single bare pole.
	local pillarHeight = boardTopY - LEADERBOARD_BASE_HEIGHT
	local pillarCenterY = LEADERBOARD_BASE_HEIGHT + pillarHeight / 2
	local pillarX = LEADERBOARD_WIDTH / 2 + 0.35
	place("PillarLeft", Vector3.new(0.5, pillarHeight, 0.5), Vector3.new(-pillarX, pillarCenterY, 0), trimColor, trimMaterial)
	place("PillarRight", Vector3.new(0.5, pillarHeight, 0.5), Vector3.new(pillarX, pillarCenterY, 0), trimColor, trimMaterial)

	-- Backing frame, set back and larger than the screen so it peeks out
	-- as a border all the way around.
	place(
		"Frame",
		Vector3.new(LEADERBOARD_WIDTH + LEADERBOARD_FRAME_MARGIN * 2, LEADERBOARD_HEIGHT + LEADERBOARD_FRAME_MARGIN * 2, LEADERBOARD_DEPTH * 0.6),
		Vector3.new(0, boardCenterY, LEADERBOARD_DEPTH * 0.35),
		trimColor,
		trimMaterial
	)

	local board = place("Board", Vector3.new(LEADERBOARD_WIDTH, LEADERBOARD_HEIGHT, LEADERBOARD_DEPTH), Vector3.new(0, boardCenterY, 0), Color3.fromRGB(25, 25, 30), Enum.Material.SmoothPlastic)

	-- Rank rows, painted onto the board's front face. LeaderboardManager finds
	-- this by name ("Display" -> "Rows") and (re)creates one TextLabel row
	-- per ranked entry (up to top 100) on every refresh -- MapBuilder only
	-- builds the empty scrolling container, since a fixed row count can't
	-- fit 100 readable entries on a ~6.5x7.5 stud board.
	local displayGui = Instance.new("SurfaceGui")
	displayGui.Name = "Display"
	displayGui.Face = Enum.NormalId.Front
	displayGui.LightInfluence = 0
	displayGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	displayGui.PixelsPerStud = 100
	displayGui.Parent = board

	-- PaddingTop must clear the Header part's own height (1.3 of the
	-- board's 7.5 studs =~ 17%) plus a margin -- otherwise Row 1's text
	-- starts underneath/behind the Header part and the two SurfaceGuis' text
	-- visibly bleeds together (Roblox doesn't depth-sort SurfaceGui text
	-- against nearby geometry reliably when they're this close). Premium
	-- (Points) board reserves extra room below that for the "Resets in:
	-- ..." strip (see the ResetTimer part built further down).
	local displayPadding = Instance.new("UIPadding")
	displayPadding.PaddingTop = premium and UDim.new(0.30, 0) or UDim.new(0.22, 0)
	displayPadding.PaddingLeft = UDim.new(0.02, 0)
	displayPadding.PaddingRight = UDim.new(0.02, 0)
	displayPadding.PaddingBottom = UDim.new(0.02, 0)
	displayPadding.Parent = displayGui

	-- Reserved space at the very bottom for a pinned "Your Rank" line (see
	-- YOUR_RANK_FOOTER_HEIGHT below) -- same pattern big Roblox leaderboard
	-- games use, so a player can see where they stand without being in the
	-- visible top rows.
	local YOUR_RANK_FOOTER_HEIGHT = 70

	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Rows"
	rows.Size = UDim2.new(1, 0, 1, -YOUR_RANK_FOOTER_HEIGHT - 10)
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

	local footerDivider = Instance.new("Frame")
	footerDivider.Name = "YourRankDivider"
	footerDivider.Size = UDim2.new(1, 0, 0, 2)
	footerDivider.Position = UDim2.new(0, 0, 1, -YOUR_RANK_FOOTER_HEIGHT - 6)
	footerDivider.BackgroundColor3 = FOUNTAIN_GOLD
	footerDivider.BorderSizePixel = 0
	footerDivider.Parent = displayGui

	-- Placeholder text only -- MapBuilder never fills this in itself. Each
	-- client's own LocalScript (BoardRankLabels.luau) overwrites this Text
	-- locally with THAT player's own rank whenever PlayerRankUpdated fires
	-- (see LeaderboardManager.luau). Setting a property from a LocalScript
	-- doesn't replicate to the server or other clients, so every player
	-- looking at the same physical board sees their own rank painted here,
	-- not whoever last happened to trigger a refresh.
	local yourRankLabel = Instance.new("TextLabel")
	yourRankLabel.Name = "YourRankLabel"
	yourRankLabel.Size = UDim2.new(1, 0, 0, YOUR_RANK_FOOTER_HEIGHT)
	yourRankLabel.Position = UDim2.new(0, 0, 1, -YOUR_RANK_FOOTER_HEIGHT)
	yourRankLabel.BackgroundTransparency = 1
	yourRankLabel.TextColor3 = FOUNTAIN_GOLD
	yourRankLabel.TextStrokeTransparency = 0.5
	yourRankLabel.Font = Enum.Font.GothamBold
	yourRankLabel.TextScaled = true
	yourRankLabel.TextWrapped = true
	yourRankLabel.Text = "You: Unranked"
	yourRankLabel.Parent = displayGui

	local headerCenterY = boardCenterY + LEADERBOARD_HEIGHT / 2 - LEADERBOARD_HEADER_HEIGHT / 2
	local header = place(
		"Header",
		Vector3.new(LEADERBOARD_WIDTH, LEADERBOARD_HEADER_HEIGHT, LEADERBOARD_DEPTH + 0.05),
		Vector3.new(0, headerCenterY, 0),
		LEADERBOARD_HEADER_COLORS[index],
		Enum.Material.SmoothPlastic
	)

	-- Painted directly onto the header bar's Front face (SurfaceGui, not a
	-- floating BillboardGui) so the title reads as printed on the sign
	-- itself, and can never render at an odd depth/position relative to
	-- the board or bleed together with the neighboring boards' titles.
	local headerGui = Instance.new("SurfaceGui")
	headerGui.Name = "HeaderLabel"
	headerGui.Face = Enum.NormalId.Front
	headerGui.LightInfluence = 0
	-- Explicit (not relying on the default) -- a sharper texture so the
	-- text doesn't look blurry/illegible from a distance.
	headerGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	headerGui.PixelsPerStud = 100
	headerGui.Parent = header

	local headerPadding = Instance.new("UIPadding")
	headerPadding.PaddingLeft = UDim.new(0.03, 0)
	headerPadding.PaddingRight = UDim.new(0.03, 0)
	headerPadding.PaddingTop = UDim.new(0.05, 0)
	headerPadding.PaddingBottom = UDim.new(0.05, 0)
	headerPadding.Parent = headerGui

	local headerText = Instance.new("TextLabel")
	headerText.Size = UDim2.new(1, 0, 1, 0)
	headerText.BackgroundTransparency = 1
	-- Explicit false, not just relying on the default -- "TOP NET WORTH"
	-- (the longest title) was wrapping to 2 cramped, overlapping-looking
	-- lines in a header bar that's only 1 stud tall; forcing single-line
	-- means TextScaled shrinks the font instead of wrapping, same as the
	-- shorter "TOP TIME"/"TOP ROLLS" titles already rendered.
	headerText.TextWrapped = false
	headerText.TextColor3 = Color3.fromRGB(255, 255, 255)
	headerText.TextStrokeTransparency = 0
	headerText.TextStrokeColor3 = Color3.new(0, 0, 0)
	-- LuckiestGuy (the game's decorative theme font) reads fine at the
	-- large sizes used in the 2D screen UI, but on a small physical sign
	-- viewed from a distance/angle its bold rounded shapes and thick
	-- outline blur together. FredokaOne is still playful/rounded (not as
	-- plain as the GothamBold used for the dense row data below) but
	-- stays legible at this size -- best of both.
	headerText.Font = Enum.Font.FredokaOne
	headerText.TextScaled = true
	headerText.Text = labelText
	headerText.Parent = headerGui

	if premium then
		-- A cube rotated 45 deg around Y reads as a diamond/gem silhouette
		-- (not a plain glowing ball) -- taller than it is wide, like a cut
		-- gem, icy blue-white instead of gold so it doesn't just look like
		-- another gold bauble matching the fountain/finials.
		local finial =
			place("Finial", Vector3.new(1.1, 1.6, 1.1), Vector3.new(0, boardTopY + 1.5, 0), Color3.fromRGB(190, 235, 255), Enum.Material.Neon)
		finial.CFrame = finial.CFrame * CFrame.Angles(0, math.rad(45), 0)
		addContinuousSpin(finial, 45)
		addSparkle(finial, Color3.fromRGB(220, 245, 255), 14)

		-- "Resets in: ..." strip, right below the header -- own physical
		-- part + SurfaceGui (same pattern as Header, not squeezed into
		-- displayGui's shared padding) so it can't fight the header/rows
		-- for space. Placeholder text only -- LeaderboardManager.luau's
		-- refresh loop fills in the real countdown (this only exists on
		-- the Points board, the one category that actually resets).
		local resetTimerHeight = 0.6
		local resetTimer = place(
			"ResetTimer",
			Vector3.new(LEADERBOARD_WIDTH, resetTimerHeight, LEADERBOARD_DEPTH + 0.05),
			Vector3.new(0, headerCenterY - LEADERBOARD_HEADER_HEIGHT / 2 - resetTimerHeight / 2 - 0.05, 0),
			Color3.fromRGB(15, 15, 18),
			Enum.Material.SmoothPlastic
		)

		local resetTimerGui = Instance.new("SurfaceGui")
		resetTimerGui.Name = "ResetTimerLabel"
		resetTimerGui.Face = Enum.NormalId.Front
		resetTimerGui.LightInfluence = 0
		resetTimerGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		resetTimerGui.PixelsPerStud = 100
		resetTimerGui.Parent = resetTimer

		local resetTimerText = Instance.new("TextLabel")
		resetTimerText.Name = "Text"
		resetTimerText.Size = UDim2.new(1, 0, 1, 0)
		resetTimerText.BackgroundTransparency = 1
		resetTimerText.TextColor3 = Color3.fromRGB(190, 235, 255)
		resetTimerText.TextStrokeTransparency = 0
		resetTimerText.Font = Enum.Font.FredokaOne
		resetTimerText.TextScaled = true
		resetTimerText.Text = "Resets in: ..."
		resetTimerText.Parent = resetTimerGui
	end
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

-- Studs around each of GRASS_MARKER_POSITIONS kept clear of trees/bushes/
-- grass decor -- unlike VIP's marker (inside TREE_EXCLUSION_RADIUS, on the
-- protected plaza), these sit out on the open grass where
-- buildTrees/buildGrassBushes/buildGrassDecor scatter freely and could
-- otherwise spawn right on top of one.
local MARKER_EXCLUSION_RADIUS = 12

local function isBlocked(x: number, z: number): boolean
	if math.sqrt(x * x + z * z) <= TREE_EXCLUSION_RADIUS then
		return true
	end
	if isNearPath(x, z) then
		return true
	end

	for _, markerPosition in GRASS_MARKER_POSITIONS do
		local markerDx = x - markerPosition.X
		local markerDz = z - markerPosition.Y
		if math.sqrt(markerDx * markerDx + markerDz * markerDz) <= MARKER_EXCLUSION_RADIUS then
			return true
		end
	end

	return false
end

-- Small forest-floor clutter scattered near a subset of trees (bushes,
-- rock clusters, mushroom clusters, stumps) -- purely decorative filler so
-- the tree grid doesn't read as bare trunks-and-paths.
local TREE_DECOR_CHANCE = 0.65
local BUSH_COLOR = Color3.fromRGB(55, 140, 65)
local ROCK_COLOR = Color3.fromRGB(120, 120, 125)
local MUSHROOM_CAP_COLOR = Color3.fromRGB(200, 70, 70)
local MUSHROOM_STEM_COLOR = Color3.fromRGB(235, 225, 200)
local STUMP_COLOR = Color3.fromRGB(130, 95, 60)

local function addBush(parent: Folder, x: number, z: number)
	local diameter = random:NextNumber(2, 3.2)
	local bush = Instance.new("Part")
	bush.Name = "Bush"
	bush.Shape = Enum.PartType.Ball
	bush.Size = Vector3.new(diameter, diameter * 0.8, diameter)
	bush.CFrame = CFrame.new(x, diameter * 0.4, z)
	bush.Color = BUSH_COLOR
	bush.Material = Enum.Material.Grass
	bush.Anchored = true
	bush.CanCollide = false
	bush.Parent = parent
end

local function addRockCluster(parent: Folder, x: number, z: number)
	local count = random:NextInteger(2, 3)
	for _ = 1, count do
		local diameter = random:NextNumber(0.8, 1.6)
		local ox = random:NextNumber(-1, 1)
		local oz = random:NextNumber(-1, 1)
		local rock = Instance.new("Part")
		rock.Name = "Rock"
		rock.Size = Vector3.new(diameter, diameter * 0.7, diameter)
		rock.CFrame = CFrame.new(x + ox, diameter * 0.35, z + oz) * CFrame.Angles(0, random:NextNumber(0, math.pi * 2), 0)
		rock.Color = ROCK_COLOR
		rock.Material = Enum.Material.Slate
		rock.Anchored = true
		rock.CanCollide = false
		rock.Parent = parent
	end
end

local function addMushroomCluster(parent: Folder, x: number, z: number)
	local count = random:NextInteger(2, 4)
	for _ = 1, count do
		local ox = random:NextNumber(-1.2, 1.2)
		local oz = random:NextNumber(-1.2, 1.2)
		local stemHeight = random:NextNumber(0.5, 0.9)
		local stem = createCylinder("MushroomStem", 0.25, stemHeight, Vector3.new(x + ox, stemHeight / 2, z + oz), MUSHROOM_STEM_COLOR, Enum.Material.SmoothPlastic)
		stem.Parent = parent

		local capDiameter = random:NextNumber(0.5, 0.8)
		local cap = Instance.new("Part")
		cap.Name = "MushroomCap"
		cap.Shape = Enum.PartType.Ball
		cap.Size = Vector3.new(capDiameter, capDiameter * 0.6, capDiameter)
		cap.CFrame = CFrame.new(x + ox, stemHeight + capDiameter * 0.2, z + oz)
		cap.Color = MUSHROOM_CAP_COLOR
		cap.Material = Enum.Material.SmoothPlastic
		cap.Anchored = true
		cap.CanCollide = false
		cap.Parent = parent
	end
end

local function addStump(parent: Folder, x: number, z: number)
	local diameter = random:NextNumber(1.4, 2)
	local height = random:NextNumber(0.8, 1.2)
	local stump = createCylinder("Stump", diameter, height, Vector3.new(x, height / 2, z), STUMP_COLOR, Enum.Material.Wood)
	stump.Parent = parent
end

-- Picks one decor cluster type and places it a few studs off from the
-- trunk (never right on top of it).
local function addTreeDecor(parent: Folder, trunkX: number, trunkZ: number)
	local angle = random:NextNumber(0, math.pi * 2)
	local distance = random:NextNumber(3, 5.5)
	local x = trunkX + math.cos(angle) * distance
	local z = trunkZ + math.sin(angle) * distance

	local roll = random:NextNumber()
	if roll < 0.35 then
		addBush(parent, x, z)
	elseif roll < 0.6 then
		addRockCluster(parent, x, z)
	elseif roll < 0.85 then
		addMushroomCluster(parent, x, z)
	else
		addStump(parent, x, z)
	end
end

-- Real 3D model ("F Tree", placed directly in Workspace) cloned across the
-- same grid the procedural trees used to fill, replacing every single one
-- -- the ORIGINAL model becomes the very first tree placed (moved into
-- place, not left behind somewhere as a stray extra tree); every other
-- grid position gets a clone. Falls back to the old procedural trunk+
-- foliage per-position if the model isn't in Workspace.
local function buildTrees(mapFolder: Folder)
	local treesFolder = Instance.new("Folder")
	treesFolder.Name = "Trees"
	treesFolder.Parent = mapFolder

	-- Centered, symmetric grid (not an arbitrary corner-anchored one) so the
	-- rows line up evenly on both sides of the plaza.
	local steps = math.floor((2 * GRASS_PLACEMENT_BOUND) / TREE_GRID_SPACING)
	local gridStart = -steps / 2 * TREE_GRID_SPACING

	local fTreeTemplate = Workspace:FindFirstChild("F Tree")
	local fTreeIsModel = fTreeTemplate ~= nil and fTreeTemplate:IsA("Model")
	local templateUsed = false

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

			if fTreeIsModel then
				local treeModel = (not templateUsed) and fTreeTemplate or fTreeTemplate:Clone()
				templateUsed = true

				-- "F Tree"'s own native size is much bigger than the old
				-- procedural trees -- a 0.9-1.1x variance (right for the
				-- OLD trees, which were already sized correctly) barely
				-- touched it. This is a separate, much smaller multiplier
				-- specifically for this model, not `scale` above.
				local fTreeScale = random:NextNumber(0.04, 0.06)
				pcall(function()
					treeModel:ScaleTo(fTreeScale)
				end)

				treeModel:PivotTo(CFrame.new(x, GROUND_TOP_Y, z))

				-- Same GetBoundingBox lift as every other replaced model --
				-- the pivot isn't necessarily at the base.
				local boundingCFrame, boundingSize = treeModel:GetBoundingBox()
				local bottomY = boundingCFrame.Position.Y - boundingSize.Y / 2
				local liftNeeded = GROUND_TOP_Y - bottomY
				if liftNeeded ~= 0 then
					treeModel:PivotTo(treeModel:GetPivot() + Vector3.new(0, liftNeeded, 0))
				end

				for _, descendant in treeModel:GetDescendants() do
					if descendant:IsA("BasePart") then
						descendant.Anchored = true
					end
				end

				if treeModel ~= fTreeTemplate then
					treeModel.Parent = treesFolder
				end
			else
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

			if random:NextNumber() < TREE_DECOR_CHANCE then
				addTreeDecor(treesFolder, x, z)
			end
		end
	end
end

-- Stylized rounded bush -- a base sphere plus 2-3 smaller overlapping
-- lobes in a lighter shade, same "chunky primitive clump" trick most
-- Roblox tycoon/simulator games use for bushes (not a single flat disc,
-- not a sparse cloud-style puff-cluster -- the lobes stay tight/overlapping
-- so it reads as one rounded bush).
local GRASS_BUSH_COUNT = 45
local GRASS_BUSH_MIN_DIAMETER = 3
local GRASS_BUSH_MAX_DIAMETER = 4.5
local GRASS_BUSH_BASE_COLOR = Color3.fromRGB(45, 125, 55)
local GRASS_BUSH_HIGHLIGHT_COLOR = Color3.fromRGB(75, 170, 85)

local function addGrassBush(parent: Folder, x: number, z: number)
	local baseDiameter = random:NextNumber(GRASS_BUSH_MIN_DIAMETER, GRASS_BUSH_MAX_DIAMETER)
	local baseCenterY = baseDiameter * 0.42

	local base = Instance.new("Part")
	base.Name = "GrassBush"
	base.Shape = Enum.PartType.Ball
	base.Size = Vector3.new(baseDiameter, baseDiameter * 0.85, baseDiameter)
	base.CFrame = CFrame.new(x, baseCenterY, z)
	base.Color = GRASS_BUSH_BASE_COLOR
	base.Material = Enum.Material.Grass
	base.Anchored = true
	base.CanCollide = false
	base.Parent = parent

	local lobeCount = random:NextInteger(2, 3)
	for _ = 1, lobeCount do
		local lobeDiameter = baseDiameter * random:NextNumber(0.55, 0.75)
		local angle = random:NextNumber(0, math.pi * 2)
		local offset = baseDiameter * 0.28

		local lobe = Instance.new("Part")
		lobe.Name = "GrassBushLobe"
		lobe.Shape = Enum.PartType.Ball
		lobe.Size = Vector3.new(lobeDiameter, lobeDiameter * 0.85, lobeDiameter)
		lobe.CFrame = CFrame.new(x + math.cos(angle) * offset, baseCenterY + lobeDiameter * 0.15, z + math.sin(angle) * offset)
		lobe.Color = GRASS_BUSH_HIGHLIGHT_COLOR
		lobe.Material = Enum.Material.Grass
		lobe.Anchored = true
		lobe.CanCollide = false
		lobe.Parent = parent
	end
end

local function buildGrassBushes(mapFolder: Folder)
	local bushFolder = Instance.new("Folder")
	bushFolder.Name = "GrassBushes"
	bushFolder.Parent = mapFolder

	local placed = 0
	local attempts = 0
	while placed < GRASS_BUSH_COUNT and attempts < GRASS_BUSH_COUNT * 6 do
		attempts += 1
		local x = random:NextNumber(-GRASS_PLACEMENT_BOUND, GRASS_PLACEMENT_BOUND)
		local z = random:NextNumber(-GRASS_PLACEMENT_BOUND, GRASS_PLACEMENT_BOUND)
		if isBlocked(x, z) then
			continue
		end

		addGrassBush(bushFolder, x, z)
		placed += 1
	end
end

-- Loose flower patch (stem + bloom, no wooden planter box) -- scattered
-- freely across the grass, unlike the boxed planters which stay ringed
-- around the plaza.
local function addFlowerPatch(parent: Folder, x: number, z: number)
	local count = random:NextInteger(3, 5)
	for _ = 1, count do
		local ox = random:NextNumber(-1, 1)
		local oz = random:NextNumber(-1, 1)
		local stemHeight = random:NextNumber(0.6, 1)
		local stem = createCylinder("FlowerStem", 0.12, stemHeight, Vector3.new(x + ox, stemHeight / 2, z + oz), Color3.fromRGB(60, 130, 60), Enum.Material.Grass)
		stem.Parent = parent

		local bloomDiameter = random:NextNumber(0.6, 0.9)
		local bloom = Instance.new("Part")
		bloom.Name = "FlowerBloom"
		bloom.Shape = Enum.PartType.Ball
		bloom.Size = Vector3.new(bloomDiameter, bloomDiameter, bloomDiameter)
		bloom.CFrame = CFrame.new(x + ox, stemHeight, z + oz)
		bloom.Color = FLOWER_COLORS[random:NextInteger(1, #FLOWER_COLORS)]
		bloom.Material = Enum.Material.SmoothPlastic
		bloom.Anchored = true
		bloom.CanCollide = false
		bloom.Parent = parent
	end
end

-- More forest-floor clutter (mushroom clusters, loose flower patches, rock
-- clusters), scattered across the whole grass field the same way
-- buildGrassBushes is -- the map felt too sparse/empty with just bushes
-- and grid-planted trees.
local GRASS_DECOR_COUNT = 40

local function buildGrassDecor(mapFolder: Folder)
	local decorFolder = Instance.new("Folder")
	decorFolder.Name = "GrassDecor"
	decorFolder.Parent = mapFolder

	local placed = 0
	local attempts = 0
	while placed < GRASS_DECOR_COUNT and attempts < GRASS_DECOR_COUNT * 6 do
		attempts += 1
		local x = random:NextNumber(-GRASS_PLACEMENT_BOUND, GRASS_PLACEMENT_BOUND)
		local z = random:NextNumber(-GRASS_PLACEMENT_BOUND, GRASS_PLACEMENT_BOUND)
		if isBlocked(x, z) then
			continue
		end

		local roll = random:NextNumber()
		if roll < 0.4 then
			addMushroomCluster(decorFolder, x, z)
		elseif roll < 0.75 then
			addFlowerPatch(decorFolder, x, z)
		else
			addRockCluster(decorFolder, x, z)
		end

		placed += 1
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

local function buildLampPost(mapFolder: Folder, position: Vector3, index: number)
	local pole = createCylinder(
		"LampPole" .. index,
		0.5,
		LAMP_POST_HEIGHT,
		position + Vector3.new(0, LAMP_POST_HEIGHT / 2, 0),
		LAMP_POLE_COLOR,
		Enum.Material.Metal
	)
	pole.Parent = mapFolder

	local head = Instance.new("Part")
	head.Name = "LampHead" .. index
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.4, 1.4, 1.4)
	head.CFrame = CFrame.new(position.X, position.Y + LAMP_POST_HEIGHT, position.Z)
	head.Color = LAMP_GLOW_COLOR
	head.Material = Enum.Material.Neon
	head.Anchored = true
	head.CanCollide = false
	head.Parent = mapFolder

	local light = Instance.new("PointLight")
	light.Color = LAMP_GLOW_COLOR
	light.Range = 18
	light.Brightness = 2
	light.Parent = head
end

-- 2 lamp posts per side per path (16 total) -- flanks the previously bare
-- stretches between the plaza and the map's edge.
local function buildLampPosts(mapFolder: Folder)
	local axes = {
		{ dx = 1, dz = 0 },
		{ dx = -1, dz = 0 },
		{ dx = 0, dz = 1 },
		{ dx = 0, dz = -1 },
	}

	local index = 0
	for _, axis in axes do
		local perpDx = -axis.dz
		local perpDz = axis.dx
		for _, distance in LAMP_POST_ABS_DISTANCES do
			for _, side in { 1, -1 } do
				index += 1
				local x = axis.dx * distance + perpDx * LAMP_POST_OFFSET * side
				local z = axis.dz * distance + perpDz * LAMP_POST_OFFSET * side
				buildLampPost(mapFolder, Vector3.new(x, GROUND_TOP_Y, z), index)
			end
		end
	end
end

local function buildPlanter(mapFolder: Folder, angleDegrees: number, index: number)
	local x, z = polarToXZ(PLANTER_RADIUS, angleDegrees)

	local boxHeight = 1.2
	local box = createBlock(
		"PlanterBox" .. index,
		Vector3.new(3, boxHeight, 3),
		Vector3.new(x, GROUND_TOP_Y + boxHeight / 2, z),
		PLANTER_BOX_COLOR,
		Enum.Material.WoodPlanks
	)
	box.Parent = mapFolder

	local soilY = GROUND_TOP_Y + boxHeight
	for i = 1, 5 do
		local fx = x + random:NextNumber(-1, 1)
		local fz = z + random:NextNumber(-1, 1)
		local stemHeight = random:NextNumber(0.8, 1.3)

		local stem = createCylinder(
			"PlanterStem" .. index .. "_" .. i,
			0.15,
			stemHeight,
			Vector3.new(fx, soilY + stemHeight / 2, fz),
			Color3.fromRGB(60, 130, 60),
			Enum.Material.Grass
		)
		stem.Parent = mapFolder

		local bloom = Instance.new("Part")
		bloom.Name = "PlanterBloom" .. index .. "_" .. i
		bloom.Shape = Enum.PartType.Ball
		bloom.Size = Vector3.new(0.9, 0.9, 0.9)
		bloom.CFrame = CFrame.new(fx, soilY + stemHeight, fz)
		bloom.Color = FLOWER_COLORS[random:NextInteger(1, #FLOWER_COLORS)]
		bloom.Material = Enum.Material.SmoothPlastic
		bloom.Anchored = true
		bloom.CanCollide = false
		bloom.Parent = mapFolder
	end
end

-- 4 planter clusters on the diagonals between the cardinal paths.
local function buildPlanters(mapFolder: Folder)
	for index, angle in PLANTER_ANGLES do
		buildPlanter(mapFolder, angle, index)
	end
end

local function buildAmbientSparkles(mapFolder: Folder)
	local sparkleFolder = Instance.new("Folder")
	sparkleFolder.Name = "AmbientSparkles"
	sparkleFolder.Parent = mapFolder

	for i = 1, AMBIENT_SPARKLE_COUNT do
		local angle = (i / AMBIENT_SPARKLE_COUNT) * 360
		local x, z = polarToXZ(AMBIENT_SPARKLE_RADIUS, angle)

		local anchor = Instance.new("Part")
		anchor.Name = "SparkleAnchor"
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.CFrame = CFrame.new(x, PLAZA_TOP_Y + 1, z)
		anchor.Transparency = 1
		anchor.CanCollide = false
		anchor.Anchored = true
		anchor.Parent = sparkleFolder

		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(FOUNTAIN_GOLD)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Lifetime = NumberRange.new(2.5, 4)
		emitter.Rate = 2
		emitter.Speed = NumberRange.new(0.5, 1)
		emitter.SpreadAngle = Vector2.new(20, 20)
		emitter.Acceleration = Vector3.new(0, 1.5, 0)
		emitter.LightEmission = 0.8
		emitter.Parent = anchor
	end
end

-- Brighter/more saturated Lighting + a mild ColorCorrection boost, plus
-- Bloom/SunRays -- Roblox's default look is fairly flat/realistic; this is
-- the cheap, asset-free way to push it toward a glossier "premium" pop
-- (the gold accents/Neon parts scattered around the map bloom noticeably
-- now instead of reading flat).
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

	local bloom = Lighting:FindFirstChild("WealthRNG_Bloom")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "WealthRNG_Bloom"
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.4
	bloom.Size = 24
	bloom.Threshold = 1.4

	local sunRays = Lighting:FindFirstChild("WealthRNG_SunRays")
	if not sunRays then
		sunRays = Instance.new("SunRaysEffect")
		sunRays.Name = "WealthRNG_SunRays"
		sunRays.Parent = Lighting
	end
	sunRays.Intensity = 0.15
	sunRays.Spread = 0.5
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
	-- Fountain itself is built later (see "M Fountain" near Robux Man/
	-- Meshy Stadium below) -- a real 3D model replaces the procedural
	-- buildFountain centerpiece, with buildFountain as a fallback if that
	-- model isn't in Workspace.
	-- The square water pool that used to sit here was removed entirely.
	-- Benches themselves are built later (see "S Bench" near Robux Man/
	-- Meshy Stadium below) -- real 3D model clones replace the procedural
	-- buildBench, with buildBench as a per-angle fallback if that model
	-- isn't in Workspace.

	-- Both shop kiosks are built later (see "Original Shop"/"Pots Shop"
	-- near Robux Man/Meshy Stadium below) -- real 3D models replace the
	-- procedural buildStand kiosk for both, with buildStand as a fallback
	-- if either model isn't in Workspace.
	buildIndexPedestal(mapFolder, INDEX_STAND_POSITION, INDEX_STAND_LABEL, "CatalogPrompt")
	buildFloorMarker(mapFolder, "VIPMarker_Disk", VIP_MARKER_POSITION, PLAZA_TOP_Y, VIP_MARKER_COLOR, VIP_MARKER_LABEL, Color3.fromRGB(255, 221, 0))
	buildFloorMarker(mapFolder, "CodesMarker_Disk", CODES_MARKER_POSITION, PLAZA_TOP_Y, CODES_MARKER_COLOR, CODES_MARKER_LABEL, Color3.fromRGB(200, 255, 230))
	buildFloorMarker(
		mapFolder,
		"GroupRewardsMarker_Disk",
		GROUP_REWARDS_MARKER_POSITION,
		GROUND_TOP_Y,
		GROUP_REWARDS_MARKER_COLOR,
		GROUP_REWARDS_MARKER_LABEL,
		Color3.fromRGB(150, 205, 255),
		true,
		LARGE_LABEL_MAX_DISTANCE
	)
	buildFloorMarker(
		mapFolder,
		"DailyRewardsMarker_Disk",
		DAILY_REWARDS_MARKER_POSITION,
		GROUND_TOP_Y,
		DAILY_REWARDS_MARKER_COLOR,
		DAILY_REWARDS_MARKER_LABEL,
		Color3.fromRGB(255, 160, 160),
		true,
		LARGE_LABEL_MAX_DISTANCE
	)
	buildFloorMarker(
		mapFolder,
		"LuckyRollMarker_Disk",
		LUCKY_ROLL_MARKER_POSITION,
		GROUND_TOP_Y,
		LUCKY_ROLL_MARKER_COLOR,
		"",
		Color3.fromRGB(220, 180, 255),
		true
	)
	buildBattleMarker(mapFolder, BATTLE_MARKER_POSITION)
	buildNextUpdateBoard(mapFolder)

	local leaderboardClusterCF = CFrame.lookAt(Vector3.new(LEADERBOARD_CENTER.X, PLAZA_TOP_Y, LEADERBOARD_CENTER.Y), Vector3.new(0, PLAZA_TOP_Y, 0))
	for index, labelText in LEADERBOARD_LABELS do
		local offsetIndex = index - 2 -- 3 boards -> -1, 0, 1
		local boardCF = leaderboardClusterCF * CFrame.new(offsetIndex * LEADERBOARD_SPACING, 0, 0)
		buildLeaderboard(mapFolder, boardCF, labelText, index)
	end

	-- "TOP POINTS" (LARP Battles' own weekly leaderboard) -- BoardIndex 4
	-- still matches LeaderboardManager's categories table. No extra
	-- rotation on top of the standard "face the plaza center" orientation
	-- -- that twist was turning the board enough that its gold Frame (set
	-- back slightly from the actual screen) ended up occluding the
	-- SurfaceGui text instead of just peeking out around it.
	local pointsBoardCF =
		CFrame.lookAt(Vector3.new(LEADERBOARD_POINTS_POSITION.X, PLAZA_TOP_Y, LEADERBOARD_POINTS_POSITION.Y), Vector3.new(0, PLAZA_TOP_Y, 0))
	buildLeaderboard(mapFolder, pointsBoardCF, "TOP POINTS", 4, true)

	buildTrees(mapFolder)
	buildGrassBushes(mapFolder)
	buildGrassDecor(mapFolder)
	buildClouds(mapFolder)
	buildLampPosts(mapFolder)
	buildPlanters(mapFolder)
	buildAmbientSparkles(mapFolder)
	applyCartoonLighting()

	mapFolder.Parent = Workspace

	-- "Robux Man" -- a model placed directly in Workspace (not part of the
	-- generated mapFolder, so it isn't destroyed/rebuilt above) -- pivoted
	-- to the given plaza position every Build() call, at a fixed rotation
	-- (not "preserve current rotation + drift" -- that would keep spinning
	-- further every single server restart since Build() runs on every one).
	-- Also strips its floating name -- Humanoid's default nameplate/health
	-- display disabled, and any custom BillboardGui nametag destroyed, in
	-- case the model came with one baked in.
	local robuxMan = Workspace:FindFirstChild("Robux Man")
	if robuxMan and robuxMan:IsA("Model") then
		local robuxManPosition = Vector3.new(-52.56655502319336, 3.6999990940093994, -11.975993156433105)
		-- Faces the fountain (plaza center, (0, ..., 0) -- see buildFountain)
		-- via CFrame.lookAt instead of a hand-picked angle, same convention
		-- the leaderboard boards already use to face the plaza.
		robuxMan:PivotTo(CFrame.lookAt(robuxManPosition, Vector3.new(0, robuxManPosition.Y, 0)))

		local humanoid = robuxMan:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end

		for _, descendant in robuxMan:GetDescendants() do
			if descendant:IsA("BillboardGui") then
				descendant:Destroy()
			end
		end

		-- Talk trigger -- just the prompt itself; the actual bubble-chat
		-- greeting + branching reply choices are RobuxManManager.luau's job
		-- (it listens for this exact prompt name), same split every other
		-- physical trigger in this file uses (MapBuilder builds/places
		-- things, a Manager owns what happens when you interact with them).
		-- Attached to the HumanoidRootPart/PrimaryPart if present (a rigged
		-- character model), else just its first BasePart.
		local promptAnchor = robuxMan.PrimaryPart or robuxMan:FindFirstChild("HumanoidRootPart") or robuxMan:FindFirstChildWhichIsA("BasePart")
		if promptAnchor and not promptAnchor:FindFirstChild("RobuxManPrompt") then
			local talkPrompt = Instance.new("ProximityPrompt")
			talkPrompt.Name = "RobuxManPrompt"
			talkPrompt.ActionText = "Talk"
			talkPrompt.ObjectText = "Robux Man"
			talkPrompt.MaxActivationDistance = 10
			talkPrompt.RequiresLineOfSight = false
			talkPrompt.Parent = promptAnchor
		end
	end

	-- "sf arena" -- another model placed directly in Workspace (same deal
	-- as "Robux Man" above -- not part of the generated mapFolder, so it
	-- survives the destroy/rebuild above) -- pivoted to the given LARP
	-- Battles-area position every Build() call. Keeps whatever rotation it
	-- already has -- no specific facing was asked for, unlike Robux Man.
	local sfArena = Workspace:FindFirstChild("sf arena")
	if sfArena and sfArena:IsA("Model") then
		local currentPivot = sfArena:GetPivot()
		sfArena:PivotTo(CFrame.new(-84.1661148071289, 4.1999993324279785, -0.3685937225818634) * currentPivot.Rotation)
	end

	-- "Original Shop" -- a real 3D model placed directly in Workspace
	-- (same deal as "Robux Man"/"sf arena" above), replacing the
	-- procedural buildStand kiosk for the main Assets/Invest shop -- same
	-- position/facing AND the exact same "ShopPrompt" ProximityPrompt
	-- AssetShopPanel.luau already listens for, just a different building.
	-- Falls back to the old procedural kiosk if this model hasn't been
	-- added to Workspace yet, so the Shop's trigger is never just silently
	-- missing.
	local originalShop = Workspace:FindFirstChild("Original Shop")
	if originalShop and originalShop:IsA("Model") then
		local shopCF = CFrame.lookAt(Vector3.new(STAND_POSITION.X, PLAZA_TOP_Y, STAND_POSITION.Y), Vector3.new(0, PLAZA_TOP_Y, 0))
		originalShop:PivotTo(shopCF)

		-- The model's pivot isn't necessarily at its base -- placing it
		-- with Y = PLAZA_TOP_Y sank half of it into the plaza floor
		-- (pivot sitting mid-height, not at the bottom). GetBoundingBox
		-- gives the model's real extents regardless of where its pivot is,
		-- so this lifts it by exactly however much is needed for its
		-- actual BOTTOM to rest on PLAZA_TOP_Y, instead of guessing a
		-- fixed offset that'd only happen to be right for this one model.
		local boundingCFrame, boundingSize = originalShop:GetBoundingBox()
		local bottomY = boundingCFrame.Position.Y - boundingSize.Y / 2
		local liftNeeded = PLAZA_TOP_Y - bottomY
		if liftNeeded ~= 0 then
			originalShop:PivotTo(originalShop:GetPivot() + Vector3.new(0, liftNeeded, 0))
		end

		for _, descendant in originalShop:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end

		-- Dedicated invisible anchor at a KNOWN, sensible spot (the shop's
		-- own position, out front toward the plaza) instead of trusting an
		-- arbitrary BasePart found somewhere inside the model -- whichever
		-- part FindFirstChildWhichIsA happened to land on could be
		-- anywhere in a model this size (back wall, roof, etc.), making
		-- the real trigger distance nothing like what it visually looked
		-- like standing "right in front of" the building.
		-- No "already exists" guard needed here (unlike originalShop's own
		-- state above) -- mapFolder is destroyed and rebuilt from scratch
		-- on every single Build() call, so this anchor is always freshly
		-- created, never stale/duplicated.
		local shopPromptAnchor = Instance.new("Part")
		shopPromptAnchor.Name = "ShopPromptAnchor"
		shopPromptAnchor.Size = Vector3.new(1, 1, 1)
		shopPromptAnchor.CFrame = shopCF * CFrame.new(0, 2, -2)
		shopPromptAnchor.Anchored = true
		shopPromptAnchor.CanCollide = false
		shopPromptAnchor.Transparency = 1
		shopPromptAnchor.Parent = mapFolder

		local shopPrompt = Instance.new("ProximityPrompt")
		shopPrompt.Name = "ShopPrompt"
		shopPrompt.ActionText = "Open Shop"
		shopPrompt.ObjectText = STAND_LABEL
		shopPrompt.MaxActivationDistance = 15
		shopPrompt.RequiresLineOfSight = false
		shopPrompt.Parent = shopPromptAnchor

		addLabel(shopPromptAnchor, STAND_LABEL, 10, UDim2.new(0, 140, 0, 30), Color3.fromRGB(255, 255, 255))
	else
		buildStand(mapFolder, STAND_POSITION, 1, STAND_ROOF_COLOR, STAND_LABEL, "ShopPrompt")
	end

	-- "Pots Shop" -- same deal as "Original Shop" above, replacing the
	-- procedural buildStand kiosk for the Potions stand with a real 3D
	-- model placed directly in Workspace. Same position/facing AND the
	-- exact same "PotionShopPrompt" ProximityPrompt PotionShopPanel.luau
	-- already listens for. Falls back to the old procedural kiosk if this
	-- model hasn't been added to Workspace yet.
	local potsShop = Workspace:FindFirstChild("Pots Shop")
	if potsShop and potsShop:IsA("Model") then
		local potsShopCF = CFrame.lookAt(Vector3.new(POTION_STAND_POSITION.X, PLAZA_TOP_Y, POTION_STAND_POSITION.Y), Vector3.new(0, PLAZA_TOP_Y, 0))
		potsShop:PivotTo(potsShopCF)

		-- Same GetBoundingBox lift as "Original Shop" -- the model's pivot
		-- isn't necessarily at its base, so this lifts it by exactly
		-- however much is needed for its actual bottom to rest on
		-- PLAZA_TOP_Y instead of guessing a fixed offset.
		local potsBoundingCFrame, potsBoundingSize = potsShop:GetBoundingBox()
		local potsBottomY = potsBoundingCFrame.Position.Y - potsBoundingSize.Y / 2
		local potsLiftNeeded = PLAZA_TOP_Y - potsBottomY
		if potsLiftNeeded ~= 0 then
			potsShop:PivotTo(potsShop:GetPivot() + Vector3.new(0, potsLiftNeeded, 0))
		end

		for _, descendant in potsShop:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end

		-- Dedicated invisible anchor (same reasoning as ShopPromptAnchor
		-- above -- an arbitrary Part found inside the model could be
		-- anywhere, making the real trigger distance nothing like what it
		-- visually looks like standing in front of the building).
		local potsShopPromptAnchor = Instance.new("Part")
		potsShopPromptAnchor.Name = "PotsShopPromptAnchor"
		potsShopPromptAnchor.Size = Vector3.new(1, 1, 1)
		potsShopPromptAnchor.CFrame = potsShopCF * CFrame.new(0, 2, -2)
		potsShopPromptAnchor.Anchored = true
		potsShopPromptAnchor.CanCollide = false
		potsShopPromptAnchor.Transparency = 1
		potsShopPromptAnchor.Parent = mapFolder

		local potsShopPrompt = Instance.new("ProximityPrompt")
		potsShopPrompt.Name = "PotionShopPrompt"
		potsShopPrompt.ActionText = "Open Shop"
		potsShopPrompt.ObjectText = POTION_STAND_LABEL
		potsShopPrompt.MaxActivationDistance = 15
		potsShopPrompt.RequiresLineOfSight = false
		potsShopPrompt.Parent = potsShopPromptAnchor

		addLabel(potsShopPromptAnchor, POTION_STAND_LABEL, 10, UDim2.new(0, 140, 0, 30), Color3.fromRGB(255, 255, 255))
	else
		buildStand(mapFolder, POTION_STAND_POSITION, 2, POTION_STAND_ROOF_COLOR, POTION_STAND_LABEL, "PotionShopPrompt")
	end

	-- "M Fountain" -- a real 3D model placed directly in Workspace,
	-- replacing the procedural buildFountain centerpiece at the plaza's
	-- exact center (0, PLAZA_TOP_Y, 0) -- same GetBoundingBox lift/anchor
	-- treatment as the shop models above. Purely decorative (no
	-- ProximityPrompt, unlike the shops), so no anchor/prompt needed --
	-- keeps whatever rotation it already has, same as sf arena/Meshy
	-- Stadium. Falls back to the old procedural fountain if this model
	-- hasn't been added to Workspace yet.
	local mFountain = Workspace:FindFirstChild("M Fountain")
	if mFountain and mFountain:IsA("Model") then
		local currentPivot = mFountain:GetPivot()
		mFountain:PivotTo(CFrame.new(0, PLAZA_TOP_Y, 0) * currentPivot.Rotation)

		local fountainBoundingCFrame, fountainBoundingSize = mFountain:GetBoundingBox()
		local fountainBottomY = fountainBoundingCFrame.Position.Y - fountainBoundingSize.Y / 2
		local fountainLiftNeeded = PLAZA_TOP_Y - fountainBottomY
		if fountainLiftNeeded ~= 0 then
			mFountain:PivotTo(mFountain:GetPivot() + Vector3.new(0, fountainLiftNeeded, 0))
		end

		for _, descendant in mFountain:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
	else
		buildFountain(mapFolder)
	end

	-- "S Bench" -- a real 3D model placed directly in Workspace, cloned 4x
	-- (BENCH_ANGLES, same closer BENCH_RADIUS as the procedural fallback)
	-- around the fountain. The ORIGINAL model becomes the first bench
	-- (moved into place, not left behind somewhere as an unused template);
	-- 3 clones (parented into mapFolder, so they're destroyed/rebuilt each
	-- Build() call same as everything else generated) fill the rest. Falls
	-- back to the old procedural buildBench per-angle if this model isn't
	-- in Workspace.
	local sBenchTemplate = Workspace:FindFirstChild("S Bench")
	if sBenchTemplate and sBenchTemplate:IsA("Model") then
		for index, angleDegrees in BENCH_ANGLES do
			local benchModel = (index == 1) and sBenchTemplate or sBenchTemplate:Clone()
			local x, z = polarToXZ(BENCH_RADIUS, angleDegrees)
			-- Extra 180-degree spin -- the model's own "front" faces the
			-- opposite way CFrame.lookAt assumes, same fix buildBench
			-- itself already needed (see its own comment above).
			local benchCF = CFrame.lookAt(Vector3.new(x, PLAZA_TOP_Y, z), Vector3.new(0, PLAZA_TOP_Y, 0)) * CFrame.Angles(0, math.rad(180), 0)
			benchModel:PivotTo(benchCF)

			-- Same GetBoundingBox lift as every other replaced model above.
			local boundingCFrame, boundingSize = benchModel:GetBoundingBox()
			local bottomY = boundingCFrame.Position.Y - boundingSize.Y / 2
			local liftNeeded = PLAZA_TOP_Y - bottomY
			if liftNeeded ~= 0 then
				benchModel:PivotTo(benchModel:GetPivot() + Vector3.new(0, liftNeeded, 0))
			end

			for _, descendant in benchModel:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
				end
			end

			if benchModel ~= sBenchTemplate then
				benchModel.Name = "S Bench" .. index
				benchModel.Parent = mapFolder
			end
		end
	else
		for index, angleDegrees in BENCH_ANGLES do
			buildBench(mapFolder, angleDegrees, index)
		end
	end

	-- "Meshy Stadium" -- another model placed directly in Workspace (same
	-- deal as "Robux Man"/"sf arena" above). Keeps whatever rotation it
	-- already has -- no specific facing was asked for. Also force-anchors
	-- every BasePart under it -- imported meshes routinely come in with
	-- Anchored = false on some/all of their parts, so a player walking into
	-- it shoves it around like a loose physics prop instead of behaving as
	-- solid scenery.
	local meshyStadium = Workspace:FindFirstChild("Meshy Stadium")
	if meshyStadium and meshyStadium:IsA("Model") then
		local currentPivot = meshyStadium:GetPivot()
		meshyStadium:PivotTo(CFrame.new(-32.52312088012695, 4.1999993324279785, -34.600303649902344) * currentPivot.Rotation)

		for _, descendant in meshyStadium:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end

		-- Floating 3D info text above the model -- initial text only (the
		-- real-time stock count) is StadiumOfferManager.luau's job (it
		-- finds this exact BillboardGui/TextLabel by name and edits .Text
		-- directly whenever the shared stock pool changes -- a plain
		-- Instance property edit already replicates to every client, no
		-- remote needed for a world-space label like this one).
		local promptAnchor = meshyStadium.PrimaryPart or meshyStadium:FindFirstChildWhichIsA("BasePart")
		if promptAnchor and not promptAnchor:FindFirstChild("StadiumInfoLabel") then
			local billboard = Instance.new("BillboardGui")
			billboard.Name = "StadiumInfoLabel"
			billboard.Size = UDim2.new(0, 170, 0, 63)
			billboard.StudsOffset = Vector3.new(0, 9, 0)
			billboard.MaxDistance = LARGE_LABEL_MAX_DISTANCE
			billboard.Adornee = promptAnchor
			billboard.Parent = promptAnchor

			local stockLine = Instance.new("TextLabel")
			stockLine.Name = "StockLine"
			stockLine.Size = UDim2.new(1, 0, 1 / 3, 0)
			stockLine.Position = UDim2.new(0, 0, 0, 0)
			stockLine.BackgroundTransparency = 1
			stockLine.Font = Enum.Font.LuckiestGuy
			stockLine.TextScaled = true
			stockLine.Text = string.format("STOCK %d/%d", StadiumOfferConfig.TotalStock, StadiumOfferConfig.TotalStock)
			stockLine.TextColor3 = Color3.fromRGB(255, 205, 90)
			stockLine.TextStrokeTransparency = 0
			stockLine.Parent = billboard

			local exclusiveLine = Instance.new("TextLabel")
			exclusiveLine.Name = "ExclusiveLine"
			exclusiveLine.Size = UDim2.new(1, 0, 1 / 3, 0)
			exclusiveLine.Position = UDim2.new(0, 0, 1 / 3, 0)
			exclusiveLine.BackgroundTransparency = 1
			exclusiveLine.Font = Enum.Font.LuckiestGuy
			exclusiveLine.TextScaled = true
			exclusiveLine.Text = "EXCLUSIVE"
			exclusiveLine.TextColor3 = Color3.fromRGB(200, 120, 255)
			exclusiveLine.TextStrokeTransparency = 0
			exclusiveLine.Parent = billboard

			local nameLine = Instance.new("TextLabel")
			nameLine.Name = "NameLine"
			nameLine.Size = UDim2.new(1, 0, 1 / 3, 0)
			nameLine.Position = UDim2.new(0, 0, 2 / 3, 0)
			nameLine.BackgroundTransparency = 1
			nameLine.Font = Enum.Font.LuckiestGuy
			nameLine.TextScaled = true
			nameLine.Text = "SOL STADIUM"
			nameLine.TextColor3 = Color3.fromRGB(80, 220, 110)
			nameLine.TextStrokeTransparency = 0
			nameLine.Parent = billboard
		end
	end

	-- Invisible proximity anchor for StadiumOfferPanel.luau's popup --
	-- parented into mapFolder (unlike the stadium model itself, which lives
	-- directly in Workspace) since it's just a plain generated marker, same
	-- as every other *Marker_Disk part, safe to destroy/rebuild every
	-- Build() call.
	local stadiumOfferMarker = Instance.new("Part")
	stadiumOfferMarker.Name = "StadiumOfferMarker"
	stadiumOfferMarker.Size = Vector3.new(1, 1, 1)
	stadiumOfferMarker.CFrame = CFrame.new(-32.52312088012695, PLAZA_TOP_Y, -34.600303649902344)
	stadiumOfferMarker.Anchored = true
	stadiumOfferMarker.CanCollide = false
	stadiumOfferMarker.Transparency = 1
	stadiumOfferMarker.Parent = mapFolder

	print("[MapBuilder] Hub map built under Workspace.Map")
end

function MapBuilder.BuildIfMissing()
	if Workspace:FindFirstChild("Map") then
		return
	end
	MapBuilder.Build()
end

return MapBuilder
