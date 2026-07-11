local Players = game:GetService("Players")

-- Doar UserId-urile din această listă pot folosi comenzile de mai jos.
-- Goală implicit: comenzile sunt dezactivate pentru toată lumea până adaugi ID-uri aici.
local ADMIN_USER_IDS = {
	-- [123456789] = true,
}

local function isAdmin(player)
	return ADMIN_USER_IDS[player.UserId] == true
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)

		if message == "!money" then
			if not isAdmin(player) then return end

			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then return end

			local money = leaderstats:FindFirstChild("Money")
			if not money then return end

			money.Value += 1000

			print(player.Name .. " received $1000")

		end
	end)
end)