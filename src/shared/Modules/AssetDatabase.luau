-- Flat catalog (not an upgrade ladder) -- every Asset can be bought
-- outright and kept forever, but only MaxEquipped of them actively pay
-- income at once (AssetManager enforces the equip cap).
--
-- This is the main progression engine, tuned (with ItemDatabase's much
-- smaller roll values as an early-game bootstrap, not the long-term
-- driver) to a rough pacing target of a player who keeps reinvesting
-- everything into the next affordable tier and always equips their best 2:
--   ~30 min  -> Millionaire  ($1,000,000 net worth)
--   ~2h      -> Billionaire  ($1,000,000,000)
--   ~4-4.5h  -> Trillionaire ($1,000,000,000,000)
-- Each tier costs ~7-8x the previous one; income per tier grows faster
-- early (rewarding quick reinvestment and hooking new players) and slows
-- to grow roughly with price by the top tiers (so the curve decelerates
-- instead of compounding forever) -- the Price/Income ratio worsening at
-- higher tiers is intentional, not a bug: absolute income still explodes,
-- it just isn't a strictly-improving "efficiency" ladder, which keeps the
-- late game from trivializing itself.
--
-- RealEstateEmpire (the top tier) breaks the "~7-8x" step on purpose --
-- its Price jumped ~55x over the previous tier (LuxuryHotelChain) while
-- its Income was left alone, deliberately pushing its payback time from
-- ~9 min (in line with the tiers below it) out to ~8.7 HOURS. It's meant
-- to be a multi-day capstone purchase reached well after "Trillionaire"
-- net worth, not just the next rung on the same ladder -- a pure prestige
-- buy, not an efficient one.
-- This is a first-pass theorycrafted model, not simulation-tested against
-- real RNG variance from rolling -- expect to retune after playtesting.
--
-- Paid as a lump sum once every 60s ("collect rent"), not trickled
-- continuously like ItemDatabase's IncomePerSecond -- IncomeManager runs a
-- separate slower timer for this. IncomePerMinute values are exactly the
-- old IncomePerSecond figures x60, so the pacing math above still holds
-- (total $/hour is unchanged, only the payout cadence is).

export type Asset = {
	Id: string,
	Name: string,
	Price: number,
	IncomePerMinute: number,
	Image: string,
	-- Never shown/buyable in AssetShopPanel.luau -- exclusively granted by
	-- BattleLeaderboardRewardManager.luau to the Top 3 of LARP Battles'
	-- weekly Points leaderboard, same idea as ItemDatabase's NotRollable.
	NotPurchasable: boolean?,
	-- Estates' OWN tier scheme, deliberately separate from RarityConfig.
	-- Order/ItemDatabase's Common/Rare/Epic/Legendary/Ultra/Luxury (only
	-- the first 4 names are shared) -- added purely for CatalogPanel.luau's
	-- Index (grouping the Estates section into sub-sections the same way
	-- the Roll section already is), assigned by price tier: Common/Rare/
	-- Epic/Legendary as normal, then Godly (was "Ultra" -- PrivateResort/
	-- LuxuryHotelChain/RealEstateEmpire), Exclusive (Top3Estate/"Sol
	-- Stadium" -- CatalogPanel also folds ItemDatabase's 4 CrateExclusive
	-- items into this same section, they just don't carry this field since
	-- they're a different database), and Leaderboards (Top1Estate/
	-- Top2Estate, the LARP Battles weekly reward Estates). Doesn't feed
	-- into any purchase/roll odds logic -- Assets are still bought
	-- outright, never weighted-rolled.
	Rarity: string,
}

local AssetDatabase = {}

-- How many owned Assets can be equipped (earning income) at the same time.
AssetDatabase.MaxEquipped = 2

-- Every tier below RealEstateEmpire is Price x15 / Income x15 from the
-- original figures (same ratio, so payback-time pacing between tiers is
-- unchanged) -- bumped up because Potions ($250K) and the Luck upgrade's
-- capstone ($500M) had grown past what the early/mid Asset tiers cost,
-- undercutting Assets' role as "the main progression engine" (see header
-- above). RealEstateEmpire deliberately left untouched -- it's already the
-- multi-day prestige capstone, not part of this pass.
local assets: { [string]: Asset } = {
	StudioApartment = { Id = "StudioApartment", Name = "Studio Apartment", Price = 1000, IncomePerMinute = 500, Image = "rbxassetid://128312083744745", Rarity = "Common" },
	DowntownCondo = { Id = "DowntownCondo", Name = "Downtown Condo", Price = 225000, IncomePerMinute = 180000, Image = "rbxassetid://136840210779575", Rarity = "Common" },
	FamilyHouse = { Id = "FamilyHouse", Name = "Family House", Price = 1800000, IncomePerMinute = 1620000, Image = "rbxassetid://120133323186928", Rarity = "Rare" },
	LuxuryTownhouse = { Id = "LuxuryTownhouse", Name = "Luxury Townhouse", Price = 15000000, IncomePerMinute = 6840000, Image = "rbxassetid://138923081012401", Rarity = "Rare" },
	BeachfrontVilla = { Id = "BeachfrontVilla", Name = "Beachfront Villa", Price = 127500000, IncomePerMinute = 54000000, Image = "rbxassetid://119101496539944", Rarity = "Epic" },
	PrivateEstate = { Id = "PrivateEstate", Name = "Private Estate", Price = 1050000000, IncomePerMinute = 396000000, Image = "rbxassetid://85135894605780", Rarity = "Epic" },
	CountrysideMansion = { Id = "CountrysideMansion", Name = "Countryside Mansion", Price = 8250000000, IncomePerMinute = 1935000000, Image = "rbxassetid://71246518719735", Rarity = "Legendary" },
	SkyscraperPenthouse = { Id = "SkyscraperPenthouse", Name = "Skyscraper Penthouse", Price = 63000000000, IncomePerMinute = 12150000000, Image = "rbxassetid://85345447282599", Rarity = "Legendary" },
	PrivateResort = { Id = "PrivateResort", Name = "Private Resort", Price = 480000000000, IncomePerMinute = 70200000000, Image = "rbxassetid://115536352813894", Rarity = "Godly" },
	-- Priced below the flat x15 (which would've been $3.6T) specifically so
	-- there's still room for RealEstateEmpire's now-fixed $100T price to
	-- read as a real capstone jump (50x from here) instead of just the next
	-- rung on the same ladder -- Income scaled down to match (same
	-- Price/Income payback ratio as every other x15 tier), not left at the
	-- x15 figure, so this doesn't become an oddly-efficient outlier.
	LuxuryHotelChain = { Id = "LuxuryHotelChain", Name = "Luxury Hotel Chain", Price = 2000000000000, IncomePerMinute = 215000000000, Image = "rbxassetid://120902816460043", Rarity = "Godly" },
	-- Income bumped above LuxuryHotelChain's 215B/min (was 192B/min --
	-- LESS than the tier below it, despite costing 50x more, since it was
	-- left untouched during a rebalance pass that only scaled every OTHER
	-- tier's income down to match its below-x15 price). Still a much worse
	-- payback ratio than the tiers below (~5.5h vs ~9min) -- deliberately,
	-- it's the prestige capstone, not an efficient buy -- just no longer
	-- LESS absolute income than a cheaper asset, which was never intended.
	RealEstateEmpire = { Id = "RealEstateEmpire", Name = "Real Estate Empire", Price = 500000000000000, IncomePerMinute = 7000000000000, Image = "rbxassetid://97450504269002", Rarity = "Godly" },
	-- New capstone-below-the-capstone -- Real Estate Empire's OLD stats
	-- (Price $100T / Income $1.5T/min) before it got pushed up to $500T /
	-- $7T/min above, kept as its own tier rather than reused so existing
	-- owners of Real Estate Empire aren't retroactively downgraded. Image
	-- left blank -- filled in once an asset Id comes in.
	PrivateAirport = { Id = "PrivateAirport", Name = "Private Airport", Price = 100000000000000, IncomePerMinute = 1500000000000, Image = "rbxassetid://136313559951473", Rarity = "Godly" },

	-- LARP Battles weekly Points leaderboard Top 3 reward -- never
	-- purchasable, granted automatically (BattleLeaderboardRewardManager.
	-- luau) at each Saturday 18:10 GMT+3 reset. Price = 1000x Income, a
	-- deliberately clean "prestige" ratio (not derived from the payback-time
	-- pacing every purchasable tier follows) -- these exist to be flexed,
	-- not to be efficient.
	Top1Estate = { Id = "Top1Estate", Name = "Abra Ai Balt", Price = 150000000000000, IncomePerMinute = 150000000000, Image = "rbxassetid://79317381275203", NotPurchasable = true, Rarity = "Leaderboards" },
	Top2Estate = { Id = "Top2Estate", Name = "Loira Chateau", Price = 90000000000000, IncomePerMinute = 90000000000, Image = "rbxassetid://121583618235564", NotPurchasable = true, Rarity = "Leaderboards" },
	Top3Estate = { Id = "Top3Estate", Name = "Sol Stadium", Price = 10000000000000, IncomePerMinute = 500000000000, Image = "rbxassetid://97852370469373", NotPurchasable = true, Rarity = "Exclusive" },

	-- LARP Battles Rank Rewards -- never purchasable, granted automatically
	-- (RankRewardManager.luau) the moment a player's rank reaches Silver/
	-- Gold/Platinum/Diamond (see BattleRankConfig.luau), alongside a flat
	-- Cash reward (RankRewardConfig.luau). Same Price = 1000x Income
	-- "prestige" ratio as Top1Estate/Top2Estate above, scaled roughly with
	-- each rank's own MinNetWorth gate. Image left blank -- filled in as
	-- asset IDs come in.
	OldFarm = { Id = "OldFarm", Name = "Old Farm", Price = 500000000000, IncomePerMinute = 500000000, Image = "rbxassetid://70900608098379", NotPurchasable = true, Rarity = "Exclusive" },
	Supermarket = { Id = "Supermarket", Name = "Supermarket", Price = 1000000000000, IncomePerMinute = 1000000000, Image = "rbxassetid://110378056920987", NotPurchasable = true, Rarity = "Exclusive" },
	SolarPark = { Id = "SolarPark", Name = "Solar Park", Price = 10000000000000, IncomePerMinute = 10000000000, Image = "rbxassetid://92159060517720", NotPurchasable = true, Rarity = "Exclusive" },
	ConstructionShop = { Id = "ConstructionShop", Name = "Construction Shop", Price = 500000000000000, IncomePerMinute = 500000000000, Image = "rbxassetid://136401020604131", NotPurchasable = true, Rarity = "Exclusive" },
}

function AssetDatabase.GetAsset(id: string?): Asset?
	if not id then
		return nil
	end
	return assets[id]
end

function AssetDatabase.GetAllAssets(): { [string]: Asset }
	return assets
end

return AssetDatabase
