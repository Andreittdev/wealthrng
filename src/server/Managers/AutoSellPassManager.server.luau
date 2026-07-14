local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EconomyConfig"))

local AUTO_SELL_PASS_ID = Economy.AutoSellPass.GamePassId

local function playerHasAutoSellPass(player)
	if AUTO_SELL_PASS_ID == 0 then
		return false
	end

	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, AUTO_SELL_PASS_ID)
	end)

	return success and result
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("HasAutoSellPass", false)

	task.spawn(function()
		local hasPass = playerHasAutoSellPass(player)
		player:SetAttribute("HasAutoSellPass", hasPass)
	end)
end)
