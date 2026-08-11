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
-- obtain. Per explicit request, this is NOT a smooth ramp -- only the
-- genuinely hard-to-get tier (Exclusive/Leaderboards, plus the Godly
-- capstone) gets to be "OP"; Common/Rare/Epic stay close to the shared
-- baseline (1x-4x) so an easy/cheap Tank is still just a basic Tank, not a
-- wall by itself. Loira Chateau (a LARP Battles weekly Top 2 reward -- can't
-- be bought at any price) is the single best tank in the game -- Sol
-- Stadium (that same weekly leaderboard's Top 3 reward, so comparably rare,
-- just one rank down) sits right behind it, ahead of Private Airport
-- (merely priciest to BUY, not competed for) and Solar Park (a Platinum
-- rank threshold, not a weekly Top-3-against-everyone placement).
--
-- A mob hits for MobDamagePerTick every TankTickSeconds (Tanks are pure
-- soak now, per explicit request -- they never hit back, see TankTickSeconds'
-- own comment), and per the "10 Tanks should hold to wave 800-850 (~10h)"
-- target, a single-digit multiplier of the shared 100-HP base dies in
-- seconds, not hours. Exact numbers are still a first pass -- 10 real hours
-- can't be hand-simulated, expect to retune after actual playtesting.
local TANK_HP_MULTIPLIER: { [string]: number } = {
	StudioApartment = 1, -- Common -- baseline, not OP at all
	FamilyHouse = 2, -- Rare
	BeachfrontVilla = 4, -- Epic
	CountrysideMansion = 8, -- Legendary
	PrivateResort = 15, -- Godly -- OP starts here
	SolarPark = 55, -- Exclusive
	PrivateAirport = 70, -- Godly capstone -- priciest purchasable Estate
	Top3Estate = 85, -- "Sol Stadium" (Exclusive, LARP Battles weekly Top 3)
	Top2Estate = 100, -- "Loira Chateau" (Leaderboards, weekly Top 2) -- best tank in the game
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

-- Tank -- pure soak, per explicit request: it never hits back, just absorbs
-- MobDamagePerTick every tick for as long as it's alive, blocking that mob
-- from reaching anything else. It only stops taking hits once it dies
-- (mob re-targets) or something ELSE (a Damage building/Ally) kills the mob
-- independently while it's stuck here.
EndlessModeUnitRoleConfig.TankTickSeconds = 1.5

-- Damage -- same "only the hard-to-get tier gets to be OP" shape as
-- TANK_HP_MULTIPLIER above, just over DamageAmount instead of HP. No
-- Leaderboards-tier Damage Estate exists (Top1Estate is a Spawner), so the
-- ceiling here is ConstructionShop -- the Diamond rank reward, the single
-- HIGHEST rank tier grants, and tied for the highest listed Price in the
-- game ($500T, same as RealEstateEmpire) despite not being purchasable at
-- any price -- comparable prestige to a Tank-tier Leaderboards reward even
-- without one existing in this role.
local DAMAGE_AMOUNT_MULTIPLIER: { [string]: number } = {
	DowntownCondo = 1, -- Common -- baseline, not OP at all
	LuxuryTownhouse = 2, -- Rare
	PrivateEstate = 4, -- Epic
	SkyscraperPenthouse = 8, -- Legendary
	LuxuryHotelChain = 15, -- Godly -- OP starts here
	OldFarm = 40, -- Exclusive (Silver rank reward)
	ConstructionShop = 90, -- Exclusive (Diamond rank reward) -- hardest-hitting Damage Estate
}

-- 1 for anything not a Damage building (or not in the table above) -- a
-- no-op multiplier, same idiom as GetTankHPMultiplier.
function EndlessModeUnitRoleConfig.GetDamageAmountMultiplier(assetId: string): number
	return DAMAGE_AMOUNT_MULTIPLIER[assetId] or 1
end

-- Range gets the same tiered treatment, milder than DamageAmount's since the
-- claimed patch itself is only ~90x65 studs (EndlessModeClaimManager's
-- PATCH_WIDTH/PATCH_DEPTH) -- ConstructionShop's 120 already covers the
-- whole thing (and then some), so a bigger multiplier here would just be
-- wasted range, not more power.
local DAMAGE_RANGE_MULTIPLIER: { [string]: number } = {
	DowntownCondo = 1, -- Common
	LuxuryTownhouse = 1.3, -- Rare
	PrivateEstate = 1.6, -- Epic
	SkyscraperPenthouse = 2, -- Legendary
	LuxuryHotelChain = 2.5, -- Godly -- OP starts here
	OldFarm = 3.5, -- Exclusive (Silver rank reward)
	ConstructionShop = 5, -- Exclusive (Diamond rank reward) -- covers the whole claimed patch
}

function EndlessModeUnitRoleConfig.GetDamageRangeMultiplier(assetId: string): number
	return DAMAGE_RANGE_MULTIPLIER[assetId] or 1
end

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
