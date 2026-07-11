local NPCDatabase = {}

NPCDatabase.Types = {

	StreetDealer = {
		DisplayName = "Street Dealer",

		SpawnChance = 45,

		NegotiationDifficulty = 0.9,

		CategoryWeights = {
			Clothing = 45,
			Shoes = 30,
			Electronics = 15,
			Collectibles = 10,
			Luxury = 0
		},

		RarityWeights = {
			Common = 75,
			Rare = 20,
			Epic = 5,
			Legendary = 0,
			Mythic = 0
		}
	},

	Sneakerhead = {
		DisplayName = "Sneakerhead",

		SpawnChance = 25,

		NegotiationDifficulty = 1.0,

		CategoryWeights = {
			Shoes = 75,
			Clothing = 20,
			Collectibles = 5,
			Electronics = 0,
			Luxury = 0
		},

		RarityWeights = {
			Common = 55,
			Rare = 32,
			Epic = 11,
			Legendary = 2,
			Mythic = 0
		}
	},

	TechDealer = {
		DisplayName = "Tech Dealer",

		SpawnChance = 15,

		NegotiationDifficulty = 1.1,

		CategoryWeights = {
			Electronics = 80,
			Collectibles = 10,
			Luxury = 10,
			Shoes = 0,
			Clothing = 0
		},

		RarityWeights = {
			Common = 45,
			Rare = 35,
			Epic = 16,
			Legendary = 4,
			Mythic = 0
		}
	},

	LuxuryCollector = {
		DisplayName = "Luxury Collector",

		SpawnChance = 10,

		NegotiationDifficulty = 1.2,

		CategoryWeights = {
			Luxury = 70,
			Collectibles = 20,
			Electronics = 10,
			Clothing = 0,
			Shoes = 0
		},

		RarityWeights = {
			Common = 30,
			Rare = 40,
			Epic = 22,
			Legendary = 8,
			Mythic = 0
		}
	},

	BlackMarketDealer = {
		DisplayName = "Black Market Dealer",

		SpawnChance = 5,

		NegotiationDifficulty = 1.35,

		CategoryWeights = {
			Clothing = 20,
			Shoes = 20,
			Electronics = 20,
			Luxury = 20,
			Collectibles = 20
		},

		RarityWeights = {
			Common = 0,
			Rare = 15,
			Epic = 55,
			Legendary = 28,
			Mythic = 2
		}
	}

}

return NPCDatabase