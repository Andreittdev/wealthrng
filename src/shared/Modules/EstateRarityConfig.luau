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
	-- Only used by Dream Castle (CrateCastle, ItemDatabase's "Luxury" tier
	-- -- separate rarity scheme from the rest of this table, see the header
	-- comment) now that InventoryPanel.luau's Estates tab renders the 4
	-- Crate-exclusive items alongside real AssetDatabase Estates -- without
	-- this, THE single rarest Estate in the game fell through to the plain
	-- white fallback below instead of a themed color.
	Luxury = Color3.fromRGB(255, 90, 200),
}
EstateRarityConfig.Colors = COLORS

function EstateRarityConfig.GetColor(rarity: string): Color3
	return EstateRarityConfig.Colors[rarity] or Color3.fromRGB(255, 255, 255)
end

return EstateRarityConfig
