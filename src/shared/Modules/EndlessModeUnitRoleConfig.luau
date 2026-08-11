-- Combat role for each placeable Estate in Endless Mode -- Tank (blocks
-- whichever mob targets it: the mob stops there and they trade hits every
-- tick until one dies, instead of the mob dealing one hit and moving on),
-- Damage (never targeted by mobs in any special way, just periodically
-- attacks whichever mob wanders within range on its own), or Spawner
-- (periodically sends out an ally that seeks the nearest mob and fights it,
-- same trade-hits idiom as Tank). Assigned per Estate PRICE TIER (not
-- individually) so every price bracket has at least a Tank+Damage pair, with
-- Spawner appearing from the Rare tier up as a more advanced option --
-- confirmed with the user before implementing, see conversation.
--
-- Flat per-role stats, not per-Estate -- same "one placeholder number for
-- everything of this kind" idiom MOB_DAMAGE etc. already used, easy to
-- retune later without touching 23 separate entries. MobHP/MobDamagePerTick
-- live here (not in EndlessModeMobManager.luau) so EndlessModeAllyManager.
-- luau's ally-vs-mob melee can reference the same "how hard does a mob hit"
-- number without requiring EndlessModeMobManager back (would be circular).

export type UnitRole = "Tank" | "Damage" | "Spawner"

local EndlessModeUnitRoleConfig = {}

local ROLES: { [string]: UnitRole } = {
	-- Common
	StudioApartment = "Tank",
	DowntownCondo = "Damage",
	-- Rare
	FamilyHouse = "Tank",
	LuxuryTownhouse = "Damage",
	CrateVilla = "Spawner", -- "Storage Unit"
	-- Epic
	BeachfrontVilla = "Tank",
	PrivateEstate = "Damage",
	CrateManor = "Spawner", -- "Premium Restaurant"
	-- Legendary
	CountrysideMansion = "Tank",
	SkyscraperPenthouse = "Damage",
	CratePalace = "Spawner", -- "Central Bank"
	-- Luxury
	CrateCastle = "Spawner", -- "Dream Castle"
	-- Godly
	PrivateResort = "Tank",
	LuxuryHotelChain = "Damage",
	RealEstateEmpire = "Spawner",
	PrivateAirport = "Tank",
	-- Exclusive
	Top3Estate = "Tank", -- "Sol Stadium"
	OldFarm = "Damage",
	Supermarket = "Spawner",
	SolarPark = "Tank",
	ConstructionShop = "Damage",
	-- Leaderboards
	Top2Estate = "Tank", -- "Loira Chateau"
	Top1Estate = "Spawner", -- "Abra Ai Balt"
}

function EndlessModeUnitRoleConfig.GetRole(assetId: string): UnitRole?
	return ROLES[assetId]
end

-- How much extra HP a Tank gets, on top of EndlessModeBuildingConfig's own
-- Base+per-upgrade formula (which stays the SAME for every building
-- regardless of type) -- scales with how hard that specific Estate is to
-- obtain, per explicit request: Loira Chateau (a LARP Battles weekly Top 2
-- reward -- can't be bought at any price) is the single best tank in the
-- game, Private Airport (the 2nd-priciest purchasable capstone) right
-- behind it, then the rest ranked by Price/rarity down to Studio Apartment
-- (weakest Tank).
--
-- Scale (~20x-120x, not the original 1x-5x): a mob hits for MobDamagePerTick
-- every TankTickSeconds, and per the "10 Tanks should hold to wave 800-850
-- (~10h)" target, a single-digit multiplier of the shared 100-HP base dies
-- in seconds, not hours -- see TankDamagePerTick's comment for the other
-- half of this fix (killing mobs faster so each one costs the Tank less HP
-- before dying). Exact numbers are still a first pass -- 10 real hours can't
-- be hand-simulated, expect to retune after actual playtesting.
local TANK_HP_MULTIPLIER: { [string]: number } = {
	StudioApartment = 20,
	FamilyHouse = 26,
	BeachfrontVilla = 32,
	CountrysideMansion = 40,
	PrivateResort = 50,
	Top3Estate = 60, -- "Sol Stadium"
	SolarPark = 70,
	PrivateAirport = 90,
	Top2Estate = 120, -- "Loira Chateau" -- best tank in the game
}

-- 1 for anything not a Tank (or not in the table above) -- a no-op
-- multiplier, so callers can always safely multiply by this without
-- special-casing non-Tank roles.
function EndlessModeUnitRoleConfig.GetTankHPMultiplier(assetId: string): number
	return TANK_HP_MULTIPLIER[assetId] or 1
end

-- Mobs -- HP is new (they used to have none, dealing one hit and despawning
-- unconditionally); MobDamagePerTick replaces EndlessModeMobManager's old
-- local MOB_DAMAGE constant, same value, just promoted here so it's shared.
-- This is the BASE damage at wave 1 -- see GetMobDamageForWave below for how
-- it actually scales up as waves climb.
EndlessModeUnitRoleConfig.MobHP = 60
EndlessModeUnitRoleConfig.MobDamagePerTick = 20

-- Per explicit request: mobs hit harder every 20 waves, not a flat amount
-- for the whole 800-wave run -- otherwise a strong-enough defense placed
-- early just coasts forever with nothing left to react to. +15% per 20-wave
-- tier means wave 800 (tier 39) mobs hit for ~6.85x their wave-1 damage --
-- placeholder rate, easy to retune, can't be hand-simulated over a real
-- 10-hour run so expect to adjust after actual playtesting.
local WAVE_DAMAGE_TIER_SIZE = 20
local WAVE_DAMAGE_INCREMENT_PER_TIER = 0.15

-- Callers (EndlessModeMobManager.luau, PetManager.luau's Spawner-ally hookup)
-- look up the OWNER's own current wave (WaveConfig.GetWaveForElapsedSeconds
-- on their session's EndlessModeElapsedSeconds) and pass it in here -- this
-- module doesn't read DataManager/WaveConfig itself to avoid pulling a
-- server-only dependency into a module also read by client code
-- (EndlessModeBuildingPanel.luau etc. only need the role/HP side of this
-- file, but Luau doesn't let a ModuleScript be "half required").
function EndlessModeUnitRoleConfig.GetMobDamageForWave(wave: number): number
	local tier = math.floor((math.max(wave, 1) - 1) / WAVE_DAMAGE_TIER_SIZE)
	local multiplier = 1 + tier * WAVE_DAMAGE_INCREMENT_PER_TIER
	return math.floor(EndlessModeUnitRoleConfig.MobDamagePerTick * multiplier)
end

-- Tank -- was 8 (a mob took 8 ticks/~160 total damage to kill), which meant
-- EVERY mob that engaged a Tank cost it 160 HP before dying -- with mobs
-- spawning every 6s but taking 12s each to die, ~2 were chewing on the same
-- Tank at once indefinitely, melting even a large HP pool in minutes. Raised
-- so a mob (MobHP=60) dies in 2 ticks/3s instead of 8/12s -- costs the Tank
-- only ~40 HP per mob (2 ticks * MobDamagePerTick) rather than 160, and
-- fewer mobs overlap since each one is gone before the next spawns.
EndlessModeUnitRoleConfig.TankDamagePerTick = 40
EndlessModeUnitRoleConfig.TankTickSeconds = 1.5

-- Damage
EndlessModeUnitRoleConfig.DamageAmount = 18
EndlessModeUnitRoleConfig.DamageTickSeconds = 1
EndlessModeUnitRoleConfig.DamageRangeStuds = 24

-- Spawner / its allies
EndlessModeUnitRoleConfig.SpawnerIntervalSeconds = 8
EndlessModeUnitRoleConfig.AllyHP = 50
EndlessModeUnitRoleConfig.AllyDamagePerTick = 12
EndlessModeUnitRoleConfig.AllyTickSeconds = 1
EndlessModeUnitRoleConfig.AllySpeedStudsPerSecond = 10
EndlessModeUnitRoleConfig.AllySize = Vector3.new(2, 2.5, 2)
EndlessModeUnitRoleConfig.AllyColor = Color3.fromRGB(60, 140, 220)

return EndlessModeUnitRoleConfig
