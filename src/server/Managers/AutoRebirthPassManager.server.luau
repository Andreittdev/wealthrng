local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EconomyConfig"))

local AUTO_REBIRTH_PASS_ID = Economy.AutoRebirthPass.GamePassId

local function playerHasAutoRebirthPass(player)
	if AUTO_REBIRTH_PASS_ID == 0 then
		return false
	end

	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, AUTO_REBIRTH_PASS_ID)
	end)

	return success and result
end

local function checkAutoRebirthPass(player)
	player:SetAttribute("HasAutoRebirthPass", playerHasAutoRebirthPass(player))
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("HasAutoRebirthPass", false)
	task.spawn(checkAutoRebirthPass, player)
end)

-- Activare imediata la cumparare, fara sa astepte un rejoin -- daca jucatorul
-- e deja eligibil pentru rebirth in momentul cumpararii, RebirthManager
-- trebuie sa reactioneze instant (asculta HasAutoRebirthPass), nu la urmatorul
-- join.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased or gamePassId ~= AUTO_REBIRTH_PASS_ID then
		return
	end

	player:SetAttribute("HasAutoRebirthPass", true)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(checkAutoRebirthPass, player)
end
