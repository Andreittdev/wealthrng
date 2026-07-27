-- Single source of truth for rarity tiers: roll weight + display color.
-- Order matters (Common -> Luxury); ItemDatabase and the UI both key off this list.
--
-- Six tiers, not five: the old top tier ("Luxury") was renamed "Ultra" and
-- kept its weight/color slot, and a new "Luxury" tier was added above it --
-- the true chase tier, deliberately tiny (2 items in ItemDatabase, weight
-- low enough for ~1-in-50k-to-100k per item) so it stays a rare-clip-worthy
-- moment instead of something players collect within a normal session.

local RarityConfig = {}

RarityConfig.Order = { "Common", "Rare", "Epic", "Legendary", "Ultra", "Luxury" }

RarityConfig.Tiers = {
	Common = { Weight = 600, Color = Color3.fromRGB(190, 190, 190) },
	-- Muted/deeper blue on purpose -- the old brighter cyan-leaning blue
	-- read too close to Ultra's turquoise at a glance.
	Rare = { Weight = 250, Color = Color3.fromRGB(65, 120, 210) },
	Epic = { Weight = 110, Color = Color3.fromRGB(170, 85, 255) },
	Legendary = { Weight = 35, Color = Color3.fromRGB(255, 170, 0) },
	-- Turquoise leaning bright/white rather than a dark teal, so it still
	-- reads as premium instead of murky.
	Ultra = { Weight = 5, Color = Color3.fromRGB(102, 240, 225) },
	-- Vivid magenta -- distinct from every other tier's color at a glance,
	-- and deliberately doesn't reuse Theme.Colors.Accent's gold so it never
	-- blends into ordinary UI chrome.
	Luxury = { Weight = 0.02, Color = Color3.fromRGB(255, 20, 147) },
}

function RarityConfig.GetColor(rarity: string): Color3
	local tier = RarityConfig.Tiers[rarity]
	return tier and tier.Color or Color3.fromRGB(255, 255, 255)
end

return RarityConfig
