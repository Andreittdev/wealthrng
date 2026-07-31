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
-- Asset (LuxuryTownhouse, see AssetDatabase.luau) is priced at exactly
-- $1,000,000, and Day 7's free Auto Roll gamepass is the biggest single
-- prize (a paid gamepass, normally Robux-only).
DailyRewardsConfig.Days = {
	{ Type = "Cash", Amount = 500 },
	{ Type = "Item", ItemId = "Day2SpecialItem" },
	{ Type = "Cash", Amount = 2000 },
	{ Type = "Asset", AssetId = "LuxuryTownhouse" },
	{ Type = "Cash", Amount = 8000 },
	{ Type = "Cash", Amount = 16000 },
	{ Type = "AutoRollGamepass" },
}

-- Standard 24h daily-reward gate.
DailyRewardsConfig.ClaimIntervalSeconds = 24 * 60 * 60

return DailyRewardsConfig
