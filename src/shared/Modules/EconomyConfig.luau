local Economy = {}

-- ============================
-- NPC OFFERS (Buy Low Sell High)
-- ============================
Economy.NPCPriceRanges = {
	Common = {Min = 50, Max = 150},
	Rare = {Min = 200, Max = 500},
	Epic = {Min = 600, Max = 1500},
	Legendary = {Min = 2000, Max = 5000}
}

Economy.NPCRarityChances = {
	Common = 60,
	Rare = 28,
	Epic = 10,
	Legendary = 2
}

Economy.ResellMarginRange = {Min = 0.15, Max = 0.30} -- 15% - 30%

Economy.NPCSpawnInterval = {Min = 10, Max = 15} -- secunde

-- ============================
-- STAND UPGRADE
-- ============================
Economy.StandUpgradeCosts = {
	[1] = 0,
	[2] = 2500,
	[3] = 10000,
	[4] = 35000,
	[5] = 100000
}

Economy.StandBonuses = {
	[1] = {Luck = 0, Sell = 0, Speed = 0},
	[2] = {Luck = 5, Sell = 3, Speed = 0},
	[3] = {Luck = 10, Sell = 8, Speed = 3},
	[4] = {Luck = 18, Sell = 15, Speed = 7},
	[5] = {Luck = 28, Sell = 25, Speed = 12}
}

-- ============================
-- VIP
-- ============================
Economy.VIP = {
	Price = 299, -- Robux
	Luck = 15,
	MoneyMultiplier = 1.5,
	ExtraInventorySlots = 25
}

-- ============================
-- PETS (echipare)
-- ============================
Economy.EquippedPetSlots = 2

-- ============================
-- CAPS GENERALE (anti-abuz balans)
-- ============================
Economy.Caps = {
	Luck = 100,
	Sell = 80,
	Speed = 50
}

-- ============================
-- MARKET
-- ============================
Economy.Market = {
	UpdateInterval = 600,       -- 10 minute
	NormalVariance = 15,        -- ±15% per update normal
	MaxPriceDeviation = 50,     -- cap ±50% față de bază

	GoldenHour = {
		Duration = 300,          -- 5 minute
		Boost = 40
	},

	MarketCrash = {
		Duration = 300,          -- 5 minute
		Drop = 40
	},

	AntiAbuseHoldTime = 900     -- 15 minute
}

return Economy