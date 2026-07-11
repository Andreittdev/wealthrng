local Pets = {}

Pets.Eggs = {

	Basic = {
		Price = 5000,
		Pets = {
			{Name = "Parcel Pup", Rarity = "Common", Chance = 40, Luck = 1, Sell = 1, Speed = 0},
			{Name = "Cap Cat", Rarity = "Common", Chance = 30, Luck = 1, Sell = 1, Speed = 0},
			{Name = "Sneaker Bunny", Rarity = "Common", Chance = 20, Luck = 2, Sell = 1, Speed = 0},
			{Name = "Camera Chick", Rarity = "Common", Chance = 10, Luck = 2, Sell = 2, Speed = 0}
		}
	},

	Rare = {
		Price = 25000,
		Pets = {
			{Name = "Watch Wolf", Rarity = "Rare", Chance = 40, Luck = 3, Sell = 2, Speed = 1},
			{Name = "Cash Croc", Rarity = "Rare", Chance = 30, Luck = 3, Sell = 3, Speed = 1},
			{Name = "Street Dragon", Rarity = "Rare", Chance = 20, Luck = 4, Sell = 3, Speed = 1},
			{Name = "Delivery Bear", Rarity = "Rare", Chance = 10, Luck = 5, Sell = 4, Speed = 2}
		}
	},

	Epic = {
		Price = 100000,
		Pets = {
			{Name = "Diamond Shark", Rarity = "Epic", Chance = 35, Luck = 5, Sell = 4, Speed = 2},
			{Name = "Vault Gorilla", Rarity = "Epic", Chance = 30, Luck = 6, Sell = 5, Speed = 2},
			{Name = "Luxury Panther", Rarity = "Epic", Chance = 20, Luck = 7, Sell = 6, Speed = 3},
			{Name = "Bull Phoenix", Rarity = "Epic", Chance = 15, Luck = 8, Sell = 7, Speed = 3}
		}
	},

	Legendary = {
		Price = 500000,
		Pets = {
			{Name = "King Of Kicks", Rarity = "Legendary", Chance = 39.9, Luck = 8, Sell = 7, Speed = 4},
			{Name = "Hype Dragon", Rarity = "Legendary", Chance = 30, Luck = 9, Sell = 8, Speed = 4},
			{Name = "Diamond Emperor", Rarity = "Legendary", Chance = 20, Luck = 10, Sell = 9, Speed = 5},
			{Name = "Billionaire Beast", Rarity = "Legendary", Chance = 10, Luck = 12, Sell = 10, Speed = 6},
			{Name = "THE COLLECTOR", Rarity = "Secret", Chance = 0.1, Luck = 25, Sell = 20, Speed = 10}
		}
	},

	Mythic = {
		Price = 2500000,
		Pets = {
			{Name = "Market Titan", Rarity = "Mythic", Chance = 39.5, Luck = 13, Sell = 11, Speed = 6},
			{Name = "Golden Mogul", Rarity = "Mythic", Chance = 30, Luck = 14, Sell = 12, Speed = 7},
			{Name = "Fortune Dragon", Rarity = "Mythic", Chance = 20, Luck = 16, Sell = 14, Speed = 8},
			{Name = "CEO X", Rarity = "Mythic", Chance = 10, Luck = 18, Sell = 16, Speed = 9},
			{Name = "THE KINGPIN", Rarity = "Secret", Chance = 0.5, Luck = 30, Sell = 25, Speed = 12}
		}
	}

}

return Pets