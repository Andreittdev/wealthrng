-- Singurul ProcessReceipt din tot jocul -- Roblox permite UN SINGUR
-- handler per joc pentru toate Developer Product-urile (nu unul per produs),
-- deci tot ce se cumpara cu Robux repetabil (Premium Egg, Cash Packs) trece
-- prin scriptul asta.
--
-- IMPORTANT: ProductId = 0 in EconomyConfig.luau sunt PLACEHOLDER-e --
-- Developer Product-urile trebuie create manual in Creator Dashboard
-- (Studio > Monetization > Developer Products > Create One), nu se pot crea
-- din cod. Pana nu primesc ID-urile reale si le pun in EconomyConfig, acest
-- script nu are cu ce sa potriveasca achizitiile (productHandlers ramane
-- gol pentru ele) si nu face nimic -- dar tot codul de granting e deja gata.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

local PetManager = require(script.Parent:WaitForChild("PetManager"))
local RobuxSpentCalculator = require(script.Parent:WaitForChild("RobuxSpentCalculator"))

-- Refolosim sistemul de notificari deja existent (ShowNotification +
-- NotificationDisplay.client.luau), in loc sa construim un remote/UI de
-- rezultat separat -- acelasi tipar folosit de StarterPackManager/
-- DailyRewardsManager/RebirthManager etc.
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local showNotificationEvent = remotes:WaitForChild("ShowNotification")

-- Aceeasi logica de "roll ponderat" ca PetManager.rollPetFromEgg, dar pe
-- RARITATE (nu pe pet direct) -- alegem intai raritatea (sanse mai bune
-- decat ouale normale), apoi PetManager.GrantRandomPetByRarity alege un pet
-- random din acea raritate.
local function rollPremiumRarity()
	local chances = Economy.PremiumEgg.RarityChances
	local total = 0

	for _, entry in ipairs(chances) do
		total += entry.Chance
	end

	local roll = math.random() * total
	local cumulative = 0

	for _, entry in ipairs(chances) do
		cumulative += entry.Chance
		if roll <= cumulative then
			return entry.Rarity
		end
	end

	return chances[1].Rarity
end

-- Adauga pretul REAL (din Marketplace, nu valoarea afisata in EconomyConfig,
-- care poate fi incorecta) la totalul de Robux cheltuit pe Developer
-- Products al jucatorului, persistat prin DataManager.
local function addDevProductSpend(player, productId)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end

	local devProductRobuxSpent = leaderstats:FindFirstChild("DevProductRobuxSpent")
	if not devProductRobuxSpent then
		return
	end

	local price = 0
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)

	if ok and info and info.PriceInRobux then
		price = info.PriceInRobux
	end

	devProductRobuxSpent.Value += price
	RobuxSpentCalculator.Recompute(player)
end

local function grantPremiumEgg(player)
	local rarity = rollPremiumRarity()
	local result = PetManager.GrantRandomPetByRarity(player, rarity)

	if result then
		if result.IsDuplicate then
			showNotificationEvent:FireClient(
				player,
				"Premium Egg: " .. result.Rarity .. " " .. result.DisplayName
					.. " (duplicate, sold for $" .. tostring(result.AutoSellCash) .. ")"
			)
		else
			showNotificationEvent:FireClient(player, "Premium Egg: got a " .. result.Rarity .. " " .. result.DisplayName .. "!")
		end
	end
end

local function grantCashPack(player, amount)
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")

	if money then
		money.Value += amount
	end

	showNotificationEvent:FireClient(player, "Cash Pack: +$" .. tostring(amount) .. " added to your balance!")
end

-- productId -> function(player) -- populat mai jos, o singura data.
local productHandlers = {}

if Economy.PremiumEgg.ProductId ~= 0 then
	productHandlers[Economy.PremiumEgg.ProductId] = function(player)
		grantPremiumEgg(player)
	end
end

for _, pack in ipairs(Economy.CashPacks) do
	if pack.ProductId ~= 0 then
		productHandlers[pack.ProductId] = function(player)
			grantCashPack(player, pack.Money)
		end
	end
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)

	-- Jucatorul a plecat intre cumparare si procesare -- Roblox va reincerca
	-- mai tarziu, cand (daca) revine.
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local handler = productHandlers[receiptInfo.ProductId]
	if not handler then
		warn("PremiumPurchaseManager: ProductId necunoscut -- " .. tostring(receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok = pcall(handler, player)
	if not ok then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local spendOk = pcall(addDevProductSpend, player, receiptInfo.ProductId)
	if not spendOk then
		warn("PremiumPurchaseManager: am acordat reward-ul dar nu am putut actualiza RobuxSpent pentru " .. player.Name)
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end
