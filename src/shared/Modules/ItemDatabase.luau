local ItemDatabase = {}

ItemDatabase.Items = {}

local categoryModules = {
	"Clothing",
	"Shoes",
	"Electronics",
	"Luxury",
	"Collectibles"
}

for _, moduleName in ipairs(categoryModules) do
	local module = script.Parent:FindFirstChild(moduleName)

	if module then
		local items = require(module)

		for itemId, item in pairs(items) do
			item.Id = item.Id or itemId
			item.ItemId = item.ItemId or item.Id
			item.Name = item.Name or item.ItemName
			item.ItemName = item.ItemName or item.Name
			item.Category = item.Category or moduleName
			item.Icon = item.Icon or "rbxassetid://0"

			ItemDatabase.Items[itemId] = item
		end
	else
		warn("Missing item category module:", moduleName)
	end
end

function ItemDatabase.GetItem(itemId)
	return ItemDatabase.Items[itemId]
end

function ItemDatabase.GetAllItems()
	return ItemDatabase.Items
end

function ItemDatabase.GetItemsByCategory(category)
	local result = {}

	for _, item in pairs(ItemDatabase.Items) do
		if item.Category == category then
			table.insert(result, item)
		end
	end

	return result
end

function ItemDatabase.GetItemsByRarity(rarity)
	local result = {}

	for _, item in pairs(ItemDatabase.Items) do
		if item.Rarity == rarity then
			table.insert(result, item)
		end
	end

	return result
end

return ItemDatabase