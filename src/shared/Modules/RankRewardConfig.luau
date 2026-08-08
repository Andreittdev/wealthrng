-- LARP Battles Rank Rewards -- a flat Cash amount granted for reaching each
-- BattleRankConfig tier (Bronze..Diamond), shown in BattlePanel's Rewards
-- card. Placeholder amounts for now, easy to retune later. Indexed by tier
-- Name so it stays trivially paired with BattleRankConfig.Tiers without
-- duplicating the RP/NetWorth thresholds here.

local RankRewardConfig = {}

local CASH_REWARD: { [string]: number } = {
	Bronze = 10000,
	Silver = 100000,
	Gold = 1000000,
	Platinum = 10000000,
	Diamond = 100000000,
}
RankRewardConfig.CashReward = CASH_REWARD

function RankRewardConfig.GetCashReward(tierName: string): number
	return CASH_REWARD[tierName] or 0
end

-- Bronze has no Estate reward (it's the starting rank, RP 0) -- only
-- Silver/Gold/Platinum/Diamond grant one, alongside their Cash reward
-- above. AssetDatabase Ids -- see its "LARP Battles Rank Rewards" entries.
local ESTATE_REWARD: { [string]: string } = {
	Silver = "OldFarm",
	Gold = "Supermarket",
	Platinum = "SolarPark",
	Diamond = "ConstructionShop",
}
RankRewardConfig.EstateReward = ESTATE_REWARD

function RankRewardConfig.GetEstateReward(tierName: string): string?
	return ESTATE_REWARD[tierName]
end

return RankRewardConfig
