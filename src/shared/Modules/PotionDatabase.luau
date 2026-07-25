-- Temporary boosts bought with in-game Cash (not Robux) at the Potions
-- stand, activate immediately. Same flavor as VIP's 3 permanent perks --
-- Luck/Speed/Cash -- just temporary and stackable on top of VIP. Only the
-- field matching a potion's own effect is set; the other two stay nil.

export type Potion = {
	Id: string,
	Name: string,
	Price: number,
	DurationSeconds: number,
	LuckWeightMultiplier: { [string]: number }?,
	CooldownMultiplier: number?,
	CashBonusPercent: number?,
}

local PotionDatabase = {}

local potions: { [string]: Potion } = {
	LuckPotion = {
		Id = "LuckPotion",
		Name = "Luck Potion",
		Price = 3000,
		DurationSeconds = 600,
		LuckWeightMultiplier = { Common = 1, Rare = 1.3, Epic = 1.6, Legendary = 2, Luxury = 2.5 },
	},
	SpeedPotion = {
		Id = "SpeedPotion",
		Name = "Speed Potion",
		Price = 3000,
		DurationSeconds = 600,
		CooldownMultiplier = 0.6,
	},
	FortunePotion = {
		Id = "FortunePotion",
		Name = "Fortune Potion",
		Price = 3000,
		DurationSeconds = 600,
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
