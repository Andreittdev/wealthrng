-- Urmareste in continuu (nu doar cand esti langa un stand fizic, ca la
-- LeaderboardRankDisplay.client.luau) rank-ul fiecarui jucator online la
-- toate cele 3 clasamente -- Most Cash Earned, Most Time Played, Most Robux
-- Spent. Doar Top 100 conteaza (cerut explicit): daca esti in Top 100, ii
-- punem un attribute (citit live de ChatCustomization.client.luau, ca sa
-- apara un tag [#N] in chat) si trimitem o notificare cand rank-ul se
-- schimba (urci/cobori/intri/iesi din Top 100).
--
-- Verificarile folosesc GetLeaderboard, care citeste dintr-un cache comun
-- (OrderedStatStore.luau, TTL 25s) -- deci a verifica toti jucatorii la
-- fiecare CHECK_INTERVAL nu inseamna un fetch nou de DataStore de fiecare
-- data, doar cand cache-ul a expirat.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CashLeaderboardStore = require(script.Parent:WaitForChild("CashLeaderboardStore"))
local TimePlayedStore = require(script.Parent:WaitForChild("TimePlayedStore"))
local RobuxSpentStore = require(script.Parent:WaitForChild("RobuxSpentStore"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local showNotificationEvent = remotes:WaitForChild("ShowNotification")

local TOP_LIMIT = 100
local CHECK_INTERVAL = 30
local RANK_SEARCH_LIMIT = 1000

local BOARDS = {
	{Store = CashLeaderboardStore, Attribute = "CashRank", Label = "Cash"},
	{Store = TimePlayedStore, Attribute = "TimeRank", Label = "Time Played"},
	{Store = RobuxSpentStore, Attribute = "RobuxRank", Label = "Robux Spent"}
}

-- knownRanks[player][attributeName] = numarul de rank, SAU false (inseamna
-- "verificat, dar in afara Top 100" -- diferit de nil, care inseamna "inca
-- neverificat NICIODATA", ca sa nu trimitem o notificare la PRIMA verificare
-- de dupa join (altfel toata lumea ar primi un mesaj "ai intrat in Top 100"
-- doar pentru ca s-a facut prima citire).
local knownRanks = {}

local function checkPlayerBoard(player, board)
	local _, rank = board.Store.GetLeaderboard(0, player.UserId, RANK_SEARCH_LIMIT)

	-- GetLeaderboard poate face un yield real (cache expirat -> GetSortedAsync)
	-- -- daca jucatorul a plecat exact in acea fereastra, PlayerRemoving a
	-- curatat deja knownRanks[player]; fara verificarea asta, codul de mai jos
	-- i-ar recrea intrarea (knownRanks[player] or {}), care ar ramane
	-- "agatata" pentru totdeauna (nimic n-o mai curata dupa asta).
	if not player.Parent then
		return
	end

	local newRank = (rank and rank <= TOP_LIMIT) and rank or false

	knownRanks[player] = knownRanks[player] or {}
	local previousRank = knownRanks[player][board.Attribute]

	player:SetAttribute(board.Attribute, newRank or nil)

	if previousRank == nil then
		-- Prima verificare pentru acest jucator+clasament -- doar stabilim
		-- baseline-ul, fara notificare.
		knownRanks[player][board.Attribute] = newRank
		return
	end

	if newRank == previousRank then
		return
	end

	knownRanks[player][board.Attribute] = newRank

	if newRank and previousRank then
		if newRank < previousRank then
			showNotificationEvent:FireClient(player, "📈 You moved up to " .. board.Label .. " Rank #" .. newRank .. "!")
		else
			showNotificationEvent:FireClient(player, "📉 You dropped to " .. board.Label .. " Rank #" .. newRank .. "!")
		end
	elseif newRank and not previousRank then
		showNotificationEvent:FireClient(player, "🎉 You entered the Top 100 " .. board.Label .. " leaderboard at Rank #" .. newRank .. "!")
	elseif not newRank and previousRank then
		showNotificationEvent:FireClient(player, "You dropped out of the Top 100 " .. board.Label .. " leaderboard")
	end
end

local function checkAllPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		for _, board in ipairs(BOARDS) do
			checkPlayerBoard(player, board)
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	knownRanks[player] = nil
end)

task.spawn(function()
	while true do
		checkAllPlayers()
		task.wait(CHECK_INTERVAL)
	end
end)
