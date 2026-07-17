-- Recalculeaza "Robux Spent" (partea de gamepass-uri) la join si la orice
-- achizitie noua -- logica reala de calcul e in RobuxSpentCalculator.luau
-- (comuna cu PremiumPurchaseManager.server.luau, care se ocupa de partea de
-- Developer Products).

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RobuxSpentCalculator = require(script.Parent:WaitForChild("RobuxSpentCalculator"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EconomyConfig"))

local KNOWN_PASS_IDS = {
	Economy.SpeedPass.GamePassId,
	Economy.AutoSellPass.GamePassId,
	Economy.StarterPack.GamePassId,
	1898198234, -- VIP (vezi VIPManager.server.luau)
	1899734044 -- Inventory (vezi NPCManager.server.luau)
}

local function setupPlayer(player)
	local leaderstats = player:WaitForChild("leaderstats", 30)
	if not leaderstats then
		return
	end

	RobuxSpentCalculator.Recompute(player)
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
		RobuxSpentCalculator.Recompute(player)
	end
end)
