-- Allies spawned by Spawner-role placed buildings (PetManager.luau calls
-- EndlessModeAllyManager.SpawnAlly on a timer) -- walks toward the nearest
-- currently-alive mob (EndlessModeMobRegistry) and trades hits with it every
-- tick until one side dies, same "simple prototype, plain block,
-- straight-line TweenService walk" idiom EndlessModeMobManager.luau's own
-- mobs use. An ally with nothing to fight (no mobs currently alive) gives up
-- and despawns after a short idle wait instead of sitting there forever.
--
-- Ally HP is tracked as a plain local (not in EndlessModeMobRegistry) --
-- unlike mobs, nothing OUTSIDE this file ever needs to find/damage an ally,
-- so there's no need to register it in the shared registry.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EndlessModeUnitRoleConfig = require(ReplicatedStorage.Modules.EndlessModeUnitRoleConfig)
local EndlessModeMobRegistry = require(ServerScriptService.Managers.EndlessModeMobRegistry)
local DataManager = require(ServerScriptService.Managers.DataManager)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)

local endlessModeCashUpdated = RemotesBootstrap:WaitForChild("EndlessModeCashUpdated")

-- Credits `owner`'s EndlessModeCash for actually DEFEATING a mob (its own HP
-- hit 0 from this ally's own hit) -- same wave-scaled reward idiom
-- PetManager.luau's own awardMobKillReward uses (duplicated rather than
-- shared, same "each file reads DataManager itself" idiom
-- EndlessModeMobManager.luau's getMobDamage already established, to avoid
-- EndlessModeAllyManager requiring PetManager back -- PetManager already
-- requires THIS file, so that would be circular). Wave is read straight off
-- session.EndlessModeWave (event-gated, see EndlessModeMobManager.luau) now,
-- not derived from elapsed time.
local function awardMobKillReward(owner: Player)
	local session = DataManager.Get(owner)
	if not session then
		return
	end
	session.EndlessModeCash += EndlessModeUnitRoleConfig.GetMobKillRewardForWave(session.EndlessModeWave)
	endlessModeCashUpdated:FireClient(owner, session.EndlessModeCash)
end

local EndlessModeAllyManager = {}

-- Close enough to start trading hits instead of walking closer.
local MELEE_RANGE_STUDS = 6
-- A mob wandering more than this far from an ally mid-melee is treated as
-- "no longer in reach" -- the ally falls back to re-picking (possibly the
-- same) target and walking again, instead of the melee loop tracking a
-- mob that's since moved well away.
local MELEE_BREAK_RANGE_STUDS = MELEE_RANGE_STUDS * 2
-- Seconds with no alive mob anywhere before an idle ally gives up and
-- despawns.
local IDLE_GIVEUP_SECONDS = 6

-- Hard cap on concurrent allies per owner -- without this, a player with
-- several Spawner Estates placed (up to MAX_COPIES_PER_ASSET_TYPE=5 copies
-- each, PetManager.luau) keeps dumping a fresh batch every
-- SpawnerIntervalSeconds(8s) FOREVER regardless of how many earlier allies
-- are still alive/fighting -- each ally is its own task.spawn loop that
-- polls EndlessModeMobRegistry.GetNearestAliveMob (an O(mob count) scan)
-- every second, so an unbounded ally count times an unbounded mob count is
-- exactly the "spawnerii fac lag" complaint. SpawnAlly below just no-ops
-- past this cap instead of queuing/dropping the batch silently -- the next
-- SpawnerIntervalSeconds tick tries again once earlier allies have died off.
local MAX_ACTIVE_ALLIES_PER_OWNER = 12

-- Tracked per owner (not globally) so ClearAlliesForOwner can precisely
-- clean up just one player's allies -- needed because allies aren't tied to
-- a claim/base's own lifecycle at all (SpawnAlly just drops them in a
-- shared global folder), so without this they'd keep fighting forever even
-- after the owner's base died or they disconnected, same orphaning bug
-- EndlessModeMobManager's mobs had (see EndlessModeClaimManager.
-- ClaimReleased) -- PetManager.luau calls ClearAlliesForOwner from the same
-- two spots it already calls clearAllPlacedBuildings from (disconnect and
-- BaseDestroyed).
local activeAlliesByOwner: { [Player]: { BasePart } } = {}

local function trackAlly(owner: Player, ally: BasePart)
	local owned = activeAlliesByOwner[owner]
	if not owned then
		owned = {}
		activeAlliesByOwner[owner] = owned
	end
	table.insert(owned, ally)
end

local function untrackAlly(owner: Player, ally: BasePart)
	local owned = activeAlliesByOwner[owner]
	if not owned then
		return
	end
	local index = table.find(owned, ally)
	if index then
		table.remove(owned, index)
	end
end

-- PetManager.luau calls this from its PlayerRemoving handler and its
-- EndlessModeClaimManager.BaseDestroyed listener, same two spots
-- clearAllPlacedBuildings already runs from.
function EndlessModeAllyManager.ClearAlliesForOwner(owner: Player)
	local owned = activeAlliesByOwner[owner]
	if not owned then
		return
	end
	local snapshot = table.clone(owned)
	for _, ally in snapshot do
		if ally.Parent then
			ally:Destroy()
		end
	end
	activeAlliesByOwner[owner] = nil
end

local function getAlliesFolder(): Folder
	local mapFolder = Workspace:FindFirstChild("Map")
	local parent: Instance = mapFolder or Workspace
	local folder = parent:FindFirstChild("EndlessModeAllies")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "EndlessModeAllies"
		folder.Parent = parent
	end
	return folder :: Folder
end

-- Per-Estate custom ally look -- per explicit "am adaugat pentru spawneri
-- pentru alias un model 3D Chef" request, Premium Restaurant's (CrateManor)
-- allies use the manually-placed "Chef" model under
-- ReplicatedStorage.EndlessModeEffects instead of the generic blue Neon
-- ball every other Spawner's allies still use. Same "manually placed
-- Studio content, name-keyed lookup" idiom PetManager.luau's own
-- EXPLOSION_PROJECTILE_CONFIG/BULLET_MODEL_NAME_BY_ASSET_ID use for thrown
-- Damage effects.
local ALLY_MODEL_NAME_BY_ASSET_ID: { [string]: string } = {
	CrateManor = "Chef", -- "Premium Restaurant"
	Top1Estate = "Abr Ai Balt", -- "Abra Ai Balt"
	CrateCastle = "Dream Casle", -- "Dream Castle"
	CratePalace = "Banker", -- "Central Bank"
}

local function getAllyEffectTemplate(templateName: string): Instance?
	local effectsFolder = ReplicatedStorage:FindFirstChild("EndlessModeEffects")
	if not effectsFolder then
		return nil
	end
	return effectsFolder:FindFirstChild(templateName)
end

-- `ally` (the plain invisible-once-this-runs Part) keeps driving every bit
-- of movement/distance/HP logic in SpawnAlly below completely unchanged --
-- this only attaches a cosmetic clone that's kept pivoted to match `ally`'s
-- own Position every time it changes (including mid-tween, since Position
-- is what TweenService is actually animating), facing whichever direction
-- it last moved in. No-ops (leaves the generic ball fully visible) if this
-- assetId has no custom model configured above, or the model isn't
-- actually present in ReplicatedStorage.EndlessModeEffects yet.
local function attachAllyVisual(ally: BasePart, assetId: string)
	local templateName = ALLY_MODEL_NAME_BY_ASSET_ID[assetId]
	if not templateName then
		return
	end

	local template = getAllyEffectTemplate(templateName)
	local usableTemplate = template and (template:IsA("Model") or template:IsA("BasePart")) and template
	if not usableTemplate then
		return
	end

	ally.Transparency = 1

	local visual = usableTemplate:Clone()
	local humanoid = visual:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		humanoid:Destroy()
	end

	-- Manually placed Studio models (the Chef etc.) routinely come in with
	-- Anchored = false on some/all of their parts -- same "sinks/topples
	-- under gravity between position updates" bug PetManager.luau's own
	-- anchorTemplate already fixes for pets/placed buildings. This clone is
	-- driven entirely by pivotVisual below (never physics), so every part
	-- needs to be Anchored or it visibly falls/collapses while the ally
	-- stands still mid-fight (no Position change to re-sync it).
	if visual:IsA("Model") then
		for _, descendant in visual:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end
	elseif visual:IsA("BasePart") then
		visual.Anchored = true
	end

	visual.Parent = Workspace

	local lastPosition = ally.Position
	local facingRotation = CFrame.new()

	local function pivotVisual(cframe: CFrame)
		if visual:IsA("Model") then
			visual:PivotTo(cframe)
		elseif visual:IsA("BasePart") then
			visual.CFrame = cframe
		end
	end

	local function sync()
		local currentPosition = ally.Position
		local delta = currentPosition - lastPosition
		if delta.Magnitude > 0.05 then
			facingRotation = CFrame.lookAt(Vector3.new(), delta.Unit)
		end
		pivotVisual(CFrame.new(currentPosition) * facingRotation)
		lastPosition = currentPosition
	end
	sync()

	local connection = ally:GetPropertyChangedSignal("Position"):Connect(sync)
	ally.Destroying:Connect(function()
		connection:Disconnect()
		visual:Destroy()
	end)
end

-- `owner` -- credited with EndlessModeCash for every mob this ally actually
-- defeats. `assetId` -- which placed Spawner Estate spawned this batch,
-- used only to look up a custom ally model (attachAllyVisual/
-- ALLY_MODEL_NAME_BY_ASSET_ID above) -- everything else about the ally
-- stays identical regardless of assetId. `mobDamagePerTick` -- the CURRENT
-- wave-scaled mob damage (EndlessModeMobManager.luau's getMobDamage,
-- computed by the caller since it needs the owner's own session/wave,
-- which this file has no reason to know about otherwise) -- how hard the
-- mob this ally ends up fighting hits back. `powerMultiplier` --
-- EndlessModeUnitRoleConfig.GetSpawnerPowerMultiplier(assetId), also
-- computed by the caller (PetManager.luau, which knows which Spawner
-- Estate this is) -- scales the ally's OWN HP and damage output, same
-- "hard-to-get tier gets to be OP" idiom Tank/Damage already use.
function EndlessModeAllyManager.SpawnAlly(owner: Player, assetId: string, position: Vector3, mobDamagePerTick: number, powerMultiplier: number?)
	if #(activeAlliesByOwner[owner] or {}) >= MAX_ACTIVE_ALLIES_PER_OWNER then
		return
	end

	task.spawn(function()
		local multiplier = powerMultiplier or 1

		local ally = Instance.new("Part")
		ally.Name = "EndlessMode_Ally"
		ally.Size = EndlessModeUnitRoleConfig.AllySize
		ally.Color = EndlessModeUnitRoleConfig.AllyColor
		ally.Material = Enum.Material.Neon
		ally.Anchored = true
		ally.CanCollide = false
		ally.CFrame = CFrame.new(position)
		ally.Parent = getAlliesFolder()
		trackAlly(owner, ally)
		attachAllyVisual(ally, assetId)

		local hp = EndlessModeUnitRoleConfig.AllyHP * multiplier
		local damagePerTick = EndlessModeUnitRoleConfig.AllyDamagePerTick * multiplier
		local idleSecondsWaited = 0

		while ally.Parent do
			local mob = EndlessModeMobRegistry.GetNearestAliveMob(ally.Position)
			if not mob then
				task.wait(1)
				idleSecondsWaited += 1
				if idleSecondsWaited >= IDLE_GIVEUP_SECONDS then
					untrackAlly(owner, ally)
					ally:Destroy()
					return
				end
				continue
			end
			idleSecondsWaited = 0

			local distance = (mob.Position - ally.Position).Magnitude
			if distance > MELEE_RANGE_STUDS then
				local duration = distance / EndlessModeUnitRoleConfig.AllySpeedStudsPerSecond
				local tween = TweenService:Create(ally, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Position = mob.Position })
				tween:Play()
				tween.Completed:Wait()
				if not ally.Parent then
					return
				end
			end

			-- Trade hits every tick until one side dies or the mob wanders
			-- out of melee range entirely (walked off toward its own
			-- target while this ally was mid-swing).
			while
				ally.Parent
				and EndlessModeMobRegistry.IsAlive(mob)
				and mob.Parent
				and (mob.Position - ally.Position).Magnitude <= MELEE_BREAK_RANGE_STUDS
			do
				task.wait(EndlessModeUnitRoleConfig.AllyTickSeconds)
				if not ally.Parent then
					return
				end
				if not EndlessModeMobRegistry.IsAlive(mob) or not mob.Parent then
					break
				end

				if EndlessModeMobRegistry.Damage(mob, damagePerTick) then
					awardMobKillReward(owner)
					break
				end

				hp -= mobDamagePerTick
				if hp <= 0 then
					untrackAlly(owner, ally)
					ally:Destroy()
					return
				end
			end
		end
	end)
end

return EndlessModeAllyManager
