local CosmeticDatabase = {}

CosmeticDatabase.Rarities = {
	Common = {
		Chance = 60,
		MoneyMultiplier = 1.03,
		NpcLuck = 0,
		SellPrice = 0
	},

	Rare = {
		Chance = 25,
		MoneyMultiplier = 1.08,
		NpcLuck = 0,
		SellPrice = 0
	},

	Epic = {
		Chance = 12,
		MoneyMultiplier = 1.15,
		NpcLuck = 8,
		SellPrice = 0
	},

	Legendary = {
		Chance = 3,
		MoneyMultiplier = 1.30,
		NpcLuck = 15,
		SellPrice = 10
	}
}

CosmeticDatabase.Items = {
	BasicGlasses = {
		DisplayName = "Basic Glasses",
		Rarity = "Common",
		Slot = "Face",
		Image = "",
		AccessoryId = 0
	},

	BlueCap = {
		DisplayName = "Blue Cap",
		Rarity = "Common",
		Slot = "Hat",
		Image = "",
		AccessoryId = 0
	},

	CoolHeadphones = {
		DisplayName = "Cool Headphones",
		Rarity = "Rare",
		Slot = "Accessory",
		Image = "",
		AccessoryId = 0
	},

	BlackHorns = {
		DisplayName = "Black Horns",
		Rarity = "Rare",
		Slot = "Hat",
		Image = "",
		AccessoryId = 0
	},

	Fedora = {
		DisplayName = "Classic Fedora",
		Rarity = "Epic",
		Slot = "Hat",
		Image = "",
		AccessoryId = 0
	},

	GoldenCrown = {
		DisplayName = "Golden Crown",
		Rarity = "Epic",
		Slot = "Hat",
		Image = "",
		AccessoryId = 0
	},

	HappyFace = {
		DisplayName = "Happy Face",
		Rarity = "Legendary",
		Slot = "Face",
		Image = "",
		AccessoryId = 0
	},

	DominusHood = {
		DisplayName = "Dominus Hood",
		Rarity = "Legendary",
		Slot = "Hat",
		Image = "",
		AccessoryId = 0
	}
}

return CosmeticDatabase