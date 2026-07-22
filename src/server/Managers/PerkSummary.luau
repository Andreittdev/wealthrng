local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))
local CosmeticManager = require(script.Parent:WaitForChild("CosmeticManager"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))

-- Singurul loc care AGREGA toate sursele de perk-uri (Stand/Rebirth/Pets/
-- Cosmetice/VIP/Friend Boost/Speed Pass/Starter Pack/Titluri) intr-un singur
-- raspuns, pentru afisare in Profile.client.luau. Doar CITESTE date deja
-- calculate in alta parte (CosmeticManager/PetManager/EconomyConfig) -- nu
-- modifica nimic si NU inlocuieste formulele reale din SellManager/NPCManager
-- (ramase neatinse, ca sa nu riscam sa schimbam economia jocului doar pentru
-- un ecran de statistici).
local PerkSummary = {}

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

function PerkSummary.GetBreakdown(player)
	local standBonuses = getStandBonuses(player)
	local cosmeticBonuses = CosmeticManager.GetBonuses(player)
	local petBonuses = PetManager.GetBonuses(player)
	local rebirthBonuses = getRebirthBonuses(player)

	local isVIP = player:GetAttribute("IsVIP") == true
	local hasSpeedPass = player:GetAttribute("HasSpeedPass") == true
	local hasStarterPack = player:GetAttribute("HasStarterPack") == true
	local hasMediumPack = player:GetAttribute("HasMediumPack") == true
	local hasElitePack = player:GetAttribute("HasElitePack") == true
	local friendBoostPercent = player:GetAttribute("FriendBoostPercent") or 0

	local sell = {
		Stand = standBonuses.Sell or 0,
		Rebirth = rebirthBonuses.Sell or 0,
		Pet = petBonuses.SellPrice or 0,
		Cosmetic = cosmeticBonuses.SellPrice or 0
	}
	sell.Total = math.clamp(sell.Stand + sell.Rebirth + sell.Pet + sell.Cosmetic, 0, Economy.Caps.Sell)
	sell.Cap = Economy.Caps.Sell

	local luck = {
		Stand = standBonuses.Luck or 0,
		Rebirth = rebirthBonuses.Luck or 0,
		Pet = petBonuses.NpcLuck or 0,
		Cosmetic = cosmeticBonuses.NpcLuck or 0,
		VIP = isVIP and Economy.VIP.Luck or 0,
		StarterPack = hasStarterPack and Economy.StarterPack.LuckBonus or 0,
		MediumPack = hasMediumPack and Economy.MediumPack.LuckBonus or 0,
		ElitePack = hasElitePack and Economy.ElitePack.LuckBonus or 0,
		Title = Economy.TokenShop.GetTitleLuckBonus(player) or 0
	}
	luck.Total = math.clamp(
		luck.Stand + luck.Rebirth + luck.Pet + luck.Cosmetic + luck.VIP + luck.StarterPack + luck.MediumPack + luck.ElitePack + luck.Title,
		0,
		Economy.Caps.Luck
	)
	luck.Cap = Economy.Caps.Luck

	local speed = {
		Stand = standBonuses.Speed or 0,
		Rebirth = rebirthBonuses.Speed or 0,
		Pet = petBonuses.NpcSpeed or 0,
		Cosmetic = cosmeticBonuses.NpcSpeed or 0,
		SpeedPass = hasSpeedPass and Economy.SpeedPass.Speed or 0
	}
	speed.Total = math.clamp(speed.Stand + speed.Rebirth + speed.Pet + speed.Cosmetic + speed.SpeedPass, 0, Economy.Caps.Speed)
	speed.Cap = Economy.Caps.Speed

	-- Multiplicator de bani (nu procent aditiv) -- acelasi tipar de calcul ca
	-- SellManager.CalculateSellPrice (VIP x Friend Boost x Cosmetice, plafonat
	-- de Economy.Caps.MoneyMultiplier). Pet MoneyMultiplier NU e inclus aici,
	-- fiindca SellManager insusi nu il foloseste la vanzare -- afisajul trebuie
	-- sa reflecte exact ce primeste jucatorul, nu o formula idealizata.
	local money = {
		Cosmetic = cosmeticBonuses.MoneyMultiplier or 1,
		VIP = isVIP and Economy.VIP.MoneyMultiplier or 1,
		FriendBoostPercent = friendBoostPercent
	}

	local totalMoneyMultiplier = money.Cosmetic * money.VIP * (1 + friendBoostPercent / 100)
	money.Total = math.min(totalMoneyMultiplier, Economy.Caps.MoneyMultiplier)
	money.Cap = Economy.Caps.MoneyMultiplier

	return {
		Sell = sell,
		Luck = luck,
		Speed = speed,
		Money = money
	}
end

return PerkSummary
