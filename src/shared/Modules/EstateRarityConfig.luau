-- Estates' own display tier scheme -- deliberately separate from
-- RarityConfig (Roll Items' Common/Rare/Epic/Legendary/Ultra/Luxury), see
-- AssetDatabase.luau's Asset.Rarity field comment for what each bucket
-- means (Common/Rare/Epic/Legendary as normal, then Godly, Exclusive,
-- Leaderboards). Colors only, no roll weights -- Estates are bought
-- outright or granted, never weighted-rolled. Single source of truth so
-- CatalogPanel.luau's Estates tab, InventoryPanel.luau's Estates detail
-- view, and IndexRewardConfig.luau's tier iteration can't drift apart.

local EstateRarityConfig = {}

EstateRarityConfig.Order = { "Common", "Rare", "Epic", "Legendary", "Godly", "Leaderboards", "Exclusive" }

local COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(190, 190, 190),
	Rare = Color3.fromRGB(65, 120, 210),
	Epic = Color3.fromRGB(80, 220, 230),
	Legendary = Color3.fromRGB(255, 170, 0),
	Godly = Color3.fromRGB(220, 40, 40),
	Exclusive = Color3.fromRGB(170, 85, 255),
	Leaderboards = Color3.fromRGB(255, 221, 0),
}
EstateRarityConfig.Colors = COLORS

function EstateRarityConfig.GetColor(rarity: string): Color3
	return EstateRarityConfig.Colors[rarity] or Color3.fromRGB(255, 255, 255)
end

return EstateRarityConfig
