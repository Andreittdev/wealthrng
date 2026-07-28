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
-- Costs are tuned against the established pacing (~30min to $1M,
-- ~2h to $1B): maxing all 3 tracks costs ~3.1M total (RollSpeed ~890k,
-- Luck ~1.65M -- priciest since it's the most impactful, PotionBoost
-- ~537k), so it's a real early-to-mid-game Cash sink that's fully done
-- well before the $1B mark, not competing with Assets as the late-game
-- sink. The Luck curve specifically is also tuned against VIP/Potion's
-- EXISTING multipliers, not just in isolation -- see its comment below.

local UpgradeConfig = {}

export type Track = {
	Id: string,
	Name: string,
	MaxLevel: number,
	BaseCost: number,
	CostGrowth: number,
}

local tracks: { [string]: Track } = {
	RollSpeed = { Id = "RollSpeed", Name = "Roll Speed", MaxLevel = 10, BaseCost = 2000, CostGrowth = 1.8 },
	Luck = { Id = "Luck", Name = "Luck Chance", MaxLevel = 10, BaseCost = 3000, CostGrowth = 1.85 },
	PotionBoost = { Id = "PotionBoost", Name = "Potion Boost Time", MaxLevel = 10, BaseCost = 1500, CostGrowth = 1.75 },
}
UpgradeConfig.Tracks = tracks

-- Order matters for consistent UI listing, same idea as RarityConfig.Order.
UpgradeConfig.Order = { "RollSpeed", "Luck", "PotionBoost" }

-- Cost to go from `currentLevel` to `currentLevel + 1`. nil once maxed.
function UpgradeConfig.GetCost(trackId: string, currentLevel: number): number?
	local track = UpgradeConfig.Tracks[trackId]
	if not track or currentLevel >= track.MaxLevel then
		return nil
	end
	return math.floor(track.BaseCost * (track.CostGrowth ^ currentLevel))
end

-- Roll Speed: -3% cooldown per level, -30% at max level (0.7x).
function UpgradeConfig.GetCooldownMultiplier(level: number): number
	return 1 - level * 0.03
end

-- Luck: same "boost non-Common tiers more" shape as VIPConfig/PotionDatabase's
-- Luck Potion, scaled linearly from 1x (level 0) to each rarity's max at
-- MaxLevel. Deliberately milder at the top than VIP's (6x Luxury) and the
-- Luck Potion's (3.5x Luxury) own multipliers -- those two ALREADY stack
-- to 21x on Luxury by themselves; a full 4x here on top would compound to
-- 84x (Luxury odds crashing from ~1-in-50k to ~1-in-1.4k), which guts the
-- "genuine rare moment" the whole Luxury tier exists for. This curve adds
-- a real, worth-buying boost without being the dominant multiplier.
local maxLuckWeightMultiplier: { [string]: number } = {
	Common = 1,
	Rare = 1.15,
	Epic = 1.3,
	Legendary = 1.5,
	Ultra = 1.75,
	Luxury = 2,
}
UpgradeConfig.MaxLuckWeightMultiplier = maxLuckWeightMultiplier

function UpgradeConfig.GetLuckMultiplier(level: number, rarity: string): number
	local maxMult = UpgradeConfig.MaxLuckWeightMultiplier[rarity] or 1
	local t = level / UpgradeConfig.Tracks.Luck.MaxLevel
	return 1 + (maxMult - 1) * t
end

-- Potion Boost Time: +5% potion duration per level, +50% at max level.
function UpgradeConfig.GetPotionDurationMultiplier(level: number): number
	return 1 + level * 0.05
end

return UpgradeConfig
