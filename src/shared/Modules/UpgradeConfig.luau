-- Permanent, purchased-with-Cash upgrade tracks (Roll Speed, Luck, Potion
-- Boost Time) -- unlike VIP (one-time Robux, flat bonus) or Potions
-- (temporary, Cash), these are incremental: each level costs more than
-- the last and stacks multiplicatively with both VIP and any active
-- Potion, the same "stack, don't replace" shape already established
-- between VIP and PotionConfig.
--
-- Pure leaf module (mirrors PotionConfig/IncomeConfig's role) -- reads a
-- session's Upgrades table, never requires UpgradeManager, so
-- RollManager/PotionManager can use it without a circular require.
--
-- BaseCost was walked up 50x (2000/3000/1500 -> 100000/150000/75000) --
-- against the ORIGINAL pacing target (~30min to $1M, ~2h to $1B), the old
-- ~3.1M total-to-max was trivial, barely denting even the $1M mark.
--
-- MaxLevel doubled from 10 to 20 on every track (per-level effect halved
-- to match, see GetCooldownMultiplier/GetPotionDurationMultiplier/
-- GetLuckMultiplier below) -- same ceiling at max level, just reached in
-- twice as many, smaller individual steps, so the climb feels more gradual
-- instead of jumping in big chunks.
--
-- BaseCost was then walked up ANOTHER 5x on top of that (still felt too
-- cheap even at the ~$616M-total pacing the 50x pass targeted) -- maxing
-- all 3 tracks now costs ~$3.1B total (RollSpeed ~247M, PotionBoost
-- ~128.5M, Luck ~2.72B -- see below for why Luck alone is so much pricier
-- than a smooth curve would give), a real chunk of the climb well past
-- $1B, not something that gets casually maxed along the way -- still
-- finishing short of the late-game Assets/Investments sink, just no
-- longer trivial next to it.
--
-- Luck's FINAL level (19 -> 20) breaks the smooth curve on purpose -- see
-- LUCK_MAX_LEVEL_COST/LUCK_MAX_LEVEL_LUXURY_MULTIPLIER below and
-- GetLuckMultiplier's comment -- a deliberately expensive capstone
-- purchase (~$1.5B by itself) that unlocks a real Luxury-odds bump, not
-- just the token 1.3x every earlier level was already ramping toward. The
-- Luck curve overall is also tuned against VIP/Potion's EXISTING
-- multipliers, not just in isolation -- see its comment below.

local UpgradeConfig = {}

export type Track = {
	Id: string,
	Name: string,
	MaxLevel: number,
	BaseCost: number,
	CostGrowth: number,
}

local tracks: { [string]: Track } = {
	RollSpeed = { Id = "RollSpeed", Name = "Roll Speed", MaxLevel = 20, BaseCost = 500000, CostGrowth = 1.28 },
	Luck = { Id = "Luck", Name = "Luck Chance", MaxLevel = 20, BaseCost = 750000, CostGrowth = 1.28 },
	PotionBoost = { Id = "PotionBoost", Name = "Potion Boost Time", MaxLevel = 20, BaseCost = 375000, CostGrowth = 1.25 },
}
UpgradeConfig.Tracks = tracks

-- Order matters for consistent UI listing, same idea as RarityConfig.Order.
UpgradeConfig.Order = { "RollSpeed", "Luck", "PotionBoost" }

-- Luck's last purchase (level 19 -> 20) is a flat override, not
-- BaseCost*CostGrowth^19 (~$225M) -- a deliberate capstone price jump, same
-- idea as AssetDatabase's RealEstateEmpire/InvestmentDatabase's
-- CelestialCore breaking their own smooth per-tier curve. See
-- GetLuckMultiplier for what it buys.
local LUCK_MAX_LEVEL_COST = 1500000000

-- Cost to go from `currentLevel` to `currentLevel + 1`. nil once maxed.
function UpgradeConfig.GetCost(trackId: string, currentLevel: number): number?
	local track = UpgradeConfig.Tracks[trackId]
	if not track or currentLevel >= track.MaxLevel then
		return nil
	end
	if trackId == "Luck" and currentLevel == track.MaxLevel - 1 then
		return LUCK_MAX_LEVEL_COST
	end
	return math.floor(track.BaseCost * (track.CostGrowth ^ currentLevel))
end

-- Roll Speed: -1.5% cooldown per level, -30% at max level (0.7x) -- same
-- ceiling as before MaxLevel doubled to 20, just spread over twice the
-- steps.
function UpgradeConfig.GetCooldownMultiplier(level: number): number
	return 1 - level * 0.015
end

-- Luck: same "boost non-Common tiers more" shape as VIPConfig/PotionDatabase's
-- Luck Potion, scaled linearly from 1x (level 0) to each rarity's max at
-- MaxLevel. Luxury ramps toward a deliberately mild 1.3x across levels
-- 1-19 (not the old 2x) -- since RarityConfig.Luxury is now almost zero
-- (see that file's header, Luxury is meant to come from Special Rolls, not
-- plain rolls), a smooth 1.3x ceiling would be functionally invisible no
-- matter what it was tuned to.
--
-- LEVEL 20 SPECIFICALLY breaks that curve: instead of landing on the same
-- 1.3x every level was already ramping toward, hitting the actual max
-- level (via the LUCK_MAX_LEVEL_COST capstone purchase above) jumps
-- Luxury straight to LUCK_MAX_LEVEL_LUXURY_MULTIPLIER (50x) -- a real,
-- felt bump exclusively for fully completing the track, not something
-- levels 1-19 partially deliver a share of. Stacked with VIP's 6x and Luck
-- Potion's 1.5x, a fully-built player at Luck level 20 hits 6*1.5*50 =
-- 450x on Luxury (~1 in ~184,000 per roll instead of the old max 11.7x
-- stack's ~1 in 7.1M) -- meaningfully exciting on its own, while staying
-- far short of Emerald Roll's fixed ~1 in 183 (see SpecialRollConfig.luau),
-- so Special Rolls stay the dominant path to Luxury, this is a bonus on
-- top of active rolling for a player who's maxed everything.
local maxLuckWeightMultiplier: { [string]: number } = {
	Common = 1,
	Rare = 1.15,
	Epic = 1.3,
	Legendary = 1.5,
	Ultra = 1.75,
	Luxury = 1.3,
}
UpgradeConfig.MaxLuckWeightMultiplier = maxLuckWeightMultiplier

local LUCK_MAX_LEVEL_LUXURY_MULTIPLIER = 50

function UpgradeConfig.GetLuckMultiplier(level: number, rarity: string): number
	local maxLevel = UpgradeConfig.Tracks.Luck.MaxLevel
	if rarity == "Luxury" and level >= maxLevel then
		return LUCK_MAX_LEVEL_LUXURY_MULTIPLIER
	end

	local maxMult = UpgradeConfig.MaxLuckWeightMultiplier[rarity] or 1
	local t = level / maxLevel
	return 1 + (maxMult - 1) * t
end

-- Potion Boost Time: +2.5% potion duration per level, +50% at max level --
-- same ceiling as before MaxLevel doubled to 20, just spread over twice
-- the steps.
function UpgradeConfig.GetPotionDurationMultiplier(level: number): number
	return 1 + level * 0.025
end

return UpgradeConfig
