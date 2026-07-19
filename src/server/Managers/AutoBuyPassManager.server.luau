local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EconomyConfig"))

local AUTO_BUY_PASS_ID = Economy.AutoBuyPass.GamePassId

local function playerHasAutoBuyPass(player)
	if AUTO_BUY_PASS_ID == 0 then
		return false
	end

	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, AUTO_BUY_PASS_ID)
	end)

	return success and result
end

local function checkAutoBuyPass(player)
	player:SetAttribute("HasAutoBuyPass", playerHasAutoBuyPass(player))
end

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute("HasAutoBuyPass", false)
	task.spawn(checkAutoBuyPass, player)
end)

-- Activare imediata la cumparare, fara sa astepte un rejoin -- spre deosebire
-- de alte pass-uri (ex: Speed Pass), aici jucatorul chiar simte diferenta
-- instant (NPCManager.server.luau incepe sa auto-accepte ofertele), deci
-- merita reactie in timp real, nu doar la urmatorul join.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased or gamePassId ~= AUTO_BUY_PASS_ID then
		return
	end

	player:SetAttribute("HasAutoBuyPass", true)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(checkAutoBuyPass, player)
end
