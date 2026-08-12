-- Endless Mode's wave enemies -- simple prototype mobs (plain blocks, no
-- Humanoid/pathfinding yet, just a straight-line TweenService walk since the
-- claimed plot is flat open ground with nothing to path around) that spawn
-- near the STREET (the front of the plot). Mobs now have real HP
-- (EndlessModeMobRegistry) -- Damage-role buildings and Spawner-role allies
-- (PetManager.luau / EndlessModeAllyManager.luau) can kill one mid-walk,
-- before it ever reaches anything.
--
-- Target priority: any of the owner's placed Estates still alive
-- (PetManager.GetAlivePlacedBuildings) are attacked FIRST -- each mob picks
-- the nearest one to its own current position. Only once none are left
-- alive does a mob fall back to marching on the base door
-- (EndlessModeClaimManager.spawnBase's "Door" part).
--
-- Arriving at a Tank-role building (EndlessModeUnitRoleConfig) is different
-- from arriving at anything else: the mob STOPS there and chips away at it
-- every tick (the Tank never hits back -- pure soak, per explicit request)
-- instead of dealing one hit and despawning. If the Tank dies, the mob
-- re-targets from where it's standing (possibly another Tank, possibly not)
-- instead of just vanishing. Only MAX_CONCURRENT_TANK_ATTACKERS mobs can be
-- stuck on the SAME Tank at once -- since it never kills any of them itself,
-- an uncapped queue would only ever grow; anything arriving at an already-
-- full Tank just deals one hit and moves past instead of joining the queue.
--
-- Structured by WAVE now, not a flat repeating timer -- wave N spawns a
-- growing count of mobs (N+1..N+2, trickled evenly across that wave's own
-- 45 seconds), and every BOSS_WAVE_INTERVAL-th wave (10, 20, 30...) ALSO
-- spawns a Boss on top of the normal count, the instant that wave begins
-- (see tick/spawnMob below). "Wave" here is the OWNER's own ongoing
-- progress (WaveConfig.GetWaveForElapsedSeconds), not reset by (re)claiming.
--
-- Only spawns while the Right plot is actually claimed (EndlessModeClaimManager.
-- GetOwner) -- no owner means nothing to attack, so nothing spawns.
--
-- Self-runs on require -- no Init() call needed, same convention as every
-- other pure-background-watcher manager.

local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EndlessModeClaimManager = require(ServerScriptService.Managers.EndlessModeClaimManager)
local PetManager = require(ServerScriptService.Managers.PetManager)
local EndlessModeMobRegistry = require(ServerScriptService.Managers.EndlessModeMobRegistry)
local DataManager = require(ServerScriptService.Managers.DataManager)
local EndlessModeUnitRoleConfig = require(ReplicatedStorage.Modules.EndlessModeUnitRoleConfig)
local WaveConfig = require(ReplicatedStorage.Modules.WaveConfig)

local EndlessModeMobManager = {}

-- Right only for now -- matches EndlessModeClaimManager's own "Right only"
-- scope (see its SIDES comment).
local SIDE = "Right"

-- First mob doesn't show up the instant you claim -- gives the player a
-- moment to actually look around first, per explicit request.
local CLAIM_GRACE_SECONDS = 5
local TICK_SECONDS = 1
local MOB_SPEED_STUDS_PER_SECOND = 8
local MOB_SIZE = Vector3.new(2.5, 3, 2.5)
local MOB_COLOR = Color3.fromRGB(120, 20, 30)
-- Must match MapBuilder.buildEndlessModeArea's own ENDLESS_MODE_ROAD_WIDTH/2
-- -- mobs spawn just past the road edge (the plot's front), not relative to
-- the door anymore (the door moved to the back, see EndlessModeClaimManager.
-- spawnBase).
local ROAD_HALF_WIDTH = 10
local SPAWN_X_MIN_OFFSET = 3
local SPAWN_X_MAX_OFFSET = 12
local SPAWN_Z_JITTER = 30

-- Swarm Waves -- per explicit request, waves where a bunch of mobs show up
-- packed right next to each other need to happen OFTEN ("foarte dese"), so
-- Explosion-tier (AOE) Damage Estates -- which hit everything within
-- EndlessModeUnitRoleConfig.ExplosionAoeRadiusStuds of the blast -- have a
-- real, frequent edge over single-target Bullet/Laser Estates instead of an
-- occasional novelty. Every SWARM_WAVE_INTERVAL-th wave, the whole wave's
-- mobs spawn clustered tightly around ONE shared point (SWARM_CLUSTER_
-- JITTER_STUDS, well inside the AOE radius) instead of scattered across the
-- normal 60-stud-wide spawn strip, AND in a fast burst (SWARM_SPAWN_
-- INTERVAL_SECONDS) instead of trickled across the whole wave duration --
-- otherwise they'd still start together but drift apart/die individually
-- long before the rest of the pack ever spawned in.
local SWARM_WAVE_INTERVAL = 2
local SWARM_CLUSTER_JITTER_STUDS = 5
local SWARM_SPAWN_INTERVAL_SECONDS = 1

type Target = { Position: Vector3, PlacementId: string?, AssetId: string? }

-- A Tank with no counter-attack (per explicit request) can only ever LOSE
-- HP, never remove an attacker on its own -- without a cap, every mob that
-- ever targeted it would stay stuck there forever (Tanks never kill them),
-- so the number simultaneously ticking it would only ever grow, snowballing
-- into an unsurvivable damage rate no amount of HP could outlast. Capping
-- concurrent attackers bounds the worst-case sustained rate to a fixed,
-- predictable number (MAX_CONCURRENT_TANK_ATTACKERS * MobDamagePerTick /
-- TankTickSeconds) -- per explicit "top 3 Tanks should hold for several
-- waves" request, that's what actually makes a big HP number mean anything.
-- A mob that arrives at an already-full Tank just deals ONE hit and moves on
-- (same as a non-Tank building), instead of joining the queue.
local MAX_CONCURRENT_TANK_ATTACKERS = 3
local tankEngagementCounts: { [string]: number } = {}

local function tryEngageTank(placementId: string): boolean
	local count = tankEngagementCounts[placementId] or 0
	if count >= MAX_CONCURRENT_TANK_ATTACKERS then
		return false
	end
	tankEngagementCounts[placementId] = count + 1
	return true
end

local function disengageTank(placementId: string)
	local count = tankEngagementCounts[placementId] or 0
	tankEngagementCounts[placementId] = math.max(0, count - 1)
end

-- Forward-declared -- sendMobToTarget, onMobArrived, and meleeTank call each
-- other (mob "wins" a melee -> re-targets -> may walk into another Tank ->
-- melee again), so each needs to already be a visible local by the time the
-- others are defined, same idiom PetManager.luau's own refreshPets uses.
local sendMobToTarget: (BasePart, Player, string, Vector3) -> ()
local onMobArrived: (BasePart, Player, string, Target) -> ()
local meleeTank: (BasePart, Player, string, string) -> ()

local function findDoor(side: string): BasePart?
	local mapFolder = Workspace:FindFirstChild("Map")
	local baseFolder = mapFolder and mapFolder:FindFirstChild("EndlessMode_ClaimBase" .. side)
	local door = baseFolder and baseFolder:FindFirstChild("Door")
	return door and door:IsA("BasePart") and door or nil
end

-- Current mob damage for THIS owner -- scales with their own wave progress
-- (WaveConfig.GetWaveForElapsedSeconds off session.EndlessModeElapsedSeconds,
-- the same clock EndlessModeWaveManager.luau/the WAVE HUD use), not a flat
-- number for the whole run. Re-read fresh on every hit rather than cached
-- once per mob, since a mob can live across a wave boundary.
local function getMobDamage(owner: Player): number
	local session = DataManager.Get(owner)
	local wave = session and WaveConfig.GetWaveForElapsedSeconds(session.EndlessModeElapsedSeconds) or 1
	return EndlessModeUnitRoleConfig.GetMobDamageForWave(wave)
end

-- Nearest alive placed Estate to `fromPosition`, or the base door if the
-- owner has none standing right now. Y is pinned to `fromPosition`'s own
-- (the mob's current height) for every candidate -- these are ground-level
-- walk targets, not asking the mob to climb/descend to a building's actual
-- (raised, bounding-box-center) anchor height.
local function pickTarget(owner: Player, fromPosition: Vector3, door: BasePart): Target
	local best: Target = { Position = door.Position }
	local nearestDistance = math.huge
	for _, building in PetManager.GetAlivePlacedBuildings(owner) do
		local walkPosition = Vector3.new(building.Position.X, fromPosition.Y, building.Position.Z)
		local distance = (walkPosition - fromPosition).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
			best = { Position = walkPosition, PlacementId = building.PlacementId, AssetId = building.AssetId }
		end
	end
	return best
end

sendMobToTarget = function(mob: BasePart, owner: Player, side: string, fromPosition: Vector3)
	local door = findDoor(side)
	if not door then
		EndlessModeMobRegistry.Unregister(mob)
		if mob.Parent then
			mob:Destroy()
		end
		return
	end

	local target = pickTarget(owner, fromPosition, door)
	local distance = (target.Position - fromPosition).Magnitude
	local duration = math.max(distance / MOB_SPEED_STUDS_PER_SECOND, 0.05)

	local tween = TweenService:Create(mob, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Position = target.Position })
	tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if playbackState ~= Enum.PlaybackState.Completed then
			-- Interrupted -- most likely the mob was destroyed mid-walk
			-- (killed by a Damage building/Ally), which OnDeath already
			-- handled. Nothing further to do.
			return
		end
		if not EndlessModeMobRegistry.IsAlive(mob) then
			return
		end
		onMobArrived(mob, owner, side, target)
	end)
	tween:Play()
end

onMobArrived = function(mob: BasePart, owner: Player, side: string, target: Target)
	if target.PlacementId then
		if not PetManager.IsBuildingAlive(owner, target.PlacementId) then
			-- Died or got picked up while this mob was still walking --
			-- re-route from here instead of hitting something that's gone.
			sendMobToTarget(mob, owner, side, mob.Position)
			return
		end

		local role = target.AssetId and EndlessModeUnitRoleConfig.GetRole(target.AssetId)
		if role == "Tank" and tryEngageTank(target.PlacementId) then
			meleeTank(mob, owner, side, target.PlacementId)
			return
		end

		PetManager.DamageBuilding(owner, target.PlacementId, getMobDamage(owner))
	elseif EndlessModeClaimManager.GetOwner(side) == owner then
		EndlessModeClaimManager.DamageBase(side, getMobDamage(owner))
	end

	EndlessModeMobRegistry.Unregister(mob)
	if mob.Parent then
		mob:Destroy()
	end
end

-- A mob that arrived at a Tank-role building (and won a slot via
-- tryEngageTank, see MAX_CONCURRENT_TANK_ATTACKERS above) stops there and
-- chips away at it every tick -- per explicit request, the Tank is PURE
-- soak, it never hits back. It just stands there absorbing hits (blocking
-- that mob from reaching anything else) until either the Tank dies (the mob
-- re-targets and moves on) or something ELSE kills the mob first (a Damage
-- building/Ally can still land hits on it independently while it's stuck
-- here). disengageTank releases its slot on every exit path so a new mob
-- can take its place.
meleeTank = function(mob: BasePart, owner: Player, side: string, placementId: string)
	task.spawn(function()
		while true do
			task.wait(EndlessModeUnitRoleConfig.TankTickSeconds)

			if not EndlessModeMobRegistry.IsAlive(mob) or not mob.Parent then
				disengageTank(placementId)
				return
			end

			if not PetManager.IsBuildingAlive(owner, placementId) then
				disengageTank(placementId)
				sendMobToTarget(mob, owner, side, mob.Position)
				return
			end

			PetManager.DamageBuilding(owner, placementId, getMobDamage(owner))
			if not PetManager.IsBuildingAlive(owner, placementId) then
				disengageTank(placementId)
				sendMobToTarget(mob, owner, side, mob.Position)
				return
			end
		end
	end)
end

local HP_BAR_SIZE = UDim2.new(0, 60, 0, 14)
local HP_BAR_BACKGROUND_COLOR = Color3.fromRGB(35, 35, 35)
local HP_BAR_FULL_COLOR = Color3.fromRGB(90, 220, 100)
local HP_BAR_LOW_COLOR = Color3.fromRGB(220, 60, 60)

-- Floating bar above a mob (a filled Frame shrinking left-to-right, not text
-- ALONE like the buildings' "N/MAX HP" label -- per explicit request) --
-- green at full health, sliding to red as it empties, with the actual
-- "N/MAX" number overlaid on top so both are visible at once. Returns the
-- fill Frame and the label so the caller can update both from
-- EndlessModeMobRegistry's OnDamage hook. Studs-up offset is derived from
-- `mob.Size` itself (not a flat MOB_SIZE-based constant) so it still floats
-- clear of the roofline on a bigger mob (e.g. a Boss, see spawnMob).
local function createHpBar(mob: BasePart): (Frame, TextLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HPBar"
	billboard.Size = HP_BAR_SIZE
	billboard.StudsOffset = Vector3.new(0, mob.Size.Y / 2 + 1.4, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = mob
	billboard.Parent = mob

	local background = Instance.new("Frame")
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = HP_BAR_BACKGROUND_COLOR
	background.BorderSizePixel = 0
	background.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = HP_BAR_FULL_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = background

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.ZIndex = 2
	label.Parent = background

	return fill, label
end

local function updateHpBar(fill: Frame, label: TextLabel, hp: number, maxHp: number)
	local fraction = maxHp > 0 and math.clamp(hp / maxHp, 0, 1) or 0
	fill.Size = UDim2.new(fraction, 0, 1, 0)
	fill.BackgroundColor3 = HP_BAR_LOW_COLOR:Lerp(HP_BAR_FULL_COLOR, fraction)
	label.Text = string.format("%d/%d", math.max(hp, 0), maxHp)
end

-- Boss placeholder -- real visuals/stats are coming later (per explicit
-- request, "mai multe detalii de aspect ulterior"). For now: a bigger, much
-- tankier version of the same plain-block mob, clearly tagged
-- ("EndlessMode_Boss") so it's easy to find and swap out later (model,
-- stats, whatever) without touching the wave-structure code around it.
-- HP is 10x a regular mob's HP at the PRECEDING wave (per explicit
-- request), not a flat number -- see GetBossHP below.
local BOSS_WAVE_INTERVAL = 10
local BOSS_HP_MULTIPLIER = 10
local BOSS_SIZE = MOB_SIZE * 2.5
local BOSS_COLOR = Color3.fromRGB(180, 40, 200)

local function getBossHP(bossWave: number): number
	return BOSS_HP_MULTIPLIER * EndlessModeUnitRoleConfig.GetMobHPForWave(bossWave - 1)
end

-- `clusterZOffset`, if given (Swarm Waves -- see SWARM_WAVE_INTERVAL below),
-- overrides the normal wide-open SPAWN_Z_JITTER with a much tighter jitter
-- around a single shared point (door.Position.Z + clusterZOffset), so every
-- mob from that wave lands bunched close together instead of spread across
-- the whole 60-stud spawn strip.
local function spawnMob(side: string, wave: number, isBoss: boolean?, clusterZOffset: number?)
	local owner = EndlessModeClaimManager.GetOwner(side)
	if not owner then
		return
	end

	local door = findDoor(side)
	if not door then
		return
	end

	local spawnX = ROAD_HALF_WIDTH + SPAWN_X_MIN_OFFSET + math.random() * (SPAWN_X_MAX_OFFSET - SPAWN_X_MIN_OFFSET)
	local spawnZ
	if clusterZOffset then
		spawnZ = door.Position.Z + clusterZOffset + (math.random() * 2 - 1) * SWARM_CLUSTER_JITTER_STUDS
	else
		spawnZ = door.Position.Z + (math.random() * 2 - 1) * SPAWN_Z_JITTER
	end
	local spawnPosition = Vector3.new(spawnX, door.Position.Y, spawnZ)

	local mob = Instance.new("Part")
	mob.Name = isBoss and "EndlessMode_Boss" or "EndlessMode_Mob"
	mob.Size = isBoss and BOSS_SIZE or MOB_SIZE
	mob.Color = isBoss and BOSS_COLOR or MOB_COLOR
	mob.Material = Enum.Material.Slate
	mob.Anchored = true
	mob.CanCollide = false
	mob.CFrame = CFrame.new(spawnPosition)
	mob.Parent = door.Parent.Parent

	local maxHp = if isBoss then getBossHP(wave) else EndlessModeUnitRoleConfig.GetMobHPForWave(wave)

	local hpBarFill, hpBarLabel = createHpBar(mob)
	hpBarLabel.Text = string.format("%d/%d", maxHp, maxHp)

	EndlessModeMobRegistry.Register(mob, maxHp, function()
		if mob.Parent then
			mob:Destroy()
		end
	end, function(hp, currentMaxHp)
		updateHpBar(hpBarFill, hpBarLabel, hp, currentMaxHp)
	end)

	sendMobToTarget(mob, owner, side, spawnPosition)
end

-- Current wave for THIS owner -- same "read the session's own elapsed time"
-- idiom getMobDamage above uses. A wave here isn't reset by claiming --
-- it's the player's own ongoing progress (session.EndlessModeElapsedSeconds
-- persists across sessions), so re-claiming after a break picks up
-- wherever their wave count already was, not back at wave 1.
local function getOwnerWave(owner: Player): number
	local session = DataManager.Get(owner)
	return session and WaveConfig.GetWaveForElapsedSeconds(session.EndlessModeElapsedSeconds) or 1
end

type WaveSpawnState = {
	Wave: number,
	TargetCount: number,
	SpawnedCount: number,
	BossSpawned: boolean,
	IsSwarmWave: boolean,
	-- Rolled ONCE when a Swarm Wave starts (an offset from the door's own Z,
	-- same coordinate space SPAWN_Z_JITTER already uses) so every mob that
	-- wave clusters around the SAME point instead of each mob picking its
	-- own random spot.
	SwarmClusterZOffset: number?,
}

-- Per explicit request: each wave spawns a GROWING NUMBER of mobs (wave N ->
-- N+1..N+2 mobs, so wave 1 = 2-3, wave 2 = 3-4, etc.), trickled out evenly
-- across that wave's own WaveConfig.WaveDurationSeconds instead of a flat
-- fixed-interval timer -- MIN_SPAWN_INTERVAL_SECONDS keeps that from turning
-- into a machine gun once a wave's target count gets very high late-game.
-- Every BOSS_WAVE_INTERVAL-th wave ALSO spawns one Boss (on top of, not
-- instead of, that wave's normal mobs), the instant the wave starts.
--
-- MAX_MOBS_PER_WAVE caps that growth -- left uncapped, wave 100 would want
-- ~100 mobs in one 45s wave (each its own Part + tween + coroutine + HP
-- bar), climbing toward 800 by the late game -- server-melting spam, not
-- escalating challenge. Once a wave's count hits the cap, further
-- difficulty comes from mob damage/HP scaling (every 20 waves) instead of
-- an ever-growing mob count.
local MIN_SPAWN_INTERVAL_SECONDS = 2
local MAX_MOBS_PER_WAVE = 18

local function getWaveMobTargetCount(wave: number): number
	local low = math.min(wave + 1, MAX_MOBS_PER_WAVE)
	local high = math.min(wave + 2, MAX_MOBS_PER_WAVE)
	return math.random(low, high)
end

local waveSpawnState: { [string]: WaveSpawnState? } = {}

-- Tracks the claim's own lifecycle (not just a flat repeating timer) so the
-- CLAIM_GRACE_SECONDS delay is measured from the moment THIS claim started,
-- not from whenever the module happened to load.
local lastOwner: { [string]: Player? } = {}
local nextSpawnAt: { [string]: number? } = {}

local function tick(side: string)
	local owner = EndlessModeClaimManager.GetOwner(side)
	if owner ~= lastOwner[side] then
		lastOwner[side] = owner
		waveSpawnState[side] = nil
		nextSpawnAt[side] = owner and (os.clock() + CLAIM_GRACE_SECONDS) or nil
	end

	local spawnAt = nextSpawnAt[side]
	if not owner or not spawnAt or os.clock() < spawnAt then
		return
	end

	local wave = getOwnerWave(owner)
	local state = waveSpawnState[side]
	if not state or state.Wave ~= wave then
		-- New wave (or first-ever spawn state for this claim) -- roll a
		-- fresh target count for it, and (every SWARM_WAVE_INTERVAL-th wave)
		-- a single shared cluster point every mob this wave spawns around.
		local isSwarmWave = wave % SWARM_WAVE_INTERVAL == 0
		state = {
			Wave = wave,
			TargetCount = getWaveMobTargetCount(wave),
			SpawnedCount = 0,
			BossSpawned = false,
			IsSwarmWave = isSwarmWave,
			SwarmClusterZOffset = isSwarmWave and ((math.random() * 2 - 1) * SPAWN_Z_JITTER) or nil,
		}
		waveSpawnState[side] = state
	end

	if wave % BOSS_WAVE_INTERVAL == 0 and not state.BossSpawned then
		state.BossSpawned = true
		spawnMob(side, wave, true)
	end

	if state.SpawnedCount < state.TargetCount then
		spawnMob(side, wave, false, state.SwarmClusterZOffset)
		state.SpawnedCount += 1
	end

	-- Swarm Waves burst out fast (SWARM_SPAWN_INTERVAL_SECONDS) so the whole
	-- cluster is on the ground together, not trickled across the wave's
	-- full duration -- otherwise the early ones would wander off/die before
	-- the later ones even spawned in, defeating the point of clustering.
	local interval = if state.IsSwarmWave
		then SWARM_SPAWN_INTERVAL_SECONDS
		else math.max(MIN_SPAWN_INTERVAL_SECONDS, WaveConfig.WaveDurationSeconds / state.TargetCount)
	nextSpawnAt[side] = os.clock() + interval
end

task.spawn(function()
	while true do
		task.wait(TICK_SECONDS)
		tick(SIDE)
	end
end)

return EndlessModeMobManager
