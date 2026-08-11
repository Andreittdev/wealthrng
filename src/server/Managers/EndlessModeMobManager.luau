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
-- from arriving at anything else: the mob STOPS there and they trade hits
-- every tick until one side dies, instead of the mob dealing one hit and
-- despawning. If the Tank dies, the mob re-targets from where it's
-- standing (possibly another Tank, possibly not) instead of just vanishing.
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

local MOB_SPAWN_INTERVAL_SECONDS = 6
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

type Target = { Position: Vector3, PlacementId: string?, AssetId: string? }

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
		if role == "Tank" then
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

-- A mob that arrived at a Tank-role building stops there and chips away at
-- it every tick -- per explicit request, the Tank is PURE soak, it never
-- hits back. It just stands there absorbing hits (blocking that mob from
-- reaching anything else) until either the Tank dies (the mob re-targets
-- and moves on) or something ELSE kills the mob first (a Damage building/
-- Ally can still land hits on it independently while it's stuck here).
meleeTank = function(mob: BasePart, owner: Player, side: string, placementId: string)
	task.spawn(function()
		while true do
			task.wait(EndlessModeUnitRoleConfig.TankTickSeconds)

			if not EndlessModeMobRegistry.IsAlive(mob) or not mob.Parent then
				return
			end

			if not PetManager.IsBuildingAlive(owner, placementId) then
				sendMobToTarget(mob, owner, side, mob.Position)
				return
			end

			PetManager.DamageBuilding(owner, placementId, getMobDamage(owner))
			if not PetManager.IsBuildingAlive(owner, placementId) then
				sendMobToTarget(mob, owner, side, mob.Position)
				return
			end
		end
	end)
end

local HP_BAR_SIZE = UDim2.new(0, 60, 0, 14)
local HP_BAR_STUDS_UP = MOB_SIZE.Y / 2 + 1.4
local HP_BAR_BACKGROUND_COLOR = Color3.fromRGB(35, 35, 35)
local HP_BAR_FULL_COLOR = Color3.fromRGB(90, 220, 100)
local HP_BAR_LOW_COLOR = Color3.fromRGB(220, 60, 60)

-- Floating bar above a mob (a filled Frame shrinking left-to-right, not text
-- ALONE like the buildings' "N/MAX HP" label -- per explicit request) --
-- green at full health, sliding to red as it empties, with the actual
-- "N/MAX" number overlaid on top so both are visible at once. Returns the
-- fill Frame and the label so the caller can update both from
-- EndlessModeMobRegistry's OnDamage hook.
local function createHpBar(mob: BasePart): (Frame, TextLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "HPBar"
	billboard.Size = HP_BAR_SIZE
	billboard.StudsOffset = Vector3.new(0, HP_BAR_STUDS_UP, 0)
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

local function spawnMob(side: string)
	local owner = EndlessModeClaimManager.GetOwner(side)
	if not owner then
		return
	end

	local door = findDoor(side)
	if not door then
		return
	end

	local spawnX = ROAD_HALF_WIDTH + SPAWN_X_MIN_OFFSET + math.random() * (SPAWN_X_MAX_OFFSET - SPAWN_X_MIN_OFFSET)
	local spawnZ = door.Position.Z + (math.random() * 2 - 1) * SPAWN_Z_JITTER
	local spawnPosition = Vector3.new(spawnX, door.Position.Y, spawnZ)

	local mob = Instance.new("Part")
	mob.Name = "EndlessMode_Mob"
	mob.Size = MOB_SIZE
	mob.Color = MOB_COLOR
	mob.Material = Enum.Material.Slate
	mob.Anchored = true
	mob.CanCollide = false
	mob.CFrame = CFrame.new(spawnPosition)
	mob.Parent = door.Parent.Parent

	local hpBarFill, hpBarLabel = createHpBar(mob)
	hpBarLabel.Text = string.format("%d/%d", EndlessModeUnitRoleConfig.MobHP, EndlessModeUnitRoleConfig.MobHP)

	EndlessModeMobRegistry.Register(mob, EndlessModeUnitRoleConfig.MobHP, function()
		if mob.Parent then
			mob:Destroy()
		end
	end, function(hp, maxHp)
		updateHpBar(hpBarFill, hpBarLabel, hp, maxHp)
	end)

	sendMobToTarget(mob, owner, side, spawnPosition)
end

-- Tracks the claim's own lifecycle (not just a flat repeating timer) so the
-- CLAIM_GRACE_SECONDS delay is measured from the moment THIS claim started,
-- not from whenever the module happened to load.
local lastOwner: Player? = nil
local nextSpawnAt: number? = nil

local function tick(side: string)
	local owner = EndlessModeClaimManager.GetOwner(side)
	if owner ~= lastOwner then
		lastOwner = owner
		nextSpawnAt = owner and (os.clock() + CLAIM_GRACE_SECONDS) or nil
	end

	if not owner or not nextSpawnAt or os.clock() < nextSpawnAt then
		return
	end

	spawnMob(side)
	nextSpawnAt = os.clock() + MOB_SPAWN_INTERVAL_SECONDS
end

task.spawn(function()
	while true do
		task.wait(TICK_SECONDS)
		tick(SIDE)
	end
end)

return EndlessModeMobManager
