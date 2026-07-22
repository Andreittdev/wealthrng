local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local showNotificationEvent = remotes:WaitForChild("ShowNotification")

local ELITE_PACK_PASS_ID = Economy.ElitePack.GamePassId

local function playerOwnsElitePack(player)
	local success, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, ELITE_PACK_PASS_ID)
	end)

	return success and owns
end

-- Acelasi tipar ca MediumPackManager -- asteapta pana cand DataManager a
-- terminat de aplicat datele salvate, ca sa nu verificam ElitePackRedeemed
-- inainte sa fie incarcat corect.
local function waitForDataApplied(player)
	if player:GetAttribute("DataApplied") then
		return
	end

	local changedSignal = player:GetAttributeChangedSignal("DataApplied")

	while player.Parent and not player:GetAttribute("DataApplied") do
		changedSignal:Wait()
	end
end

local function grantElitePackRewards(player)
	if player:GetAttribute("ElitePackRedeemed") then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")

	if money then
		money.Value += Economy.ElitePack.Money
	end

	local pet = PetManager.GrantRandomPetByRarity(player, Economy.ElitePack.PetRarity)

	player:SetAttribute("ElitePackRedeemed", true)

	local message = "🎁 Elite Pack claimed! +$" .. Economy.ElitePack.Money

	if pet and not pet.IsDuplicate then
		message = message .. " and " .. pet.DisplayName .. "!"
	elseif pet and pet.IsDuplicate then
		message = message .. " (+$" .. pet.AutoSellCash .. " for a duplicate pet)"
	end

	showNotificationEvent:FireClient(player, message)

	print(player.Name .. " redeemed the Elite Pack gamepass")
end

local function checkElitePack(player)
	local hasElitePack = playerOwnsElitePack(player)

	player:SetAttribute("HasElitePack", hasElitePack)

	if not hasElitePack then
		return
	end

	waitForDataApplied(player)

	if not player.Parent then
		return
	end

	grantElitePackRewards(player)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(checkElitePack, player)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased or gamePassId ~= ELITE_PACK_PASS_ID then
		return
	end

	player:SetAttribute("HasElitePack", true)
	waitForDataApplied(player)

	if player.Parent then
		grantElitePackRewards(player)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(checkElitePack, player)
end
