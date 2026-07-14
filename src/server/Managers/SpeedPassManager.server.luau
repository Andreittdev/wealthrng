local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EconomyConfig"))

local SPEED_PASS_ID = Economy.SpeedPass.GamePassId

local function playerHasSpeedPass(player)
	if SPEED_PASS_ID == 0 then
		return false
	end

	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, SPEED_PASS_ID)
	end)

	return success and result
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("HasSpeedPass", false)

	task.spawn(function()
		local hasPass = playerHasSpeedPass(player)
		player:SetAttribute("HasSpeedPass", hasPass)
	end)
end)
