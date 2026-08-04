-- Daily Rewards: stand near the plaza's red "Daily Rewards" floor marker
-- (MapBuilder's buildFloorMarker) and claim once every ClaimIntervalSeconds
-- for a 7-day reward cycle. Mixed reward types now (started as a cash-only
-- prototype) -- each entry's Type says what DailyRewardsManager.luau grants
-- and what DailyRewardsProximityPanel.luau shows on that day's card:
--   Cash             -- Amount credited directly.
--   Item             -- ItemId granted outright via InventoryManager.AddItem
--                       (same as pulling it from a roll, just guaranteed).
--                       Day 2 uses this with a dedicated NotRollable item
--                       (ItemDatabase.Day2SpecialItem) instead of a random
--                       Epic pull, so every player gets the exact same,
--                       nameable Day 2 reward instead of whatever the RNG
--                       happened to land on.
--   Asset            -- AssetId granted outright (same effect as buying it
--                       from AssetShopPanel, just free) -- a no-op if
--                       already owned, not a refund.
--   AutoRollGamepass -- grants ownership of the Auto Roll gamepass itself
--                       (AutoRollManager.Grant), same as actually buying it
--                       -- a no-op if already owned.

local DailyRewardsConfig = {}

-- Escalates in value across the week without being purely cash -- Day 4's
-- Asset (LuxuryTownhouse, see AssetDatabase.luau) is priced at $15,000,000.
-- Day 5 ($10M) dips slightly below Day 4's asset value on purpose -- Day 4
-- is the week's "big reveal" showcase day, not the new floor -- then Day 6
-- ($25M) climbs back past it before Day 7's $100M caps the week as the
-- single biggest prize.
DailyRewardsConfig.Days = {
	{ Type = "Cash", Amount = 20000 },
	{ Type = "Item", ItemId = "Day2SpecialItem" },
	{ Type = "Cash", Amount = 500000 },
	{ Type = "Asset", AssetId = "LuxuryTownhouse" },
	{ Type = "Cash", Amount = 10000000 },
	{ Type = "Cash", Amount = 25000000 },
	{ Type = "Cash", Amount = 100000000 },
}

-- Standard 24h daily-reward gate.
DailyRewardsConfig.ClaimIntervalSeconds = 24 * 60 * 60

return DailyRewardsConfig
