local CrateDatabase = {}

CrateDatabase.Crates = {
	Basic = {
		DisplayName = "BASIC CRATE",
		Price = 5000,
		Image = "rbxassetid://74935479405354",
		Color = Color3.fromRGB(140, 140, 140),
		OddsText = "Common 82%\nRare 15%\nEpic 2.8%\nLegendary 0.2%",
		Rewards = {
			"Vintage Glasses",
			"Leather Bag",
			"Silver Watch",
			"Canvas Backpack",
			"Street Sneakers",
			"Sport Cap",
			"Casual Hoodie",
			"Steel Chain",
			"Denim Jacket",
			"Canvas Belt"
		}
	},

	Rare = {
		DisplayName = "RARE CRATE",
		Price = 15000,
		Image = "rbxassetid://106365548236252",
		Color = Color3.fromRGB(60, 150, 255),
		OddsText = "Rare 78%\nEpic 20%\nLegendary 2%",
		Rewards = {
			"Crystal Watch",
			"Executive Bag",
			"Polar Glasses",
			"Gold Chain",
			"Platinum Watch",
			"Shadow Sneakers",
			"Prestige Jacket",
			"Royal Backpack"
		}
	},

	Epic = {
		DisplayName = "EPIC CRATE",
		Price = 75000,
		Image = "rbxassetid://95342136200599",
		Color = Color3.fromRGB(170, 90, 255),
		OddsText = "Epic 75%\nLegendary 25%",
		Rewards = {
			"Eclipse Watch",
			"Phantom Chain",
			"Monarch Bag",
			"Zenith Glasses",
			"Inferno Sneakers",
			"Onyx Jacket"
		}
	},

	Legendary = {
		DisplayName = "LEGENDARY CRATE",
		Price = 300000,
		Image = "rbxassetid://108372759589989",
		Color = Color3.fromRGB(255, 180, 40),
		OddsText = "Imperium 5%\nSovereign 10%\nElysium 20%\nRegalia 30%\nEminence 35%",
		Rewards = {
			"Imperium",
			"Sovereign",
			"Elysium",
			"Regalia",
			"Eminence"
		}
	}
}

return CrateDatabase