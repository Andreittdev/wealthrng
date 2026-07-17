-- Calculeaza "Robux Spent" pentru fiecare jucator -- suma preturilor REALE
-- (din Marketplace, nu valorile hardcodate din EconomyConfig, care pot fi
-- gresite -- vezi comentariul din EconomyConfig.luau despre StarterPack) ale
-- TUTUROR gamepass-urilor pe care le detine.
--
-- Nu tine o suma incrementala separata -- recalculeaza de fiecare data din
-- ownership-ul REAL (UserOwnsGamePassAsync), care e mereu adevarul absolut
-- si permanent (odata cumparat, ramane cumparat) -- asta prinde si
-- jucatorii care aveau deja pass-uri cumparate INAINTE sa existe sistemul
-- asta de tracking, nu doar cumpararile noi.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RobuxSpentStore = require(script.Parent:WaitForChild("RobuxSpentStore"))

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EconomyConfig"))

-- Toate gamepass-urile cunoscute din joc, indiferent daca au manager propriu
-- sau nu (VIP-ul, de exemplu, nu are GamePassId in EconomyConfig -- e
-- hardcodat direct in VIPManager.server.luau).
local KNOWN_PASS_IDS = {
	Economy.SpeedPass.GamePassId,
	Economy.AutoSellPass.GamePassId,
	Economy.StarterPack.GamePassId,
	1898198234, -- VIP (vezi VIPManager.server.luau)
	1899734044 -- Inventory (vezi NPCManager.server.luau)
}

-- Cache de preturi (passId -> Robux), valabil pe durata serverului -- nu
-- interogam Marketplace-ul de fiecare data, doar prima data pentru fiecare
-- pass.
local priceCache = {}

local function getPassPrice(passId)
	if priceCache[passId] ~= nil then
		return priceCache[passId]
	end

	local price = 0

	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
	end)

	if ok and info and info.PriceInRobux then
		price = info.PriceInRobux
	end

	priceCache[passId] = price
	return price
end

local function recomputeRobuxSpent(player)
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

	local total = 0

	for _, passId in ipairs(KNOWN_PASS_IDS) do
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

	robuxSpent.Value = total
	RobuxSpentStore.QueueUpdate(player)
end

local function setupPlayer(player)
	local leaderstats = player:WaitForChild("leaderstats", 30)
	if not leaderstats then
		return
	end

	recomputeRobuxSpent(player)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

-- Recalculam imediat dupa orice achizitie noua de gamepass (din orice
-- manager) -- nu asteptam pana la urmatorul join.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then
		return
	end

	local isKnown = false
	for _, passId in ipairs(KNOWN_PASS_IDS) do
		if passId == gamePassId then
			isKnown = true
			break
		end
	end

	if isKnown then
		recomputeRobuxSpent(player)
	end
end)
