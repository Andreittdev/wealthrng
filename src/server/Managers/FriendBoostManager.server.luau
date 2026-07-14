local Players = game:GetService("Players")

-- +10% Cash per prieten Roblox prezent in ACELASI server, maxim 30% (3
-- prieteni). Recalculat pentru toti jucatorii de fiecare data cand cineva
-- intra sau iese (numarul de prieteni prezenti se poate schimba pentru
-- oricine altcineva din server, nu doar pentru cel care a intrat/iesit).
local BOOST_PER_FRIEND = 10
local MAX_BOOST_PERCENT = 30

local function countFriendsInServer(player)
	local count = 0

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			local isFriend = false

			-- IsFriendsWith poate arunca eroare daca serviciul de prietenii
			-- Roblox e indisponibil temporar -- nu vrem sa crape tot scriptul
			-- pentru asta, doar sa ignoram acel jucator la numaratoare.
			pcall(function()
				isFriend = player:IsFriendsWith(otherPlayer.UserId)
			end)

			if isFriend then
				count += 1
			end
		end
	end

	return count
end

local function recalculateBoost(player)
	local friendCount = countFriendsInServer(player)
	local boost = math.min(friendCount * BOOST_PER_FRIEND, MAX_BOOST_PERCENT)
	player:SetAttribute("FriendBoostPercent", boost)
end

local function recalculateAll()
	for _, player in ipairs(Players:GetPlayers()) do
		recalculateBoost(player)
	end
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("FriendBoostPercent", 0)
	recalculateAll()
end)

Players.PlayerRemoving:Connect(function()
	-- Player-ul care pleaca inca apare in Players:GetPlayers() cat timp ruleaza
	-- PlayerRemoving -- amanam recalcularea pentru dupa ce chiar a fost scos.
	task.defer(recalculateAll)
end)

recalculateAll()
