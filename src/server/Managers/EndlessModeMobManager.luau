-- Endless Mode's wave enemies -- simple prototype mobs (plain blocks, no
-- Humanoid/pathfinding yet, just a straight-line TweenService walk since the
-- claimed plot is flat open ground with nothing to path around) that spawn
-- near the STREET (the front of the plot).
--
-- Target priority, per explicit request: any of the owner's placed Estates
-- still alive (PetManager.GetAlivePlacedBuildings) are attacked FIRST --
-- each mob picks the nearest one to its own spawn point. Only once none are
-- left alive does a mob fall back to marching the full depth of the base to
-- reach the door (EndlessModeClaimManager.spawnBase's "Door" part), same as
-- before.
--
-- Only spawns while the Right plot is actually claimed (EndlessModeClaimManager.
-- GetOwner) -- no owner means nothing to attack, so nothing spawns.
--
-- Self-runs on require -- no Init() call needed, same convention as every
-- other pure-background-watcher manager.

local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local EndlessModeClaimManager = require(ServerScriptService.Managers.EndlessModeClaimManager)
local PetManager = require(ServerScriptService.Managers.PetManager)

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
local MOB_DAMAGE = 20
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

local function findDoor(side: string): BasePart?
	local mapFolder = Workspace:FindFirstChild("Map")
	local baseFolder = mapFolder and mapFolder:FindFirstChild("EndlessMode_ClaimBase" .. side)
	local door = baseFolder and baseFolder:FindFirstChild("Door")
	return door and door:IsA("BasePart") and door or nil
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

	-- Nearest ALIVE placed Estate wins -- nil (and the door's own position)
	-- if the owner has none standing, meaning this mob marches on the base
	-- instead. Picked once at spawn (no dynamic re-targeting), same
	-- "simple prototype, no pathfinding" scope as the straight-line walk.
	local targetPlacementId: string? = nil
	local targetPosition = door.Position
	local nearestDistance = math.huge
	for _, building in PetManager.GetAlivePlacedBuildings(owner) do
		local buildingWalkPosition = Vector3.new(building.Position.X, spawnPosition.Y, building.Position.Z)
		local distance = (buildingWalkPosition - spawnPosition).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
			targetPlacementId = building.PlacementId
			targetPosition = buildingWalkPosition
		end
	end

	local mob = Instance.new("Part")
	mob.Name = "EndlessMode_Mob"
	mob.Size = MOB_SIZE
	mob.Color = MOB_COLOR
	mob.Material = Enum.Material.Slate
	mob.Anchored = true
	mob.CanCollide = false
	mob.CFrame = CFrame.new(spawnPosition)
	mob.Parent = door.Parent.Parent

	local distance = (spawnPosition - targetPosition).Magnitude
	local duration = distance / MOB_SPEED_STUDS_PER_SECOND

	local tween = TweenService:Create(mob, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Position = targetPosition })
	tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		-- Re-checked against the OWNER captured at spawn, not just "still
		-- claimed by someone" -- guards against the plot changing hands
		-- entirely while this mob was mid-walk.
		if playbackState == Enum.PlaybackState.Completed and EndlessModeClaimManager.GetOwner(side) == owner then
			if targetPlacementId then
				PetManager.DamageBuilding(owner, targetPlacementId, MOB_DAMAGE)
			else
				EndlessModeClaimManager.DamageBase(side, MOB_DAMAGE)
			end
		end
		if mob.Parent then
			mob:Destroy()
		end
	end)
	tween:Play()
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
