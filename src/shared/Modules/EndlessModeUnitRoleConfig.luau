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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EndlessModeBuildingConfig = require(ReplicatedStorage.Modules.EndlessModeBuildingConfig)

export type UnitRole = "Tank" | "Damage" | "Spawner"

local EndlessModeUnitRoleConfig = {}

-- Per explicit request: an Estate's rarity-based "OP-ness" isn't available
-- starting at level 0/1 -- EVERY Estate starts at the same 1x baseline
-- (a level-1 Loira Chateau is meant to feel about as weak as a level-1
-- Studio Apartment) and only reaches its full listed multiplier (200x for
-- Loira Chateau, etc.) once it's actually upgraded all the way to
-- EndlessModeBuildingConfig.MaxUpgradeLevel. Linear in between. Applies to
-- all 3 roles' multiplier tables below (Tank HP, Damage amount/range,
-- Spawner power) -- "good only at max level" is a property of the whole
-- economy, not just one stat.
local function scaleMultiplierByLevel(fullMultiplier: number, upgradeLevel: number): number
	local progress = math.clamp(upgradeLevel / EndlessModeBuildingConfig.MaxUpgradeLevel, 0, 1)
	return 1 + (fullMultiplier - 1) * progress
end

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
-- own comment). Combined with EndlessModeMobManager.luau's
-- MAX_CONCURRENT_TANK_ATTACKERS cap (a Tank that never kills its attackers
-- needs a hard cap on how many can pile onto it at once, or the sustained
-- damage rate only ever grows), the top 3 (SolarPark/PrivateAirport/
-- Top3Estate/Top2Estate) get a large enough multiplier that they hold for
-- several waves under that capped worst-case rate, per explicit request --
-- Common/Rare/Epic/early-Godly stay near baseline (1x-15x) so an easy/cheap
-- Tank is still just a basic Tank, not a wall by itself. Exact numbers are
-- still a first pass -- can't be hand-simulated over a real multi-wave run,
-- expect to retune after actual playtesting.
local TANK_HP_MULTIPLIER: { [string]: number } = {
	StudioApartment = 1, -- Common -- baseline, not OP at all
	FamilyHouse = 2, -- Rare
	BeachfrontVilla = 4, -- Epic
	CountrysideMansion = 8, -- Legendary
	PrivateResort = 15, -- Godly -- OP starts here
	SolarPark = 90, -- Exclusive
	-- Lowered from 120, per explicit request -- Central Bank/Premium
	-- Restaurant/Storage Unit (Spawner) needed to overtake it in the overall
	-- top 10, without gutting it as a Tank (still well above baseline,
	-- still a real wall, just no longer top-10-overall material).
	PrivateAirport = 22, -- Godly capstone -- priciest purchasable Estate
	Top3Estate = 150, -- "Sol Stadium" (Exclusive, LARP Battles weekly Top 3)
	Top2Estate = 200, -- "Loira Chateau" (Leaderboards, weekly Top 2) -- best tank in the game
}

-- 1 for anything not a Tank (or not in the table above) -- a no-op
-- multiplier, so callers can always safely multiply by this without
-- special-casing non-Tank roles. Ramps in with upgradeLevel -- see
-- scaleMultiplierByLevel above.
function EndlessModeUnitRoleConfig.GetTankHPMultiplier(assetId: string, upgradeLevel: number): number
	return scaleMultiplierByLevel(TANK_HP_MULTIPLIER[assetId] or 1, upgradeLevel)
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

-- EndlessModeCash awarded for actually DEFEATING a mob (its HP hit 0 from a
-- Damage building or an Ally -- not a mob that just delivered its hit and
-- despawned against a building/base/full Tank, see PetManager.luau/
-- EndlessModeAllyManager.luau's own OnDeath-triggered award). Base value
-- (wave 1) is enough for the first 2 upgrade levels (500+1000 =
-- EndlessModeBuildingConfig's own costs), per explicit request -- scales up
-- on the SAME every-20-wave tier as everything else here, so it keeps pace
-- as upgrades get pricier deeper into a run instead of becoming trivial.
EndlessModeUnitRoleConfig.MobKillReward = 1500

function EndlessModeUnitRoleConfig.GetMobKillRewardForWave(wave: number): number
	local tier = math.floor((math.max(wave, 1) - 1) / WAVE_DAMAGE_TIER_SIZE)
	local multiplier = 1 + tier * WAVE_DAMAGE_INCREMENT_PER_TIER
	return math.floor(EndlessModeUnitRoleConfig.MobKillReward * multiplier)
end

-- Same every-20-wave tier/rate as GetMobDamageForWave above, just applied to
-- MobHP instead -- a regular mob at wave 21 is tougher than one at wave 1,
-- not just harder-hitting. EndlessModeMobManager.luau's Boss HP is derived
-- from this too (10x whatever a regular mob at the PRECEDING wave has, per
-- explicit request), so it scales up right along with everything else.
function EndlessModeUnitRoleConfig.GetMobHPForWave(wave: number): number
	local tier = math.floor((math.max(wave, 1) - 1) / WAVE_DAMAGE_TIER_SIZE)
	local multiplier = 1 + tier * WAVE_DAMAGE_INCREMENT_PER_TIER
	return math.floor(EndlessModeUnitRoleConfig.MobHP * multiplier)
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
	-- Lowered from 40, per explicit request -- same reasoning as
	-- PrivateAirport above (TANK_HP_MULTIPLIER): Central Bank/Premium
	-- Restaurant/Storage Unit needed to overtake it overall, without
	-- gutting it as a Damage Estate.
	OldFarm = 18, -- Exclusive (Silver rank reward)
	ConstructionShop = 90, -- Exclusive (Diamond rank reward) -- hardest-hitting Damage Estate
}

-- 1 for anything not a Damage building (or not in the table above) -- a
-- no-op multiplier, same idiom as GetTankHPMultiplier -- also ramps in with
-- upgradeLevel the same way.
function EndlessModeUnitRoleConfig.GetDamageAmountMultiplier(assetId: string, upgradeLevel: number): number
	return scaleMultiplierByLevel(DAMAGE_AMOUNT_MULTIPLIER[assetId] or 1, upgradeLevel)
end

export type DamageEffectType = "Bullet" | "Laser" | "Explosion"

-- Per explicit request ("nu vreau sa aiba toate efect de laser") -- 3
-- different visual attack effects grouped by rarity, not one shared laser
-- scaled by thickness: Common/Rare get a small traveling bullet ("un mic
-- efect"), Epic/Legendary get the laser beam, Godly/Exclusive get a bigger
-- impact/explosion at the target instead. PetManager.luau's
-- showDamageEffect dispatches on this.
local DAMAGE_EFFECT_TYPE: { [string]: DamageEffectType } = {
	DowntownCondo = "Bullet", -- Common
	LuxuryTownhouse = "Bullet", -- Rare
	PrivateEstate = "Laser", -- Epic
	SkyscraperPenthouse = "Laser", -- Legendary
	LuxuryHotelChain = "Explosion", -- Godly
	OldFarm = "Explosion", -- Exclusive
	ConstructionShop = "Explosion", -- Exclusive
}

-- "Laser" for anything not a Damage building (or not in the table above) --
-- matches the original single-effect behavior as a safe fallback.
function EndlessModeUnitRoleConfig.GetDamageEffectType(assetId: string): DamageEffectType
	return DAMAGE_EFFECT_TYPE[assetId] or "Laser"
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

function EndlessModeUnitRoleConfig.GetDamageRangeMultiplier(assetId: string, upgradeLevel: number): number
	return scaleMultiplierByLevel(DAMAGE_RANGE_MULTIPLIER[assetId] or 1, upgradeLevel)
end

EndlessModeUnitRoleConfig.DamageAmount = 18
EndlessModeUnitRoleConfig.DamageRangeStuds = 24

-- Explosion-tier Estates (Luxury Hotel Chain, Old Farm, Construction Shop)
-- hit EVERY mob within this many studs of where the blast actually lands,
-- not just the one originally targeted -- per explicit request, so a
-- cluster of mobs standing together (e.g. a big wave) can get wiped by a
-- single hit instead of the AOE tier behaving identically to Bullet/Laser's
-- single-target hits. Flat and NOT level/rarity-scaled -- it's a shared
-- property of the "Explosion" effect itself, same as every Explosion Estate
-- getting the same core-flash/native-blast visuals regardless of tier.
EndlessModeUnitRoleConfig.ExplosionAoeRadiusStuds = 12

-- Attack cooldown itself is now ALSO part of the "good only at max level"
-- ramp, per explicit request -- a freshly-placed (level 0) Damage Estate
-- attacks slowly, and every upgrade shaves the wait down, same 5-step
-- table idiom EndlessModeBuildingConfig.SCALE_MULTIPLIER_BY_LEVEL already
-- uses (a flat per-level table, not a formula, since it's an explicit
-- 5-step curve, not something meant to be computed). Level 0 continues the
-- same -0.5s/level line the requested 1-5 values already trace (3, 2.5, 2,
-- 1.5, 1) one more step back.
local DAMAGE_COOLDOWN_SECONDS_BY_LEVEL = {
	[0] = 3.5,
	[1] = 3,
	[2] = 2.5,
	[3] = 2,
	[4] = 1.5,
	[5] = 1,
}

-- Per-Estate cooldown multiplier, on top of the level curve above -- per
-- explicit request, Downtown Condo (the weakest Damage Estate: ×1 damage,
-- ×1 range, no OP ceiling at all) attacks noticeably faster to compensate,
-- instead of hitting the softest AND the slowest. 1 (no change) for
-- everything else.
local DAMAGE_COOLDOWN_MULTIPLIER_BY_ASSET_ID: { [string]: number } = {
	DowntownCondo = 0.5, -- attacks twice as often as the level curve alone would give
}

function EndlessModeUnitRoleConfig.GetDamageCooldownSeconds(assetId: string, upgradeLevel: number): number
	local level = math.clamp(upgradeLevel, 0, EndlessModeBuildingConfig.MaxUpgradeLevel)
	local multiplier = DAMAGE_COOLDOWN_MULTIPLIER_BY_ASSET_ID[assetId] or 1
	return DAMAGE_COOLDOWN_SECONDS_BY_LEVEL[level] * multiplier
end

-- Spawner / its allies -- AllyHP/AllyDamagePerTick below are the BASE
-- (1x) values; GetSpawnerPowerMultiplier scales both together per Estate,
-- same "hard-to-get tier gets to be OP" idiom Tank/Damage already use.
-- Deliberately does NOT touch SpawnerIntervalSeconds (how OFTEN a new BATCH
-- of allies spawns) -- unlike HP/damage, scaling spawn RATE risks the same
-- runaway-spam problem MAX_MOBS_PER_WAVE had to cap elsewhere, so every
-- Spawner sends out a batch at the same pace; GetSpawnerAllyCount below
-- controls how MANY allies come out per batch instead, per explicit
-- request ("la inceput 1, dupa mai multi") -- 1 at low levels, ramping to 3
-- at MaxUpgradeLevel.
EndlessModeUnitRoleConfig.SpawnerIntervalSeconds = 8
EndlessModeUnitRoleConfig.AllyHP = 50
EndlessModeUnitRoleConfig.AllyDamagePerTick = 12
EndlessModeUnitRoleConfig.AllyTickSeconds = 1
EndlessModeUnitRoleConfig.AllySpeedStudsPerSecond = 10
EndlessModeUnitRoleConfig.AllySize = Vector3.new(2, 2.5, 2)
EndlessModeUnitRoleConfig.AllyColor = Color3.fromRGB(60, 140, 220)

-- How many allies come out in a single batch (every SpawnerIntervalSeconds)
-- -- 1 at low levels, ramping up to 3 at MaxUpgradeLevel. Same shape as
-- scaleMultiplierByLevel but over a small integer count instead of a
-- multiplier, so it's kept separate rather than reusing that helper.
function EndlessModeUnitRoleConfig.GetSpawnerAllyCount(upgradeLevel: number): number
	local progress = math.clamp(upgradeLevel / EndlessModeBuildingConfig.MaxUpgradeLevel, 0, 1)
	return 1 + math.floor(progress * 2)
end

-- Abra Ai Balt (Top1Estate -- the LARP Battles weekly Top 1 reward, one rank
-- HARDER to get than Loira Chateau's Top 2) ends up the single highest
-- multiplier in the whole game before Dream Castle below, ahead of every
-- Tank -- fitting, since it's the single hardest reward-based thing to
-- obtain. Supermarket (Gold rank reward) sits between the Silver-reward-
-- tier (~40x on the Damage side) and the Platinum/Diamond-tier (~90x),
-- matching its own rank's position. RealEstateEmpire is the priciest
-- PURCHASABLE Estate in the game ($500T, tied with ConstructionShop)
-- despite not being a reward.
--
-- Dream Castle (CrateCastle), per explicit request, is THE single rarest
-- Estate in the entire game -- pulled from a Crate (pure RNG), it's the
-- ONLY Estate anywhere with no guaranteed path to owning it at all: every
-- reward tier above (rank, weekly leaderboard) is guaranteed EVENTUALLY
-- just by playing/grinding, but a Crate pull might never land. Its
-- multiplier is set above every other Estate's in the game (Tank, Damage,
-- or Spawner) to reflect that.
local SPAWNER_POWER_MULTIPLIER: { [string]: number } = {
	-- Storage Unit/Premium Restaurant/Central Bank bumped up from their
	-- original 1/2/4, per explicit request -- meant to land in the overall
	-- top 10 (ahead of Old Farm/Private Airport, which were lowered to
	-- make room, see TANK_HP_MULTIPLIER/DAMAGE_AMOUNT_MULTIPLIER above).
	CrateVilla = 25, -- "Storage Unit" (Rare)
	CrateManor = 35, -- "Premium Restaurant" (Epic)
	-- Raised from 48, per explicit request -- Central Bank now beats the
	-- Solar Park/Construction Shop tier (90) to sit at #5 overall.
	CratePalace = 100, -- "Central Bank" (Legendary)
	-- Raised from 40, per explicit request -- lands right behind the Solar
	-- Park/Construction Shop tier (90) at #7 overall.
	RealEstateEmpire = 80, -- Godly -- priciest purchasable Estate in the game -- OP starts here
	-- Lowered from 50, per explicit request -- pushed out of the overall
	-- top 10 by Real Estate Empire above (still well above baseline, just
	-- no longer top-10-overall material).
	Supermarket = 20, -- Exclusive (Gold rank reward)
	Top1Estate = 250, -- "Abra Ai Balt" (Leaderboards, weekly Top 1)
	CrateCastle = 300, -- "Dream Castle" (Luxury, pure Crate RNG) -- rarest, best Estate in the entire game
}

-- 1 for anything not a Spawner building (or not in the table above) -- a
-- no-op multiplier, same idiom as GetTankHPMultiplier/GetDamageAmountMultiplier
-- -- also ramps in with upgradeLevel the same way.
function EndlessModeUnitRoleConfig.GetSpawnerPowerMultiplier(assetId: string, upgradeLevel: number): number
	return scaleMultiplierByLevel(SPAWNER_POWER_MULTIPLIER[assetId] or 1, upgradeLevel)
end

return EndlessModeUnitRoleConfig
