-- Luck Pass gamepass: a cheap (49 Robux), permanent, modest Luck boost --
-- deliberately weaker per-rarity than both VIP's LuckWeightMultiplier (6x
-- Luxury) and a Luck Potion's (1.5x Luxury), since it stacks multiplicatively
-- with both of those PLUS the Luck Upgrade track in RollManager.pickRarity.
-- PotionDatabase.luau's header already documents once having to nerf the
-- Potion's own Luxury multiplier (3.5x -> 1.5x) because the VIP+Potion+
-- Upgrade stack was gutting Luxury's rarity -- this stays intentionally
-- mild so a 4th multiplier in that same chain doesn't reopen that problem.

local LuckPassConfig = {}

LuckPassConfig.GamepassId = 1934300860

LuckPassConfig.LuckWeightMultiplier = {
	Common = 1,
	Rare = 1.15,
	Epic = 1.3,
	Legendary = 1.5,
	Ultra = 1.75,
	Luxury = 1.2,
}

return LuckPassConfig
