-- Canonical item schema, one shape for every rarity tier:
-- { Id, Name, Rarity, Value, Image }
-- Placeholder items/values -- reskin and rebalance freely, the rest of the
-- system only depends on the shape, not the specific entries below.

export type Item = {
	Id: string,
	Name: string,
	Rarity: string,
	Value: number,
	Image: string,
}

local ItemDatabase = {}

local items: { [string]: Item } = {
	-- Common
	Watch = { Id = "Watch", Name = "Wrist Watch", Rarity = "Common", Value = 25, Image = "rbxassetid://0" },
	Sneakers = { Id = "Sneakers", Name = "Sneakers", Rarity = "Common", Value = 40, Image = "rbxassetid://0" },
	Bike = { Id = "Bike", Name = "Bicycle", Rarity = "Common", Value = 60, Image = "rbxassetid://0" },

	-- Rare
	GoldChain = { Id = "GoldChain", Name = "Gold Chain", Rarity = "Rare", Value = 500, Image = "rbxassetid://0" },
	DesignerBag = { Id = "DesignerBag", Name = "Designer Bag", Rarity = "Rare", Value = 750, Image = "rbxassetid://0" },

	-- Epic
	DiamondRing = { Id = "DiamondRing", Name = "Diamond Ring", Rarity = "Epic", Value = 5000, Image = "rbxassetid://0" },
	SportsCar = { Id = "SportsCar", Name = "Sports Car", Rarity = "Epic", Value = 8500, Image = "rbxassetid://0" },

	-- Legendary
	Yacht = { Id = "Yacht", Name = "Yacht", Rarity = "Legendary", Value = 75000, Image = "rbxassetid://0" },
	PrivateJet = { Id = "PrivateJet", Name = "Private Jet", Rarity = "Legendary", Value = 150000, Image = "rbxassetid://0" },

	-- Luxury
	Mansion = { Id = "Mansion", Name = "Mansion", Rarity = "Luxury", Value = 1000000, Image = "rbxassetid://0" },
	Bugatti = { Id = "Bugatti", Name = "Bugatti", Rarity = "Luxury", Value = 2500000, Image = "rbxassetid://0" },
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
