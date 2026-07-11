local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	local leaderstats = player:WaitForChild("leaderstats")
	local money = leaderstats:WaitForChild("Money")

	task.wait(2)

	money.Value = 5000000
end)