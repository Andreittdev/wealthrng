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
}

local AssetDatabase = {}

-- How many owned Assets can be equipped (earning income) at the same time.
AssetDatabase.MaxEquipped = 2

local assets: { [string]: Asset } = {
	StudioApartment = { Id = "StudioApartment", Name = "Studio Apartment", Price = 2000, IncomePerMinute = 1440 },
	DowntownCondo = { Id = "DowntownCondo", Name = "Downtown Condo", Price = 15000, IncomePerMinute = 12000 },
	FamilyHouse = { Id = "FamilyHouse", Name = "Family House", Price = 120000, IncomePerMinute = 108000 },
	LuxuryTownhouse = { Id = "LuxuryTownhouse", Name = "Luxury Townhouse", Price = 1000000, IncomePerMinute = 456000 },
	BeachfrontVilla = { Id = "BeachfrontVilla", Name = "Beachfront Villa", Price = 8500000, IncomePerMinute = 3600000 },
	PrivateEstate = { Id = "PrivateEstate", Name = "Private Estate", Price = 70000000, IncomePerMinute = 26400000 },
	CountrysideMansion = { Id = "CountrysideMansion", Name = "Countryside Mansion", Price = 550000000, IncomePerMinute = 129000000 },
	SkyscraperPenthouse = { Id = "SkyscraperPenthouse", Name = "Skyscraper Penthouse", Price = 4200000000, IncomePerMinute = 810000000 },
	PrivateResort = { Id = "PrivateResort", Name = "Private Resort", Price = 32000000000, IncomePerMinute = 4680000000 },
	LuxuryHotelChain = { Id = "LuxuryHotelChain", Name = "Luxury Hotel Chain", Price = 240000000000, IncomePerMinute = 25800000000 },
	RealEstateEmpire = { Id = "RealEstateEmpire", Name = "Real Estate Empire", Price = 1800000000000, IncomePerMinute = 192000000000 },
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
