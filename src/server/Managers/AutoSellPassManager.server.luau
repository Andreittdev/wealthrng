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

-- OwnsAutoSellPass = detine gamepass-ul REAL sau a primit perk-ul cadou
-- (GiftedAutoSellPass, persistat de DataManager) -- NU tine cont de
-- AutoSellPassEnabled (folosit doar ca sa stim cand sa aratam toggle-ul din
-- Settings).
-- HasAutoSellPass = OwnsAutoSellPass SI AutoSellPassEnabled (implicit true)
-- -- vezi comentariul din VIPManager.server.luau pentru motivul recalcularii
-- pe schimbare, nu doar o data la join.
local function recompute(player)
	local real = player:GetAttribute("RealAutoSellPass") == true
	local gifted = player:GetAttribute("GiftedAutoSellPass") == true
	local owns = real or gifted
	local enabled = player:GetAttribute("AutoSellPassEnabled") ~= false

	player:SetAttribute("OwnsAutoSellPass", owns)
	player:SetAttribute("HasAutoSellPass", owns and enabled)
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("RealAutoSellPass", false)
	player:SetAttribute("OwnsAutoSellPass", false)
	player:SetAttribute("HasAutoSellPass", false)

	player:GetAttributeChangedSignal("RealAutoSellPass"):Connect(function()
		recompute(player)
	end)
	player:GetAttributeChangedSignal("GiftedAutoSellPass"):Connect(function()
		recompute(player)
	end)
	player:GetAttributeChangedSignal("AutoSellPassEnabled"):Connect(function()
		recompute(player)
	end)

	task.spawn(function()
		local hasPass = playerHasAutoSellPass(player)
		player:SetAttribute("RealAutoSellPass", hasPass)
	end)
end)
