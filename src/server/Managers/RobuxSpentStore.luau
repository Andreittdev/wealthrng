-- OrderedDataStore separat, DOAR pentru clasamentul "Most Robux Spent" --
-- scorul e RobuxSpent (in Robux), calculat de RobuxSpentTracker.server.luau
-- din preturile REALE ale gamepass-urilor detinute (nu din valorile
-- hardcodate din EconomyConfig, care pot fi incorecte -- vezi comentariul
-- din EconomyConfig.luau despre StarterPack).

local OrderedStatStore = require(script.Parent:WaitForChild("OrderedStatStore"))

local UPDATE_INTERVAL = 30

-- V2 (nu V1) -- reset complet, cerut explicit (vezi CashLeaderboardStore).
return OrderedStatStore.new("RobuxSpentLeaderboard_V2", UPDATE_INTERVAL, function(player)
	local hiddenStats = player:FindFirstChild("HiddenStats")
	local robuxSpent = hiddenStats and hiddenStats:FindFirstChild("RobuxSpent")
	return robuxSpent and robuxSpent.Value
end)
