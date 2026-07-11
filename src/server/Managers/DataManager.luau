local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local DataManager = {}

local playerDataStore = DataStoreService:GetDataStore("PlayerData_V2")

local function getDefaultData()
	return {
		Money = 1000,
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
        StarterPackRedeemed = false
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
	data.BankMoney = data.BankMoney or 0
	data.StandLevel = data.StandLevel or 1
	data.Inventory = data.Inventory or {}
	data.Cosmetics = data.Cosmetics or {}
	data.EquippedCosmetics = data.EquippedCosmetics or getDefaultData().EquippedCosmetics
    data.Pets = data.Pets or {}
	data.EquippedPets = data.EquippedPets or {"",""}
	data.StarterPackRedeemed = data.StarterPackRedeemed or false

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
	local equippedCosmetics = player:FindFirstChild("EquippedCosmetics")

	if not leaderstats or not inventory then
		return
	end

	local money = leaderstats:FindFirstChild("Money")
	if not money then
		return
	end

	local dataToSave = {
		Money = money.Value,
		BankMoney = bankMoney and bankMoney.Value or 0,
		StandLevel = standLevel and standLevel.Value or 1,
		Inventory = {},
		Cosmetics = {},
		EquippedCosmetics = {},
        Pets = {},
        EquippedPets = {"",""},
        StarterPackRedeemed = player:GetAttribute("StarterPackRedeemed") == true
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
				table.insert(dataToSave.Pets, {
					InstanceName = petValue.Name,
					PetId = petValue.Value
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

	player:SetAttribute("StarterPackRedeemed", data.StarterPackRedeemed == true)

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

	for _, savedPet in ipairs(data.Pets or {}) do
		local value = Instance.new("StringValue")
		value.Name = savedPet.InstanceName
		value.Value = savedPet.PetId
		value.Parent = pets
	end

	local equippedPets = player:FindFirstChild("EquippedPets")
	if not equippedPets then
		equippedPets = Instance.new("Folder")
		equippedPets.Name = "EquippedPets"
		equippedPets.Parent = player
	end

	equippedPets:ClearAllChildren()

	local slot1 = Instance.new("StringValue")
	slot1.Name = "Slot1"
	slot1.Value = data.EquippedPets and data.EquippedPets[1] or ""
	slot1.Parent = equippedPets

	local slot2 = Instance.new("StringValue")
	slot2.Name = "Slot2"
	slot2.Value = data.EquippedPets and data.EquippedPets[2] or ""
	slot2.Parent = equippedPets
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