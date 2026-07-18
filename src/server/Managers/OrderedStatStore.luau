-- Factory generica pentru un OrderedDataStore de leaderboard -- extrasa din
-- CashLeaderboardStore (folosita acolo pentru "Most Cash Earned"), ca sa
-- poata fi refolosita si pentru alte clasamente (ex: "Most Time Played")
-- fara sa copiem aceeasi logica de throttle/paginare de fiecare data.
--
-- getValue(player) trebuie sa intoarca numarul curent (scorul) al
-- jucatorului, sau nil daca inca nu exista (ex: leaderstats neincarcate).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local OrderedStatStore = {}

-- GetSortedAsync accepta maxim 100 de intrari per pagina -- pentru liste mai
-- mari trebuie sa avansam manual prin pagini (AdvanceToNextPageAsync).
local MAX_PAGE_SIZE = 100

function OrderedStatStore.new(dataStoreName, updateInterval, getValue)
	local store = DataStoreService:GetOrderedDataStore(dataStoreName)
	local pendingUpdate = {}
	local api = {}

	local function flushPlayer(player)
		local value = getValue(player)
		if not value then
			return
		end

		local success, err = pcall(function()
			store:SetAsync(tostring(player.UserId), value)
		end)

		if not success then
			warn("OrderedStatStore(" .. dataStoreName .. "): nu am putut salva scorul pentru " .. player.Name .. " -- " .. tostring(err))
		end
	end

	-- Throttle -- nu scriem in DataStore la fiecare schimbare (ar depasi
	-- rapid limita de request-uri) -- doar la interval, si o data la plecare.
	function api.QueueUpdate(player)
		pendingUpdate[player] = true
	end

	task.spawn(function()
		while true do
			task.wait(updateInterval)

			for player in pairs(pendingUpdate) do
				pendingUpdate[player] = nil
				flushPlayer(player)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		pendingUpdate[player] = nil
		flushPlayer(player)
	end)

	-- Cache COMUN -- inainte, tabla (GetTop, la fiecare 30s) si placa
	-- "Your Rank" (GetLeaderboard cu targetUserId, la fiecare cerere de
	-- rank a unui jucator apropiat) faceau FIECARE propriul fetch complet
	-- din DataStore (pana la 5-10 avansari de pagina), desi citeau exact
	-- aceleasi date -- bug real de performanta/request-uri, gasit la audit.
	-- Acum ambele citesc din ACEEASI lista, reimprospatata cel mult o data
	-- la CACHE_TTL secunde.
	local CACHE_TTL = 25
	local CACHE_MAX_ENTRIES = 1000
	local cache = nil -- {list = {...}, fetchedAt = os.clock()}

	local function fetchList(maxCount)
		local list = {}

		local success, pages = pcall(function()
			return store:GetSortedAsync(false, MAX_PAGE_SIZE)
		end)

		if not success or not pages then
			return list
		end

		local position = 0

		while true do
			local page = pages:GetCurrentPage()

			for _, entry in ipairs(page) do
				position += 1

				if position <= maxCount then
					table.insert(list, {UserId = tonumber(entry.key), Score = entry.value, Rank = position})
				end
			end

			if position >= maxCount or pages.IsFinished then
				break
			end

			local advanceOk = pcall(function()
				pages:AdvanceToNextPageAsync()
			end)

			if not advanceOk then
				break
			end
		end

		return list
	end

	local function getCachedList()
		local now = os.clock()

		if cache and (now - cache.fetchedAt) < CACHE_TTL then
			return cache.list
		end

		local list = fetchList(CACHE_MAX_ENTRIES)
		cache = {list = list, fetchedAt = now}
		return list
	end

	-- Intoarce pana la `listCount` intrari (Top N), sortate descrescator, ca
	-- {{UserId=..., Score=..., Rank=...}, ...} -- gol daca DataStore-ul nu
	-- raspunde, niciodata eroare.
	--
	-- Daca `targetUserId` e dat, in plus cauta si locul LUI exact (chiar
	-- daca e mai jos decat listCount), din ACELASI cache. Returneaza
	-- (list, rank, score).
	function api.GetLeaderboard(listCount, targetUserId, rankSearchLimit)
		local fullList = getCachedList()
		local list = {}

		for i = 1, math.min(listCount, #fullList) do
			table.insert(list, fullList[i])
		end

		local rank = nil
		local rankScore = nil

		if targetUserId then
			local targetKey = tostring(targetUserId)

			for _, entry in ipairs(fullList) do
				if tostring(entry.UserId) == targetKey then
					rank = entry.Rank
					rankScore = entry.Score
					break
				end
			end
		end

		return list, rank, rankScore
	end

	-- Pastrat pentru compatibilitate cu apeluri simple, fara nevoie de rank.
	function api.GetTop(count)
		local list = api.GetLeaderboard(count)
		return list
	end

	return api
end

return OrderedStatStore
