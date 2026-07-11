local ItemsDatabase = {}

ItemsDatabase.Items = {
	-- COMMON
	VintageGlasses = {DisplayName="Vintage Glasses", Type="Glasses", Rarity="Common", MoneyBonus=2, LuckBonus=0, SellBonus=0, Image=""},
	LeatherBag = {DisplayName="Leather Bag", Type="Bag", Rarity="Common", MoneyBonus=3, LuckBonus=0, SellBonus=0, Image=""},
	SilverWatch = {DisplayName="Silver Watch", Type="Watch", Rarity="Common", MoneyBonus=4, LuckBonus=0, SellBonus=0, Image=""},
	CanvasBackpack = {DisplayName="Canvas Backpack", Type="Backpack", Rarity="Common", MoneyBonus=3, LuckBonus=0, SellBonus=0, Image=""},
	StreetSneakers = {DisplayName="Street Sneakers", Type="Sneakers", Rarity="Common", MoneyBonus=5, LuckBonus=0, SellBonus=0, Image=""},
	SportCap = {DisplayName="Sport Cap", Type="Hat", Rarity="Common", MoneyBonus=2, LuckBonus=0, SellBonus=0, Image=""},
	CasualHoodie = {DisplayName="Casual Hoodie", Type="Clothing", Rarity="Common", MoneyBonus=4, LuckBonus=0, SellBonus=0, Image=""},
	SteelChain = {DisplayName="Steel Chain", Type="Chain", Rarity="Common", MoneyBonus=5, LuckBonus=0, SellBonus=0, Image=""},
	DenimJacket = {DisplayName="Denim Jacket", Type="Clothing", Rarity="Common", MoneyBonus=4, LuckBonus=0, SellBonus=0, Image=""},
	CanvasBelt = {DisplayName="Canvas Belt", Type="Belt", Rarity="Common", MoneyBonus=3, LuckBonus=0, SellBonus=0, Image=""},

	-- RARE
	CrystalWatch = {DisplayName="Crystal Watch", Type="Watch", Rarity="Rare", MoneyBonus=8, LuckBonus=0, SellBonus=0, Image=""},
	ExecutiveBag = {DisplayName="Executive Bag", Type="Bag", Rarity="Rare", MoneyBonus=9, LuckBonus=0, SellBonus=0, Image=""},
	PolarGlasses = {DisplayName="Polar Glasses", Type="Glasses", Rarity="Rare", MoneyBonus=8, LuckBonus=0, SellBonus=0, Image=""},
	GoldChain = {DisplayName="Gold Chain", Type="Chain", Rarity="Rare", MoneyBonus=10, LuckBonus=0, SellBonus=0, Image=""},
	PlatinumWatch = {DisplayName="Platinum Watch", Type="Watch", Rarity="Rare", MoneyBonus=11, LuckBonus=0, SellBonus=0, Image=""},
	ShadowSneakers = {DisplayName="Shadow Sneakers", Type="Sneakers", Rarity="Rare", MoneyBonus=10, LuckBonus=0, SellBonus=0, Image=""},
	PrestigeJacket = {DisplayName="Prestige Jacket", Type="Clothing", Rarity="Rare", MoneyBonus=9, LuckBonus=0, SellBonus=0, Image=""},
	RoyalBackpack = {DisplayName="Royal Backpack", Type="Backpack", Rarity="Rare", MoneyBonus=10, LuckBonus=0, SellBonus=0, Image=""},

	-- EPIC
	EclipseWatch = {DisplayName="Eclipse Watch", Type="Watch", Rarity="Epic", MoneyBonus=15, LuckBonus=5, SellBonus=0, Image=""},
	PhantomChain = {DisplayName="Phantom Chain", Type="Chain", Rarity="Epic", MoneyBonus=16, LuckBonus=6, SellBonus=0, Image=""},
	MonarchBag = {DisplayName="Monarch Bag", Type="Bag", Rarity="Epic", MoneyBonus=17, LuckBonus=7, SellBonus=0, Image=""},
	ZenithGlasses = {DisplayName="Zenith Glasses", Type="Glasses", Rarity="Epic", MoneyBonus=18, LuckBonus=8, SellBonus=0, Image=""},
	InfernoSneakers = {DisplayName="Inferno Sneakers", Type="Sneakers", Rarity="Epic", MoneyBonus=19, LuckBonus=9, SellBonus=0, Image=""},
	OnyxJacket = {DisplayName="Onyx Jacket", Type="Clothing", Rarity="Epic", MoneyBonus=20, LuckBonus=10, SellBonus=0, Image=""},

	-- LEGENDARY
	Imperium = {DisplayName="Imperium", Type="Watch", Rarity="Legendary", MoneyBonus=30, LuckBonus=20, SellBonus=15, DropWeight=5, Image=""},
	Sovereign = {DisplayName="Sovereign", Type="Chain", Rarity="Legendary", MoneyBonus=27, LuckBonus=18, SellBonus=13, DropWeight=10, Image=""},
	Elysium = {DisplayName="Elysium", Type="Glasses", Rarity="Legendary", MoneyBonus=25, LuckBonus=17, SellBonus=12, DropWeight=20, Image=""},
	Regalia = {DisplayName="Regalia", Type="Bag", Rarity="Legendary", MoneyBonus=23, LuckBonus=16, SellBonus=11, DropWeight=30, Image=""},
	Eminence = {DisplayName="Eminence", Type="Sneakers", Rarity="Legendary", MoneyBonus=22, LuckBonus=15, SellBonus=10, DropWeight=35, Image=""}
}

return ItemsDatabase