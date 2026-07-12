local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local MarketManager = require(modulesFolder:WaitForChild("MarketManager"))
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))

local CosmeticManager = require(script.Parent:WaitForChild("CosmeticManager"))

local SellManager = {}

local function getNumberValue(folder, name, default)
	local value = folder:FindFirstChild(name)
	if value and value:IsA("NumberValue") then
		return value.Value
	end
	return default
end

local function getStringValue(folder, name, default)
	local value = folder:FindFirstChild(name)
	if value and value:IsA("StringValue") then
		return value.Value
	end
	return default
end

local function getStandLevel(player)
	local standLevel = player:FindFirstChild("StandLevel")
	if standLevel then
		return standLevel.Value
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local levelValue = leaderstats:FindFirstChild("StandLevel")
		if levelValue then
			return levelValue.Value
		end
	end

	return 1
end

local function getStandSellBonus(player)
	local level = getStandLevel(player)
	local bonus = Economy.GetStandBonus and Economy.GetStandBonus(level) or Economy.StandBonuses[level] or Economy.StandBonuses[1]

	return bonus.Sell or 0
end

local function getRebirthSellBonus(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local rebirths = leaderstats and leaderstats:FindFirstChild("Rebirths")

	if not rebirths then
		return 0
	end

	return Economy.Rebirth.GetCumulativeBonuses(rebirths.Value).Sell
end

function SellManager.CalculateSellPrice(player, itemFolder)
	if not player or not itemFolder then
		return 0
	end

	local buyPrice = getNumberValue(itemFolder, "BuyPrice", 0)
	local baseValue = getNumberValue(itemFolder, "BaseValue", buyPrice)
	local minSell = getNumberValue(itemFolder, "MinSell", math.floor(baseValue * 0.75))
	local maxSell = getNumberValue(itemFolder, "MaxSell", math.floor(baseValue * 1.5))
	local category = getStringValue(itemFolder, "Category", "Misc")
	local purchaseTime = getNumberValue(itemFolder, "PurchaseTime", 0)

	local marketMultiplier = 1

	if MarketManager.GetFinalMarketMultiplier then
		marketMultiplier = MarketManager.GetFinalMarketMultiplier(category, purchaseTime)
	elseif MarketManager.GetCategoryMultiplier then
		marketMultiplier = MarketManager.GetCategoryMultiplier(category)
	end

	local standSellBonus = getStandSellBonus(player)
	local cosmeticBonuses = CosmeticManager.GetBonuses(player)
	local petBonuses = PetManager.GetBonuses(player)

	local cosmeticSellBonus = cosmeticBonuses.SellPrice or 0
	local petSellBonus = petBonuses.SellPrice or 0
	local moneyMultiplier = cosmeticBonuses.MoneyMultiplier or 1

	if player:GetAttribute("IsVIP") then
		moneyMultiplier *= Economy.VIP.MoneyMultiplier
	end

	local rebirthSellBonus = getRebirthSellBonus(player)

	local totalSellBonus = standSellBonus + cosmeticSellBonus + petSellBonus + rebirthSellBonus
	totalSellBonus = math.clamp(totalSellBonus, 0, Economy.Caps.Sell)

	local rawPrice = baseValue
	rawPrice *= marketMultiplier
	rawPrice *= (1 + totalSellBonus / 100)

	local finalPrice = math.floor(rawPrice)

	finalPrice = math.clamp(finalPrice, minSell, maxSell)

	-- moneyMultiplier (VIP, cosmetice) se aplica DUPA clamp-ul per-item, nu
	-- inainte -- altfel bonusul se pierde in mare parte in clamp-ul de
	-- MaxSell (ex. un jucator nou, fara alte bonusuri, primea doar +33% in
	-- loc de +50% promis de VIP, iar la jucatori cu Sell% deja mare, VIP nu
	-- mai adauga nimic). Aplicat aici, VIP livreaza mereu bonusul integral,
	-- indiferent cat de saturate sunt celelalte bonusuri de Sell%.
	finalPrice = math.floor(finalPrice * moneyMultiplier)

	return finalPrice
end

function SellManager.SellItem(player, itemFolder)
	if not player or not itemFolder then
		return false
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return false
	end

	local money = leaderstats:FindFirstChild("Money")
	if not money then
		return false
	end

	local buyPrice = getNumberValue(itemFolder, "BuyPrice", 0)
	local sellPrice = SellManager.CalculateSellPrice(player, itemFolder)
	local profit = sellPrice - buyPrice

	money.Value += sellPrice

	print(
		player.Name ..
			" sold item for $" .. sellPrice ..
			" | Profit: $" .. profit
	)

	itemFolder:Destroy()

	return true
end

return SellManager