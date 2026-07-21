local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local showNotificationEvent = remotes:WaitForChild("ShowNotification")

local STARTER_PACK_PASS_ID = Economy.StarterPack.GamePassId

local function playerOwnsStarterPack(player)
	local success, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, STARTER_PACK_PASS_ID)
	end)

	return success and owns
end

-- Asteapta pana cand DataManager a terminat de aplicat datele salvate,
-- ca sa nu verificam StarterPackRedeemed inainte sa fie incarcat corect.
local function waitForDataApplied(player)
	if player:GetAttribute("DataApplied") then
		return
	end

	local changedSignal = player:GetAttributeChangedSignal("DataApplied")

	while player.Parent and not player:GetAttribute("DataApplied") do
		changedSignal:Wait()
	end
end

local function grantStarterPackRewards(player)
	if player:GetAttribute("StarterPackRedeemed") then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")

	if money then
		money.Value += Economy.StarterPack.Money
	end

	local pet = PetManager.GrantRandomPetByRarity(player, Economy.StarterPack.PetRarity)

	player:SetAttribute("StarterPackRedeemed", true)

	local message = "🎁 Starter Pack claimed! +$" .. Economy.StarterPack.Money

	if pet and not pet.IsDuplicate then
		message = message .. " and " .. pet.DisplayName .. "!"
	elseif pet and pet.IsDuplicate then
		message = message .. " (+$" .. pet.AutoSellCash .. " for a duplicate pet)"
	end

	showNotificationEvent:FireClient(player, message)

	print(player.Name .. " redeemed the Starter Pack gamepass")
end

-- HasStarterPack = detine gamepass-ul REAL SAU l-a primit cadou
-- (GiftedStarterPack, setat de PremiumPurchaseManager.grantGiftPass) --
-- acelasi tipar "real SAU cadou" ca VIP/SpeedPass/AutoSellPass/InventoryPass.
local function checkStarterPack(player)
	local hasStarterPack = playerOwnsStarterPack(player) or player:GetAttribute("GiftedStarterPack") == true

	if not hasStarterPack then
		player:SetAttribute("HasStarterPack", false)
		return
	end

	player:SetAttribute("HasStarterPack", true)

	waitForDataApplied(player)

	if not player.Parent then
		return
	end

	grantStarterPackRewards(player)
end

local function setupPlayer(player)
	task.spawn(checkStarterPack, player)

	-- Cadoul poate ajunge LIVE, in timpul sesiunii (cineva ii cumpara
	-- Starter Pack cat jucatorul e deja pe server) -- checkStarterPack de mai
	-- sus ruleaza doar o data, la apel, deci fara asta recompensa unica
	-- (bani + pet) nu s-ar acorda pana la urmatorul join.
	player:GetAttributeChangedSignal("GiftedStarterPack"):Connect(function()
		if player:GetAttribute("GiftedStarterPack") then
			task.spawn(checkStarterPack, player)
		end
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased or gamePassId ~= STARTER_PACK_PASS_ID then
		return
	end

	player:SetAttribute("HasStarterPack", true)
	waitForDataApplied(player)

	if player.Parent then
		grantStarterPackRewards(player)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end
