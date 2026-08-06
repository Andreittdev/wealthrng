-- "Exclusive Crate" -- Robux-only Developer Product purchases, each one
-- opening N crates at once, each crate independently landing on one of
-- EXACTLY 4 Crate-exclusive Estates (ItemDatabase's CrateVilla/CrateManor/
-- CratePalace/CrateCastle) via this module's own flat per-Estate
-- percentages -- no rarity tiers/weights involved at all, per explicit
-- request (this used to roll a rarity first via RarityConfig's 6 tiers,
-- then an item within it; now each Estate just has its own direct percent).
-- Percentages are placeholders -- the shape (very common first Estate,
-- progressively rarer) mirrors the reference screenshot's odds table.
--
-- ProductId 0 = not yet created on the Creator Dashboard -- ShopPanel.luau's
-- Crate section shows that tier disabled/"Coming Soon" until a real one is set.

local CrateConfig = {}

export type EstateOdds = { ItemId: string, Percent: number }
export type PurchaseTier = { Id: string, Quantity: number, ProductId: number, RobuxPrice: number }

-- Sums to 100 -- ordered common -> rare.
local ESTATES: { EstateOdds } = {
	{ ItemId = "CrateVilla", Percent = 65 },
	{ ItemId = "CrateManor", Percent = 27 },
	{ ItemId = "CratePalace", Percent = 7 },
	{ ItemId = "CrateCastle", Percent = 1 },
}

function CrateConfig.GetEstateOdds(): { EstateOdds }
	return ESTATES
end

-- Weighted pick straight off the percentages above (they already sum to
-- 100, so no separate normalization step is needed) -- returns an ItemId
-- directly, no rarity indirection.
function CrateConfig.RollItemId(random: Random): string
	local roll = random:NextNumber() * 100
	local cumulative = 0
	for _, entry in ESTATES do
		cumulative += entry.Percent
		if roll <= cumulative then
			return entry.ItemId
		end
	end
	return ESTATES[1].ItemId
end

-- 4 purchase tiers, per the reference screenshot -- quantity of crates
-- opened in one purchase. RobuxPrice is display-only
-- (MarketplaceService.PromptProductPurchase doesn't take a price -- it
-- reads whatever's configured against ProductId on the Creator Dashboard);
-- shown here just so the panel can render a price before GetProductInfo
-- resolves, same convention StadiumOfferPanel.luau uses.
local purchaseTiers: { PurchaseTier } = {
	{ Id = "Crate1", Quantity = 1, ProductId = 3630269828, RobuxPrice = 99 },
	{ Id = "Crate2", Quantity = 2, ProductId = 3630300175, RobuxPrice = 159 },
	{ Id = "Crate3", Quantity = 3, ProductId = 3630303050, RobuxPrice = 219 },
}
CrateConfig.PurchaseTiers = purchaseTiers

function CrateConfig.GetTierByProductId(productId: number): PurchaseTier?
	if productId == 0 then
		return nil
	end
	for _, tier in CrateConfig.PurchaseTiers do
		if tier.ProductId == productId then
			return tier
		end
	end
	return nil
end

return CrateConfig
