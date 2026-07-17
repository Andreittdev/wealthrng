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
        EquippedTitle = "",
        BoughtTokenItems = {},
        StarterPackRedeemed = false,
        RebirthCount = 0,
        RebirthTokens = 0,
        RebirthPetClaimed = false,
        DailyStreakDay = 0,
        DailyLastClaimTimestamp = 0
	}
end

function DataManager.LoadData(player)
	local data

	local success, err = pcall(function()
		data = playerDataStore:GetAsync(player.UserId)
	end)

	if not success then
		warn("Failed to load data for " .. player.Name .. ": " .. err)
	end

	if not data then
		data = getDefaultData()
	end

	data.Money = data.Money or 1000
	data.CashEarned = data.CashEarned or 0
	data.TimePlayed = data.TimePlayed or 0
	data.BankMoney = data.BankMoney or 0
	data.StandLevel = data.StandLevel or 1
	data.Inventory = data.Inventory or {}
	data.Cosmetics = data.Cosmetics or {}
	data.EquippedCosmetics = data.EquippedCosmetics or getDefaultData().EquippedCosmetics
    data.Pets = data.Pets or {}
	data.EquippedPets = data.EquippedPets or {"",""}
	data.DiscoveredPets = data.DiscoveredPets or {}
	data.EquippedTitle = data.EquippedTitle or ""
	data.BoughtTokenItems = data.BoughtTokenItems or {}
	data.StarterPackRedeemed = data.StarterPackRedeemed or false
	data.RebirthCount = data.RebirthCount or 0
	data.RebirthTokens = data.RebirthTokens or 0
	data.RebirthPetClaimed = data.RebirthPetClaimed or false
	data.DailyStreakDay = data.DailyStreakDay or 0
	data.DailyLastClaimTimestamp = data.DailyLastClaimTimestamp or 0

	return data
end

function DataManager.SaveData(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local inventory = player:FindFirstChild("Inventory")
	local standLevel = player:FindFirstChild("StandLevel")
	local bankMoney = player:FindFirstChild("BankMoney")
	local cosmetics = player:FindFirstChild("Cosmetics")
    local pets = player:FindFirstChild("Pets")
    local equippedPets = player:FindFirstChild("EquippedPets")
	local discoveredPets = player:FindFirstChild("DiscoveredPets")
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

	local dataToSave = {
		Money = money.Value,
		CashEarned = cashEarned and cashEarned.Value or 0,
		TimePlayed = timePlayed and timePlayed.Value or 0,
		BankMoney = bankMoney and bankMoney.Value or 0,
		StandLevel = standLevel and standLevel.Value or 1,
		Inventory = {},
		Cosmetics = {},
		EquippedCosmetics = {},
        Pets = {},
        EquippedPets = {"",""},
        DiscoveredPets = {},
        EquippedTitle = player:GetAttribute("EquippedTitle") or "",
        BoughtTokenItems = {},
        StarterPackRedeemed = player:GetAttribute("StarterPackRedeemed") == true,
        RebirthCount = leaderstats:FindFirstChild("Rebirths") and leaderstats.Rebirths.Value or 0,
        RebirthTokens = player:FindFirstChild("RebirthTokens") and player.RebirthTokens.Value or 0,
        RebirthPetClaimed = player:GetAttribute("RebirthPetClaimed") == true,
        DailyStreakDay = player:GetAttribute("DailyStreakDay") or 0,
        DailyLastClaimTimestamp = player:GetAttribute("DailyLastClaimTimestamp") or 0
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

	-- Titlurile/cosmeticele cumparate din Token Shop erau marcate doar ca
	-- atribute (TokenShopBought_<Id>), niciodata salvate -- disparea la
	-- rejoin. Le salvam generic, dupa numele atributului.
	for attributeName, attributeValue in pairs(player:GetAttributes()) do
		if attributeName:sub(1, 16) == "TokenShopBought_" and attributeValue == true then
			table.insert(dataToSave.BoughtTokenItems, attributeName)
		end
	end

	local success, err = pcall(function()
		playerDataStore:SetAsync(player.UserId, dataToSave)
	end)

	if not success then
		warn("Failed to save data for " .. player.Name .. ": " .. err)
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
		money.Value = data.Money or 500
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
			if delta > 0 then
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
	player:SetAttribute("EquippedTitle", data.EquippedTitle or "")

	for _, attributeName in ipairs(data.BoughtTokenItems or {}) do
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