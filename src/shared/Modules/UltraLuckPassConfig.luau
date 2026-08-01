-- Ultra Luck Pass gamepass: the premium (249 Robux) sibling of Luck Pass
-- (49 Robux, see LuckPassConfig.luau) -- notably stronger on Rare-Ultra,
-- but Luxury still deliberately capped. Fully stacked (VIP x6 * Luck
-- Potion x1.5 * Luck Upgrade capstone x50 * Luck Pass x1.2 * this x1.6) the
-- combined Luxury weight multiplier lands around ~864x -- still under the
-- ~1050x combo that once pushed Luxury down to a ~1-in-2.4k roll and had to
-- be nerfed (see PotionDatabase.luau's header), just with real room to feel
-- worth the price on Rare/Epic/Legendary/Ultra instead.

local UltraLuckPassConfig = {}

UltraLuckPassConfig.GamepassId = 1934486874

UltraLuckPassConfig.LuckWeightMultiplier = {
	Common = 1,
	Rare = 1.4,
	Epic = 1.8,
	Legendary = 2.5,
	Ultra = 3.5,
	Luxury = 1.6,
}

return UltraLuckPassConfig
