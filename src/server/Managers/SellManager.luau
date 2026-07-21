local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local MarketManager = require(modulesFolder:WaitForChild("MarketManager"))
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))

local CosmeticManager = require(script.Parent:WaitForChild("CosmeticManager"))
local SFXServer = require(script.Parent:WaitForChild("SFXServer"))

local SellManager = {}

-- BuyPrice/BaseValue/MinSell/MaxSell/PurchaseTime sunt salvate ca IntValue
-- (InventoryManager.createInt), NU NumberValue -- sunt clase SURORI in
-- Roblox (ambele mostenesc din ValueBase, dar niciuna din cealalta), deci
-- IntValue:IsA("NumberValue") e mereu false. Verificarea veche (doar
-- NumberValue) cadea mereu pe branch-ul de default -- bug vechi, invizibil
-- pana acum (pretul de vanzare era mereu 0 pe sub, mascat de mesajul generic
-- "Sold item successfully" care nu arata suma).
local function getNumberValue(folder, name, default)
	local value = folder:FindFirstChild(name)
	if value and (value:IsA("NumberValue") or value:IsA("IntValue")) then
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

	-- Calculat direct din cap-urile hard (Sell%/market), nu citit dintr-un
	-- atribut static -- vezi Economy.GetMaxSell. Evita si un vector de exploit
	-- teoretic (un atribut MaxSell manipulat client-side nu ar mai avea efect).
	local maxSell = Economy.GetMaxSell(baseValue)
	local category = getStringValue(itemFolder, "Category", "Misc")
	local purchaseTime = getNumberValue(itemFolder, "PurchaseTime", 0)

	local marketMultiplier = 1

	if MarketManager.GetFinalMarketMultiplier then
		marketMultiplier = MarketManager.GetFinalMarketMultiplier(category, purchaseTime)
	elseif MarketManager.GetCategoryMultiplier then
		marketMultiplier = MarketManager.GetCategoryMultiplier(category)
	end

	-- Piata NEGATIVA pentru categoria asta chiar acum (marketMultiplier < 1,
	-- pretul de baza a scazut) -- niciun bonus de Sell% sau multiplicator de
	-- bani (VIP/Friend Boost/cosmetice) nu mai compenseaza pierderea. Cerut
	-- explicit: cand piata scade, jucatorul chiar simte pierderea, perks-urile
	-- nu o anuleaza -- il vinde pe minus, si asta e.
	local isMarketNegative = marketMultiplier < 1

	local standSellBonus = getStandSellBonus(player)
	local cosmeticBonuses = CosmeticManager.GetBonuses(player)
	local petBonuses = PetManager.GetBonuses(player)

	local cosmeticSellBonus = cosmeticBonuses.SellPrice or 0
	local petSellBonus = petBonuses.SellPrice or 0
	local moneyMultiplier = cosmeticBonuses.MoneyMultiplier or 1

	if player:GetAttribute("IsVIP") then
		moneyMultiplier *= Economy.VIP.MoneyMultiplier
	end

	local friendBoostPercent = player:GetAttribute("FriendBoostPercent") or 0
	moneyMultiplier *= (1 + friendBoostPercent / 100)

	local rebirthSellBonus = getRebirthSellBonus(player)

	local totalSellBonus = standSellBonus + cosmeticSellBonus + petSellBonus + rebirthSellBonus
	totalSellBonus = math.clamp(totalSellBonus, 0, Economy.Caps.Sell)

	if isMarketNegative then
		totalSellBonus = 0
		moneyMultiplier = 1
	end

	local rawPrice = baseValue
	rawPrice *= marketMultiplier
	rawPrice *= (1 + totalSellBonus / 100)

	local finalPrice = math.floor(rawPrice)

	if isMarketNegative then
		-- NU aplicam podeaua de MinSell aici -- MinSell e de obicei peste
		-- BuyPrice, deci ar anula exact pierderea pe care piata negativa
		-- trebuie s-o produca. Ramane doar plafonul de MaxSell (irelevant
		-- oricum, pretul e deja sub baseValue).
		finalPrice = math.min(finalPrice, maxSell)
	else
		finalPrice = math.clamp(finalPrice, minSell, maxSell)
	end

	-- moneyMultiplier (VIP, cosmetice) se aplica DUPA clamp-ul per-item, nu
	-- inainte -- altfel bonusul se pierde in mare parte in clamp-ul de
	-- MaxSell (ex. un jucator nou, fara alte bonusuri, primea doar +33% in
	-- loc de +50% promis de VIP, iar la jucatori cu Sell% deja mare, VIP nu
	-- mai adauga nimic). Aplicat aici, VIP livreaza mereu bonusul integral,
	-- indiferent cat de saturate sunt celelalte bonusuri de Sell%.
	--
	-- Singurul bonus fara plafon pana acum -- VIP x Friend Boost x cosmetice
	-- se aduna liber (5 cosmetice Legendary + VIP + Friend Boost ~4.4x, fara
	-- limita). Plafonat la Economy.Caps.MoneyMultiplier.
	moneyMultiplier = math.min(moneyMultiplier, Economy.Caps.MoneyMultiplier)
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

	local itemName = getStringValue(itemFolder, "ItemName", "Item")
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

	SFXServer.Play(player, "Sell")

	return true, sellPrice, profit, itemName
end

return SellManager