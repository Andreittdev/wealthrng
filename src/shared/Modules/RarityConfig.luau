-- Single source of truth for rarity tiers: roll weight + display color.
-- Order matters (Common -> Luxury); ItemDatabase and the UI both key off this list.
--
-- Six tiers, not five: the old top tier ("Luxury") was renamed "Ultra" and
-- kept its weight/color slot, and a new "Luxury" tier was added above it --
-- the true chase tier.
--
-- Epic/Legendary/Ultra weights were cut hard so those tiers read as
-- genuinely rare, matching the big-number RNG-game feel (Sol's RNG etc.).
--
-- Luxury's weight went through several passes trying to balance "time to
-- first Luxury item" for a F2P player against a fully-boosted one (VIP +
-- Speed/Luck Potion + maxed Upgrades) -- each pass discovered the same
-- structural problem: VIP/Potion/Upgrade's luck stack multiplies THIS
-- weight straight through (11.7x), so raising it to help F2P always blew
-- the fully-boosted player's time down far more than intended, and
-- lowering it to rein in the fully-boosted player always dragged F2P's
-- time out to months. The fix: this weight is now set almost to zero
-- (~1-in-83,000,000 baseline, functionally "not how you get Luxury from a
-- normal roll") -- virtually ALL of both populations' Luxury odds now come
-- from SpecialRollConfig's Golden/Diamond/Ruby/Emerald tiers instead (see
-- that file's header), which have FIXED odds that don't get the VIP/
-- Potion/Upgrade multiplier at all. That decouples the two populations'
-- outcomes from this weight entirely -- the only remaining gap between
-- them is purely from rolling faster (VIP's cooldown + Speed Potion +
-- Roll Speed Upgrade), which charges Golden/Diamond/Ruby/Emerald quicker
-- in real time, not from better odds per claim. Net current result: F2P
-- ~14.5 days, fully-boosted ~3 days, for either of the 2 Luxury items at
-- ~3h/day of active play.
local RarityConfig = {}

RarityConfig.Order = { "Common", "Rare", "Epic", "Legendary", "Ultra", "Luxury" }

RarityConfig.Tiers = {
	Common = { Weight = 600, Color = Color3.fromRGB(190, 190, 190) },
	-- Muted/deeper blue on purpose -- the old brighter cyan-leaning blue
	-- read too close to Ultra's turquoise at a glance.
	Rare = { Weight = 220, Color = Color3.fromRGB(65, 120, 210) },
	-- ~1 in 104 at base roll rate -- cut hard from the original 90 so the
	-- climb from Rare to Epic feels like a real step, not a coin flip.
	Epic = { Weight = 8, Color = Color3.fromRGB(170, 85, 255) },
	-- ~1 in 1,658 at base roll rate -- cut hard from the original 18 for
	-- the same reason; still comfortably more common than Ultra (below)
	-- so the ladder keeps escalating in order.
	Legendary = { Weight = 0.5, Color = Color3.fromRGB(255, 170, 0) },
	-- Turquoise leaning bright/white rather than a dark teal, so it still
	-- reads as premium instead of murky. ~1 in 16,570 at base roll rate --
	-- cut further (from 0.35) specifically to make room for Lucky Roll's
	-- 6-stage ladder (SpecialRollConfig.luau) to hit its top callout
	-- (5000x on the final 90-min stage) without needing >100% of that
	-- stage's rolls to land Ultra -- see that file's header for the math.
	Ultra = { Weight = 0.05, Color = Color3.fromRGB(102, 240, 225) },
	-- Vivid magenta -- distinct from every other tier's color at a glance,
	-- and deliberately doesn't reuse Theme.Colors.Accent's gold so it never
	-- blends into ordinary UI chrome. Deliberately almost zero (see header
	-- comment) -- Luxury is meant to come from SpecialRollConfig's Golden/
	-- Diamond/Ruby/Emerald tiers now, not from plain normal rolls.
	Luxury = { Weight = 0.00001, Color = Color3.fromRGB(255, 20, 147) },
}

function RarityConfig.GetColor(rarity: string): Color3
	local tier = RarityConfig.Tiers[rarity]
	return tier and tier.Color or Color3.fromRGB(255, 255, 255)
end

return RarityConfig
