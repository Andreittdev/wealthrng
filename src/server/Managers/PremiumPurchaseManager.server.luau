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
local DataStoreService = game:GetService("DataStoreService")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

local PetManager = require(script.Parent:WaitForChild("PetManager"))
local RobuxSpentCalculator = require(script.Parent:WaitForChild("RobuxSpentCalculator"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local SFXServer = require(script.Parent:WaitForChild("SFXServer"))

-- Tinem minte ce PurchaseId-uri am procesat deja -- Roblox reincearca acelasi
-- receipt (posibil in sesiuni server diferite) pana cand ProcessReceipt
-- intoarce PurchaseGranted, deci fara asta un restart de server intre
-- acordarea reward-ului si confirmare putea acorda a doua oara acelasi
-- Cash Pack/Premium Egg pentru o singura plata.
local processedPurchasesStore = DataStoreService:GetDataStore("ProcessedPurchases_V1")

local function isPurchaseAlreadyProcessed(purchaseId)
	local ok, result = pcall(function()
		return processedPurchasesStore:GetAsync(purchaseId)
	end)
	return ok and result == true
end

local function markPurchaseProcessed(purchaseId)
	local ok, err = pcall(function()
		processedPurchasesStore:SetAsync(purchaseId, true)
	end)
	if not ok then
		warn("PremiumPurchaseManager: nu am putut marca PurchaseId " .. tostring(purchaseId) .. " ca procesat: " .. tostring(err))
	end
end

-- Refolosim sistemul de notificari deja existent (ShowNotification +
-- NotificationDisplay.client.luau), in loc sa construim un remote/UI de
-- rezultat separat -- acelasi tipar folosit de StarterPackManager/
-- DailyRewardsManager/RebirthManager etc.
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local showNotificationEvent = remotes:WaitForChild("ShowNotification")

local setGiftTargetEvent = remotes:FindFirstChild("SetGiftTarget")
if not setGiftTargetEvent then
	setGiftTargetEvent = Instance.new("RemoteEvent")
	setGiftTargetEvent.Name = "SetGiftTarget"
	setGiftTargetEvent.Parent = remotes
end

-- Roblox nu are niciun API de "gift gamepass la alt jucator" -- vezi
-- comentariul din Economy.GiftPasses (EconomyConfig.luau). Clientul apeleaza
-- SetGiftTarget CHIAR INAINTE de PromptProductPurchase, ca sa stim cui sa
-- acordam perk-ul cand vine receipt-ul (ProcessReceipt nu primite decat
-- PlayerId-ul CUMPARATORULUI + ProductId, niciun payload custom).
--
-- Cheie dubla (cumparator -> productId -> destinatar), nu un singur slot per
-- cumparator -- altfel doua cadouri diferite (produse diferite) trimise
-- rapid unul dupa altul s-ar suprascrie intre ele inainte ca receipt-urile
-- sa se intoarca.
local pendingGiftTargets = {}

local function onSetGiftTarget(player, productId, recipientUserId)
	local isValidGiftProduct = false
	for _, giftEntry in ipairs(Economy.GiftPasses) do
		if giftEntry.ProductId == productId then
			isValidGiftProduct = true
			break
		end
	end

	if not isValidGiftProduct then
		return
	end

	if typeof(recipientUserId) ~= "number" then
		return
	end

	pendingGiftTargets[player] = pendingGiftTargets[player] or {}
	pendingGiftTargets[player][productId] = recipientUserId
end

setGiftTargetEvent.OnServerEvent:Connect(onSetGiftTarget)

Players.PlayerRemoving:Connect(function(player)
	pendingGiftTargets[player] = nil
end)

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
	local hiddenStats = DataManager.GetHiddenStats(player)
	local devProductRobuxSpent = hiddenStats:FindFirstChild("DevProductRobuxSpent")
	if not devProductRobuxSpent then
		devProductRobuxSpent = Instance.new("IntValue")
		devProductRobuxSpent.Name = "DevProductRobuxSpent"
		devProductRobuxSpent.Parent = hiddenStats
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

-- Ambele functii de grant intorc true/false -- ProcessReceipt foloseste
-- valoarea ca sa stie daca a acordat CU ADEVARAT reward-ul inainte sa
-- confirme PurchaseGranted (altfel un leaderstats inca neincarcat facea
-- handler-ul sa "reuseasca" fara sa dea nimic, iar Robux-ul era luat degeaba,
-- fara nicio reincercare posibila dupa aceea).
local function grantPremiumEgg(player)
	local rarity = rollPremiumRarity()
	local result = PetManager.GrantRandomPetByRarity(player, rarity)

	if not result then
		return false
	end

	if result.IsDuplicate then
		showNotificationEvent:FireClient(
			player,
			"Premium Egg: " .. result.Rarity .. " " .. result.DisplayName
				.. " (duplicate, sold for $" .. tostring(result.AutoSellCash) .. ")"
		)
	else
		showNotificationEvent:FireClient(player, "Premium Egg: got a " .. result.Rarity .. " " .. result.DisplayName .. "!")
	end

	return true
end

local function grantCashPack(player, amount)
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")

	if not money then
		return false
	end

	money.Value += amount
	showNotificationEvent:FireClient(player, "Cash Pack: +$" .. tostring(amount) .. " added to your balance!")
	return true
end

-- purchaser = cine a platit; giftEntry = intrarea din Economy.GiftPasses.
-- Cauta destinatarul ales (setat prin SetGiftTarget chiar inainte de
-- PromptProductPurchase) -- daca a plecat intre timp (sau nu a fost setat
-- deloc, ex: cineva a cumparat direct fara sa treaca prin UI-ul de gift),
-- acordam perk-ul CUMPARATORULUI insusi, ca sa nu piarda Robux-ul platit
-- degeaba.
local function grantGiftPass(purchaser, giftEntry)
	local targets = pendingGiftTargets[purchaser]
	local recipientUserId = targets and targets[giftEntry.ProductId]
	local recipient = recipientUserId and Players:GetPlayerByUserId(recipientUserId)

	if not recipient then
		recipient = purchaser
		showNotificationEvent:FireClient(
			purchaser,
			"🎁 Your gift recipient wasn't found, so you got " .. giftEntry.Name .. " for yourself instead!"
		)
	else
		showNotificationEvent:FireClient(recipient, "🎁 " .. purchaser.Name .. " gifted you " .. giftEntry.Name .. "!")

		if recipient ~= purchaser then
			showNotificationEvent:FireClient(purchaser, "🎁 Gifted " .. giftEntry.Name .. " to " .. recipient.Name .. "!")
		end
	end

	recipient:SetAttribute(giftEntry.GrantAttribute, true)

	if targets then
		targets[giftEntry.ProductId] = nil
	end

	DataManager.SaveData(recipient)

	return true
end

-- productId -> function(player) -> boolean (adevarat doar daca s-a acordat efectiv)
local productHandlers = {}

if Economy.PremiumEgg.ProductId ~= 0 then
	productHandlers[Economy.PremiumEgg.ProductId] = function(player)
		return grantPremiumEgg(player)
	end
end

for _, pack in ipairs(Economy.CashPacks) do
	if pack.ProductId ~= 0 then
		productHandlers[pack.ProductId] = function(player)
			return grantCashPack(player, pack.Money)
		end
	end
end

for _, giftEntry in ipairs(Economy.GiftPasses) do
	if giftEntry.ProductId ~= 0 then
		productHandlers[giftEntry.ProductId] = function(player)
			return grantGiftPass(player, giftEntry)
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

	if isPurchaseAlreadyProcessed(receiptInfo.PurchaseId) then
		-- Deja acordat intr-o sesiune anterioara -- Roblox tot reincearca
		-- receipt-ul pana confirmam din nou, dar NU mai acordam a doua oara.
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local handler = productHandlers[receiptInfo.ProductId]
	if not handler then
		warn("PremiumPurchaseManager: ProductId necunoscut -- " .. tostring(receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(handler, player)
	if not ok or not granted then
		-- Fie handler-ul a aruncat eroare, fie n-a putut acorda efectiv
		-- reward-ul (ex: leaderstats inca nu exista) -- NU marcam procesat,
		-- ca Roblox sa reincerce receipt-ul mai tarziu in loc sa piarda plata.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	markPurchaseProcessed(receiptInfo.PurchaseId)
	SFXServer.Play(player, "Purchase")

	local spendOk = pcall(addDevProductSpend, player, receiptInfo.ProductId)
	if not spendOk then
		warn("PremiumPurchaseManager: am acordat reward-ul dar nu am putut actualiza RobuxSpent pentru " .. player.Name)
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end
