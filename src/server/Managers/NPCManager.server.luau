local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local NPCDatabase = require(modulesFolder:WaitForChild("NPCDatabase"))
local TradeManager = require(script.Parent:WaitForChild("TradeManager"))
local InventoryManager = require(script.Parent:WaitForChild("InventoryManager"))
local SellManager = require(script.Parent:WaitForChild("SellManager"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local MarketManager = require(modulesFolder:WaitForChild("MarketManager"))
local StandDisplayManager = require(script.Parent:WaitForChild("StandDisplayManager"))
local CosmeticManager = require(script.Parent:WaitForChild("CosmeticManager"))
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))

local showTradeEvent = remotesFolder:WaitForChild("ShowTrade")
local buyItemEvent = remotesFolder:WaitForChild("BuyItem")
local skipTradeEvent = remotesFolder:WaitForChild("SkipTrade")
local sellFirstItemEvent = remotesFolder:WaitForChild("SellFirstItem")
local sellSelectedItemEvent = remotesFolder:WaitForChild("SellSelectedItem")
local requestInventoryEvent = remotesFolder:WaitForChild("RequestInventory")
local showInventoryEvent = remotesFolder:WaitForChild("ShowInventory")
local showNotificationEvent = remotesFolder:WaitForChild("ShowNotification")
local marketUpdateEvent = remotesFolder:WaitForChild("MarketUpdate")
local openPetCrateEvent = remotesFolder:WaitForChild("OpenPetCrate")
local petOpenedEvent = remotesFolder:WaitForChild("PetOpened")

local INVENTORY_PASS_ID = 1899734044
local DEFAULT_MAX_INVENTORY = 50
local PASS_MAX_INVENTORY = 150

local npcFolder = ServerStorage:WaitForChild("NPCs")
local npcTemplate = npcFolder:WaitForChild("TestNPC")

local activeTrades = {}

-- NPC-urile pornesc din portalul cel mai APROAPE de standul jucatorului (Nord
-- sau Sud), nu mereu din acelasi -- altfel jucatorii cu stand langa Sud ar
-- astepta mult mai mult decat cei langa Nord, nedrept intre cei 6 jucatori.
-- Cautate o singura data la pornire; daca un portal nu exista (harta veche,
-- fara TownMap), cadem pe o pozitie aproximativa, ca sa nu crape.
local function findPortalPosition(name, fallback)
	local townMap = workspace:FindFirstChild("TownMap")
	local portalPanel = townMap and townMap:FindFirstChild(name)

	if portalPanel then
		return portalPanel.Position
	end

	warn("NPCManager: Workspace.TownMap." .. name .. " nu a fost gasit -- folosesc o pozitie aproximativa.")
	return fallback
end

local portalNorthPosition = findPortalPosition("PortalNorth", Vector3.new(0, 5, 600))
local portalSouthPosition = findPortalPosition("PortalSouth", Vector3.new(0, 5, 200))

local function getClosestPortalPosition(targetPosition)
	local distanceToNorth = (targetPosition - portalNorthPosition).Magnitude
	local distanceToSouth = (targetPosition - portalSouthPosition).Magnitude

	if distanceToSouth < distanceToNorth then
		return portalSouthPosition
	end

	return portalNorthPosition
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

local function getStandBonuses(player)
	local level = getStandLevel(player)
	return Economy.StandBonuses[level] or Economy.StandBonuses[1]
end

local function getRebirthBonuses(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local rebirths = leaderstats and leaderstats:FindFirstChild("Rebirths")

	if not rebirths then
		return {Sell = 0, Luck = 0, Speed = 0}
	end

	return Economy.Rebirth.GetCumulativeBonuses(rebirths.Value)
end

local function getSpawnDelay(player)
	local bonuses = getStandBonuses(player)
	local cosmeticBonuses = CosmeticManager.GetBonuses(player)
	local petBonuses = PetManager.GetBonuses(player)
	local rebirthBonuses = getRebirthBonuses(player)

	local speedPassBonus = player:GetAttribute("HasSpeedPass") and Economy.SpeedPass.Speed or 0

	local totalSpeed = bonuses.Speed + (cosmeticBonuses.NpcSpeed or 0) + (petBonuses.NpcSpeed or 0) + rebirthBonuses.Speed + speedPassBonus
	totalSpeed = math.clamp(totalSpeed, 0, Economy.Caps.Speed)

	local reduction = 1 - (totalSpeed / 100)

	local minDelay = Economy.NPCSpawnInterval.Min * reduction
	local maxDelay = Economy.NPCSpawnInterval.Max * reduction

	return minDelay + math.random() * (maxDelay - minDelay)
end

local function sendInventory(player)
	local inventory = player:FindFirstChild("Inventory")
	local items = {}

	if inventory then
		for _, item in ipairs(inventory:GetChildren()) do
			table.insert(items, {
				Id = item.Name,
				ItemName = item:FindFirstChild("ItemName") and item.ItemName.Value or item.Name,
				Rarity = item:FindFirstChild("Rarity") and item.Rarity.Value or "Common",
				Category = item:FindFirstChild("Category") and item.Category.Value or "Unknown",
				BuyPrice = item:FindFirstChild("BuyPrice") and item.BuyPrice.Value or 0,
				Image = item:FindFirstChild("Image") and item.Image.Value or ""
			})
		end
	end

	showInventoryEvent:FireClient(player, items)
end

local function getMaxInventory(player)
	local maxInventory = DEFAULT_MAX_INVENTORY

	local success, ownsPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, INVENTORY_PASS_ID)
	end)

	if success and ownsPass then
		maxInventory = PASS_MAX_INVENTORY
	end

	-- VIP promite +25 sloturi (Economy.VIP.ExtraInventorySlots) -- se aduna
	-- aditiv peste orice ai deja (default sau Inventory Pass), nu il inlocuieste.
	if player:GetAttribute("IsVIP") then
		maxInventory += Economy.VIP.ExtraInventorySlots
	end

	return maxInventory
end

local function getRandomNPCType()
	local totalWeight = 0
	local pool = {}

	for npcType, npcData in pairs(NPCDatabase.Types) do
		local weight = npcData.SpawnChance or 0

		if weight > 0 then
			totalWeight += weight

			table.insert(pool, {
				Type = npcType,
				Weight = weight
			})
		end
	end

	if totalWeight <= 0 then
		warn("No NPC spawn weights found")
		return nil
	end

	local roll = math.random() * totalWeight
	local current = 0

	for _, npc in ipairs(pool) do
		current += npc.Weight

		if roll <= current then
			return npc.Type
		end
	end

	return pool[1].Type
end

local function getPlayerStand(player)
	local standsFolder = workspace:WaitForChild("GeneratedStands")

	for _, stand in ipairs(standsFolder:GetChildren()) do
		if stand:GetAttribute("OwnerUserId") == player.UserId then
			return stand
		end
	end

	return nil
end

-- NPCSpot sta chiar PE platforma standului -- NPC-ul ajungea sa mearga pe
-- stand, nu in fata lui. Mutam tinta spre strada (spre X=0) cu un offset
-- fix, ca sa se opreasca inainte de platforma, cu fata la jucator.
local FRONT_OF_STAND_OFFSET = 14

local function getNPCSpotPosition(stand)
	local base = stand:FindFirstChild("Base")
	if not base then
		return nil
	end

	local npcSpot = base:FindFirstChild("NPCSpot")
	if not npcSpot then
		return nil
	end

	local spotPosition = npcSpot.Position
	local towardStreetSign = spotPosition.X < 0 and 1 or -1

	return Vector3.new(
		spotPosition.X + towardStreetSign * FRONT_OF_STAND_OFFSET,
		spotPosition.Y,
		spotPosition.Z
	)
end

-- X-ul mijlocului strazii, citit direct din piesa "Street" a TownMapBuilder
-- (nu hardcodat) -- daca strada se muta vreodata, ramane corect.
local function getStreetCenterX()
	local townMap = workspace:FindFirstChild("TownMap")
	local street = townMap and townMap:FindFirstChild("Street")

	if street then
		return street.Position.X
	end

	return 0
end

local streetCenterX = getStreetCenterX()

-- PathfindingService genera multe waypoint-uri apropiate, iar NPC-ul se
-- oprea/reorienta la fiecare -- de-aia mersul parea sacadat ("merge si se
-- opreste"). Inlocuit cu un traseu simplu, in 2 pasi, GARANTAT pe strada:
-- 1) merge pe mijlocul strazii (X strazii) pana ajunge la Z-ul standului,
-- 2) abia apoi vireaza spre stand. Doar o singura cotitura, mers neted.
local function moveNPCTo(npc, destination)
	local humanoid = npc:WaitForChild("Humanoid")

	local streetWaypoint = Vector3.new(streetCenterX, destination.Y, destination.Z)

	humanoid:MoveTo(streetWaypoint)
	humanoid.MoveToFinished:Wait()

	humanoid:MoveTo(destination)
	humanoid.MoveToFinished:Wait()
end

local function removeNPC(player)
	local trade = activeTrades[player]

	if trade and trade.NPC then
		trade.NPC:Destroy()
	end

	activeTrades[player] = nil
end

local function spawnNPCForPlayer(player, pendingDelay)
	if activeTrades[player] then
		return
	end

	local stand = getPlayerStand(player)
	if not stand then
		return
	end

	local npcSpotPosition = getNPCSpotPosition(stand)
	if not npcSpotPosition then
		return
	end

	local npcType = getRandomNPCType()
	if not npcType then
		return
	end

	local npcData = NPCDatabase.Types[npcType]
	if not npcData then
		return
	end

	-- Rezervam slotul IMEDIAT, inainte de orice yield -- altfel guard-ul de
	-- mai sus (activeTrades[player]) nu se seteaza decat mult mai tarziu (dupa
	-- task.wait + MoveToFinished, ~10-16s), lasand o fereastra in care doua
	-- apeluri concurente (ex: watchStandForClaim + spawn-ul de la join) trec
	-- amandoua de guard si creeaza doi NPC pentru acelasi jucator, unul orfan.
	activeTrades[player] = {Pending = true}

	local npc = npcTemplate:Clone()
	npc.Name = npcData.DisplayName
	npc.Parent = workspace

	local humanoid = npc:WaitForChild("Humanoid")
	local rootPart = npc:WaitForChild("HumanoidRootPart")

	local bonuses = getStandBonuses(player)
	local cosmeticBonuses = CosmeticManager.GetBonuses(player)
	local petBonuses = PetManager.GetBonuses(player)
	local rebirthBonuses = getRebirthBonuses(player)

	-- Viteza reala a NPC-ului -- toate sursele de Speed (stand, cosmetice,
	-- peturi, rebirth), nu doar stand-ul, la fel ca la getSpawnDelay mai sus
	-- (inainte doar stand-ul conta aici, desi upgrade-urile/peturile de Speed
	-- promiteau ca NPC-urile vin mai repede).
	local speedPassBonus = player:GetAttribute("HasSpeedPass") and Economy.SpeedPass.Speed or 0

	local totalSpeedBonus = bonuses.Speed
		+ (cosmeticBonuses.NpcSpeed or 0)
		+ (petBonuses.NpcSpeed or 0)
		+ rebirthBonuses.Speed
		+ speedPassBonus
	totalSpeedBonus = math.clamp(totalSpeedBonus, 0, Economy.Caps.Speed)

	local speedMultiplier = 1 + (totalSpeedBonus / 100)

	-- Porneste din portal, nu langa stand -- jucatorul trebuie sa vada NPC-ul
	-- venind de-acolo, oricat de departe ar fi standul lui.
	local closestPortalPosition = getClosestPortalPosition(npcSpotPosition)
	rootPart.CFrame = CFrame.new(closestPortalPosition + Vector3.new(0, 3, 0))

	-- IMPORTANT pentru corectitudine intre cei 6 jucatori: WalkSpeed NU e fix
	-- -- se calculeaza din distanta reala pana la stand, ca fiecare jucator sa
	-- astepte acelasi timp de BAZA (BASE_TRAVEL_TIME), indiferent cat de
	-- aproape/departe e standul lui de un portal. Bonusul de Speed% reduce
	-- acel timp (upgrade-urile inca conteaza), dar POZITIA pe harta nu mai da
	-- avantaj/dezavantaj gratuit.
	local BASE_TRAVEL_TIME = 6

	local legOne = math.abs(npcSpotPosition.Z - closestPortalPosition.Z)
	local legTwo = math.abs(npcSpotPosition.X - streetCenterX)
	local totalTravelDistance = math.max(legOne + legTwo, 1)

	local travelTime = BASE_TRAVEL_TIME / speedMultiplier
	humanoid.WalkSpeed = totalTravelDistance / travelTime

	-- Mersul dureaza acum travelTime secunde -- nu mai asteptam SEPARAT
	-- intregul getSpawnDelay() inainte de asta, altfel timpul total per ciclu
	-- (asteptare + mers) ar depasi ce era calibrat inainte (doar spawnDelay,
	-- fara mers vizibil). Scadem mersul din asteptare, ca timpul total sa
	-- ramana acelasi ca inainte -- doar impartit acum in "asteptare" +
	-- "mers vizibil", nu doar asteptare goala.
	local remainingWait = math.max(0, (pendingDelay or 0) - travelTime)
	if remainingWait > 0 then
		task.wait(remainingWait)
	end

	moveNPCTo(npc, npcSpotPosition)

	if not player.Parent then
		-- Jucatorul a plecat cat timp NPC-ul se deplasa -- curatam si iesim,
		-- ca sa nu ramana un NPC orfan in Workspace pentru totdeauna.
		npc:Destroy()
		activeTrades[player] = nil
		return
	end

	local vipLuck = player:GetAttribute("IsVIP") and Economy.VIP.Luck or 0
	local starterPackLuck = player:GetAttribute("HasStarterPack") and Economy.StarterPack.LuckBonus or 0
	local rebirthLuck = getRebirthBonuses(player).Luck
	local titleLuck = Economy.TokenShop.GetTitleLuckBonus(player)

	local totalLuck = bonuses.Luck + cosmeticBonuses.NpcLuck + petBonuses.NpcLuck + vipLuck + starterPackLuck + rebirthLuck + titleLuck
	totalLuck = math.clamp(totalLuck, 0, Economy.Caps.Luck)

	local offer = TradeManager.CreateOffer(npcType, totalLuck)

	if offer then
		activeTrades[player] = {
			NPC = npc,
			Offer = offer,
		}

		showTradeEvent:FireClient(player, offer)
	else
		-- CreateOffer nu a putut genera nicio oferta (ex: categorie goala) --
		-- eliberam slotul si reincercam mai tarziu, in loc sa lasam ciclul de
		-- trade al jucatorului blocat definitiv (fara NPC, fara reincercare).
		npc:Destroy()
		activeTrades[player] = nil

		task.delay(5, function()
			if player.Parent then
				spawnNPCForPlayer(player, getSpawnDelay(player))
			end
		end)
	end
end
local function handleOpenPetCrate(player)
	local pet = PetManager.OpenCrate(player)

	if not pet then
		warn("Pet crate failed for " .. player.Name)
		return
	end

	petOpenedEvent:FireClient(player, pet)

	showNotificationEvent:FireClient(
		player,
		"🐾 You received " .. pet.DisplayName .. " (" .. pet.Rarity .. ")"
	)
end

local buyInProgress = {}

-- getMaxInventory face un yield (UserOwnsGamePassAsync) inainte sa taxeze --
-- fara guard-ul asta, doua BuyItem trase foarte rapid pot ambele trece de
-- verificarile de mai jos in acel interval si taxa jucatorul de doua ori
-- pentru un singur item.
local function doHandleBuy(player, clientOffer)
	local trade = activeTrades[player]
	if not trade then return end

	local offer = trade.Offer
	if not offer then return end

	if not clientOffer or clientOffer.ItemId ~= offer.ItemId then
		warn("Invalid offer from " .. player.Name)
		return
	end

	local inventory = player:FindFirstChild("Inventory")
	if not inventory then return end

	local maxInventory = getMaxInventory(player)

	if #inventory:GetChildren() >= maxInventory then
		-- Auto-Sell Pass: nu blocheaza cumpararea, vinde automat cel mai
		-- vechi item ca sa faca loc -- e o plasa de siguranta ("nu mai
		-- raman blocat"), NU un auto-sell instant la fiecare cumparare (asta
		-- ar fi facut Inventory Pass-ul complet inutil pentru cine are si
		-- Auto-Sell -- inventarul n-ar mai avea nevoie de sloturi deloc).
		local autoSold = false

		if player:GetAttribute("HasAutoSellPass") then
			local oldestItem = nil
			local oldestTime = math.huge

			for _, child in ipairs(inventory:GetChildren()) do
				local purchaseTime = child:FindFirstChild("PurchaseTime")
				local timeValue = purchaseTime and purchaseTime.Value or 0

				if timeValue < oldestTime then
					oldestTime = timeValue
					oldestItem = child
				end
			end

			if oldestItem then
				local oldestName = oldestItem:FindFirstChild("ItemName")
				local oldestNameText = oldestName and oldestName.Value or "item"

				if SellManager.SellItem(player, oldestItem) then
					autoSold = true
					showNotificationEvent:FireClient(player, "🔄 Auto-Sold " .. oldestNameText .. " to make room")
				end
			end
		end

		if not autoSold then
			showNotificationEvent:FireClient(player, "🎒 Inventory Full! Press + to upgrade.")
			return
		end
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local money = leaderstats:FindFirstChild("Money")
	if not money then return end

	local buyPrice = tonumber(offer.BuyPrice) or 0

	if money.Value < buyPrice then
		showNotificationEvent:FireClient(player, "❌ Not enough money")
		return
	end

	money.Value -= buyPrice

	InventoryManager.AddItem(player, offer)
	StandDisplayManager.UpdateStand(player)
	sendInventory(player)

	showNotificationEvent:FireClient(player, "✅ Bought " .. tostring(offer.ItemName) .. " for $" .. tostring(buyPrice))

	removeNPC(player)

	spawnNPCForPlayer(player, getSpawnDelay(player))
end

local function handleBuy(player, clientOffer)
	if buyInProgress[player] then
		return
	end

	buyInProgress[player] = true

	local ok, err = pcall(doHandleBuy, player, clientOffer)
	if not ok then
		warn("NPCManager: handleBuy error for " .. player.Name .. ": " .. tostring(err))
	end

	buyInProgress[player] = nil
end

local function handleSkip(player)
	removeNPC(player)

	-- Skip ramane putin mai lent decat buy, ca penalizare naturala.
	spawnNPCForPlayer(player, getSpawnDelay(player) + 2)
end

local function handleSellFirstItem(player)
	local inventory = player:FindFirstChild("Inventory")
	if not inventory then return end

	local firstItem = inventory:FindFirstChild("1")

	if not firstItem then
		showNotificationEvent:FireClient(player, "🎒 Inventory is empty")
		return
	end

	local success = SellManager.SellItem(player, firstItem)

	if success then
		showNotificationEvent:FireClient(player, "💰 Sold item successfully")
		sendInventory(player)
		StandDisplayManager.UpdateStand(player)
	end
end

local function handleSellSelectedItem(player, itemId)
	local inventory = player:FindFirstChild("Inventory")
	if not inventory then return end

	local item = inventory:FindFirstChild(tostring(itemId))

	if not item then
		showNotificationEvent:FireClient(player, "❌ Item not found")
		return
	end

	local success = SellManager.SellItem(player, item)

	if success then
		showNotificationEvent:FireClient(player, "💰 Sold selected item")
		sendInventory(player)
		StandDisplayManager.UpdateStand(player)
	end
end

local function onPlayerAdded(player)
	local data = DataManager.LoadData(player)

	task.wait(1)
	DataManager.ApplyData(player, data)

	marketUpdateEvent:FireClient(player, MarketManager.GetClientData())

	task.wait(7)
	spawnNPCForPlayer(player)
end

local function onPlayerRemoving(player)
	removeNPC(player)
	buyInProgress[player] = nil
	DataManager.SaveData(player)
end

-- Standurile nu se mai asigneaza automat (StandManager: jucatorul trebuie sa
-- dea Claim manual) -- deci spawnNPCForPlayer de la join (dupa 7s) de multe
-- ori nu gaseste niciun stand inca si nu face nimic, iar apoi NIMIC nu-l mai
-- declanseaza vreodata pentru jucatorul ala. Ascultam direct atributul
-- "Occupied" de pe fiecare stand -- cand devine true (Claim reusit), pornim
-- primul NPC pe loc, din portal.
local function watchStandForClaim(stand)
	stand:GetAttributeChangedSignal("Occupied"):Connect(function()
		if not stand:GetAttribute("Occupied") then
			return
		end

		local ownerUserId = stand:GetAttribute("OwnerUserId")
		local player = Players:GetPlayerByUserId(ownerUserId)

		if player and not activeTrades[player] then
			spawnNPCForPlayer(player)
		end
	end)
end

do
	local standsFolder = workspace:WaitForChild("GeneratedStands")

	for _, stand in ipairs(standsFolder:GetChildren()) do
		watchStandForClaim(stand)
	end

	standsFolder.ChildAdded:Connect(watchStandForClaim)
end

buyItemEvent.OnServerEvent:Connect(handleBuy)
skipTradeEvent.OnServerEvent:Connect(handleSkip)
sellFirstItemEvent.OnServerEvent:Connect(handleSellFirstItem)
sellSelectedItemEvent.OnServerEvent:Connect(handleSellSelectedItem)
requestInventoryEvent.OnServerEvent:Connect(sendInventory)
openPetCrateEvent.OnServerEvent:Connect(handleOpenPetCrate)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end