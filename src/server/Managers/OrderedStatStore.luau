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

	-- Intoarce pana la `listCount` intrari (Top N), sortate descrescator, ca
	-- {{UserId=..., Score=..., Rank=...}, ...} -- gol daca DataStore-ul nu
	-- raspunde, niciodata eroare.
	--
	-- Daca `targetUserId` e dat, in plus cauta si locul LUI exact (chiar
	-- daca e mai jos decat listCount) -- opreste cautarea la
	-- `rankSearchLimit` locuri. Returneaza (list, rank, score).
	function api.GetLeaderboard(listCount, targetUserId, rankSearchLimit)
		local list = {}
		local rank = nil
		local rankScore = nil
		local targetKey = targetUserId and tostring(targetUserId)
		rankSearchLimit = rankSearchLimit or listCount

		local success, pages = pcall(function()
			return store:GetSortedAsync(false, MAX_PAGE_SIZE)
		end)

		if not success or not pages then
			return list, nil, nil
		end

		local position = 0

		while true do
			local page = pages:GetCurrentPage()

			for _, entry in ipairs(page) do
				position += 1

				if position <= listCount then
					table.insert(list, {UserId = tonumber(entry.key), Score = entry.value, Rank = position})
				end

				if targetKey and entry.key == targetKey then
					rank = position
					rankScore = entry.value
				end
			end

			local haveEnoughList = position >= listCount
			local haveRankOrNoNeed = (not targetKey) or rank ~= nil
			local hitSearchLimit = position >= rankSearchLimit

			if (haveEnoughList and haveRankOrNoNeed) or hitSearchLimit or pages.IsFinished then
				break
			end

			local advanceOk = pcall(function()
				pages:AdvanceToNextPageAsync()
			end)

			if not advanceOk then
				break
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
