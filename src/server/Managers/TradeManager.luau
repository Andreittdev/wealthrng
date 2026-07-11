local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")

local ItemDatabase = require(modulesFolder:WaitForChild("ItemDatabase"))
local NPCDatabase = require(modulesFolder:WaitForChild("NPCDatabase"))
local MarketManager = require(modulesFolder:WaitForChild("Market"):WaitForChild("MarketManager"))

local TradeManager = {}

local function chooseWeighted(weights, luckBonus)
	local pool = {}
	local totalWeight = 0

	for key, weight in pairs(weights) do
		local finalWeight = weight

		if luckBonus and luckBonus > 0 then
			if key == "Rare" or key == "Epic" or key == "Legendary" or key == "Mythic" then
				finalWeight = finalWeight * (1 + luckBonus / 100)
			end
		end

		if finalWeight > 0 then
			totalWeight += finalWeight
			table.insert(pool, {
				Key = key,
				Weight = finalWeight
			})
		end
	end

	if totalWeight <= 0 then
		return nil
	end

	local roll = math.random() * totalWeight
	local current = 0

	for _, entry in ipairs(pool) do
		current += entry.Weight

		if roll <= current then
			return entry.Key
		end
	end

	return pool[1] and pool[1].Key or nil
end

local function getItemsByCategoryAndRarity(category, rarity)
	local result = {}

	for itemId, item in pairs(ItemDatabase.Items) do
		if item.Category == category and item.Rarity == rarity then
			table.insert(result, {
				Id = itemId,
				Data = item
			})
		end
	end

	return result
end

local function getRandomItemForNPC(npcData, luckBonus)
	local category = chooseWeighted(npcData.CategoryWeights or {}, 0)
	local rarity = chooseWeighted(npcData.RarityWeights or {}, luckBonus)

	if not category or not rarity then
		return nil, nil
	end

	local items = getItemsByCategoryAndRarity(category, rarity)

	if #items == 0 then
		local fallbackItems = ItemDatabase.GetItemsByCategory(category)

		for _, item in ipairs(fallbackItems) do
			table.insert(items, {
				Id = item.Id or item.ItemId,
				Data = item
			})
		end
	end

	if #items == 0 then
		return nil, nil
	end

	local chosen = items[math.random(1, #items)]
	return chosen.Id, chosen.Data
end

function TradeManager.CreateOffer(npcType, luckBonus)
	luckBonus = luckBonus or 0

	local npcData = NPCDatabase.Types[npcType]

	if not npcData then
		warn("NPC type not found: " .. tostring(npcType))
		return nil
	end

	local itemId, item = getRandomItemForNPC(npcData, luckBonus)

	if not item then
		warn("No item found for NPC: " .. tostring(npcType))
		return nil
	end

	local marketTrend = "Stable"

	if MarketManager.GetTrendName then
		marketTrend = MarketManager.GetTrendName(item.Category)
	elseif MarketManager.GetTrend then
		marketTrend = MarketManager.GetTrend(item.Category)
	end
	local marketMultiplier = 1
	if MarketManager.GetCategoryMultiplier then
		marketMultiplier = MarketManager.GetCategoryMultiplier(item.Category or "Misc")
	end

	local finalBuyPrice = math.floor((item.BuyPrice or 0) * marketMultiplier)

	local offer = {
		NPCType = npcData.DisplayName or npcType,

		ItemId = item.Id or item.ItemId or itemId,
		ItemName = item.ItemName or item.Name or item.DisplayName or "Unknown Item",

		BuyPrice = finalBuyPrice,
		BaseValue = item.ExpectedValue or item.BaseValue or item.BuyPrice or 0,

		MinSell = item.MinSell,
		MaxSell = item.MaxSell,

		Rarity = item.Rarity or "Common",
		Category = item.Category or "Misc",

		Condition = item.Condition or "Good",
		Image = item.Icon or item.Image or "",

		MarketTrend = marketTrend,
		NegotiationDifficulty = npcData.NegotiationDifficulty or 1,

		PurchaseTime = os.time()
	}

	return offer
end

return TradeManager