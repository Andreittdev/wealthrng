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

-- `mobDamagePerTick` -- the CURRENT wave-scaled mob damage (EndlessModeMobManager.
-- luau's getMobDamage, computed by the caller since it needs the owner's own
-- session/wave, which this file has no reason to know about otherwise) --
-- how hard the mob this ally ends up fighting hits back.
function EndlessModeAllyManager.SpawnAlly(position: Vector3, mobDamagePerTick: number)
	task.spawn(function()
		local ally = Instance.new("Part")
		ally.Name = "EndlessMode_Ally"
		ally.Size = EndlessModeUnitRoleConfig.AllySize
		ally.Color = EndlessModeUnitRoleConfig.AllyColor
		ally.Material = Enum.Material.Neon
		ally.Anchored = true
		ally.CanCollide = false
		ally.CFrame = CFrame.new(position)
		ally.Parent = getAlliesFolder()

		local hp = EndlessModeUnitRoleConfig.AllyHP
		local idleSecondsWaited = 0

		while ally.Parent do
			local mob = EndlessModeMobRegistry.GetNearestAliveMob(ally.Position)
			if not mob then
				task.wait(1)
				idleSecondsWaited += 1
				if idleSecondsWaited >= IDLE_GIVEUP_SECONDS then
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

				EndlessModeMobRegistry.Damage(mob, EndlessModeUnitRoleConfig.AllyDamagePerTick)
				if not EndlessModeMobRegistry.IsAlive(mob) then
					break
				end

				hp -= mobDamagePerTick
				if hp <= 0 then
					ally:Destroy()
					return
				end
			end
		end
	end)
end

return EndlessModeAllyManager
