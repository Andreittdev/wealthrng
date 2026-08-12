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
-- an uncapped queue would only ever grow. Per explicit bug report, a mob
-- arriving at an ALREADY-FULL Tank no longer deals a "free" hit and
-- instantly self-destructs (that read as mobs dying with no attacker/damage
-- ever applied to them, since nothing had actually killed them) -- it now
-- RE-TARGETS instead, same as when a Tank it was already fighting dies
-- (excluding that specific saturated Tank so it doesn't just walk straight
-- back into the same dead end), falling through to another building or the
-- base if nothing else is left. A mob is only EVER removed from the field
-- either by dying to real combat damage or by actually reaching/hitting a
-- target -- see removeMob below.
--
-- Structured by WAVE now, not a flat repeating timer -- wave N spawns a
-- growing count of mobs (N+1..N+2, trickled evenly across that wave's own
-- 45 seconds), and every BOSS_WAVE_INTERVAL-th wave (10, 20, 30...) ALSO
-- spawns a Boss on top of the normal count, the instant that wave begins
-- (see tick/spawnMob below). Per explicit request, wave progression is now
-- EVENT-gated, not time-based -- session.EndlessModeWave (this file's own,
-- the only writer) only advances once every mob wave N was ever going to
-- spawn (including its Boss, on a Boss wave) has both been spawned AND left
-- the field (killed, or reached its target), tracked in aliveMobsThisWave
-- below. Not reset by (re)claiming, same "player's own ongoing progress"
-- property the old elapsed-time version had.
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
local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)

local endlessModeLoadoutCountdownUpdated = RemotesBootstrap:WaitForChild("EndlessModeLoadoutCountdownUpdated")
local endlessModeCashUpdated = RemotesBootstrap:WaitForChild("EndlessModeCashUpdated")

local EndlessModeMobManager = {}

-- Right only for now -- matches EndlessModeClaimManager's own "Right only"
-- scope (see its SIDES comment).
local SIDE = "Right"

-- The first mob doesn't show up the instant you claim -- per explicit
-- request, split into two distinct, player-visible phases (EndlessMode
-- LoadoutCountdown.luau shows a live countdown for both) instead of one
-- silent flat delay: up to LOADOUT_PICK_SECONDS to actually pick your up-to-
-- 4 Estate loadout (EndlessModeLoadoutHotbar.luau/InventoryPanel.luau --
-- the Sidebar's Inventory button hides once this ends, locking further
-- changes in for the rest of this claim), then POST_PICK_GRACE_SECONDS more
-- as a final "place your Estates" warning before the first mob actually
-- spawns. Picking ends EARLY (before the full LOADOUT_PICK_SECONDS) the
-- instant the player equips all AssetDatabase.MaxEquippedEndlessMode
-- Estates -- per explicit request, finishing your pick shouldn't force you
-- to sit out the rest of a timer that was only ever a CAP, not a fixed
-- wait. See pickingEndedAt/updateLoadoutCountdown below.
local LOADOUT_PICK_SECONDS = 30
local POST_PICK_GRACE_SECONDS = 10
local TICK_SECONDS = 1
local MOB_SPEED_STUDS_PER_SECOND = 8
local MOB_SIZE = Vector3.new(2.5, 3, 2.5)
local MOB_COLOR = Color3.fromRGB(120, 20, 30)
-- Must match MapBuilder.buildEndlessModeArea's own ENDLESS_MODE_ROAD_WIDTH/2
-- -- mobs spawn ON the road itself, BEFORE its edge, not relative to the
-- door anymore (the door moved to the back, see EndlessModeClaimManager.
-- spawnBase). Per a real bug report ("mobi... se spawneaza direct in
-- Estates"): the road edge (X = ROAD_HALF_WIDTH) is also exactly where
-- EndlessModeClaimManager's own claimed patch/placement grid STARTS -- the
-- old offsets (+3 to +12 PAST that edge) put mobs inside the first
-- buildable column instead of on the road in front of it, so a mob could
-- spawn literally overlapping an Estate placed in that front row. Spawning
-- BELOW ROAD_HALF_WIDTH instead keeps every spawn point safely on the road,
-- never inside a placeable tile, regardless of what's built there.
local ROAD_HALF_WIDTH = 10
local SPAWN_X_MIN_OFFSET_FROM_ROAD_EDGE = 2
local SPAWN_X_MAX_OFFSET_FROM_ROAD_EDGE = 8
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
-- A mob that arrives at an already-full Tank re-routes to another target
-- instead of joining the queue (or dealing a "free" hit -- see onMobArrived
-- below).
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
	local count = math.max(0, (tankEngagementCounts[placementId] or 0) - 1)
	-- Cleared entirely (not left at a stale 0) once nothing's engaged --
	-- placementId is a fresh GUID per placement, so leaving a 0-valued
	-- entry behind forever would grow this table by one for every Tank
	-- ever placed across the server's whole lifetime.
	tankEngagementCounts[placementId] = count > 0 and count or nil
end

-- Per-side count of mobs from the CURRENT wave still active on the field --
-- spawned, but not yet gone (killed in combat OR reached their target and
-- expired, either way -- see removeMob below). Wave progression (tick's own
-- clear-check) only advances session.EndlessModeWave once this hits 0 AND
-- every mob that wave was ever going to spawn already has, per explicit "sa
-- treaca la waveul urmator numai dupa ce au fost omorati toti mobii"
-- request.
local aliveMobsThisWave: { [string]: number } = {}

-- Per-side list of every mob currently alive/mid-walk on that side --
-- separate from aliveMobsThisWave (a count) because this needs the actual
-- BasePart references. Exists ONLY to fix a real orphaning bug: spawnMob
-- parents mobs to door.Parent.Parent (the Map folder), the SAME folder
-- EndlessModeClaimManager's spawnBase parents baseFolder to -- siblings,
-- not parent/child, so when a claim releases (base actually dies, or the
-- owner disconnects) clearBase's base:Destroy() never touches any mob still
-- on the field. The ClaimReleased listener below force-removes everything
-- still tracked here for that side.
local activeMobsBySide: { [string]: { BasePart } } = {}

-- The ONLY place a spawned mob is ever removed from the field -- whether it
-- died to real combat damage (a Damage building/Ally reduced its HP to 0,
-- see spawnMob's OnDeath below, which routes through here too) or it
-- successfully reached/hit a target and expired (onMobArrived/
-- sendMobToTarget's own no-door edge case). Centralizing this is what makes
-- aliveMobsThisWave an honest count -- every mob that ever spawns is
-- guaranteed to decrement it exactly once, by exactly one path, whenever it
-- actually leaves.
local function removeMob(mob: BasePart, side: string)
	if EndlessModeMobRegistry.IsAlive(mob) then
		EndlessModeMobRegistry.Unregister(mob)
	end
	if mob.Parent then
		mob:Destroy()
	end
	aliveMobsThisWave[side] = math.max(0, (aliveMobsThisWave[side] or 0) - 1)

	local sideMobs = activeMobsBySide[side]
	if sideMobs then
		local index = table.find(sideMobs, mob)
		if index then
			table.remove(sideMobs, index)
		end
	end
end

-- EndlessModeClaimManager fires this (side) from inside releaseClaim, for
-- EITHER release path (base death or plain disconnect). Iterates a COPY of
-- the side's list since removeMob mutates activeMobsBySide[side] mid-call.
EndlessModeClaimManager.ClaimReleased.Event:Connect(function(side: string)
	local sideMobs = activeMobsBySide[side]
	if sideMobs then
		local snapshot = table.clone(sideMobs)
		for _, mob in snapshot do
			removeMob(mob, side)
		end
	end
	activeMobsBySide[side] = nil
	aliveMobsThisWave[side] = 0
end)

-- Forward-declared -- sendMobToTarget, onMobArrived, and meleeTank call each
-- other (mob "wins" a melee -> re-targets -> may walk into another Tank ->
-- melee again), so each needs to already be a visible local by the time the
-- others are defined, same idiom PetManager.luau's own refreshPets uses.
local sendMobToTarget: (BasePart, Player, string, Vector3, string?) -> ()
local onMobArrived: (BasePart, Player, string, Target) -> ()
local meleeTank: (BasePart, Player, string, string) -> ()

local function findDoor(side: string): BasePart?
	local mapFolder = Workspace:FindFirstChild("Map")
	local baseFolder = mapFolder and mapFolder:FindFirstChild("EndlessMode_ClaimBase" .. side)
	local door = baseFolder and baseFolder:FindFirstChild("Door")
	return door and door:IsA("BasePart") and door or nil
end

-- Current mob damage for THIS owner -- scales with their own wave progress
-- (session.EndlessModeWave, event-gated now -- see tick below), not a flat
-- number for the whole run. Re-read fresh on every hit rather than cached
-- once per mob, since a mob can live across a wave boundary.
local function getMobDamage(owner: Player): number
	local session = DataManager.Get(owner)
	local wave = (session and session.EndlessModeWave) or 1
	return EndlessModeUnitRoleConfig.GetMobDamageForWave(wave)
end

-- Nearest alive placed Estate to `fromPosition`, or the base door if the
-- owner has none standing right now (or the only one left is `excludePlacementId`
-- -- a Tank already at MAX_CONCURRENT_TANK_ATTACKERS, which onMobArrived
-- routes here through instead of letting a mob hit it for free). Y is
-- pinned to `fromPosition`'s own (the mob's current height) for every
-- candidate -- these are ground-level walk targets, not asking the mob to
-- climb/descend to a building's actual (raised, bounding-box-center) anchor
-- height.
local function pickTarget(owner: Player, fromPosition: Vector3, door: BasePart, excludePlacementId: string?): Target
	local best: Target = { Position = door.Position }
	local nearestDistance = math.huge
	for _, building in PetManager.GetAlivePlacedBuildings(owner) do
		if building.PlacementId ~= excludePlacementId then
			local walkPosition = Vector3.new(building.Position.X, fromPosition.Y, building.Position.Z)
			local distance = (walkPosition - fromPosition).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				best = { Position = walkPosition, PlacementId = building.PlacementId, AssetId = building.AssetId }
			end
		end
	end
	return best
end

sendMobToTarget = function(mob: BasePart, owner: Player, side: string, fromPosition: Vector3, excludePlacementId: string?)
	local door = findDoor(side)
	if not door then
		removeMob(mob, side)
		return
	end

	local target = pickTarget(owner, fromPosition, door, excludePlacementId)
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
		if role == "Tank" then
			if tryEngageTank(target.PlacementId) then
				meleeTank(mob, owner, side, target.PlacementId)
				return
			end
			-- Already at MAX_CONCURRENT_TANK_ATTACKERS -- per explicit bug
			-- report, this no longer deals a "free" hit and instantly
			-- self-destructs (nothing had actually killed it, so that read
			-- as mobs dying without receiving damage from anyone). It just
			-- re-routes instead, excluding THIS specific saturated Tank so
			-- it doesn't immediately walk right back into the same dead
			-- end -- falls through to another building, or the base, same
			-- as a Tank that died mid-melee already does below.
			sendMobToTarget(mob, owner, side, mob.Position, target.PlacementId)
			return
		end

		PetManager.DamageBuilding(owner, target.PlacementId, getMobDamage(owner))
	elseif EndlessModeClaimManager.GetOwner(side) == owner then
		EndlessModeClaimManager.DamageBase(side, getMobDamage(owner))
	end

	removeMob(mob, side)
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

	local spawnX = ROAD_HALF_WIDTH
		- SPAWN_X_MIN_OFFSET_FROM_ROAD_EDGE
		- math.random() * (SPAWN_X_MAX_OFFSET_FROM_ROAD_EDGE - SPAWN_X_MIN_OFFSET_FROM_ROAD_EDGE)
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

	-- Counted toward aliveMobsThisWave the instant it's actually on the
	-- field (registered) -- OnDeath (a real combat kill, mob already
	-- unregistered by EndlessModeMobRegistry.Damage by the time this fires)
	-- routes through the SAME removeMob helper as every other "this mob is
	-- gone" path, so the count can never miss a decrement no matter how the
	-- mob actually left.
	EndlessModeMobRegistry.Register(mob, maxHp, function()
		removeMob(mob, side)
	end, function(hp, currentMaxHp)
		updateHpBar(hpBarFill, hpBarLabel, hp, currentMaxHp)
	end)
	aliveMobsThisWave[side] = (aliveMobsThisWave[side] or 0) + 1
	local sideMobs = activeMobsBySide[side]
	if not sideMobs then
		sideMobs = {}
		activeMobsBySide[side] = sideMobs
	end
	table.insert(sideMobs, mob)

	sendMobToTarget(mob, owner, side, spawnPosition)
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
-- grace delay is measured from the moment THIS claim started, not from
-- whenever the module happened to load.
local lastOwner: { [string]: Player? } = {}
local nextSpawnAt: { [string]: number? } = {}
local claimedAt: { [string]: number? } = {}
-- Set ONCE per claim -- the moment Picking phase actually ended, whether
-- that's LOADOUT_PICK_SECONDS after claimedAt (the cap) or earlier (the
-- player equipped all AssetDatabase.MaxEquippedEndlessMode Estates before
-- that). Anchors the Locked phase's own POST_PICK_GRACE_SECONDS countdown
-- AND the mob-spawn gate (nextSpawnAt) -- see updateLoadoutCountdown below.
local pickingEndedAt: { [string]: number? } = {}
-- Last Phase actually pushed to the owner (EndlessModeLoadoutCountdownUpdated)
-- -- lets updateLoadoutCountdown below fire the ONE-TIME nil clear exactly
-- once when the whole grace window elapses, instead of re-firing nil every
-- tick for the rest of the claim.
local lastLoadoutCountdownPhase: { [string]: ("Picking" | "Locked")? } = {}

-- Short pause once a wave is confirmed cleared before the next one's mobs
-- start trickling in -- gives the player a breath/moment to notice it
-- happened, instead of the very next mob appearing on the exact same tick
-- the last one died.
local WAVE_CLEAR_GRACE_SECONDS = 3

-- Live countdown for EndlessModeLoadoutCountdown.luau -- Picking until
-- pickingEndedAt[side] gets set (see its own comment above), Locked for
-- POST_PICK_GRACE_SECONDS after that, nil (fired once, to clear the
-- client's own display) once the whole window has passed. Runs every tick
-- regardless of the mob-spawn gate below, same "always current, not tied to
-- spawn pacing" reasoning the wave-clear check uses.
local function updateLoadoutCountdown(side: string, owner: Player, session)
	local now = os.clock()

	if not pickingEndedAt[side] then
		local elapsedSinceClaim = now - (claimedAt[side] or now)
		local reachedFullLoadout = #session.EquippedAssets >= AssetDatabase.MaxEquippedEndlessMode
		if reachedFullLoadout or elapsedSinceClaim >= LOADOUT_PICK_SECONDS then
			-- Picking just ended (right now) -- anchors both the Locked
			-- countdown below AND the mob-spawn gate to THIS moment, not a
			-- fixed claim+40 that would ignore an early finish.
			pickingEndedAt[side] = now
			nextSpawnAt[side] = now + POST_PICK_GRACE_SECONDS
		end
	end

	local phase: ("Picking" | "Locked")? = nil
	local secondsRemaining = 0
	if pickingEndedAt[side] then
		local elapsedSincePickingEnded = now - pickingEndedAt[side]
		if elapsedSincePickingEnded < POST_PICK_GRACE_SECONDS then
			phase = "Locked"
			secondsRemaining = math.ceil(POST_PICK_GRACE_SECONDS - elapsedSincePickingEnded)
		end
	else
		phase = "Picking"
		secondsRemaining = math.ceil(LOADOUT_PICK_SECONDS - (now - (claimedAt[side] or now)))
	end

	if phase then
		endlessModeLoadoutCountdownUpdated:FireClient(owner, { Phase = phase, SecondsRemaining = secondsRemaining })
	elseif lastLoadoutCountdownPhase[side] then
		endlessModeLoadoutCountdownUpdated:FireClient(owner, nil)
	end
	lastLoadoutCountdownPhase[side] = phase
end

local function tick(side: string)
	local owner = EndlessModeClaimManager.GetOwner(side)
	if owner ~= lastOwner[side] then
		-- Clears the OLD owner's own countdown display -- they might still
		-- be standing right there physically (unclaimed but not yet walked
		-- off), so their HUD shouldn't keep showing a stale countdown for a
		-- claim that no longer exists.
		if lastOwner[side] and lastLoadoutCountdownPhase[side] then
			endlessModeLoadoutCountdownUpdated:FireClient(lastOwner[side] :: Player, nil)
		end
		lastOwner[side] = owner
		waveSpawnState[side] = nil
		aliveMobsThisWave[side] = 0
		claimedAt[side] = owner and os.clock() or nil
		pickingEndedAt[side] = nil
		lastLoadoutCountdownPhase[side] = nil
		-- Not set to a fixed claim+40 anymore -- updateLoadoutCountdown sets
		-- this itself, dynamically, the instant Picking actually ends
		-- (early or at the cap).
		nextSpawnAt[side] = nil
	end

	if not owner then
		return
	end

	local session = DataManager.Get(owner)
	if not session then
		return
	end

	updateLoadoutCountdown(side, owner, session)

	local wave = session.EndlessModeWave
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
		aliveMobsThisWave[side] = 0
	end

	-- Wave-clear check -- runs every tick (every TICK_SECONDS), independent
	-- of the spawn-pacing gate below, so advancing to the next wave doesn't
	-- have to wait on a stale spawn-interval timer once there's nothing
	-- left to spawn AND nothing left alive. Per explicit request, this is
	-- what actually GATES progression now -- not elapsed time.
	local requiresBoss = wave % BOSS_WAVE_INTERVAL == 0
	local allSpawned = state.SpawnedCount >= state.TargetCount and (not requiresBoss or state.BossSpawned)
	if allSpawned and (aliveMobsThisWave[side] or 0) <= 0 then
		-- Wave-clear Cash bonus, on TOP of whatever individual kill rewards
		-- already came in during the wave -- per explicit "la fiecare wave
		-- trecut cu brio" request.
		session.EndlessModeCash += EndlessModeUnitRoleConfig.GetWaveClearRewardForWave(wave)
		endlessModeCashUpdated:FireClient(owner, session.EndlessModeCash)

		session.EndlessModeWave = math.min(wave + 1, WaveConfig.MaxWave)
		waveSpawnState[side] = nil
		nextSpawnAt[side] = os.clock() + WAVE_CLEAR_GRACE_SECONDS
		return
	end

	local spawnAt = nextSpawnAt[side]
	if not spawnAt or os.clock() < spawnAt then
		return
	end

	if requiresBoss and not state.BossSpawned then
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
