local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local CashLeaderboardStore = require(script.Parent:WaitForChild("CashLeaderboardStore"))
local TimePlayedStore = require(script.Parent:WaitForChild("TimePlayedStore"))

local DataManager = {}

local playerDataStore = DataStoreService:GetDataStore("PlayerData_V2")

local function getDefaultData()
	return {
		Money = 1000,
		CashEarned = 0,
		TimePlayed = 0,
		DevProductRobuxSpent = 0,
		BankMoney = 0,
		StandLevel = 1,
		Inventory = {},
		Cosmetics = {},
		EquippedCosmetics = {
			Watch = "",
			Bag = "",
			Glasses = "",
			Sneakers = "",
			Chain = ""
		},
        Pets = {},
        EquippedPets = {"",""},
        DiscoveredPets = {},
        DiscoveredItems = {},
        EquippedTitle = "",
        BoughtTokenItems = {},
        RedeemedCodes = {},
        StarterPackRedeemed = false,
        MediumPackRedeemed = false,
        ElitePackRedeemed = false,
        RebirthCount = 0,
        RebirthTokens = 0,
        RebirthPetClaimed = false,
        DailyStreakDay = 0,
        DailyLastClaimTimestamp = 0,
        GiftedVIP = false,
        GiftedSpeedPass = false,
        GiftedAutoSellPass = false,
        GiftedInventoryPass = false,
        GiftedStarterPack = false,
        NotificationsEnabled = true,
        SellDuplicatesEnabled = true,
        MusicVolume = 0.5,
        SFXVolume = 0.5,
        LowGraphicsMode = false,
        AutoRebirthEnabled = true,
        AutoBuyFilterCommon = true,
        AutoBuyFilterRare = true,
        AutoBuyFilterEpic = true,
        AutoBuyFilterLegendary = true,
        AutoBuyFilterMythic = true,
        AutoSellPassEnabled = true,
        AutoBuyPassEnabled = true,
        AutoSellFilterClothing = true,
        AutoSellFilterShoes = true,
        AutoSellFilterElectronics = true,
        AutoSellFilterLuxury = true,
        AutoSellFilterCollectibles = true,
        PityCountLegendary = 0,
        PityCountMythic = 0,
        TutorialCompleted = false
	}
end

function DataManager.LoadData(player)
	local data
	local success = false

	-- 3 incercari cu backoff -- un singur GetAsync esuat (hiccup tranzitoriu
	-- de DataStore) altfel trata un jucator VECHI ca fiind cont nou (data
	-- ramanea nil -> getDefaultData()), iar la iesire SaveData suprascria
	-- salvarea lui reala cu datele default, pierzand-o definitiv.
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return playerDataStore:GetAsync(player.UserId)
		end)

		if ok then
			data = result
			success = true
			break
		end

		warn("Failed to load data for " .. player.Name .. " (attempt " .. attempt .. "/3): " .. tostring(result))
		if attempt < 3 then
			task.wait(2)
		end
	end

	if not success then
		-- Toate incercarile au esuat -- nu stim daca jucatorul e nou sau nu.
		-- Il lasam sa joace cu date default (mai bine decat sa-l blocam),
		-- dar marcam esecul ca atribut pe Instance-ul Player (dispare automat
		-- cand pleaca, fara sa mai tinem noi vreun tabel manual) ca sa
		-- SaveData sa STIE sa NU suprascrie salvarea lui reala la iesire.
		player:SetAttribute("DataLoadFailed", true)
		warn("DataManager: nu am putut incarca datele pentru " .. player.Name .. " dupa 3 incercari -- salvarea va fi sarita in aceasta sesiune ca sa nu-i stergem contul real")
	end

	if not data then
		data = getDefaultData()
	end

	data.Money = data.Money or 1000
	data.CashEarned = data.CashEarned or 0
	data.TimePlayed = data.TimePlayed or 0
	data.DevProductRobuxSpent = data.DevProductRobuxSpent or 0
	data.BankMoney = data.BankMoney or 0
	data.StandLevel = data.StandLevel or 1
	data.Inventory = data.Inventory or {}
	data.Cosmetics = data.Cosmetics or {}
	data.EquippedCosmetics = data.EquippedCosmetics or getDefaultData().EquippedCosmetics
    data.Pets = data.Pets or {}
	data.EquippedPets = data.EquippedPets or {"",""}
	data.DiscoveredPets = data.DiscoveredPets or {}
	data.DiscoveredItems = data.DiscoveredItems or {}
	data.EquippedTitle = data.EquippedTitle or ""
	data.BoughtTokenItems = data.BoughtTokenItems or {}
	data.RedeemedCodes = data.RedeemedCodes or {}
	data.StarterPackRedeemed = data.StarterPackRedeemed or false
	data.MediumPackRedeemed = data.MediumPackRedeemed or false
	data.ElitePackRedeemed = data.ElitePackRedeemed or false
	data.RebirthCount = data.RebirthCount or 0
	data.RebirthTokens = data.RebirthTokens or 0
	data.RebirthPetClaimed = data.RebirthPetClaimed or false
	data.DailyStreakDay = data.DailyStreakDay or 0
	data.DailyLastClaimTimestamp = data.DailyLastClaimTimestamp or 0
	data.GiftedVIP = data.GiftedVIP or false
	data.GiftedSpeedPass = data.GiftedSpeedPass or false
	data.GiftedAutoSellPass = data.GiftedAutoSellPass or false
	data.GiftedInventoryPass = data.GiftedInventoryPass or false
	data.GiftedStarterPack = data.GiftedStarterPack or false

	-- "or true" ar fi un bug aici -- daca jucatorul a dezactivat explicit
	-- (false), "false or true" da mereu true, ignorandu-i alegerea. Verificam
	-- nil separat, ca implicit sa fie true DOAR cand nu exista deloc salvat.
	if data.NotificationsEnabled == nil then
		data.NotificationsEnabled = true
	end
	if data.SellDuplicatesEnabled == nil then
		data.SellDuplicatesEnabled = true
	end
	if data.AutoRebirthEnabled == nil then
		data.AutoRebirthEnabled = true
	end
	if data.AutoBuyFilterCommon == nil then
		data.AutoBuyFilterCommon = true
	end
	if data.AutoBuyFilterRare == nil then
		data.AutoBuyFilterRare = true
	end
	if data.AutoBuyFilterEpic == nil then
		data.AutoBuyFilterEpic = true
	end
	if data.AutoBuyFilterLegendary == nil then
		data.AutoBuyFilterLegendary = true
	end
	if data.AutoBuyFilterMythic == nil then
		data.AutoBuyFilterMythic = true
	end
	if data.AutoSellPassEnabled == nil then
		data.AutoSellPassEnabled = true
	end
	if data.AutoBuyPassEnabled == nil then
		data.AutoBuyPassEnabled = true
	end
	if data.AutoSellFilterClothing == nil then
		data.AutoSellFilterClothing = true
	end
	if data.AutoSellFilterShoes == nil then
		data.AutoSellFilterShoes = true
	end
	if data.AutoSellFilterElectronics == nil then
		data.AutoSellFilterElectronics = true
	end
	if data.AutoSellFilterLuxury == nil then
		data.AutoSellFilterLuxury = true
	end
	if data.AutoSellFilterCollectibles == nil then
		data.AutoSellFilterCollectibles = true
	end
	data.PityCountLegendary = data.PityCountLegendary or 0
	data.PityCountMythic = data.PityCountMythic or 0

	-- Implicit TRUE cand lipseste -- inseamna un jucator VECHI, salvat
	-- inainte sa existe acest camp, care deja stie sa joace. Un jucator chiar
	-- nou nu ajunge niciodata aici cu nil, pentru ca getDefaultData() de mai
	-- sus ii seteaza deja explicit false.
	if data.TutorialCompleted == nil then
		data.TutorialCompleted = true
	end

	data.MusicVolume = data.MusicVolume or 0.5
	data.SFXVolume = data.SFXVolume or 0.5
	data.LowGraphicsMode = data.LowGraphicsMode or false

	return data
end

function DataManager.SaveData(player)
	if player:GetAttribute("DataLoadFailed") then
		warn("DataManager: sar salvarea pentru " .. player.Name .. " -- datele lui nu s-au incarcat cu succes in aceasta sesiune")
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local inventory = player:FindFirstChild("Inventory")
	local standLevel = player:FindFirstChild("StandLevel")
	local bankMoney = player:FindFirstChild("BankMoney")
	local cosmetics = player:FindFirstChild("Cosmetics")
    local pets = player:FindFirstChild("Pets")
    local equippedPets = player:FindFirstChild("EquippedPets")
	local discoveredPets = player:FindFirstChild("DiscoveredPets")
	local discoveredItems = player:FindFirstChild("DiscoveredItems")
	local equippedCosmetics = player:FindFirstChild("EquippedCosmetics")

	if not leaderstats or not inventory then
		return
	end

	local money = leaderstats:FindFirstChild("Money")
	if not money then
		return
	end

	local cashEarned = leaderstats:FindFirstChild("CashEarned")
	local timePlayed = leaderstats:FindFirstChild("TimePlayed")
	local devProductRobuxSpent = leaderstats:FindFirstChild("DevProductRobuxSpent")

	local dataToSave = {
		Money = money.Value,
		CashEarned = cashEarned and cashEarned.Value or 0,
		TimePlayed = timePlayed and timePlayed.Value or 0,
		DevProductRobuxSpent = devProductRobuxSpent and devProductRobuxSpent.Value or 0,
		BankMoney = bankMoney and bankMoney.Value or 0,
		StandLevel = standLevel and standLevel.Value or 1,
		Inventory = {},
		Cosmetics = {},
		EquippedCosmetics = {},
        Pets = {},
        EquippedPets = {"",""},
        DiscoveredPets = {},
        DiscoveredItems = {},
        EquippedTitle = player:GetAttribute("EquippedTitle") or "",
        BoughtTokenItems = {},
        RedeemedCodes = {},
        StarterPackRedeemed = player:GetAttribute("StarterPackRedeemed") == true,
        MediumPackRedeemed = player:GetAttribute("MediumPackRedeemed") == true,
        ElitePackRedeemed = player:GetAttribute("ElitePackRedeemed") == true,
        RebirthCount = leaderstats:FindFirstChild("Rebirths") and leaderstats.Rebirths.Value or 0,
        RebirthTokens = player:FindFirstChild("RebirthTokens") and player.RebirthTokens.Value or 0,
        RebirthPetClaimed = player:GetAttribute("RebirthPetClaimed") == true,
        DailyStreakDay = player:GetAttribute("DailyStreakDay") or 0,
        DailyLastClaimTimestamp = player:GetAttribute("DailyLastClaimTimestamp") or 0,
        GiftedVIP = player:GetAttribute("GiftedVIP") == true,
        GiftedSpeedPass = player:GetAttribute("GiftedSpeedPass") == true,
        GiftedAutoSellPass = player:GetAttribute("GiftedAutoSellPass") == true,
        GiftedInventoryPass = player:GetAttribute("GiftedInventoryPass") == true,
        GiftedStarterPack = player:GetAttribute("GiftedStarterPack") == true,
        -- ~= false (nu == true) -- implicit ramane true cand atributul inca
        -- nu exista (jucator nou/nesalvat inca), respectand totusi o
        -- dezactivare explicita.
        NotificationsEnabled = player:GetAttribute("NotificationsEnabled") ~= false,
        SellDuplicatesEnabled = player:GetAttribute("SellDuplicatesEnabled") ~= false,
        AutoRebirthEnabled = player:GetAttribute("AutoRebirthEnabled") ~= false,
        AutoBuyFilterCommon = player:GetAttribute("AutoBuyFilterCommon") ~= false,
        AutoBuyFilterRare = player:GetAttribute("AutoBuyFilterRare") ~= false,
        AutoBuyFilterEpic = player:GetAttribute("AutoBuyFilterEpic") ~= false,
        AutoBuyFilterLegendary = player:GetAttribute("AutoBuyFilterLegendary") ~= false,
        AutoBuyFilterMythic = player:GetAttribute("AutoBuyFilterMythic") ~= false,
        AutoSellPassEnabled = player:GetAttribute("AutoSellPassEnabled") ~= false,
        AutoBuyPassEnabled = player:GetAttribute("AutoBuyPassEnabled") ~= false,
        AutoSellFilterClothing = player:GetAttribute("AutoSellFilterClothing") ~= false,
        AutoSellFilterShoes = player:GetAttribute("AutoSellFilterShoes") ~= false,
        AutoSellFilterElectronics = player:GetAttribute("AutoSellFilterElectronics") ~= false,
        AutoSellFilterLuxury = player:GetAttribute("AutoSellFilterLuxury") ~= false,
        AutoSellFilterCollectibles = player:GetAttribute("AutoSellFilterCollectibles") ~= false,
        PityCountLegendary = player:GetAttribute("PityCountLegendary") or 0,
        PityCountMythic = player:GetAttribute("PityCountMythic") or 0,
        TutorialCompleted = player:GetAttribute("TutorialCompleted") == true,
        MusicVolume = player:GetAttribute("MusicVolume") or 0.5,
        SFXVolume = player:GetAttribute("SFXVolume") or 0.5,
        LowGraphicsMode = player:GetAttribute("LowGraphicsMode") == true
	}

	for _, item in ipairs(inventory:GetChildren()) do
		table.insert(dataToSave.Inventory, {
			ItemId = item:FindFirstChild("ItemId") and item.ItemId.Value or "",
			ItemName = item:FindFirstChild("ItemName") and item.ItemName.Value or item.Name,
			Rarity = item:FindFirstChild("Rarity") and item.Rarity.Value or "Common",
			Category = item:FindFirstChild("Category") and item.Category.Value or "Unknown",
			Condition = item:FindFirstChild("Condition") and item.Condition.Value or "Good",
			BuyPrice = item:FindFirstChild("BuyPrice") and item.BuyPrice.Value or 0,
			Image = item:FindFirstChild("Image") and item.Image.Value or ""
		})
	end

	if cosmetics then
		for _, cosmetic in ipairs(cosmetics:GetChildren()) do
			table.insert(dataToSave.Cosmetics, cosmetic.Value)
		end
	end

	if equippedCosmetics then
		for _, slot in ipairs(equippedCosmetics:GetChildren()) do
			dataToSave.EquippedCosmetics[slot.Name] = slot.Value
		end
	end
	if pets then
		for _, petValue in ipairs(pets:GetChildren()) do
			if petValue:IsA("StringValue") then
				-- Salvam si bonusurile (nu doar InstanceName/PetId) -- altfel,
				-- la reincarcare, petii recreati nu mai aveau NpcLuck/SellPrice/
				-- NpcSpeed pe ei, iar echiparea unui pet dupa un rejoin dadea
				-- 0 bonus in tacere (bug real, gasit cat timp reparam equip-ul).
				table.insert(dataToSave.Pets, {
					InstanceName = petValue.Name,
					PetId = petValue.Value,
					DisplayName = petValue:GetAttribute("DisplayName"),
					Rarity = petValue:GetAttribute("Rarity"),
					Image = petValue:GetAttribute("Image"),
					NpcLuck = petValue:GetAttribute("NpcLuck"),
					SellPrice = petValue:GetAttribute("SellPrice"),
					NpcSpeed = petValue:GetAttribute("NpcSpeed")
				})
			end
		end
	end

	if equippedPets then
		local slot1 = equippedPets:FindFirstChild("Slot1")
		local slot2 = equippedPets:FindFirstChild("Slot2")
		dataToSave.EquippedPets[1] = slot1 and slot1.Value or ""
		dataToSave.EquippedPets[2] = slot2 and slot2.Value or ""
	end

	-- DiscoveredPets tine minte FIECARE PetId prin care a trecut vreodata
	-- jucatorul (chiar daca a fost duplicat/vandut automat) -- folosit de
	-- Index ca sa arate peturile nedescoperite ca o umbra neagra.
	if discoveredPets then
		for _, petIdValue in ipairs(discoveredPets:GetChildren()) do
			table.insert(dataToSave.DiscoveredPets, petIdValue.Name)
		end
	end

	-- DiscoveredItems -- acelasi tipar ca DiscoveredPets, dar pentru iteme de
	-- tranzactionat (folosit de Index ca sa arate itemele nedescoperite ca o
	-- umbra neagra).
	if discoveredItems then
		for _, itemIdValue in ipairs(discoveredItems:GetChildren()) do
			table.insert(dataToSave.DiscoveredItems, itemIdValue.Name)
		end
	end

	-- Titlurile/cosmeticele cumparate din Token Shop erau marcate doar ca
	-- atribute (TokenShopBought_<Id>), niciodata salvate -- disparea la
	-- rejoin. Le salvam generic, dupa numele atributului.
	for attributeName, attributeValue in pairs(player:GetAttributes()) do
		if attributeName:sub(1, 16) == "TokenShopBought_" and attributeValue == true then
			table.insert(dataToSave.BoughtTokenItems, attributeName)
		elseif attributeName:sub(1, 13) == "CodeRedeemed_" and attributeValue == true then
			table.insert(dataToSave.RedeemedCodes, attributeName)
		end
	end

	for attempt = 1, 3 do
		local ok, err = pcall(function()
			playerDataStore:SetAsync(player.UserId, dataToSave)
		end)

		if ok then
			return
		end

		warn("Failed to save data for " .. player.Name .. " (attempt " .. attempt .. "/3): " .. tostring(err))
		if attempt < 3 then
			task.wait(2)
		end
	end
end

function DataManager.ApplyData(player, data)
	if player:GetAttribute("DataApplied") then
		return
	end

	player:SetAttribute("DataApplied", true)

	local leaderstats = player:FindFirstChild("leaderstats")
	local inventory = player:FindFirstChild("Inventory")

	if not leaderstats or not inventory then
		return
	end

	local money = leaderstats:FindFirstChild("Money")
	if money then
		money.Value = data.Money or 1000
	end

	local cashEarned = leaderstats:FindFirstChild("CashEarned")
	if not cashEarned then
		cashEarned = Instance.new("IntValue")
		cashEarned.Name = "CashEarned"
		cashEarned.Parent = leaderstats
	end
	cashEarned.Value = data.CashEarned or 0

	-- Trimitem imediat o intrare in leaderboard, chiar daca scorul e 0 --
	-- altfel un jucator nou (sau unul care nu a mai castigat bani de la
	-- ultimul join) nu apare DELOC pe tabla/podium pana nu-i creste scorul
	-- prima data, ceea ce putea insemna minute intregi de "-" / nume lipsa.
	CashLeaderboardStore.QueueUpdate(player)

	-- Urmarim orice CRESTERE a lui Money (vanzari, recompense, dobanda,
	-- gamepass-uri etc.) ca "bani castigati", indiferent de sursa -- fara sa
	-- fie nevoie sa modificam fiecare script care aduna bani in joc.
	-- Scaderile (cheltuieli) NU se scad din CashEarned -- e un total
	-- cumulativ ("lifetime"), pentru clasament, nu balanta curenta.
	--
	-- money.Value e deja setat mai sus (linia anterioara), deci baseline-ul
	-- de "lastMoney" de aici e valoarea REALA, incarcata din DataStore -- nu
	-- valoarea implicita (1000) cu care porneste un jucator nou -- altfel
	-- primul update ar adauga artificial diferenta la CashEarned la fiecare
	-- rejoin.
	if money and not player:GetAttribute("CashEarnedTrackerConnected") then
		player:SetAttribute("CashEarnedTrackerConnected", true)

		local lastMoney = money.Value

		money:GetPropertyChangedSignal("Value"):Connect(function()
			local delta = money.Value - lastMoney
			-- SuppressCashEarnedTracking -- setat temporar de BankManager in
			-- jurul unei retrageri, ca sa NU numaram ca "bani castigati" bani
			-- pe care jucatorul ii avea deja si doar ii muta inapoi din
			-- banca (altfel depune+retrage in bucla umfla CashEarned la
			-- infinit, gratis, pe clasamentul global).
			if delta > 0 and not player:GetAttribute("SuppressCashEarnedTracking") then
				cashEarned.Value += delta
				CashLeaderboardStore.QueueUpdate(player)
			end
			lastMoney = money.Value
		end)
	end

	local timePlayed = leaderstats:FindFirstChild("TimePlayed")
	if not timePlayed then
		timePlayed = Instance.new("IntValue")
		timePlayed.Name = "TimePlayed"
		timePlayed.Parent = leaderstats
	end
	timePlayed.Value = data.TimePlayed or 0

	-- Suma cumulata (Robux) din Developer Products (Premium Egg, Cash Packs)
	-- -- alimentata de PremiumPurchaseManager.server.luau la fiecare
	-- achizitie, citita de RobuxSpentCalculator ca sa o adauge la partea de
	-- gamepass-uri (RobuxSpent = gamepass-uri + astea).
	local devProductRobuxSpent = leaderstats:FindFirstChild("DevProductRobuxSpent")
	if not devProductRobuxSpent then
		devProductRobuxSpent = Instance.new("IntValue")
		devProductRobuxSpent.Name = "DevProductRobuxSpent"
		devProductRobuxSpent.Parent = leaderstats
	end
	devProductRobuxSpent.Value = data.DevProductRobuxSpent or 0

	-- Aceeasi logica -- intrare imediata in leaderboard, chiar la 0 minute.
	TimePlayedStore.QueueUpdate(player)

	-- +1 minut la fiecare 60 de secunde petrecute efectiv in joc (nu conteaza
	-- daca personajul e mort/AFK -- doar daca e conectat la server). Se
	-- opreste singur cand jucatorul pleaca (player.Parent devine nil).
	if not player:GetAttribute("TimePlayedTrackerConnected") then
		player:SetAttribute("TimePlayedTrackerConnected", true)

		task.spawn(function()
			while player.Parent do
				task.wait(60)

				if not player.Parent then
					break
				end

				timePlayed.Value += 1
				TimePlayedStore.QueueUpdate(player)
			end
		end)
	end

	player:SetAttribute("StarterPackRedeemed", data.StarterPackRedeemed == true)
	player:SetAttribute("MediumPackRedeemed", data.MediumPackRedeemed == true)
	player:SetAttribute("ElitePackRedeemed", data.ElitePackRedeemed == true)
	player:SetAttribute("EquippedTitle", data.EquippedTitle or "")

	for _, attributeName in ipairs(data.BoughtTokenItems or {}) do
		player:SetAttribute(attributeName, true)
	end

	for _, attributeName in ipairs(data.RedeemedCodes or {}) do
		player:SetAttribute(attributeName, true)
	end

	local rebirths = leaderstats:FindFirstChild("Rebirths")
	if not rebirths then
		rebirths = Instance.new("IntValue")
		rebirths.Name = "Rebirths"
		rebirths.Parent = leaderstats
	end
	rebirths.Value = data.RebirthCount or 0

	local rebirthTokens = player:FindFirstChild("RebirthTokens")
	if not rebirthTokens then
		rebirthTokens = Instance.new("IntValue")
		rebirthTokens.Name = "RebirthTokens"
		rebirthTokens.Parent = player
	end
	rebirthTokens.Value = data.RebirthTokens or 0

	player:SetAttribute("RebirthPetClaimed", data.RebirthPetClaimed == true)
	player:SetAttribute("DailyStreakDay", data.DailyStreakDay or 0)
	player:SetAttribute("DailyLastClaimTimestamp", data.DailyLastClaimTimestamp or 0)

	-- Gifted*: sursa de adevar pentru perk-urile primite cadou (vezi
	-- VIPManager/SpeedPassManager/AutoSellPassManager -- recalculeaza
	-- IsVIP/HasSpeedPass/HasAutoSellPass ca "real SAU cadou" de fiecare data
	-- cand oricare din cele doua se schimba, inclusiv aici la incarcare).
	player:SetAttribute("GiftedVIP", data.GiftedVIP == true)
	player:SetAttribute("GiftedSpeedPass", data.GiftedSpeedPass == true)
	player:SetAttribute("GiftedAutoSellPass", data.GiftedAutoSellPass == true)
	player:SetAttribute("GiftedInventoryPass", data.GiftedInventoryPass == true)
	player:SetAttribute("GiftedStarterPack", data.GiftedStarterPack == true)

	-- ~= false -- vezi comentariul din SaveData: implicit true, respectand o
	-- dezactivare explicita salvata anterior.
	player:SetAttribute("NotificationsEnabled", data.NotificationsEnabled ~= false)
	player:SetAttribute("SellDuplicatesEnabled", data.SellDuplicatesEnabled ~= false)
	player:SetAttribute("AutoRebirthEnabled", data.AutoRebirthEnabled ~= false)
	player:SetAttribute("AutoBuyFilterCommon", data.AutoBuyFilterCommon ~= false)
	player:SetAttribute("AutoBuyFilterRare", data.AutoBuyFilterRare ~= false)
	player:SetAttribute("AutoBuyFilterEpic", data.AutoBuyFilterEpic ~= false)
	player:SetAttribute("AutoBuyFilterLegendary", data.AutoBuyFilterLegendary ~= false)
	player:SetAttribute("AutoBuyFilterMythic", data.AutoBuyFilterMythic ~= false)
	player:SetAttribute("AutoSellPassEnabled", data.AutoSellPassEnabled ~= false)
	player:SetAttribute("AutoBuyPassEnabled", data.AutoBuyPassEnabled ~= false)
	player:SetAttribute("AutoSellFilterClothing", data.AutoSellFilterClothing ~= false)
	player:SetAttribute("AutoSellFilterShoes", data.AutoSellFilterShoes ~= false)
	player:SetAttribute("AutoSellFilterElectronics", data.AutoSellFilterElectronics ~= false)
	player:SetAttribute("AutoSellFilterLuxury", data.AutoSellFilterLuxury ~= false)
	player:SetAttribute("AutoSellFilterCollectibles", data.AutoSellFilterCollectibles ~= false)
	player:SetAttribute("PityCountLegendary", data.PityCountLegendary or 0)
	player:SetAttribute("PityCountMythic", data.PityCountMythic or 0)
	player:SetAttribute("TutorialCompleted", data.TutorialCompleted == true)
	player:SetAttribute("MusicVolume", data.MusicVolume or 0.5)
	player:SetAttribute("SFXVolume", data.SFXVolume or 0.5)
	player:SetAttribute("LowGraphicsMode", data.LowGraphicsMode == true)

	local bankMoney = player:FindFirstChild("BankMoney")
	if not bankMoney then
		bankMoney = Instance.new("IntValue")
		bankMoney.Name = "BankMoney"
		bankMoney.Parent = player
	end

	bankMoney.Value = data.BankMoney or 0

	local standLevel = player:FindFirstChild("StandLevel")
	if not standLevel then
		standLevel = Instance.new("IntValue")
		standLevel.Name = "StandLevel"
		standLevel.Parent = player
	end

	standLevel.Value = data.StandLevel or 1

	inventory:ClearAllChildren()

	for index, savedItem in ipairs(data.Inventory or {}) do
		local item = Instance.new("Folder")
		item.Name = tostring(index)
		item.Parent = inventory

		local itemId = Instance.new("StringValue")
		itemId.Name = "ItemId"
		itemId.Value = savedItem.ItemId or ""
		itemId.Parent = item

		local itemName = Instance.new("StringValue")
		itemName.Name = "ItemName"
		itemName.Value = savedItem.ItemName or "Unknown Item"
		itemName.Parent = item

		local rarity = Instance.new("StringValue")
		rarity.Name = "Rarity"
		rarity.Value = savedItem.Rarity or "Common"
		rarity.Parent = item

		local category = Instance.new("StringValue")
		category.Name = "Category"
		category.Value = savedItem.Category or "Unknown"
		category.Parent = item

		local condition = Instance.new("StringValue")
		condition.Name = "Condition"
		condition.Value = savedItem.Condition or "Good"
		condition.Parent = item

		local buyPrice = Instance.new("IntValue")
		buyPrice.Name = "BuyPrice"
		buyPrice.Value = savedItem.BuyPrice or 0
		buyPrice.Parent = item

		local image = Instance.new("StringValue")
		image.Name = "Image"
		image.Value = savedItem.Image or ""
		image.Parent = item
	end

	local cosmetics = player:FindFirstChild("Cosmetics")
	if not cosmetics then
		cosmetics = Instance.new("Folder")
		cosmetics.Name = "Cosmetics"
		cosmetics.Parent = player
	end

	cosmetics:ClearAllChildren()

	for _, cosmeticId in ipairs(data.Cosmetics or {}) do
		local value = Instance.new("StringValue")
		value.Name = cosmeticId
		value.Value = cosmeticId
		value.Parent = cosmetics
	end

	local equippedCosmetics = player:FindFirstChild("EquippedCosmetics")
	if not equippedCosmetics then
		equippedCosmetics = Instance.new("Folder")
		equippedCosmetics.Name = "EquippedCosmetics"
		equippedCosmetics.Parent = player
	end

	equippedCosmetics:ClearAllChildren()

	local slots = {"Watch", "Bag", "Glasses", "Sneakers", "Chain"}

	for _, slotName in ipairs(slots) do
		local value = Instance.new("StringValue")
		value.Name = slotName
		value.Value = data.EquippedCosmetics and data.EquippedCosmetics[slotName] or ""
		value.Parent = equippedCosmetics
	end
	local pets = player:FindFirstChild("Pets")
	if not pets then
		pets = Instance.new("Folder")
		pets.Name = "Pets"
		pets.Parent = player
	end

	pets:ClearAllChildren()

	-- Prima instanta gasita pentru fiecare PetId -- folosita mai jos ca sa
	-- reconstruim slot-urile echipate (salvate doar ca PetId, nu InstanceName).
	local firstInstanceForPetId = {}

	for _, savedPet in ipairs(data.Pets or {}) do
		local value = Instance.new("StringValue")
		value.Name = savedPet.InstanceName
		value.Value = savedPet.PetId

		-- Bonusurile trebuie restaurate ca atribute (nu doar Value=PetId) --
		-- altfel un pet echipat dupa un rejoin dadea 0 bonus in tacere,
		-- fiindca PetManager.GetBonuses citeste atributele, nu PetId-ul.
		value:SetAttribute("DisplayName", savedPet.DisplayName)
		value:SetAttribute("Rarity", savedPet.Rarity)
		value:SetAttribute("Image", savedPet.Image or "")
		value:SetAttribute("NpcLuck", savedPet.NpcLuck or 0)
		value:SetAttribute("SellPrice", savedPet.SellPrice or 0)
		value:SetAttribute("NpcSpeed", savedPet.NpcSpeed or 0)

		value.Parent = pets

		if not firstInstanceForPetId[savedPet.PetId] then
			firstInstanceForPetId[savedPet.PetId] = value
		end
	end

	local equippedPets = player:FindFirstChild("EquippedPets")
	if not equippedPets then
		equippedPets = Instance.new("Folder")
		equippedPets.Name = "EquippedPets"
		equippedPets.Parent = player
	end

	equippedPets:ClearAllChildren()

	local function buildEquippedSlot(slotName, savedPetId)
		local slot = Instance.new("StringValue")
		slot.Name = slotName
		slot.Value = savedPetId or ""
		slot.Parent = equippedPets

		local matchingPet = savedPetId and savedPetId ~= "" and firstInstanceForPetId[savedPetId]
		if matchingPet then
			slot:SetAttribute("InstanceName", matchingPet.Name)
			for attributeName, attributeValue in pairs(matchingPet:GetAttributes()) do
				slot:SetAttribute(attributeName, attributeValue)
			end
		end

		return slot
	end

	buildEquippedSlot("Slot1", data.EquippedPets and data.EquippedPets[1])
	buildEquippedSlot("Slot2", data.EquippedPets and data.EquippedPets[2])

	local discoveredPets = player:FindFirstChild("DiscoveredPets")
	if not discoveredPets then
		discoveredPets = Instance.new("Folder")
		discoveredPets.Name = "DiscoveredPets"
		discoveredPets.Parent = player
	end

	discoveredPets:ClearAllChildren()

	for _, petId in ipairs(data.DiscoveredPets or {}) do
		local marker = Instance.new("BoolValue")
		marker.Name = petId
		marker.Value = true
		marker.Parent = discoveredPets
	end

	local discoveredItems = player:FindFirstChild("DiscoveredItems")
	if not discoveredItems then
		discoveredItems = Instance.new("Folder")
		discoveredItems.Name = "DiscoveredItems"
		discoveredItems.Parent = player
	end

	discoveredItems:ClearAllChildren()

	for _, itemId in ipairs(data.DiscoveredItems or {}) do
		local marker = Instance.new("BoolValue")
		marker.Name = itemId
		marker.Value = true
		marker.Parent = discoveredItems
	end
end

Players.PlayerRemoving:Connect(function(player)
	DataManager.SaveData(player)
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		DataManager.SaveData(player)
	end
end)

return DataManager