local Economy = {}

-- ============================
-- NPC OFFERS (Buy Low Sell High)
-- ============================
Economy.NPCPriceRanges = {
	Common = {Min = 50, Max = 150},
	Rare = {Min = 200, Max = 500},
	Epic = {Min = 600, Max = 1500},
	Legendary = {Min = 2000, Max = 5000}
}

Economy.NPCRarityChances = {
	Common = 60,
	Rare = 28,
	Epic = 10,
	Legendary = 2
}

Economy.ResellMarginRange = {Min = 0.15, Max = 0.30} -- 15% - 30%

Economy.NPCSpawnInterval = {Min = 10, Max = 15} -- secunde

-- ============================
-- STAND UPGRADE
-- ============================
Economy.StandUpgradeCosts = {
	[1] = 0,
	[2] = 2500,
	[3] = 10000,
	[4] = 35000,
	[5] = 100000
}

Economy.StandBonuses = {
	[1] = {Luck = 0, Sell = 0, Speed = 0},
	[2] = {Luck = 5, Sell = 3, Speed = 0},
	[3] = {Luck = 10, Sell = 8, Speed = 3},
	[4] = {Luck = 18, Sell = 15, Speed = 7},
	[5] = {Luck = 28, Sell = 25, Speed = 12}
}

-- ============================
-- VIP
-- ============================
Economy.VIP = {
	Price = 299, -- Robux
	Luck = 15,
	MoneyMultiplier = 1.5,
	ExtraInventorySlots = 25
}

-- ============================
-- STARTER PACK (gamepass)
-- ============================
Economy.StarterPack = {
	GamePassId = 1908301457,
	RobuxPrice = 2, -- doar text afisat in UI; pretul real e cel setat in Creator Dashboard
	Money = 2000,
	PetRarity = "Common",
	LuckBonus = 2 -- +2%, permanent, cat timp detii gamepass-ul
}

-- ============================
-- PETS (echipare)
-- ============================
Economy.EquippedPetSlots = 2

-- ============================
-- REBIRTH
-- ============================
Economy.Rebirth = {
	RequiredStandLevel = 5,

	-- Pragul de bani cerut pentru al N-lea rebirth -- calibrat cu media
	-- geometrica intre ce ar avea nevoie un jucator FARA VIP si unul CU VIP,
	-- ca ambele profiluri sa ajunga cat mai aproape de 40/50/60/70/80 minute
	-- la rebirth-urile 1-5 (perks-urile mixte Sell/Luck/Speed facand jucatorii
	-- sa castige mai repede decat un model bazat doar pe Sell).
	RequiredMoneyByRebirth = {
		[1] = 220000,
		[2] = 360000,
		[3] = 530000,
		[4] = 710000,
		[5] = 910000
	},

	-- Pentru rebirth 6+ (neclibrat inca), crestem pragul cu un pas fix.
	RequiredMoneyStepAfter5 = 180000,

	-- Perks-urile PROPRII fiecarui rebirth (nu identice) -- amestec de
	-- Sell/Luck/Speed, nu doar Sell, ca sa nu se plafoneze la jucatorii VIP
	-- (Sell singur satureaza pretul maxim per item la VIP + stand mare).
	-- Bonusurile sunt permanente si se ADUNA cu cele din rebirth-urile anterioare.
	PerksByRebirth = {
		[1] = {Sell = 5, Luck = 3, Speed = 0},
		[2] = {Sell = 5, Luck = 3, Speed = 3},
		[3] = {Sell = 7, Luck = 5, Speed = 3},
		[4] = {Sell = 7, Luck = 5, Speed = 5},
		[5] = {Sell = 10, Luck = 7, Speed = 5}
	},

	-- Pentru rebirth 6+ (neclibrat inca), repetam ultima treapta cunoscuta.
	PerksAfter5 = {Sell = 10, Luck = 7, Speed = 5},

	TokensForExclusivePet = 5,

	-- Pet exclusiv, obtinut DOAR prin Rebirth (nu apare in niciun ou) --
	-- calibrat undeva intre un Legendary obisnuit si un Mythic/Secret de varf,
	-- ca sa fie un reward vizibil, dar nu OP.
	ExclusivePet = {
		PetId = "RebirthPhoenix",
		DisplayName = "Rebirth Phoenix",
		Rarity = "Legendary",
		Image = "rbxassetid://90287359233643",
		Bonuses = {
			NpcLuck = 10,
			SellPrice = 8,
			NpcSpeed = 5
		}
	}
}

-- rebirthNumber = al catelea rebirth urmeaza sa faca jucatorul (1 pentru primul).
function Economy.Rebirth.GetRequiredMoney(rebirthNumber)
	local byRebirth = Economy.Rebirth.RequiredMoneyByRebirth
	local knownMax = 5

	if byRebirth[rebirthNumber] then
		return byRebirth[rebirthNumber]
	end

	local extraSteps = rebirthNumber - knownMax
	return byRebirth[knownMax] + extraSteps * Economy.Rebirth.RequiredMoneyStepAfter5
end

-- Perks-urile pe care le primesti facand chiar acel rebirth (nu cumulate).
function Economy.Rebirth.GetPerks(rebirthNumber)
	return Economy.Rebirth.PerksByRebirth[rebirthNumber] or Economy.Rebirth.PerksAfter5
end

-- Suma tuturor perk-urilor de la rebirth 1 pana la rebirthCount (inclusiv) --
-- bonusul total, permanent, activ acum, pe care il are jucatorul.
function Economy.Rebirth.GetCumulativeBonuses(rebirthCount)
	local total = {Sell = 0, Luck = 0, Speed = 0}

	for i = 1, rebirthCount do
		local perks = Economy.Rebirth.GetPerks(i)
		total.Sell += perks.Sell or 0
		total.Luck += perks.Luck or 0
		total.Speed += perks.Speed or 0
	end

	return total
end

-- ============================
-- TOKEN SHOP (cumperi cu Rebirth Tokens)
-- ============================
-- Fiecare intrare: {
--   Id = "string unic",
--   Name = "Nume afisat",
--   Cost = numar (in Rebirth Tokens),
--   Icon = "emoji sau rbxassetid://...",
--   OneTime = true/false (daca poate fi cumparat o singura data per jucator),
--   Type = "Money" | "Pet" | "Cosmetic" | ... (folosit de TokenShopManager
--          ca sa stie ce sa acorde -- se adauga pe masura ce stabilim rewards)
-- }
-- Curba de preturi gandita sa nu strice economia: itemele ieftine sunt
-- accesibile repede, cele scumpe cer multe rebirth-uri (12 tokens = 12
-- rebirth-uri, ore de joc) -- nu se pot "cumpara" repede.
-- Momentan doar Money si Pet -- cosmeticele nu au inca UI/vizual in joc,
-- deci nu le punem in shop pana nu exista un mod sa le vezi/porti.
Economy.TokenShop = {
	Items = {
		{
			Id = "TraderTitle",
			Name = "Trader",
			Icon = "🏷️",
			Cost = 1,
			OneTime = true, -- e un titlu permanent, nu are sens sa-l cumperi de 2 ori
			Type = "Title",
			Category = "Titles",
			Description = "+3% Luck, forever",
			ChatColor = Color3.fromRGB(170, 170, 170), -- gri
			-- Luck, nu multiplier de bani -- multiplier-ul se plafoneaza rapid
			-- la jucatorii avansati (VIP + rebirth-uri) din cauza MaxSell per item,
			-- Luck-ul nu se plafoneaza in acelasi fel (iti creste sansa la iteme
			-- de raritate mai mare, nu doar pretul aceluiasi item).
			LuckBonus = 3
		},
		{
			Id = "MillionaireTitle",
			Name = "Millionaire",
			Icon = "💼",
			Cost = 3,
			OneTime = true,
			Type = "Title",
			Category = "Titles",
			Description = "+7% Luck, forever",
			ChatColor = Color3.fromRGB(120, 230, 120), -- verde deschis
			LuckBonus = 7
		},
		{
			Id = "RebirthPhoenixPet",
			Name = "Rebirth Phoenix",
			Icon = "🔥",
			Cost = 5,
			OneTime = true,
			Type = "Pet",
			Category = "Pets",
			Description = "EXCLUSIVE Pet!",
			-- Acelasi pet ca cel gratuit din Rebirth (Economy.Rebirth.ExclusivePet)
			-- -- jucatorul ii poate cere pe langa cel gratuit, cumparandu-l aici.
			Pet = {
				PetId = "RebirthPhoenix",
				DisplayName = "Rebirth Phoenix",
				Rarity = "Legendary",
				Image = "rbxassetid://90287359233643",
				Bonuses = {
					NpcLuck = 10,
					SellPrice = 8,
					NpcSpeed = 5
				}
			}
		},
		{
			Id = "RebirthGuardianPet",
			Name = "Rebirth Guardian",
			Icon = "🐺",
			Cost = 8,
			OneTime = true,
			Type = "Pet",
			Category = "Pets",
			Description = "EXCLUSIVE Pet!",
			-- Al doilea pet exclusiv de Rebirth (diferit de cel gratuit la 5 tokens),
			-- mai puternic decat Rebirth Sprite pentru ca directa costa mai mult.
			Pet = {
				PetId = "RebirthGuardian",
				DisplayName = "Rebirth Guardian",
				Rarity = "Legendary",
				Image = "rbxassetid://73604540890894",
				Bonuses = {
					NpcLuck = 12,
					SellPrice = 10,
					NpcSpeed = 6
				}
			}
		},
		{
			Id = "BillionaireTitle",
			Name = "Billionaire",
			Icon = "👑",
			Cost = 12,
			OneTime = true,
			Type = "Title",
			Category = "Titles",
			Description = "+20% Luck, forever",
			ChatColor = Color3.fromRGB(20, 110, 40), -- verde inchis
			LuckBonus = 20
		}
	}
}

-- Suma bonusurilor de Luck de la toate titlurile pe care le detine jucatorul
-- (fiecare titlu cumparat e permanent -- se aduna, nu se inlocuiesc).
function Economy.TokenShop.GetTitleLuckBonus(player)
	local total = 0

	for _, item in ipairs(Economy.TokenShop.Items) do
		if item.Type == "Title" and player:GetAttribute("TokenShopBought_" .. item.Id) then
			total += item.LuckBonus or 0
		end
	end

	return total
end

-- ============================
-- DAILY REWARDS (ciclu de 7 zile, se repeta)
-- ============================
-- Zilele cu bani cresc treptat (500 -> 3000) -- suficient de mult ca sa se
-- simta ca un reward "wow" (jumatate din banii de start la Ziua 1, pana la
-- 3x la Ziua 6), dar tot mic fata de pragurile de Rebirth (200k+), deci
-- raman doar un bonus de a te loga zilnic, nu un mod de a scurtcircuita
-- progresia principala. Ziua 2 da un pet Common random
-- (acelasi mecanism ca la Starter Pack), ziua 4 da 1 Rebirth Token (acelasi
-- ordin de marime ca cel mai ieftin item din Token Shop), iar ziua 7 da un
-- pet Epic exclusiv (nu apare in niciun ou) -- calibrat la nivelul celui mai
-- bun pet Epic normal (Bull Phoenix: Luck 8/Sell 7/Speed 3), nu mai puternic
-- -- "exclusiv" inseamna ca nu-l poti obtine altfel, nu ca e mai tare.
Economy.DailyRewards = {
	CycleLength = 7,

	-- Cat trebuie sa treaca de la ultima revendicare ca sa poti revendica
	-- din nou (nu neaparat la miezul noptii -- evita probleme de fus orar).
	CooldownHours = 20,

	-- Daca a trecut mai mult decat atat de la ultima revendicare, seria se
	-- reseteaza la ziua 1 (ai ratat o zi intreaga).
	ResetWindowHours = 48,

	Days = {
		[1] = {Type = "Money", Amount = 500, Icon = "💰", Description = "+$500"},
		[2] = {Type = "RandomPet", Rarity = "Common", Icon = "🐾", Description = "Random Pet"},
		[3] = {Type = "Money", Amount = 1000, Icon = "💰", Description = "+$1,000"},
		[4] = {Type = "RebirthTokens", Amount = 1, Icon = "🔥", Description = "+1 Rebirth Token"},
		[5] = {Type = "Money", Amount = 2000, Icon = "💰", Description = "+$2,000"},
		[6] = {Type = "Money", Amount = 3000, Icon = "💰", Description = "+$3,000"},
		[7] = {
			Type = "SpecificPet",
			Icon = "👑",
			Description = "Exclusive Pet",
			Pet = {
				PetId = "StreakChampion",
				DisplayName = "Streak Champion",
				Rarity = "Epic",
				Image = "rbxassetid://109426827753803",
				Bonuses = {NpcLuck = 8, SellPrice = 7, NpcSpeed = 3}
			}
		}
	}
}

-- ============================
-- CAPS GENERALE (anti-abuz balans)
-- ============================
Economy.Caps = {
	Luck = 100,
	Sell = 300, -- ridicat fata de 80, ca sa lase loc de progresie prin Rebirth
	Speed = 50,

	-- Multiplicatorul final de bani (VIP x Friend Boost x Cosmetice), aplicat
	-- DUPA clamp-ul de MaxSell -- singurul bonus fara plafon pana acum. Cu
	-- VIP(1.5) x Friend Boost(1.3) x 5 cosmetice Legendary (~2.27), un jucator
	-- complet maxat ajungea la ~4.4x fara nicio limita. Plafonat la 4x.
	MoneyMultiplier = 4
}

-- ============================
-- MARKET
-- ============================
Economy.Market = {
	UpdateInterval = 600,       -- 10 minute
	NormalVariance = 15,        -- ±15% per update normal
	MaxPriceDeviation = 50,     -- cap ±50% față de bază

	GoldenHour = {
		Duration = 300,          -- 5 minute
		Boost = 40
	},

	MarketCrash = {
		Duration = 300,          -- 5 minute
		Drop = 40
	},

	AntiAbuseHoldTime = 900     -- 15 minute
}

return Economy