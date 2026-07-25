-- Every VIP Gamepass number in one place, shared by server (RollManager,
-- SellManager, VIPManager) and client (RollPanel's Buy VIP button + cooldown mirror).

local VIPConfig = {}

VIPConfig.GamepassId = 1928251044

-- Overrides RollConfig.BaseCooldownSeconds for VIP.
VIPConfig.RollCooldownSeconds = 0.75

-- Multiplies RarityConfig weights before the weighted roll, VIP only.
-- Common stays at 1 so only rare+ tiers get a relative boost.
VIPConfig.LuckWeightMultiplier = {
	Common = 1,
	Rare = 1.5,
	Epic = 2,
	Legendary = 3,
	Luxury = 4,
}

-- Extra % cash credited when a VIP sells an item.
VIPConfig.SellBonusPercent = 25

return VIPConfig
