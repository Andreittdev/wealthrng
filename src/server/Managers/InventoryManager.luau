local InventoryManager = {}

local nextItemId = 1

local function createString(parent, name, value)
	local v = Instance.new("StringValue")
	v.Name = name
	v.Value = value or ""
	v.Parent = parent
end

local function createInt(parent, name, value)
	local v = Instance.new("IntValue")
	v.Name = name
	v.Value = tonumber(value) or 0
	v.Parent = parent
end

function InventoryManager.AddItem(player, offer)
	local inventory = player:FindFirstChild("Inventory")

	if not inventory then
		warn("Inventory not found")
		return
	end

	local item = Instance.new("Folder")
	item.Name = tostring(nextItemId)
	item.Parent = inventory

	nextItemId += 1

	createString(item, "ItemId", offer.ItemId)
	createString(item, "ItemName", offer.ItemName or "Unknown Item")
	createString(item, "Rarity", offer.Rarity or "Common")
	createString(item, "Category", offer.Category or "Unknown")
	createString(item, "Condition", offer.Condition or "Good")
	createString(item, "Image", offer.Image or "")

	createInt(item, "BuyPrice", offer.BuyPrice)
	createInt(item, "BaseValue", offer.BaseValue or offer.BuyPrice)
	createInt(item, "MinSell", offer.MinSell or offer.BuyPrice)
	createInt(item, "MaxSell", offer.MaxSell or offer.BaseValue or offer.BuyPrice)
	createInt(item, "PurchaseTime", offer.PurchaseTime or os.time())

	print(player.Name .. " received " .. tostring(offer.ItemName))
end

return InventoryManager