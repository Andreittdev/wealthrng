-- OrderedDataStore separat, DOAR pentru clasamentul "Most Cash Earned" --
-- tine scorul (CashEarned) pentru FIECARE jucator care a trecut vreodata prin
-- joc (nu doar cei online acum), ca sa poata fi interogat de pancarda fizica
-- din LeaderboardStand.server.luau, indiferent pe ce server ruleaza.
--
-- Separat de DataManager's PlayerData_V2 (care e un GetAsync/SetAsync normal,
-- indexat pe UserId, fara sortare) -- un OrderedDataStore permite
-- GetSortedAsync, adica "da-mi Top 10", ceea ce un DataStore normal nu poate.

local OrderedStatStore = require(script.Parent:WaitForChild("OrderedStatStore"))

local UPDATE_INTERVAL = 30

-- V2 (nu V1) -- cerut explicit un reset complet al clasamentului (inclusiv
-- scorul vechi al contului de test buylowsellhigh5) -- schimband numele
-- DataStore-ului, TOATA lumea porneste de la zero, fara sa fie nevoie sa
-- stergem manual intrari individuale din DataStore-ul vechi.
return OrderedStatStore.new("CashEarnedLeaderboard_V2", UPDATE_INTERVAL, function(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local cashEarned = leaderstats and leaderstats:FindFirstChild("CashEarned")
	return cashEarned and cashEarned.Value
end)
