local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local showNotificationEvent = remotes:WaitForChild("ShowNotification")

local MEDIUM_PACK_PASS_ID = Economy.MediumPack.GamePassId

local function playerOwnsMediumPack(player)
	local success, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, MEDIUM_PACK_PASS_ID)
	end)

	return success and owns
end

-- Asteapta pana cand DataManager a terminat de aplicat datele salvate,
-- ca sa nu verificam MediumPackRedeemed inainte sa fie incarcat corect
-- (acelasi tipar ca StarterPackManager.waitForDataApplied).
local function waitForDataApplied(player)
	if player:GetAttribute("DataApplied") then
		return
	end

	local changedSignal = player:GetAttributeChangedSignal("DataApplied")

	while player.Parent and not player:GetAttribute("DataApplied") do
		changedSignal:Wait()
	end
end

local function grantMediumPackRewards(player)
	if player:GetAttribute("MediumPackRedeemed") then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")

	if money then
		money.Value += Economy.MediumPack.Money
	end

	local pet = PetManager.GrantRandomPetByRarity(player, Economy.MediumPack.PetRarity)

	player:SetAttribute("MediumPackRedeemed", true)

	local message = "🎁 Medium Pack claimed! +$" .. Economy.MediumPack.Money

	if pet and not pet.IsDuplicate then
		message = message .. " and " .. pet.DisplayName .. "!"
	elseif pet and pet.IsDuplicate then
		message = message .. " (+$" .. pet.AutoSellCash .. " for a duplicate pet)"
	end

	showNotificationEvent:FireClient(player, message)

	print(player.Name .. " redeemed the Medium Pack gamepass")
end

local function checkMediumPack(player)
	local hasMediumPack = playerOwnsMediumPack(player)

	player:SetAttribute("HasMediumPack", hasMediumPack)

	if not hasMediumPack then
		return
	end

	waitForDataApplied(player)

	if not player.Parent then
		return
	end

	grantMediumPackRewards(player)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(checkMediumPack, player)
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased or gamePassId ~= MEDIUM_PACK_PASS_ID then
		return
	end

	player:SetAttribute("HasMediumPack", true)
	waitForDataApplied(player)

	if player.Parent then
		grantMediumPackRewards(player)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(checkMediumPack, player)
end
