local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = ReplicatedStorage:WaitForChild("Modules")

local ItemsDatabase = require(modules:WaitForChild("ItemsDatabase"))
local Economy = require(modules:WaitForChild("EconomyConfig"))

local CosmeticManager = {}

local EQUIP_SLOTS = {
	"Watch",
	"Bag",
	"Glasses",
	"Sneakers",
	"Chain"
}

function CosmeticManager.CreateInventory(player)
	local folder = player:FindFirstChild("Cosmetics")

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Cosmetics"
		folder.Parent = player
	end

	local equipped = player:FindFirstChild("EquippedCosmetics")

	if not equipped then
		equipped = Instance.new("Folder")
		equipped.Name = "EquippedCosmetics"
		equipped.Parent = player

		for _, slot in ipairs(EQUIP_SLOTS) do
			local value = Instance.new("StringValue")
			value.Name = slot
			value.Value = ""
			value.Parent = equipped
		end
	end
end

local function rollRarity(crateType)
	local chances = Economy.CrateChances[crateType] or Economy.CrateChances.Basic

	local total = 0
	for _, chance in pairs(chances) do
		total += chance
	end

	local roll = math.random() * total
	local current = 0

	for rarity, chance in pairs(chances) do
		current += chance
		if roll <= current then
			return rarity
		end
	end

	return "Common"
end

local function getRandomItemByRarity(rarity)
	local pool = {}
	local totalWeight = 0

	for itemId, item in pairs(ItemsDatabase.Items) do
		if item.Rarity == rarity then
			local weight = item.DropWeight or 1
			totalWeight += weight

			table.insert(pool, {
				Id = itemId,
				Weight = weight
			})
		end
	end

	if #pool == 0 then
		return nil
	end

	local roll = math.random() * totalWeight
	local current = 0

	for _, entry in ipairs(pool) do
		current += entry.Weight
		if roll <= current then
			return entry.Id
		end
	end

	return pool[1].Id
end

function CosmeticManager.OpenCrate(player, crateType)
	CosmeticManager.CreateInventory(player)

	crateType = crateType or "Basic"

	local rarity = rollRarity(crateType)
	local itemId = getRandomItemByRarity(rarity)

	if not itemId then
		return nil
	end

	local itemData = ItemsDatabase.Items[itemId]
	local cosmetics = player:FindFirstChild("Cosmetics")

	local itemValue = Instance.new("StringValue")
	itemValue.Name = itemId
	itemValue.Value = itemId
	itemValue.Parent = cosmetics

	return {
		ItemId = itemId,
		DisplayName = itemData.DisplayName,
		Type = itemData.Type,
		Rarity = itemData.Rarity,
		MoneyBonus = itemData.MoneyBonus or 0,
		LuckBonus = itemData.LuckBonus or 0,
		SellBonus = itemData.SellBonus or 0,
		Image = itemData.Image or ""
	}
end

-- Acorda direct un cosmetic specific (nu il ruleaza dintr-o crate) -- pentru
-- recompense unice, ca cele din Token Shop.
function CosmeticManager.GrantSpecificCosmetic(player, itemId)
	CosmeticManager.CreateInventory(player)

	local itemData = ItemsDatabase.Items[itemId]
	if not itemData then
		warn("GrantSpecificCosmetic: unknown item id " .. tostring(itemId))
		return nil
	end

	local cosmetics = player:FindFirstChild("Cosmetics")
	if not cosmetics then
		return nil
	end

	if cosmetics:FindFirstChild(itemId) then
		return nil
	end

	local itemValue = Instance.new("StringValue")
	itemValue.Name = itemId
	itemValue.Value = itemId
	itemValue.Parent = cosmetics

	return {
		ItemId = itemId,
		DisplayName = itemData.DisplayName,
		Type = itemData.Type,
		Rarity = itemData.Rarity,
		MoneyBonus = itemData.MoneyBonus or 0,
		LuckBonus = itemData.LuckBonus or 0,
		SellBonus = itemData.SellBonus or 0,
		Image = itemData.Image or ""
	}
end

function CosmeticManager.Equip(player, itemId)
	CosmeticManager.CreateInventory(player)

	local itemData = ItemsDatabase.Items[itemId]
	if not itemData then
		return false
	end

	local cosmetics = player:FindFirstChild("Cosmetics")
	if not cosmetics or not cosmetics:FindFirstChild(itemId) then
		return false
	end

	local equipped = player:FindFirstChild("EquippedCosmetics")
	if not equipped then
		return false
	end

	local slotValue = equipped:FindFirstChild(itemData.Type)
	if not slotValue then
		return false
	end

	slotValue.Value = itemId
	return true
end

function CosmeticManager.Unequip(player, slotName)
	CosmeticManager.CreateInventory(player)

	local equipped = player:FindFirstChild("EquippedCosmetics")
	if not equipped then
		return false
	end

	local slotValue = equipped:FindFirstChild(slotName)
	if not slotValue then
		return false
	end

	slotValue.Value = ""
	return true
end

function CosmeticManager.GetBonuses(player)
	CosmeticManager.CreateInventory(player)

	local bonuses = {
		MoneyMultiplier = 1,
		NpcLuck = 0,
		SellPrice = 0
	}

	local equipped = player:FindFirstChild("EquippedCosmetics")
	if not equipped then
		return bonuses
	end

	for _, slotValue in ipairs(equipped:GetChildren()) do
		local itemId = slotValue.Value
		local item = ItemsDatabase.Items[itemId]

		if item then
			bonuses.MoneyMultiplier += ((item.MoneyBonus or 0) / 100)
			bonuses.NpcLuck += item.LuckBonus or 0
			bonuses.SellPrice += item.SellBonus or 0
		end
	end

	return bonuses
end

return CosmeticManager