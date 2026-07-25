-- Flat catalog (not an upgrade ladder) -- every Asset can be bought
-- outright and kept forever, but only MaxEquipped of them actively pay
-- income at once (AssetManager enforces the equip cap). Placeholder prices/
-- income -- tuned so even the cheapest clearly beats the best rolled item's
-- income (ItemDatabase's Bugatti = 30,000/s), since Assets require
-- deliberate saving instead of RNG luck.

export type Asset = {
	Id: string,
	Name: string,
	Price: number,
	IncomePerSecond: number,
}

local AssetDatabase = {}

-- How many owned Assets can be equipped (earning income) at the same time.
AssetDatabase.MaxEquipped = 2

local assets: { [string]: Asset } = {
	StudioApartment = { Id = "StudioApartment", Name = "Studio Apartment", Price = 50000, IncomePerSecond = 2000 },
	FamilyHouse = { Id = "FamilyHouse", Name = "Family House", Price = 500000, IncomePerSecond = 15000 },
	LuxuryVilla = { Id = "LuxuryVilla", Name = "Luxury Villa", Price = 5000000, IncomePerSecond = 100000 },
	PrivateEstate = { Id = "PrivateEstate", Name = "Private Estate", Price = 50000000, IncomePerSecond = 750000 },
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
