-- Canonical item schema, one shape for every rarity tier:
-- { Id, Name, Rarity, Value, IncomePerSecond, Image }
-- IncomePerSecond is passive cash earned per second while the item sits
-- unsold in inventory (roughly Value/20 -- deliberately a worse ratio than
-- AssetDatabase's tiers, since rolled items are meant to be an early/mid-
-- game bootstrap and a fun variance hit, not the long-term income engine;
-- Assets carry that job once affordable). Values top out around
-- AssetDatabase's tier3-4 range (a lucky Luxury roll should feel like a
-- genuine windfall, not a rounding error) but the *average* roll stays
-- far below that -- see AssetDatabase's header for the overall pacing
-- target this economy is tuned around (~30 min to Millionaire, ~2h to
-- Billionaire, ~4-5h to Trillionaire); rolling should feel rewarding
-- without being able to reliably shortcut that curve.
--
-- Personal-flex items only (watches, jewelry, vehicles, boats, jets) --
-- deliberately no real estate/commercial space (that's AssetDatabase's
-- job) and no precious metals/ores (that's InvestmentDatabase's job), so
-- rolling never competes conceptually with the physical shop's two
-- categories. Names are all generic/invented, no real-world brands
-- (no Bugatti/Rolex/etc.) to avoid trademark issues.
-- Placeholder values -- reskin and rebalance freely, the rest of the
-- system only depends on the shape, not the specific entries below.

export type Item = {
	Id: string,
	Name: string,
	Rarity: string,
	Value: number,
	IncomePerSecond: number,
	Image: string,
}

local ItemDatabase = {}

-- Only one rolled/held item can be equipped (earning IncomePerSecond) at a
-- time -- matches the genre norm (Sol's RNG-style: one active
-- aura/effect, not a Pet-Simulator-style multi-slot loadout), and keeps
-- item income a small early/mid-game bonus rather than a second ladder
-- that could out-snowball AssetDatabase's, which the economy's pacing is
-- tuned around. Unequipped items still count their full Value toward Net
-- Worth, they just don't generate passive income. Equipping a new item
-- swaps out whatever was equipped before (see InventoryManager.Equip) --
-- no need to manually unequip first.
ItemDatabase.MaxEquipped = 1

-- All Values are the original pass x6 (bumped up after the first pass felt
-- too small to be exciting for a game whose whole point is rolling) --
-- IncomePerSecond re-derived from the new Value at the same ~Value/20
-- ratio, not just multiplied along, to keep that documented relationship
-- accurate.
local items: { [string]: Item } = {
	-- Common
	Watch = { Id = "Watch", Name = "Wrist Watch", Rarity = "Common", Value = 30, IncomePerSecond = 2, Image = "rbxassetid://0" },
	Headphones = { Id = "Headphones", Name = "Headphones", Rarity = "Common", Value = 42, IncomePerSecond = 2, Image = "rbxassetid://0" },
	Sunglasses = { Id = "Sunglasses", Name = "Sunglasses", Rarity = "Common", Value = 54, IncomePerSecond = 3, Image = "rbxassetid://0" },
	Sneakers = { Id = "Sneakers", Name = "Sneakers", Rarity = "Common", Value = 72, IncomePerSecond = 4, Image = "rbxassetid://0" },
	Backpack = { Id = "Backpack", Name = "Backpack", Rarity = "Common", Value = 90, IncomePerSecond = 5, Image = "rbxassetid://0" },
	Skateboard = { Id = "Skateboard", Name = "Skateboard", Rarity = "Common", Value = 108, IncomePerSecond = 5, Image = "rbxassetid://0" },
	Scooter = { Id = "Scooter", Name = "Scooter", Rarity = "Common", Value = 132, IncomePerSecond = 7, Image = "rbxassetid://0" },
	Bike = { Id = "Bike", Name = "Bicycle", Rarity = "Common", Value = 156, IncomePerSecond = 8, Image = "rbxassetid://0" },
	Cap = { Id = "Cap", Name = "Cap", Rarity = "Common", Value = 20, IncomePerSecond = 1, Image = "rbxassetid://0" },
	Wallet = { Id = "Wallet", Name = "Wallet", Rarity = "Common", Value = 26, IncomePerSecond = 1, Image = "rbxassetid://0" },
	Belt = { Id = "Belt", Name = "Belt", Rarity = "Common", Value = 34, IncomePerSecond = 2, Image = "rbxassetid://0" },
	Gloves = { Id = "Gloves", Name = "Gloves", Rarity = "Common", Value = 46, IncomePerSecond = 2, Image = "rbxassetid://0" },
	Scarf = { Id = "Scarf", Name = "Scarf", Rarity = "Common", Value = 60, IncomePerSecond = 3, Image = "rbxassetid://0" },
	Umbrella = { Id = "Umbrella", Name = "Umbrella", Rarity = "Common", Value = 78, IncomePerSecond = 4, Image = "rbxassetid://0" },
	Wristband = { Id = "Wristband", Name = "Wristband", Rarity = "Common", Value = 96, IncomePerSecond = 5, Image = "rbxassetid://0" },
	Beanie = { Id = "Beanie", Name = "Beanie", Rarity = "Common", Value = 114, IncomePerSecond = 6, Image = "rbxassetid://0" },
	FannyPack = { Id = "FannyPack", Name = "Fanny Pack", Rarity = "Common", Value = 138, IncomePerSecond = 7, Image = "rbxassetid://0" },
	Rollerblades = { Id = "Rollerblades", Name = "Rollerblades", Rarity = "Common", Value = 162, IncomePerSecond = 8, Image = "rbxassetid://0" },
	Longboard = { Id = "Longboard", Name = "Longboard", Rarity = "Common", Value = 174, IncomePerSecond = 9, Image = "rbxassetid://0" },
	PocketKnife = { Id = "PocketKnife", Name = "Pocket Knife", Rarity = "Common", Value = 186, IncomePerSecond = 9, Image = "rbxassetid://0" },

	-- Rare
	GoldChain = { Id = "GoldChain", Name = "Gold Chain", Rarity = "Rare", Value = 210, IncomePerSecond = 11, Image = "rbxassetid://0" },
	LeatherJacket = { Id = "LeatherJacket", Name = "Leather Jacket", Rarity = "Rare", Value = 270, IncomePerSecond = 14, Image = "rbxassetid://0" },
	LuxuryWatch = { Id = "LuxuryWatch", Name = "Luxury Watch", Rarity = "Rare", Value = 330, IncomePerSecond = 17, Image = "rbxassetid://0" },
	DesignerBag = { Id = "DesignerBag", Name = "Designer Bag", Rarity = "Rare", Value = 408, IncomePerSecond = 20, Image = "rbxassetid://0" },
	ElectricScooter = { Id = "ElectricScooter", Name = "Electric Scooter", Rarity = "Rare", Value = 480, IncomePerSecond = 24, Image = "rbxassetid://0" },
	Motorcycle = { Id = "Motorcycle", Name = "Motorcycle", Rarity = "Rare", Value = 570, IncomePerSecond = 29, Image = "rbxassetid://0" },
	Drone = { Id = "Drone", Name = "Drone", Rarity = "Rare", Value = 660, IncomePerSecond = 33, Image = "rbxassetid://0" },
	GamingSetup = { Id = "GamingSetup", Name = "Gaming Setup", Rarity = "Rare", Value = 780, IncomePerSecond = 39, Image = "rbxassetid://0" },
	CologneSet = { Id = "CologneSet", Name = "Cologne Set", Rarity = "Rare", Value = 195, IncomePerSecond = 10, Image = "rbxassetid://0" },
	DesignerShoes = { Id = "DesignerShoes", Name = "Designer Shoes", Rarity = "Rare", Value = 240, IncomePerSecond = 12, Image = "rbxassetid://0" },
	SilkSuit = { Id = "SilkSuit", Name = "Silk Suit", Rarity = "Rare", Value = 285, IncomePerSecond = 14, Image = "rbxassetid://0" },
	CameraKit = { Id = "CameraKit", Name = "Camera Kit", Rarity = "Rare", Value = 345, IncomePerSecond = 17, Image = "rbxassetid://0" },
	Smartwatch = { Id = "Smartwatch", Name = "Smartwatch", Rarity = "Rare", Value = 390, IncomePerSecond = 20, Image = "rbxassetid://0" },
	RacingHelmet = { Id = "RacingHelmet", Name = "Racing Helmet", Rarity = "Rare", Value = 435, IncomePerSecond = 22, Image = "rbxassetid://0" },
	HomeStudioMic = { Id = "HomeStudioMic", Name = "Home Studio Mic", Rarity = "Rare", Value = 465, IncomePerSecond = 23, Image = "rbxassetid://0" },
	Segway = { Id = "Segway", Name = "Segway", Rarity = "Rare", Value = 525, IncomePerSecond = 26, Image = "rbxassetid://0" },
	VRHeadset = { Id = "VRHeadset", Name = "VR Headset", Rarity = "Rare", Value = 555, IncomePerSecond = 28, Image = "rbxassetid://0" },
	LeatherBoots = { Id = "LeatherBoots", Name = "Leather Boots", Rarity = "Rare", Value = 600, IncomePerSecond = 30, Image = "rbxassetid://0" },
	LongboardElite = { Id = "LongboardElite", Name = "Longboard Elite", Rarity = "Rare", Value = 630, IncomePerSecond = 32, Image = "rbxassetid://0" },
	PortableSpeakerSystem = { Id = "PortableSpeakerSystem", Name = "Portable Speaker System", Rarity = "Rare", Value = 705, IncomePerSecond = 35, Image = "rbxassetid://0" },

	-- Epic
	DiamondRing = { Id = "DiamondRing", Name = "Diamond Ring", Rarity = "Epic", Value = 1080, IncomePerSecond = 54, Image = "rbxassetid://0" },
	LuxurySuit = { Id = "LuxurySuit", Name = "Luxury Suit", Rarity = "Epic", Value = 1320, IncomePerSecond = 66, Image = "rbxassetid://0" },
	GoldBracelet = { Id = "GoldBracelet", Name = "Gold Bracelet", Rarity = "Epic", Value = 1620, IncomePerSecond = 81, Image = "rbxassetid://0" },
	HomeTheater = { Id = "HomeTheater", Name = "Home Theater System", Rarity = "Epic", Value = 1920, IncomePerSecond = 96, Image = "rbxassetid://0" },
	JetSki = { Id = "JetSki", Name = "Jet Ski", Rarity = "Epic", Value = 2280, IncomePerSecond = 114, Image = "rbxassetid://0" },
	RacingMotorbike = { Id = "RacingMotorbike", Name = "Racing Motorbike", Rarity = "Epic", Value = 2640, IncomePerSecond = 132, Image = "rbxassetid://0" },
	SportsCar = { Id = "SportsCar", Name = "Sports Car", Rarity = "Epic", Value = 3060, IncomePerSecond = 153, Image = "rbxassetid://0" },
	Speedboat = { Id = "Speedboat", Name = "Speedboat", Rarity = "Epic", Value = 3540, IncomePerSecond = 177, Image = "rbxassetid://0" },
	PearlNecklace = { Id = "PearlNecklace", Name = "Pearl Necklace", Rarity = "Epic", Value = 960, IncomePerSecond = 48, Image = "rbxassetid://0" },
	DesignerWatchSet = { Id = "DesignerWatchSet", Name = "Designer Watch Set", Rarity = "Epic", Value = 1200, IncomePerSecond = 60, Image = "rbxassetid://0" },
	HomeGymSetup = { Id = "HomeGymSetup", Name = "Home Gym Setup", Rarity = "Epic", Value = 1440, IncomePerSecond = 72, Image = "rbxassetid://0" },
	RecordingStudioRig = { Id = "RecordingStudioRig", Name = "Recording Studio Rig", Rarity = "Epic", Value = 1560, IncomePerSecond = 78, Image = "rbxassetid://0" },
	CustomMotorbike = { Id = "CustomMotorbike", Name = "Custom Motorbike", Rarity = "Epic", Value = 1740, IncomePerSecond = 87, Image = "rbxassetid://0" },
	ATV = { Id = "ATV", Name = "ATV", Rarity = "Epic", Value = 1860, IncomePerSecond = 93, Image = "rbxassetid://0" },
	Snowmobile = { Id = "Snowmobile", Name = "Snowmobile", Rarity = "Epic", Value = 2040, IncomePerSecond = 102, Image = "rbxassetid://0" },
	DroneFleet = { Id = "DroneFleet", Name = "Drone Fleet", Rarity = "Epic", Value = 2160, IncomePerSecond = 108, Image = "rbxassetid://0" },
	ConvertibleCar = { Id = "ConvertibleCar", Name = "Convertible Car", Rarity = "Epic", Value = 2400, IncomePerSecond = 120, Image = "rbxassetid://0" },
	RaceKart = { Id = "RaceKart", Name = "Race Kart", Rarity = "Epic", Value = 2760, IncomePerSecond = 138, Image = "rbxassetid://0" },
	LuxuryCamperVan = { Id = "LuxuryCamperVan", Name = "Luxury Camper Van", Rarity = "Epic", Value = 2940, IncomePerSecond = 147, Image = "rbxassetid://0" },
	KartingTrackPass = { Id = "KartingTrackPass", Name = "Karting Track Pass", Rarity = "Epic", Value = 3300, IncomePerSecond = 165, Image = "rbxassetid://0" },

	-- Legendary
	RaceCar = { Id = "RaceCar", Name = "Race Car", Rarity = "Legendary", Value = 7200, IncomePerSecond = 360, Image = "rbxassetid://0" },
	LuxuryMotorhome = { Id = "LuxuryMotorhome", Name = "Luxury Motorhome", Rarity = "Legendary", Value = 9000, IncomePerSecond = 450, Image = "rbxassetid://0" },
	Helicopter = { Id = "Helicopter", Name = "Helicopter", Rarity = "Legendary", Value = 11400, IncomePerSecond = 570, Image = "rbxassetid://0" },
	ArmoredSUV = { Id = "ArmoredSUV", Name = "Armored SUV", Rarity = "Legendary", Value = 14400, IncomePerSecond = 720, Image = "rbxassetid://0" },
	Yacht = { Id = "Yacht", Name = "Yacht", Rarity = "Legendary", Value = 18000, IncomePerSecond = 900, Image = "rbxassetid://0" },
	PrivateJet = { Id = "PrivateJet", Name = "Private Jet", Rarity = "Legendary", Value = 22200, IncomePerSecond = 1110, Image = "rbxassetid://0" },
	SupercarCollection = { Id = "SupercarCollection", Name = "Supercar Collection", Rarity = "Legendary", Value = 27000, IncomePerSecond = 1350, Image = "rbxassetid://0" },
	Submarine = { Id = "Submarine", Name = "Submarine", Rarity = "Legendary", Value = 33000, IncomePerSecond = 1650, Image = "rbxassetid://0" },
	VintageCarCollection = { Id = "VintageCarCollection", Name = "Vintage Car Collection", Rarity = "Legendary", Value = 6300, IncomePerSecond = 315, Image = "rbxassetid://0" },
	CustomChopper = { Id = "CustomChopper", Name = "Custom Chopper", Rarity = "Legendary", Value = 6900, IncomePerSecond = 345, Image = "rbxassetid://0" },
	ArmoredLimoFleet = { Id = "ArmoredLimoFleet", Name = "Armored Limo Fleet", Rarity = "Legendary", Value = 7800, IncomePerSecond = 390, Image = "rbxassetid://0" },
	PrivateHelicopterFleet = { Id = "PrivateHelicopterFleet", Name = "Private Helicopter Fleet", Rarity = "Legendary", Value = 8400, IncomePerSecond = 420, Image = "rbxassetid://0" },
	LuxurySailboat = { Id = "LuxurySailboat", Name = "Luxury Sailboat", Rarity = "Legendary", Value = 9900, IncomePerSecond = 495, Image = "rbxassetid://0" },
	MonsterTruck = { Id = "MonsterTruck", Name = "Monster Truck", Rarity = "Legendary", Value = 10500, IncomePerSecond = 525, Image = "rbxassetid://0" },
	AmphibiousVehicle = { Id = "AmphibiousVehicle", Name = "Amphibious Vehicle", Rarity = "Legendary", Value = 12600, IncomePerSecond = 630, Image = "rbxassetid://0" },
	PrivateJetCharter = { Id = "PrivateJetCharter", Name = "Private Jet Charter", Rarity = "Legendary", Value = 15600, IncomePerSecond = 780, Image = "rbxassetid://0" },
	LuxuryTrainCar = { Id = "LuxuryTrainCar", Name = "Luxury Train Car", Rarity = "Legendary", Value = 19200, IncomePerSecond = 960, Image = "rbxassetid://0" },
	StealthSpeedboat = { Id = "StealthSpeedboat", Name = "Stealth Speedboat", Rarity = "Legendary", Value = 24000, IncomePerSecond = 1200, Image = "rbxassetid://0" },
	CustomYacht = { Id = "CustomYacht", Name = "Custom Yacht", Rarity = "Legendary", Value = 28800, IncomePerSecond = 1440, Image = "rbxassetid://0" },
	PrivateAirship = { Id = "PrivateAirship", Name = "Private Airship", Rarity = "Legendary", Value = 36000, IncomePerSecond = 1800, Image = "rbxassetid://0" },

	-- Luxury
	DiamondCrown = { Id = "DiamondCrown", Name = "Diamond Crown", Rarity = "Luxury", Value = 48000, IncomePerSecond = 2400, Image = "rbxassetid://0" },
	GoldenTrophy = { Id = "GoldenTrophy", Name = "Golden Trophy", Rarity = "Luxury", Value = 66000, IncomePerSecond = 3300, Image = "rbxassetid://0" },
	MegaYacht = { Id = "MegaYacht", Name = "Mega Yacht", Rarity = "Luxury", Value = 90000, IncomePerSecond = 4500, Image = "rbxassetid://0" },
	ArmoredLimousine = { Id = "ArmoredLimousine", Name = "Armored Limousine", Rarity = "Luxury", Value = 120000, IncomePerSecond = 6000, Image = "rbxassetid://0" },
	Hypercar = { Id = "Hypercar", Name = "Hypercar", Rarity = "Luxury", Value = 162000, IncomePerSecond = 8100, Image = "rbxassetid://0" },
	GoldenPrivateJet = { Id = "GoldenPrivateJet", Name = "Golden Private Jet", Rarity = "Luxury", Value = 210000, IncomePerSecond = 10500, Image = "rbxassetid://0" },
	PrivateRocket = { Id = "PrivateRocket", Name = "Private Rocket", Rarity = "Luxury", Value = 270000, IncomePerSecond = 13500, Image = "rbxassetid://0" },
	DiamondSupercar = { Id = "DiamondSupercar", Name = "Diamond Supercar", Rarity = "Luxury", Value = 348000, IncomePerSecond = 17400, Image = "rbxassetid://0" },
	PlatinumCrown = { Id = "PlatinumCrown", Name = "Platinum Crown", Rarity = "Luxury", Value = 42000, IncomePerSecond = 2100, Image = "rbxassetid://0" },
	JeweledScepter = { Id = "JeweledScepter", Name = "Jeweled Scepter", Rarity = "Luxury", Value = 54000, IncomePerSecond = 2700, Image = "rbxassetid://0" },
	GoldenStatue = { Id = "GoldenStatue", Name = "Golden Statue", Rarity = "Luxury", Value = 78000, IncomePerSecond = 3900, Image = "rbxassetid://0" },
	DiamondYacht = { Id = "DiamondYacht", Name = "Diamond Yacht", Rarity = "Luxury", Value = 105000, IncomePerSecond = 5250, Image = "rbxassetid://0" },
	ArmoredConvoy = { Id = "ArmoredConvoy", Name = "Armored Convoy", Rarity = "Luxury", Value = 138000, IncomePerSecond = 6900, Image = "rbxassetid://0" },
	GoldenHypercar = { Id = "GoldenHypercar", Name = "Golden Hypercar", Rarity = "Luxury", Value = 186000, IncomePerSecond = 9300, Image = "rbxassetid://0" },
	DiamondStuddedJet = { Id = "DiamondStuddedJet", Name = "Diamond-Studded Jet", Rarity = "Luxury", Value = 234000, IncomePerSecond = 11700, Image = "rbxassetid://0" },
	PrivateSuperyacht = { Id = "PrivateSuperyacht", Name = "Private Superyacht", Rarity = "Luxury", Value = 300000, IncomePerSecond = 15000, Image = "rbxassetid://0" },
	GoldenSubmarine = { Id = "GoldenSubmarine", Name = "Golden Submarine", Rarity = "Luxury", Value = 318000, IncomePerSecond = 15900, Image = "rbxassetid://0" },
	OrbitalShuttle = { Id = "OrbitalShuttle", Name = "Orbital Shuttle", Rarity = "Luxury", Value = 390000, IncomePerSecond = 19500, Image = "rbxassetid://0" },
	DiamondSpaceRocket = { Id = "DiamondSpaceRocket", Name = "Diamond Space Rocket", Rarity = "Luxury", Value = 420000, IncomePerSecond = 21000, Image = "rbxassetid://0" },
	GoldenFighterJet = { Id = "GoldenFighterJet", Name = "Golden Fighter Jet", Rarity = "Luxury", Value = 450000, IncomePerSecond = 22500, Image = "rbxassetid://0" },
}

function ItemDatabase.GetItem(id: string): Item?
	return items[id]
end

function ItemDatabase.GetAllItems(): { [string]: Item }
	return items
end

function ItemDatabase.GetItemsByRarity(rarity: string): { Item }
	local result = {}
	for _, item in items do
		if item.Rarity == rarity then
			table.insert(result, item)
		end
	end
	return result
end

return ItemDatabase
