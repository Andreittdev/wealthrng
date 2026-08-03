-- Canonical item schema, one shape for every rarity tier:
-- { Id, Name, Rarity, Value, IncomePerSecond, Image }
-- IncomePerSecond is passive cash earned per second while the item sits
-- unsold in inventory. Common/Rare/Epic stay at the original ~Value/20
-- ratio (deliberately a worse ratio than AssetDatabase's tiers, since a
-- rolled item is meant to be an early-game bootstrap for those 3 tiers,
-- not a long-term income engine). Legendary/Ultra/Luxury are DIFFERENT --
-- see the "endgame relevance" note below. Values top out around
-- AssetDatabase's tier3-4 range (a lucky Luxury roll should feel like a
-- genuine windfall, not a rounding error) but the *average* roll stays
-- far below that -- see AssetDatabase's header for the overall pacing
-- target this economy is tuned around (~30 min to Millionaire, ~2h to
-- Billionaire, ~4-5h to Trillionaire); rolling should feel rewarding
-- without being able to reliably shortcut that curve.
--
-- Endgame relevance (Legendary/Ultra/Luxury only): Value (and therefore
-- sell price, roll-within-rarity odds, and the pacing curve above) is
-- UNCHANGED from the ~Value/20 baseline for these 3 tiers too -- only
-- IncomePerSecond got an extra multiplier on top (Legendary x30, Ultra
-- x300, Luxury x1500) specifically so equipping one of these still means
-- something once a player has real Assets, instead of being a rounding
-- error. Before this, the single best possible item (a Luxury pull) paid
-- ~$2.7M/min -- about 0.0007% of two maxed-out Assets' combined income
-- ($384B/min) -- meaning days of grinding for a Luxury item bought
-- literally nothing once a player had decent Assets equipped. Now a
-- Luxury item pays ~$4B/min (~1% of that same 2-maxed-Assets income,
-- roughly matching AssetDatabase's PrivateResort tier on its own) and an
-- Ultra item pays enough to sit around CountrysideMansion/SkyscraperPenthouse
-- territory -- still clearly secondary to Assets (which stay the real
-- long-term engine, unlike Items only 1 of which can ever be equipped at
-- once, see MaxEquipped below), but no longer invisible. Items and Assets
-- pay out independently and stack additively (IncomeManager ticks both),
-- not competing for the same equip slot.
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
	-- True only for items granted exclusively through some other means
	-- (currently just GroupRewardChest, via GroupRewardsManager.luau) --
	-- excluded from the normal weighted roll so it can't also come out of
	-- a regular roll. GetItemsByRarity still returns it (CatalogPanel
	-- should still be able to show it); GetRollableItemsByRarity is what
	-- RollManager/RollOdds use instead.
	NotRollable: boolean?,
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
-- accurate. Legendary/Ultra/Luxury's IncomePerSecond then got the extra
-- endgame-relevance multiplier on top (see header comment) -- their Value
-- fields were NOT touched by that pass.
local items: { [string]: Item } = {
	-- Common
	Watch = { Id = "Watch", Name = "Wrist Watch", Rarity = "Common", Value = 30, IncomePerSecond = 2, Image = "rbxassetid://119741941418230" },
	Headphones = { Id = "Headphones", Name = "Headphones", Rarity = "Common", Value = 42, IncomePerSecond = 2, Image = "rbxassetid://118509750139000" },
	Sunglasses = { Id = "Sunglasses", Name = "Sunglasses", Rarity = "Common", Value = 54, IncomePerSecond = 3, Image = "rbxassetid://83798532772724" },
	Sneakers = { Id = "Sneakers", Name = "Sneakers", Rarity = "Common", Value = 72, IncomePerSecond = 4, Image = "rbxassetid://72574430652709" },
	Backpack = { Id = "Backpack", Name = "Backpack", Rarity = "Common", Value = 90, IncomePerSecond = 5, Image = "rbxassetid://108837248731027" },
	Skateboard = { Id = "Skateboard", Name = "Skateboard", Rarity = "Common", Value = 108, IncomePerSecond = 5, Image = "rbxassetid://103075510883021" },
	Scooter = { Id = "Scooter", Name = "Scooter", Rarity = "Common", Value = 132, IncomePerSecond = 7, Image = "rbxassetid://112875419459640" },
	Bike = { Id = "Bike", Name = "Bicycle", Rarity = "Common", Value = 156, IncomePerSecond = 8, Image = "rbxassetid://125449471698065" },
	Cap = { Id = "Cap", Name = "Cap", Rarity = "Common", Value = 20, IncomePerSecond = 1, Image = "rbxassetid://117019465838323" },
	Wallet = { Id = "Wallet", Name = "Wallet", Rarity = "Common", Value = 26, IncomePerSecond = 1, Image = "rbxassetid://100112161386588" },
	Belt = { Id = "Belt", Name = "Belt", Rarity = "Common", Value = 34, IncomePerSecond = 2, Image = "rbxassetid://89871264215891" },
	Gloves = { Id = "Gloves", Name = "Gloves", Rarity = "Common", Value = 46, IncomePerSecond = 2, Image = "rbxassetid://121825939758502" },
	Scarf = { Id = "Scarf", Name = "Scarf", Rarity = "Common", Value = 60, IncomePerSecond = 3, Image = "rbxassetid://116465789453040" },
	Umbrella = { Id = "Umbrella", Name = "Umbrella", Rarity = "Common", Value = 78, IncomePerSecond = 4, Image = "rbxassetid://100747880731516" },
	Wristband = { Id = "Wristband", Name = "Wristband", Rarity = "Common", Value = 96, IncomePerSecond = 5, Image = "rbxassetid://71751447953283" },
	Beanie = { Id = "Beanie", Name = "Beanie", Rarity = "Common", Value = 114, IncomePerSecond = 6, Image = "rbxassetid://101578019815837" },
	FannyPack = { Id = "FannyPack", Name = "Fanny Pack", Rarity = "Common", Value = 138, IncomePerSecond = 7, Image = "rbxassetid://101453950089334" },
	Rollerblades = { Id = "Rollerblades", Name = "Rollerblades", Rarity = "Common", Value = 162, IncomePerSecond = 8, Image = "rbxassetid://81873848590782" },
	Longboard = { Id = "Longboard", Name = "Longboard", Rarity = "Common", Value = 174, IncomePerSecond = 9, Image = "rbxassetid://118768282186280" },
	PocketKnife = { Id = "PocketKnife", Name = "Fish", Rarity = "Common", Value = 186, IncomePerSecond = 9, Image = "rbxassetid://119049229386897" },
	PearlNecklace = { Id = "PearlNecklace", Name = "Pearl Necklace", Rarity = "Common", Value = 210, IncomePerSecond = 11, Image = "rbxassetid://93076949097198" },

	-- Rare
	LeatherJacket = { Id = "LeatherJacket", Name = "Leather Jacket", Rarity = "Rare", Value = 270, IncomePerSecond = 14, Image = "rbxassetid://85720781135273" },
	LuxuryWatch = { Id = "LuxuryWatch", Name = "Luxury Watch", Rarity = "Rare", Value = 330, IncomePerSecond = 17, Image = "rbxassetid://134953740369625" },
	DesignerBag = { Id = "DesignerBag", Name = "Designer Bag", Rarity = "Rare", Value = 408, IncomePerSecond = 20, Image = "rbxassetid://104967148505266" },
	ElectricScooter = { Id = "ElectricScooter", Name = "Electric Scooter", Rarity = "Rare", Value = 480, IncomePerSecond = 24, Image = "rbxassetid://75299024994415" },
	Motorcycle = { Id = "Motorcycle", Name = "Motorcycle", Rarity = "Rare", Value = 570, IncomePerSecond = 29, Image = "rbxassetid://83196119587389" },
	Drone = { Id = "Drone", Name = "Drone", Rarity = "Rare", Value = 660, IncomePerSecond = 33, Image = "rbxassetid://121270590214322" },
	GamingSetup = { Id = "GamingSetup", Name = "Gaming Setup", Rarity = "Rare", Value = 780, IncomePerSecond = 39, Image = "rbxassetid://108468634544464" },
	CologneSet = { Id = "CologneSet", Name = "Cologne Set", Rarity = "Rare", Value = 195, IncomePerSecond = 10, Image = "rbxassetid://129765358689097" },
	DesignerShoes = { Id = "DesignerShoes", Name = "Designer Shoes", Rarity = "Rare", Value = 240, IncomePerSecond = 12, Image = "rbxassetid://114324948144468" },
	HomeGymSetup = { Id = "HomeGymSetup", Name = "Dumbbell", Rarity = "Rare", Value = 285, IncomePerSecond = 14, Image = "rbxassetid://125349881822344" },
	CameraKit = { Id = "CameraKit", Name = "Camera", Rarity = "Rare", Value = 345, IncomePerSecond = 17, Image = "rbxassetid://133332295051714" },
	Smartwatch = { Id = "Smartwatch", Name = "Smartwatch", Rarity = "Rare", Value = 390, IncomePerSecond = 20, Image = "rbxassetid://132547192034252" },
	RacingHelmet = { Id = "RacingHelmet", Name = "Racing Helmet", Rarity = "Rare", Value = 435, IncomePerSecond = 22, Image = "rbxassetid://116252331950646" },
	HomeStudioMic = { Id = "HomeStudioMic", Name = "Home Studio Mic", Rarity = "Rare", Value = 465, IncomePerSecond = 23, Image = "rbxassetid://117717407463773" },
	Segway = { Id = "Segway", Name = "Segway", Rarity = "Rare", Value = 525, IncomePerSecond = 26, Image = "rbxassetid://96600881166401" },
	VRHeadset = { Id = "VRHeadset", Name = "VR Headset", Rarity = "Rare", Value = 555, IncomePerSecond = 28, Image = "rbxassetid://133655835226903" },
	LeatherBoots = { Id = "LeatherBoots", Name = "Leather Boots", Rarity = "Rare", Value = 600, IncomePerSecond = 30, Image = "rbxassetid://119238622516844" },
	LongboardElite = { Id = "LongboardElite", Name = "Longboard Elite", Rarity = "Rare", Value = 630, IncomePerSecond = 32, Image = "rbxassetid://133022797473552" },
	PortableSpeakerSystem = { Id = "PortableSpeakerSystem", Name = "Portable Speaker System", Rarity = "Rare", Value = 705, IncomePerSecond = 35, Image = "rbxassetid://127671971245631" },

	-- Epic
	GoldChain = { Id = "GoldChain", Name = "Gold Chain", Rarity = "Epic", Value = 960, IncomePerSecond = 48, Image = "rbxassetid://99233560062479" },
	DiamondRing = { Id = "DiamondRing", Name = "Diamond Ring", Rarity = "Epic", Value = 1080, IncomePerSecond = 54, Image = "rbxassetid://101276080383060" },
	LuxurySuit = { Id = "LuxurySuit", Name = "Luxury Suit", Rarity = "Epic", Value = 1320, IncomePerSecond = 66, Image = "rbxassetid://134565243301027" },
	GoldBracelet = { Id = "GoldBracelet", Name = "Gold Bracelet", Rarity = "Epic", Value = 1620, IncomePerSecond = 81, Image = "rbxassetid://101171946609317" },
	HomeTheater = { Id = "HomeTheater", Name = "Home Theater System", Rarity = "Epic", Value = 1920, IncomePerSecond = 96, Image = "rbxassetid://77307392703922" },
	JetSki = { Id = "JetSki", Name = "Jet Ski", Rarity = "Epic", Value = 2280, IncomePerSecond = 114, Image = "rbxassetid://100902202279398" },
	RacingMotorbike = { Id = "RacingMotorbike", Name = "Racing Motorbike", Rarity = "Epic", Value = 2640, IncomePerSecond = 132, Image = "rbxassetid://134149569345833" },
	SportsCar = { Id = "SportsCar", Name = "Sports Car", Rarity = "Epic", Value = 3060, IncomePerSecond = 153, Image = "rbxassetid://132574050222221" },
	Speedboat = { Id = "Speedboat", Name = "Speedboat", Rarity = "Epic", Value = 3540, IncomePerSecond = 177, Image = "rbxassetid://78795502631757" },
	DesignerWatchSet = { Id = "DesignerWatchSet", Name = "Designer Watch Set", Rarity = "Epic", Value = 1200, IncomePerSecond = 60, Image = "rbxassetid://103216713984485" },
	SilkSuit = { Id = "SilkSuit", Name = "Silk Suit", Rarity = "Epic", Value = 1440, IncomePerSecond = 72, Image = "rbxassetid://132846124662140" },
	RecordingStudioRig = { Id = "RecordingStudioRig", Name = "Recording Studio Rig", Rarity = "Epic", Value = 1560, IncomePerSecond = 78, Image = "rbxassetid://114217906336500" },
	CustomMotorbike = { Id = "CustomMotorbike", Name = "Custom Motorbike", Rarity = "Epic", Value = 1740, IncomePerSecond = 87, Image = "rbxassetid://89270902878129" },
	ATV = { Id = "ATV", Name = "ATV", Rarity = "Epic", Value = 1860, IncomePerSecond = 93, Image = "rbxassetid://72965781183567" },
	Snowmobile = { Id = "Snowmobile", Name = "Snowmobile", Rarity = "Epic", Value = 2040, IncomePerSecond = 102, Image = "rbxassetid://123133944349664" },
	DroneFleet = { Id = "DroneFleet", Name = "Drone Fleet", Rarity = "Epic", Value = 2160, IncomePerSecond = 108, Image = "rbxassetid://110687271059060" },
	ConvertibleCar = { Id = "ConvertibleCar", Name = "Convertible Car", Rarity = "Epic", Value = 2400, IncomePerSecond = 120, Image = "rbxassetid://120743111977366" },
	RaceKart = { Id = "RaceKart", Name = "Race Kart", Rarity = "Epic", Value = 2760, IncomePerSecond = 138, Image = "rbxassetid://96351912127555" },
	LuxuryCamperVan = { Id = "LuxuryCamperVan", Name = "Luxury Camper Van", Rarity = "Epic", Value = 2940, IncomePerSecond = 147, Image = "rbxassetid://93436754598970" },
	KartingTrackPass = { Id = "KartingTrackPass", Name = "Karting Track Pass", Rarity = "Epic", Value = 3300, IncomePerSecond = 165, Image = "rbxassetid://91608021557289" },
	-- One-time Group Rewards claim (GroupRewardsConfig.luau/
	-- GroupRewardsManager.luau) -- deliberately worth far more than a
	-- normal Epic roll, since it's a free thank-you for joining the
	-- group, not something pulled from the normal weighted roll table.
	GroupRewardChest = { Id = "GroupRewardChest", Name = "Group Reward Chest", Rarity = "Epic", Value = 50000, IncomePerSecond = 2500, Image = "rbxassetid://0", NotRollable = true },
	-- Day 2's fixed Daily Rewards item (DailyRewardsConfig.luau, replaces
	-- the old "random Epic item" pull so every player gets the same,
	-- nameable thing on Day 2) -- Value/IncomePerSecond sit right in the
	-- middle of the normal Epic range above (~Value/20 ratio, same as every
	-- other Common/Rare/Epic item), just not part of the roll pool.
	Day2SpecialItem = { Id = "Day2SpecialItem", Name = "Day 2 Treasure Case", Rarity = "Epic", Value = 1800, IncomePerSecond = 90, Image = "rbxassetid://121292786068518", NotRollable = true },

	-- Legendary -- IncomePerSecond x30 over the ~Value/20 baseline (see
	-- header's "endgame relevance" note); Value itself unchanged.
	PlatinumCrown = { Id = "PlatinumCrown", Name = "Platinum Crown", Rarity = "Legendary", Value = 7200, IncomePerSecond = 10800, Image = "rbxassetid://118274687783850" },
	LuxuryMotorhome = { Id = "LuxuryMotorhome", Name = "Luxury Motorhome", Rarity = "Legendary", Value = 9000, IncomePerSecond = 13500, Image = "rbxassetid://134406694125426" },
	Helicopter = { Id = "Helicopter", Name = "Helicopter", Rarity = "Legendary", Value = 11400, IncomePerSecond = 17100, Image = "rbxassetid://134380255700329" },
	ArmoredSUV = { Id = "ArmoredSUV", Name = "Armored SUV", Rarity = "Legendary", Value = 14400, IncomePerSecond = 21600, Image = "rbxassetid://131870391152073" },
	Yacht = { Id = "Yacht", Name = "Yacht", Rarity = "Legendary", Value = 18000, IncomePerSecond = 27000, Image = "rbxassetid://74535569916987" },
	PrivateJet = { Id = "PrivateJet", Name = "Private Jet", Rarity = "Legendary", Value = 22200, IncomePerSecond = 33300, Image = "rbxassetid://79217095167961" },
	SupercarCollection = { Id = "SupercarCollection", Name = "Supercar Collection", Rarity = "Legendary", Value = 27000, IncomePerSecond = 40500, Image = "rbxassetid://77189238810491" },
	Submarine = { Id = "Submarine", Name = "Submarine", Rarity = "Legendary", Value = 33000, IncomePerSecond = 49500, Image = "rbxassetid://78547934005857" },
	VintageCarCollection = { Id = "VintageCarCollection", Name = "Vintage Car Collection", Rarity = "Legendary", Value = 6300, IncomePerSecond = 9450, Image = "rbxassetid://132265333375267" },
	CustomChopper = { Id = "CustomChopper", Name = "Custom Chopper", Rarity = "Legendary", Value = 6900, IncomePerSecond = 10350, Image = "rbxassetid://114868414654130" },
	ArmoredLimoFleet = { Id = "ArmoredLimoFleet", Name = "Armored Limo Fleet", Rarity = "Legendary", Value = 7800, IncomePerSecond = 11700, Image = "rbxassetid://104569131723695" },
	PrivateHelicopterFleet = { Id = "PrivateHelicopterFleet", Name = "Private Helicopter Fleet", Rarity = "Legendary", Value = 8400, IncomePerSecond = 12600, Image = "rbxassetid://105237585382462" },
	LuxurySailboat = { Id = "LuxurySailboat", Name = "Luxury Sailboat", Rarity = "Legendary", Value = 9900, IncomePerSecond = 14850, Image = "rbxassetid://131716131069927" },
	MonsterTruck = { Id = "MonsterTruck", Name = "Monster Truck", Rarity = "Legendary", Value = 10500, IncomePerSecond = 15750, Image = "rbxassetid://117547471625050" },
	AmphibiousVehicle = { Id = "AmphibiousVehicle", Name = "Amphibious Vehicle", Rarity = "Legendary", Value = 12600, IncomePerSecond = 18900, Image = "rbxassetid://90695834851129" },
	PrivateJetCharter = { Id = "PrivateJetCharter", Name = "Private Jet Charter", Rarity = "Legendary", Value = 15600, IncomePerSecond = 23400, Image = "rbxassetid://107096565207004" },
	LuxuryTrainCar = { Id = "LuxuryTrainCar", Name = "Luxury Train Car", Rarity = "Legendary", Value = 19200, IncomePerSecond = 28800, Image = "rbxassetid://125126553435784" },
	StealthSpeedboat = { Id = "StealthSpeedboat", Name = "Stealth Speedboat", Rarity = "Legendary", Value = 24000, IncomePerSecond = 36000, Image = "rbxassetid://130440675883566" },
	CustomYacht = { Id = "CustomYacht", Name = "Custom Yacht", Rarity = "Legendary", Value = 28800, IncomePerSecond = 43200, Image = "rbxassetid://97115338393502" },
	PrivateAirship = { Id = "PrivateAirship", Name = "Private Airship", Rarity = "Legendary", Value = 36000, IncomePerSecond = 54000, Image = "rbxassetid://103535495210510" },

	-- Ultra -- IncomePerSecond x300 over the ~Value/20 baseline; Value unchanged.
	DiamondCrown = { Id = "DiamondCrown", Name = "Diamond Crown", Rarity = "Ultra", Value = 48000, IncomePerSecond = 720000, Image = "rbxassetid://100113265333060" },
	GoldenTrophy = { Id = "GoldenTrophy", Name = "Golden Trophy", Rarity = "Ultra", Value = 66000, IncomePerSecond = 990000, Image = "rbxassetid://91270016875367" },
	MegaYacht = { Id = "MegaYacht", Name = "Mega Yacht", Rarity = "Ultra", Value = 90000, IncomePerSecond = 1350000, Image = "rbxassetid://76537381301012" },
	ArmoredLimousine = { Id = "ArmoredLimousine", Name = "Armored Limousine", Rarity = "Ultra", Value = 120000, IncomePerSecond = 1800000, Image = "rbxassetid://131943850468806" },
	Hypercar = { Id = "Hypercar", Name = "Hypercar", Rarity = "Ultra", Value = 162000, IncomePerSecond = 2430000, Image = "rbxassetid://123620891280974" },
	GoldenPrivateJet = { Id = "GoldenPrivateJet", Name = "Golden Private Jet", Rarity = "Ultra", Value = 210000, IncomePerSecond = 3150000, Image = "rbxassetid://127950076146933" },
	-- Image was "rbxassetid://0" (broken/blank placeholder) -- unlike
	-- GroupRewardChest/Day2SpecialItem, this item IS normally rollable, so
	-- players were seeing a broken image in the reveal/inventory/equip UI.
	-- Reusing GoldenPrivateJet's image as a stand-in until a dedicated
	-- rocket image id is provided.
	PrivateRocket = { Id = "PrivateRocket", Name = "Private Rocket", Rarity = "Ultra", Value = 270000, IncomePerSecond = 4050000, Image = "rbxassetid://127950076146933" },
	DiamondSupercar = { Id = "DiamondSupercar", Name = "Diamond Supercar", Rarity = "Ultra", Value = 348000, IncomePerSecond = 5220000, Image = "rbxassetid://129814625035916" },
	RaceCar = { Id = "RaceCar", Name = "Race Car", Rarity = "Ultra", Value = 42000, IncomePerSecond = 630000, Image = "rbxassetid://105809267920652" },
	JeweledScepter = { Id = "JeweledScepter", Name = "Jeweled Scepter", Rarity = "Ultra", Value = 54000, IncomePerSecond = 810000, Image = "rbxassetid://135861272860998" },
	GoldenStatue = { Id = "GoldenStatue", Name = "Golden Statue", Rarity = "Ultra", Value = 78000, IncomePerSecond = 1170000, Image = "rbxassetid://100268876990404" },
	DiamondYacht = { Id = "DiamondYacht", Name = "Diamond Yacht", Rarity = "Ultra", Value = 105000, IncomePerSecond = 1575000, Image = "rbxassetid://129984270026433" },
	ArmoredConvoy = { Id = "ArmoredConvoy", Name = "Armored Convoy", Rarity = "Ultra", Value = 138000, IncomePerSecond = 2070000, Image = "rbxassetid://87942635740431" },
	GoldenHypercar = { Id = "GoldenHypercar", Name = "Golden Hypercar", Rarity = "Ultra", Value = 186000, IncomePerSecond = 2790000, Image = "rbxassetid://127318987809600" },
	DiamondStuddedJet = { Id = "DiamondStuddedJet", Name = "Diamond-Studded Jet", Rarity = "Ultra", Value = 234000, IncomePerSecond = 3510000, Image = "rbxassetid://99005604986380" },
	PrivateSuperyacht = { Id = "PrivateSuperyacht", Name = "Private Superyacht", Rarity = "Ultra", Value = 300000, IncomePerSecond = 4500000, Image = "rbxassetid://132599504761379" },
	GoldenSubmarine = { Id = "GoldenSubmarine", Name = "Golden Submarine", Rarity = "Ultra", Value = 318000, IncomePerSecond = 4770000, Image = "rbxassetid://99673268017035" },
	OrbitalShuttle = { Id = "OrbitalShuttle", Name = "Orbital Shuttle", Rarity = "Ultra", Value = 390000, IncomePerSecond = 5850000, Image = "rbxassetid://103514008772036" },
	DiamondSpaceRocket = { Id = "DiamondSpaceRocket", Name = "Diamond Space Rocket", Rarity = "Ultra", Value = 420000, IncomePerSecond = 6300000, Image = "rbxassetid://79469039857485" },
	GoldenFighterJet = { Id = "GoldenFighterJet", Name = "Golden Fighter Jet", Rarity = "Ultra", Value = 450000, IncomePerSecond = 6750000, Image = "rbxassetid://92307710118432" },

	-- Luxury -- the true chase tier, above Ultra. Only 2 items on purpose
	-- (see RarityConfig's header comment): a normal session shouldn't
	-- realistically produce one, so pulling either is meant to be a
	-- genuine "post it in chat" moment, not just the top of the grind.
	-- IncomePerSecond x1500 over the ~Value/20 baseline (the biggest
	-- endgame-relevance jump of any tier, see header comment) -- puts
	-- these roughly on par with AssetDatabase's PrivateResort tier (~$4.68B/
	-- min) on their own, while still leaving 2 maxed-out Assets far ahead
	-- overall. Value itself unchanged.
	DiamondStarCruiser = { Id = "DiamondStarCruiser", Name = "Ancient Pyramid", Rarity = "Luxury", Value = 900000, IncomePerSecond = 67500000, Image = "rbxassetid://74654052867804" },
	CrownJewelCollection = { Id = "CrownJewelCollection", Name = "Ruby Skyscraper", Rarity = "Luxury", Value = 600000, IncomePerSecond = 45000000, Image = "rbxassetid://138288535175001" },
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

-- Same as GetItemsByRarity but excludes NotRollable items (e.g.
-- GroupRewardChest) -- what RollManager.pickItem and RollOdds.GetOneInN
-- actually use, so an exclusive-claim item can't also come out of a normal
-- roll. GetItemsByRarity itself stays unfiltered for browsing (CatalogPanel).
function ItemDatabase.GetRollableItemsByRarity(rarity: string): { Item }
	local result = {}
	for _, item in items do
		if item.Rarity == rarity and not item.NotRollable then
			table.insert(result, item)
		end
	end
	return result
end

-- Items sharing a rarity no longer have identical odds -- the pricier an
-- item is *within its own tier*, the rarer it is to roll, on a dampened
-- (sqrt) curve so the spread feels meaningful without making the priciest
-- item in a tier a near-impossible pull. Both RollManager (actual pick)
-- and RollOdds (displayed "1 in N") must use this exact function so the
-- odds shown to players match the real math.
function ItemDatabase.GetRollWeight(item: Item): number
	return 1 / math.sqrt(math.max(item.Value, 1))
end

return ItemDatabase
