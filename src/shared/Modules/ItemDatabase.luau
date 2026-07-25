-- Canonical item schema, one shape for every rarity tier:
-- { Id, Name, Rarity, Value, IncomePerSecond, Image }
-- IncomePerSecond is passive cash earned per second while the item sits
-- unsold in inventory (roughly Value/65, so holding for income is a real
-- alternative to selling, not strictly better -- rebalance freely).
-- Placeholder items/values -- reskin and rebalance freely, the rest of the
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

local items: { [string]: Item } = {
	-- Common
	Watch = { Id = "Watch", Name = "Wrist Watch", Rarity = "Common", Value = 25, IncomePerSecond = 1, Image = "rbxassetid://0" },
	Sneakers = { Id = "Sneakers", Name = "Sneakers", Rarity = "Common", Value = 40, IncomePerSecond = 1, Image = "rbxassetid://0" },
	Bike = { Id = "Bike", Name = "Bicycle", Rarity = "Common", Value = 60, IncomePerSecond = 2, Image = "rbxassetid://0" },

	-- Rare
	GoldChain = { Id = "GoldChain", Name = "Gold Chain", Rarity = "Rare", Value = 500, IncomePerSecond = 8, Image = "rbxassetid://0" },
	DesignerBag = { Id = "DesignerBag", Name = "Designer Bag", Rarity = "Rare", Value = 750, IncomePerSecond = 12, Image = "rbxassetid://0" },

	-- Epic
	DiamondRing = { Id = "DiamondRing", Name = "Diamond Ring", Rarity = "Epic", Value = 5000, IncomePerSecond = 75, Image = "rbxassetid://0" },
	SportsCar = { Id = "SportsCar", Name = "Sports Car", Rarity = "Epic", Value = 8500, IncomePerSecond = 130, Image = "rbxassetid://0" },

	-- Legendary
	Yacht = { Id = "Yacht", Name = "Yacht", Rarity = "Legendary", Value = 75000, IncomePerSecond = 1000, Image = "rbxassetid://0" },
	PrivateJet = { Id = "PrivateJet", Name = "Private Jet", Rarity = "Legendary", Value = 150000, IncomePerSecond = 2000, Image = "rbxassetid://0" },

	-- Luxury
	Mansion = { Id = "Mansion", Name = "Mansion", Rarity = "Luxury", Value = 1000000, IncomePerSecond = 12000, Image = "rbxassetid://0" },
	Bugatti = { Id = "Bugatti", Name = "Bugatti", Rarity = "Luxury", Value = 2500000, IncomePerSecond = 30000, Image = "rbxassetid://0" },
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
