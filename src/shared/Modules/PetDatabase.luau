local Pets = {}

local Economy = require(script.Parent:WaitForChild("EconomyConfig"))

Pets.Eggs = {

	Basic = {
		Price = 5000,
		Pets = {
			{Name = "Parcel Pup", Rarity = "Common", Chance = 40, Luck = 1, Sell = 1, Speed = 0, Image = "rbxassetid://94988329197481"},
			{Name = "Cap Cat", Rarity = "Common", Chance = 30, Luck = 1, Sell = 1, Speed = 0, Image = "rbxassetid://79844970928890"},
			{Name = "Sneaker Bunny", Rarity = "Common", Chance = 20, Luck = 2, Sell = 1, Speed = 0, Image = "rbxassetid://76685922333555"},
			{Name = "Camera Chick", Rarity = "Common", Chance = 10, Luck = 2, Sell = 2, Speed = 0, Image = "rbxassetid://123769964478266"}
		}
	},

	Rare = {
		Price = 25000,
		Pets = {
			{Name = "Watch Wolf", Rarity = "Rare", Chance = 40, Luck = 3, Sell = 2, Speed = 1, Image = "rbxassetid://135493901598622"},
			{Name = "Cash Croc", Rarity = "Rare", Chance = 30, Luck = 3, Sell = 3, Speed = 1, Image = "rbxassetid://127209331273106"},
			{Name = "Street Dragon", Rarity = "Rare", Chance = 20, Luck = 4, Sell = 3, Speed = 1, Image = "rbxassetid://102625323595055"},
			{Name = "Delivery Bear", Rarity = "Rare", Chance = 10, Luck = 5, Sell = 4, Speed = 2, Image = "rbxassetid://87843309933117"}
		}
	},

	Epic = {
		Price = 100000,
		Pets = {
			{Name = "Diamond Shark", Rarity = "Epic", Chance = 35, Luck = 5, Sell = 4, Speed = 2, Image = "rbxassetid://128725474199510"},
			{Name = "Vault Gorilla", Rarity = "Epic", Chance = 30, Luck = 6, Sell = 5, Speed = 2, Image = "rbxassetid://132671627749695"},
			{Name = "Luxury Panther", Rarity = "Epic", Chance = 20, Luck = 7, Sell = 6, Speed = 3, Image = "rbxassetid://113844810144129"},
			{Name = "Bull Phoenix", Rarity = "Epic", Chance = 15, Luck = 8, Sell = 7, Speed = 3, Image = "rbxassetid://75503287884334"}
		}
	},

	Legendary = {
		Price = 500000,
		Pets = {
			{Name = "King Of Kicks", Rarity = "Legendary", Chance = 39.9, Luck = 8, Sell = 7, Speed = 4, Image = "rbxassetid://131342079845243"},
			{Name = "Hype Dragon", Rarity = "Legendary", Chance = 30, Luck = 9, Sell = 8, Speed = 4, Image = "rbxassetid://113560516680662"},
			{Name = "Diamond Emperor", Rarity = "Legendary", Chance = 20, Luck = 10, Sell = 9, Speed = 5, Image = "rbxassetid://112937280899690"},
			{Name = "B Beast", Rarity = "Legendary", Chance = 10, Luck = 12, Sell = 10, Speed = 6, Image = "rbxassetid://77761425616150"},
			{Name = "THE COLLECTOR", Rarity = "Secret", Chance = 0.1, Luck = 25, Sell = 20, Speed = 10, Image = "rbxassetid://139001462245720"}
		}
	},

	Mythic = {
		Price = 2000000,
		Pets = {
			{Name = "Market", Rarity = "Mythic", Chance = 39.5, Luck = 13, Sell = 11, Speed = 6, Image = "rbxassetid://111004557886325"},
			{Name = "Golden Mogul", Rarity = "Mythic", Chance = 30, Luck = 14, Sell = 12, Speed = 7},
			{Name = "Fortune Dragon", Rarity = "Mythic", Chance = 20, Luck = 16, Sell = 14, Speed = 8, Image = "rbxassetid://94055455280858"},
			{Name = "CEO X", Rarity = "Mythic", Chance = 10, Luck = 18, Sell = 16, Speed = 9, Image = "rbxassetid://84827384554941"},
			{Name = "Millionaire", Rarity = "Secret", Chance = 0.5, Luck = 30, Sell = 25, Speed = 12, Image = "rbxassetid://119628540326297"}
		}
	}

}

local function sanitizeId(text)
	text = tostring(text or "Pet")
	text = text:gsub("[^%w_]", "")
	return text
end

Pets.Pets = {}

for _, eggData in pairs(Pets.Eggs) do
	for _, rawPet in ipairs(eggData.Pets) do
		local petId = sanitizeId(rawPet.Name)

		Pets.Pets[petId] = {
			DisplayName = rawPet.Name,
			Rarity = rawPet.Rarity,
			Image = rawPet.Image or "",
			Source = "Egg",

			Bonuses = {
				NpcLuck = rawPet.Luck or 0,
				SellPrice = rawPet.Sell or 0,
				NpcSpeed = rawPet.Speed or 0
			}
		}
	end
end

-- Pet-urile exclusive (Rebirth, Token Shop, Daily Rewards) nu apar in niciun
-- ou, deci nu erau inregistrate nicaieri central -- lipseau complet din
-- Pets.Pets (bug gasit separat, cat timp reparam Equip-ul: nu se afisau in
-- panoul de Pets al jucatorului daca le detinea). Le adaugam aici, ca sa
-- existe un singur loc cu TOATE pet-urile din joc.
local function registerExclusivePet(petData, source)
	if not petData or not petData.PetId then
		return
	end

	Pets.Pets[petData.PetId] = {
		DisplayName = petData.DisplayName,
		Rarity = petData.Rarity,
		Image = petData.Image or "",
		Source = source,

		Bonuses = {
			NpcLuck = petData.Bonuses and petData.Bonuses.NpcLuck or 0,
			SellPrice = petData.Bonuses and petData.Bonuses.SellPrice or 0,
			NpcSpeed = petData.Bonuses and petData.Bonuses.NpcSpeed or 0
		}
	}
end

registerExclusivePet(Economy.Rebirth.ExclusivePet, "Rebirth Exclusive")

for _, item in ipairs(Economy.TokenShop.Items) do
	if item.Type == "Pet" then
		registerExclusivePet(item.Pet, "Token Shop Exclusive")
	end
end

for _, day in pairs(Economy.DailyRewards.Days) do
	if day.Type == "SpecificPet" then
		registerExclusivePet(day.Pet, "Daily Reward Exclusive")
	end
end

return Pets