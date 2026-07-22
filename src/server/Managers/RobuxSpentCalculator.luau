-- Calculeaza "Robux Spent" total pentru un jucator -- suma dintre:
-- 1) TOATE gamepass-urile detinute (recalculat din ownership REAL, vezi mai
--    jos -- prinde si achizitii vechi, dinainte sa existe tracking-ul).
-- 2) Developer Product-urile cumparate (Premium Egg, Cash Packs) -- astea NU
--    au "ownership" (sunt repetabile), deci se ACUMULEAZA incremental in
--    leaderstats.DevProductRobuxSpent de catre PremiumPurchaseManager.server.luau
--    la fiecare achizitie, si persista prin DataManager (salvat/incarcat).
--
-- Modul separat (nu un Script) ca sa poata fi apelat si de
-- RobuxSpentTracker.server.luau (gamepass-uri) SI de
-- PremiumPurchaseManager.server.luau (developer products), fara sa
-- duplicam logica sau sa se calce pe picioare unul pe altul.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RobuxSpentStore = require(script.Parent:WaitForChild("RobuxSpentStore"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EconomyConfig"))

local RobuxSpentCalculator = {}

-- Toate gamepass-urile cunoscute din joc, indiferent daca au manager propriu
-- sau nu (VIP-ul, de exemplu, nu are GamePassId in EconomyConfig -- e
-- hardcodat direct in VIPManager.server.luau).
local KNOWN_PASS_IDS = {
	Economy.SpeedPass.GamePassId,
	Economy.AutoSellPass.GamePassId,
	Economy.StarterPack.GamePassId,
	Economy.MediumPack.GamePassId,
	Economy.ElitePack.GamePassId,
	Economy.AutoBuyPass.GamePassId,
	Economy.AutoRebirthPass.GamePassId,
	1898198234, -- VIP (vezi VIPManager.server.luau)
	1899734044 -- Inventory (vezi NPCManager.server.luau)
}

-- Cache de preturi (id -> Robux), valabil pe durata serverului -- nu
-- interogam Marketplace-ul de fiecare data, doar prima data pentru fiecare
-- id.
local passPriceCache = {}

local function getPassPrice(passId)
	if passPriceCache[passId] ~= nil then
		return passPriceCache[passId]
	end

	local price = 0

	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
	end)

	if ok and info and info.PriceInRobux then
		price = info.PriceInRobux
	end

	passPriceCache[passId] = price
	return price
end

local function getGamepassTotal(player)
	local total = 0

	for _, passId in ipairs(KNOWN_PASS_IDS) do
		if passId == 0 then
			continue
		end

		local owns = false

		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)

		if ok then
			owns = result
		end

		if owns then
			total += getPassPrice(passId)
		end
	end

	return total
end

function RobuxSpentCalculator.Recompute(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end

	local robuxSpent = leaderstats:FindFirstChild("RobuxSpent")
	if not robuxSpent then
		robuxSpent = Instance.new("IntValue")
		robuxSpent.Name = "RobuxSpent"
		robuxSpent.Parent = leaderstats
	end

	local devProductSpent = leaderstats:FindFirstChild("DevProductRobuxSpent")
	local devProductTotal = devProductSpent and devProductSpent.Value or 0

	robuxSpent.Value = getGamepassTotal(player) + devProductTotal
	RobuxSpentStore.QueueUpdate(player)
end

return RobuxSpentCalculator
