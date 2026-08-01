-- Temporary boosts bought with in-game Cash (not Robux) at the Potions
-- stand, activate immediately. Same flavor as VIP's 3 permanent perks --
-- Luck/Speed/Cash -- just temporary and stackable on top of VIP. Only the
-- field matching a potion's own effect is set; the other two stay nil.
--
-- Price walked up twice: 3000 -> 50000 -> 250000. After UpgradeConfig's
-- tracks got rescaled 50x (starting at $75K-150K per level) and Assets/
-- Investments went up into the trillions, even $50K still read as pocket
-- change. $250K sits at roughly 2.5x a first-level Upgrade and ~1/4 of
-- LuxuryTownhouse (Asset) -- a real, felt spend every time, especially
-- since it's meant to be rebought repeatedly (every 10 min), not a single
-- permanent purchase like an Upgrade level.

export type Potion = {
	Id: string,
	Name: string,
	Price: number,
	DurationSeconds: number,
	Image: string,
	LuckWeightMultiplier: { [string]: number }?,
	CooldownMultiplier: number?,
	CashBonusPercent: number?,
}

local PotionDatabase = {}

local potions: { [string]: Potion } = {
	LuckPotion = {
		Id = "LuckPotion",
		Name = "Luck Potion",
		Price = 250000,
		DurationSeconds = 600,
		Image = "rbxassetid://84813784990662",
		-- Luxury deliberately milder (1.5x, not the old 3.5x) -- it stacks
			-- multiplicatively with VIP's 6x and the Luck Upgrade's own max
			-- Luxury multiplier, and the combined stack was pushing a fully
			-- built player's Luxury odds from ~1-in-50k down to ~1-in-2.4k (a
			-- Luxury every ~12 min of active rolling), which guts the
			-- "genuine rare moment" the tier exists for. See UpgradeConfig's
			-- matching comment for the other half of this same fix.
			LuckWeightMultiplier = { Common = 1, Rare = 1.3, Epic = 1.6, Legendary = 2, Ultra = 2.5, Luxury = 1.5 },
	},
	SpeedPotion = {
		Id = "SpeedPotion",
		Name = "Speed Potion",
		Price = 250000,
		DurationSeconds = 600,
		Image = "rbxassetid://127880368455184",
		CooldownMultiplier = 0.6,
	},
	FortunePotion = {
		Id = "FortunePotion",
		Name = "Fortune Potion",
		Price = 250000,
		DurationSeconds = 600,
		Image = "rbxassetid://128041182972051",
		CashBonusPercent = 40,
	},
}

function PotionDatabase.GetPotion(id: string): Potion?
	return potions[id]
end

function PotionDatabase.GetAllPotions(): { [string]: Potion }
	return potions
end

return PotionDatabase
