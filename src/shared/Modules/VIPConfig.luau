-- Every VIP Gamepass number in one place, shared by server (RollManager,
-- SellManager, VIPManager) and client (RollPanel's Buy VIP button + cooldown mirror).

local VIPConfig = {}

VIPConfig.GamepassId = 1928251044

-- Overrides RollConfig.BaseCooldownSeconds for VIP.
VIPConfig.RollCooldownSeconds = 0.75

-- Multiplies RarityConfig weights before the weighted roll, VIP only.
-- Common stays at 1 so only rare+ tiers get a relative boost. Must have an
-- entry for every RarityConfig.Order tier -- RollManager.pickRarity does
-- `weight *= VIPConfig.LuckWeightMultiplier[rarity]` with no `or 1`
-- fallback, so a missing key errors out every VIP roll, not just under-boosts it.
VIPConfig.LuckWeightMultiplier = {
	Common = 1,
	Rare = 1.5,
	Epic = 2,
	Legendary = 3,
	Ultra = 4,
	Luxury = 6,
}

-- Extra % cash credited when a VIP sells an item.
VIPConfig.SellBonusPercent = 25

return VIPConfig
