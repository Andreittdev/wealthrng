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

-- Marcheaza un ItemId ca "descoperit vreodata" -- ramane asa chiar daca
-- exemplarul respectiv e ulterior vandut, la fel ca markDiscovered din
-- PetManager.luau (folosit de Index ca sa stie ce iteme sa arate normal vs.
-- ca o umbra neagra/nedescoperit).
local function markItemDiscovered(player, itemId)
	if not itemId or itemId == "" then
		return
	end

	local discovered = player:FindFirstChild("DiscoveredItems")
	if not discovered then
		discovered = Instance.new("Folder")
		discovered.Name = "DiscoveredItems"
		discovered.Parent = player
	end

	if discovered:FindFirstChild(itemId) then
		return
	end

	local marker = Instance.new("BoolValue")
	marker.Name = itemId
	marker.Value = true
	marker.Parent = discovered
end

function InventoryManager.AddItem(player, offer)
	local inventory = player:FindFirstChild("Inventory")

	if not inventory then
		warn("Inventory not found")
		return
	end

	-- Prefix "New" -- nextItemId e un contor GLOBAL, comun tuturor jucatorilor
	-- de pe server, in timp ce iteme restaurate din DataStore sunt numite
	-- "1".."N" (DataManager.luau:398, per jucator). Fara prefix, un jucator
	-- care revine cu iteme restaurate putea primi un item nou cu acelasi nume
	-- ca unul restaurat -- coliziune care facea unul din ele de negasit/
	-- ne-vandabil (FindFirstChild gasea mereu primul).
	local item = Instance.new("Folder")
	item.Name = "New" .. tostring(nextItemId)
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

	markItemDiscovered(player, offer.ItemId)

	print(player.Name .. " received " .. tostring(offer.ItemName))

	return item
end

return InventoryManager