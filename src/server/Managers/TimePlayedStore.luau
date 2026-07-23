-- OrderedDataStore separat, DOAR pentru clasamentul "Most Time Played" --
-- scorul e TimePlayed (in MINUTE), acumulat cat timp jucatorul e conectat
-- (vezi DataManager.luau -- se incrementeaza automat, +1 la fiecare 60
-- secunde petrecute in joc).

local OrderedStatStore = require(script.Parent:WaitForChild("OrderedStatStore"))

local UPDATE_INTERVAL = 30

-- V2 (nu V1) -- reset complet, cerut explicit (vezi CashLeaderboardStore).
return OrderedStatStore.new("TimePlayedLeaderboard_V2", UPDATE_INTERVAL, function(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local timePlayed = leaderstats and leaderstats:FindFirstChild("TimePlayed")
	return timePlayed and timePlayed.Value
end)
