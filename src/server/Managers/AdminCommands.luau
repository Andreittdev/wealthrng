local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)

		if message == "!money" then

			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then return end

			local money = leaderstats:FindFirstChild("Money")
			if not money then return end

			money.Value += 1000

			print(player.Name .. " received $10000")

		end
	end)
end)