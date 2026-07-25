-- Single source of truth for rarity tiers: roll weight + display color.
-- Order matters (Common -> Luxury); ItemDatabase and the UI both key off this list.

local RarityConfig = {}

RarityConfig.Order = { "Common", "Rare", "Epic", "Legendary", "Luxury" }

RarityConfig.Tiers = {
	Common = { Weight = 600, Color = Color3.fromRGB(190, 190, 190) },
	Rare = { Weight = 250, Color = Color3.fromRGB(85, 170, 255) },
	Epic = { Weight = 110, Color = Color3.fromRGB(170, 85, 255) },
	Legendary = { Weight = 35, Color = Color3.fromRGB(255, 170, 0) },
	Luxury = { Weight = 5, Color = Color3.fromRGB(255, 85, 130) },
}

function RarityConfig.GetColor(rarity: string): Color3
	local tier = RarityConfig.Tiers[rarity]
	return tier and tier.Color or Color3.fromRGB(255, 255, 255)
end

return RarityConfig
