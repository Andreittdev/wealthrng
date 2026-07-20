local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PetDatabase = require(modulesFolder:WaitForChild("PetDatabase"))
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

local PetManager = {}

local MAX_EQUIPPED = Economy.EquippedPetSlots or 2

-- Cash foarte mic primit pentru duplicate.
-- Îl ajustăm după testarea economiei.
local DUPLICATE_SELL_VALUES = {
	Common = 100,
	Rare = 500,
	Epic = 2500,
	Legendary = 15000,
	Mythic = 75000,
	Secret = 0
}

local VALID_EGGS = {
	Basic = true,
	Rare = true,
	Epic = true,
	Legendary = true,
	Mythic = true
}

-- Pity: dupa atatea oua deschise LA RAND fara Secret (per tip de ou, per
-- jucator), urmatorul e garantat Secret, indiferent de rezultatul rulat
-- normal -- plafoneaza cazul de ghinion extrem, fara sa schimbe sansa reala
-- (0.1%/0.5%) pentru cine are noroc mai devreme. Doar Legendary si Mythic au
-- Secret -- celelalte oua nu au nevoie de pity.
-- Praguri = exact media reala (1/sansa) -- Legendary (0.1% -> 1000),
-- Mythic (0.5% -> 200). La 2x media (~13.5% dintre jucatori afectati) tot
-- insemna sute de ore in cel mai rau caz, prea mult ca sa rezolve cu adevarat
-- plangerea initiala -- la 1x media, pity-ul prinde ~50% dintre jucatori
-- (jumatate au noroc mai devreme), dar plafonul chiar simte a "rezolvat".
local PITY_THRESHOLDS = {
	Legendary = 1000,
	Mythic = 200
}

local function getPityAttributeName(eggType)
	return "PityCount" .. eggType
end

local function sanitizeId(text)
	text = tostring(text or "Pet")
	text = text:gsub("[^%w_]", "")
	return text
end

local function getMoneyValue(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end

	return leaderstats:FindFirstChild("Money")
end

local function getEggData(eggType)
	if type(eggType) ~= "string" then
		return nil
	end

	if not VALID_EGGS[eggType] then
		return nil
	end

	return PetDatabase.Eggs and PetDatabase.Eggs[eggType]
end

function PetManager.CreateInventory(player)
	if not player then
		return
	end

	local pets = player:FindFirstChild("Pets")
	if not pets then
		pets = Instance.new("Folder")
		pets.Name = "Pets"
		pets.Parent = player
	end

	local equipped = player:FindFirstChild("EquippedPets")
	if not equipped then
		equipped = Instance.new("Folder")
		equipped.Name = "EquippedPets"
		equipped.Parent = player
	end

	local discovered = player:FindFirstChild("DiscoveredPets")
	if not discovered then
		discovered = Instance.new("Folder")
		discovered.Name = "DiscoveredPets"
		discovered.Parent = player
	end
end

-- Marcheaza un PetId ca "descoperit vreodata" -- ramane asa chiar daca
-- exemplarul respectiv e ulterior vandut/duplicat, folosit de Index ca sa
-- stie ce peturi sa arate normal vs. ca o umbra neagra (nedescoperit).
local function markDiscovered(player, petId)
	if not petId then
		return
	end

	local discovered = player:FindFirstChild("DiscoveredPets")
	if not discovered then
		return
	end

	if discovered:FindFirstChild(petId) then
		return
	end

	local marker = Instance.new("BoolValue")
	marker.Name = petId
	marker.Value = true
	marker.Parent = discovered
end

local function normalizePetData(rawPet)
	local petName = rawPet.Name or rawPet.DisplayName or "Unknown Pet"
	local rarity = rawPet.Rarity or "Common"
	local luck = tonumber(rawPet.Luck) or 0
	local sell = tonumber(rawPet.Sell) or 0
	local speed = tonumber(rawPet.Speed) or 0

	return {
		PetId = sanitizeId(petName),
		DisplayName = petName,
		Rarity = rarity,
		Chance = tonumber(rawPet.Chance) or 0,
		Image = rawPet.Image or "",

		Bonuses = rawPet.Bonuses or {
			NpcLuck = luck,
			SellPrice = sell,
			NpcSpeed = speed
		},

		Ability = rawPet.Ability
	}
end

local function findSecretPet(eggData)
	for _, rawPet in ipairs(eggData.Pets) do
		if rawPet.Rarity == "Secret" then
			return normalizePetData(rawPet)
		end
	end

	return nil
end

local function rollPetFromEgg(eggData, player, eggType)
	if not eggData or type(eggData.Pets) ~= "table" then
		return nil
	end

	local pityThreshold = eggType and PITY_THRESHOLDS[eggType]
	local pityAttribute = eggType and getPityAttributeName(eggType)

	-- Daca acesta ar fi ATINS pragul de pity (inca nu s-a intamplat un
	-- Secret in ultimele pityThreshold-1 oua), fortam Secret-ul direct,
	-- inainte sa mai rulam sansa normala.
	if pityThreshold and player then
		local attemptsSinceSecret = player:GetAttribute(pityAttribute) or 0

		if attemptsSinceSecret + 1 >= pityThreshold then
			local secretPet = findSecretPet(eggData)

			if secretPet then
				player:SetAttribute(pityAttribute, 0)
				return secretPet
			end
		end
	end

	local totalChance = 0

	for _, rawPet in ipairs(eggData.Pets) do
		local chance = tonumber(rawPet.Chance) or 0

		if chance > 0 then
			totalChance += chance
		end
	end

	if totalChance <= 0 then
		warn("Egg has no valid pet chances")
		return nil
	end

	local roll = math.random() * totalChance
	local currentChance = 0
	local rolledPet = nil

	for _, rawPet in ipairs(eggData.Pets) do
		local chance = tonumber(rawPet.Chance) or 0
		currentChance += chance

		if roll <= currentChance then
			rolledPet = normalizePetData(rawPet)
			break
		end
	end

	if not rolledPet then
		rolledPet = normalizePetData(eggData.Pets[#eggData.Pets])
	end

	if pityThreshold and player then
		if rolledPet.Rarity == "Secret" then
			player:SetAttribute(pityAttribute, 0)
		else
			player:SetAttribute(pityAttribute, (player:GetAttribute(pityAttribute) or 0) + 1)
		end
	end

	return rolledPet
end

local function playerAlreadyOwnsPet(player, petId)
	local pets = player:FindFirstChild("Pets")
	if not pets then
		return false
	end

	for _, petInstance in ipairs(pets:GetChildren()) do
		if petInstance:IsA("StringValue") and petInstance.Value == petId then
			return true
		end
	end

	return false
end

local function giveDuplicateCash(player, rarity)
	local amount = DUPLICATE_SELL_VALUES[rarity] or 0

	if amount <= 0 then
		return 0
	end

	local money = getMoneyValue(player)
	if not money then
		return 0
	end

	money.Value += amount
	return amount
end

local function savePet(player, petData)
	local pets = player:FindFirstChild("Pets")
	if not pets then
		return nil
	end

	local instanceName =
		petData.PetId
		.. "_"
		.. HttpService:GenerateGUID(false)

	local petValue = Instance.new("StringValue")
	petValue.Name = instanceName
	petValue.Value = petData.PetId

	petValue:SetAttribute("DisplayName", petData.DisplayName)
	petValue:SetAttribute("Rarity", petData.Rarity)
	petValue:SetAttribute(
		"NpcLuck",
		petData.Bonuses and petData.Bonuses.NpcLuck or 0
	)
	petValue:SetAttribute(
		"SellPrice",
		petData.Bonuses and petData.Bonuses.SellPrice or 0
	)
	petValue:SetAttribute(
		"NpcSpeed",
		petData.Bonuses and petData.Bonuses.NpcSpeed or 0
	)
	petValue:SetAttribute("Image", petData.Image or "")

	petValue.Parent = pets

	markDiscovered(player, petData.PetId)

	return petValue
end

local function processRolledPet(player, petData)
	local isSecret = petData.Rarity == "Secret"
	local isDuplicate = playerAlreadyOwnsPet(player, petData.PetId)

	-- Primul exemplar se păstrează.
	-- Secret se păstrează mereu.
	if not isDuplicate or isSecret then
		local savedPet = savePet(player, petData)

		if not savedPet then
			return nil
		end

		return {
			InstanceName = savedPet.Name,
			PetId = petData.PetId,
			DisplayName = petData.DisplayName,
			Rarity = petData.Rarity,
			Image = petData.Image,
			Bonuses = petData.Bonuses,
			Ability = petData.Ability,

			IsDuplicate = false,
			AutoSold = false,
			AutoSellCash = 0
		}
	end

	-- Duplicatele normale se transformă în puțin cash.
	local cashReceived = giveDuplicateCash(player, petData.Rarity)

	return {
		InstanceName = nil,
		PetId = petData.PetId,
		DisplayName = petData.DisplayName,
		Rarity = petData.Rarity,
		Image = petData.Image,
		Bonuses = petData.Bonuses,
		Ability = petData.Ability,

		IsDuplicate = true,
		AutoSold = true,
		AutoSellCash = cashReceived
	}
end

function PetManager.CanAffordEgg(player, eggType, hatchCount)
	local eggData = getEggData(eggType)
	if not eggData then
		return false, 0
	end

	hatchCount = math.clamp(tonumber(hatchCount) or 1, 1, 3)

	local totalPrice = (tonumber(eggData.Price) or 0) * hatchCount
	local money = getMoneyValue(player)

	if not money then
		return false, totalPrice
	end

	return money.Value >= totalPrice, totalPrice
end

function PetManager.OpenEgg(player, eggType, hatchCount)
	if not player then
		return nil, "InvalidPlayer"
	end

	PetManager.CreateInventory(player)

	local eggData = getEggData(eggType)
	if not eggData then
		warn("Invalid egg type:", eggType)
		return nil, "InvalidEgg"
	end

	hatchCount = math.clamp(tonumber(hatchCount) or 1, 1, 3)

	local canAfford, totalPrice =
		PetManager.CanAffordEgg(player, eggType, hatchCount)

	if not canAfford then
		return nil, "NotEnoughMoney"
	end

	local money = getMoneyValue(player)
	if not money then
		return nil, "MoneyMissing"
	end

	-- Plata se face o singură dată pentru toate hatch-urile.
	money.Value -= totalPrice

	local results = {}

	for _ = 1, hatchCount do
		local rolledPet = rollPetFromEgg(eggData, player, eggType)

		if rolledPet then
			local result = processRolledPet(player, rolledPet)

			if result then
				table.insert(results, result)
			end
		end
	end

	if #results == 0 then
		-- În caz de problemă neașteptată, restituim plata.
		money.Value += totalPrice
		return nil, "RollFailed"
	end

	print(
		player.Name,
		"opened",
		hatchCount,
		eggType,
		"egg(s) for $" .. totalPrice
	)

	return results, nil
end

-- Acorda un pet aleatoriu de o raritate anume, in afara sistemului de oua platite
-- (ex. recompensa unica dintr-un gamepass). Refoloseste logica de duplicate din OpenEgg.
function PetManager.GrantRandomPetByRarity(player, rarity)
	if not player then
		return nil
	end

	PetManager.CreateInventory(player)

	local pool = {}

	for _, eggData in pairs(PetDatabase.Eggs) do
		if type(eggData.Pets) == "table" then
			for _, rawPet in ipairs(eggData.Pets) do
				if rawPet.Rarity == rarity then
					table.insert(pool, rawPet)
				end
			end
		end
	end

	if #pool == 0 then
		warn("GrantRandomPetByRarity: no pets found for rarity", rarity)
		return nil
	end

	local rolledPet = normalizePetData(pool[math.random(1, #pool)])

	return processRolledPet(player, rolledPet)
end

-- Acorda direct un pet predefinit (nu il ruleaza din nicio oua) -- pentru
-- recompense unice, ca pet-ul exclusiv de Rebirth. Il salveaza mereu; e
-- responsabilitatea apelantului sa nu cheme asta de doua ori pentru acelasi
-- jucator (ex. un flag "deja primit").
function PetManager.GrantSpecificPet(player, petData)
	if not player or not petData then
		return nil
	end

	PetManager.CreateInventory(player)

	local savedPet = savePet(player, petData)

	if not savedPet then
		return nil
	end

	return {
		InstanceName = savedPet.Name,
		PetId = petData.PetId,
		DisplayName = petData.DisplayName,
		Rarity = petData.Rarity,
		Image = petData.Image,
		Bonuses = petData.Bonuses,

		IsDuplicate = false,
		AutoSold = false,
		AutoSellCash = 0
	}
end

-- Compatibilitate temporară cu NPCManager-ul vechi.
-- OpenCrate întoarce un singur pet, ca înainte.
function PetManager.OpenCrate(player, crateType)
	local eggType = crateType or "Basic"

	-- Dacă vechiul sistem trimite "BasicCrate", îl convertim.
	eggType = tostring(eggType)
	eggType = eggType:gsub("Egg", "")
	eggType = eggType:gsub("Crate", "")

	if not VALID_EGGS[eggType] then
		eggType = "Basic"
	end

	local results, errorCode = PetManager.OpenEgg(player, eggType, 1)

	if not results then
		warn(
			"PetManager.OpenCrate failed:",
			player and player.Name,
			eggType,
			errorCode
		)

		return nil
	end

	return results[1]
end

-- EquippedPets foloseste 2 slot-uri FIXE ("Slot1"/"Slot2"), nu un StringValue
-- numit dupa petInstanceName -- asta pentru ca DataManager.SaveData/ApplyData
-- (persistenta) citesc/scriu specific "Slot1"/"Slot2", nu orice nume de copil.
-- Slot-ul retine si "InstanceName" ca atribut, ca sa stim exact CARE pet din
-- folderul Pets e echipat (nu doar ce PetId, in caz ca ai doua copii identice).
local EQUIP_SLOT_NAMES = {"Slot1", "Slot2"}

local function findEquippedSlotFor(equipped, petInstanceName)
	for _, slotName in ipairs(EQUIP_SLOT_NAMES) do
		local slot = equipped:FindFirstChild(slotName)
		if slot and slot:GetAttribute("InstanceName") == petInstanceName then
			return slot
		end
	end
	return nil
end

local function findEmptySlot(equipped)
	for _, slotName in ipairs(EQUIP_SLOT_NAMES) do
		local slot = equipped:FindFirstChild(slotName)
		if not slot or slot.Value == "" then
			return slotName
		end
	end
	return nil
end

function PetManager.IsEquipped(player, petInstanceName)
	local equipped = player:FindFirstChild("EquippedPets")
	if not equipped then
		return false
	end

	return findEquippedSlotFor(equipped, petInstanceName) ~= nil
end

function PetManager.Equip(player, petInstanceName)
	PetManager.CreateInventory(player)

	local pets = player:FindFirstChild("Pets")
	local equipped = player:FindFirstChild("EquippedPets")

	if not pets or not equipped then
		return false, "InventoryMissing"
	end

	local pet = pets:FindFirstChild(petInstanceName)

	if not pet or not pet:IsA("StringValue") then
		return false, "PetMissing"
	end

	if findEquippedSlotFor(equipped, petInstanceName) then
		return false, "AlreadyEquipped"
	end

	local targetSlotName = findEmptySlot(equipped)
	if not targetSlotName then
		return false, "MaxEquipped"
	end

	local slot = equipped:FindFirstChild(targetSlotName)
	if not slot then
		slot = Instance.new("StringValue")
		slot.Name = targetSlotName
		slot.Parent = equipped
	end

	slot.Value = pet.Value
	slot:SetAttribute("InstanceName", petInstanceName)

	for attributeName, attributeValue in pairs(pet:GetAttributes()) do
		slot:SetAttribute(attributeName, attributeValue)
	end

	return true
end

function PetManager.Unequip(player, petInstanceName)
	local equipped = player:FindFirstChild("EquippedPets")
	if not equipped then
		return false
	end

	local slot = findEquippedSlotFor(equipped, petInstanceName)
	if not slot then
		return false
	end

	slot.Value = ""
	for attributeName, _ in pairs(slot:GetAttributes()) do
		slot:SetAttribute(attributeName, nil)
	end

	return true
end

function PetManager.GetBonuses(player)
	PetManager.CreateInventory(player)

	local equipped = player:FindFirstChild("EquippedPets")

	local bonuses = {
		NpcLuck = 0,
		SellPrice = 0,
		MoneyMultiplier = 1,
		InventorySlots = 0,
		NpcSpeed = 0,
		XP = 0,
		RareChance = 0
	}

	if equipped then
		for _, equippedPet in ipairs(equipped:GetChildren()) do
			if not equippedPet:IsA("StringValue") then
				continue
			end

			local npcLuck =
				tonumber(equippedPet:GetAttribute("NpcLuck")) or 0

			bonuses.NpcLuck += npcLuck

			-- Compatibilitate pentru viitoare bonusuri salvate ca atribute.
			for bonusName, _ in pairs(bonuses) do
				if bonusName ~= "NpcLuck"
					and bonusName ~= "MoneyMultiplier"
				then
					local amount =
						tonumber(equippedPet:GetAttribute(bonusName))

					if amount then
						bonuses[bonusName] += amount
					end
				end
			end

			local petMultiplier =
				tonumber(equippedPet:GetAttribute("MoneyMultiplier"))

			if petMultiplier and petMultiplier > 1 then
				bonuses.MoneyMultiplier *= petMultiplier
			end
		end
	end
	return bonuses
end

function PetManager.GetEggPrice(eggType)
	local eggData = getEggData(eggType)
	return eggData and eggData.Price or nil
end

function PetManager.GetMaxEquipped()
	return MAX_EQUIPPED
end

return PetManager