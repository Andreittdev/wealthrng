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

-- HasSpeedPass = detine gamepass-ul REAL sau a primit perk-ul cadou
-- (GiftedSpeedPass, persistat de DataManager) -- recalculat de fiecare data
-- cand ORICARE dintre cele doua se schimba, nu doar o singura data la join,
-- ca rezultatul sa nu depinda de ordinea in care ruleaza acest script fata
-- de DataManager.ApplyData (scripturi separate, fara garantie de ordine
-- intre handlere PlayerAdded diferite).
local function recompute(player)
	local real = player:GetAttribute("RealSpeedPass") == true
	local gifted = player:GetAttribute("GiftedSpeedPass") == true
	player:SetAttribute("HasSpeedPass", real or gifted)
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("RealSpeedPass", false)
	player:SetAttribute("HasSpeedPass", false)

	player:GetAttributeChangedSignal("RealSpeedPass"):Connect(function()
		recompute(player)
	end)
	player:GetAttributeChangedSignal("GiftedSpeedPass"):Connect(function()
		recompute(player)
	end)

	task.spawn(function()
		local hasPass = playerHasSpeedPass(player)
		player:SetAttribute("RealSpeedPass", hasPass)
	end)
end)
