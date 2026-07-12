local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))
local CosmeticManager = require(script.Parent:WaitForChild("CosmeticManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local showNotificationEvent = remotes:WaitForChild("ShowNotification")

local requestPurchaseEvent = remotes:FindFirstChild("RequestTokenPurchase")
if not requestPurchaseEvent then
	requestPurchaseEvent = Instance.new("RemoteEvent")
	requestPurchaseEvent.Name = "RequestTokenPurchase"
	requestPurchaseEvent.Parent = remotes
end

local purchaseResultEvent = remotes:FindFirstChild("TokenPurchaseResult")
if not purchaseResultEvent then
	purchaseResultEvent = Instance.new("RemoteEvent")
	purchaseResultEvent.Name = "TokenPurchaseResult"
	purchaseResultEvent.Parent = remotes
end

local function getTokensValue(player)
	return player:FindFirstChild("RebirthTokens")
end

local function findItem(itemId)
	for _, item in ipairs(Economy.TokenShop.Items) do
		if item.Id == itemId then
			return item
		end
	end
	return nil
end

local function hasAlreadyBought(player, item)
	if not item.OneTime then
		return false
	end

	return player:GetAttribute("TokenShopBought_" .. item.Id) == true
end

-- Aici se leaga acordarea efectiva a recompensei, dupa Type. Se completeaza
-- pe masura ce stabilim ce recompense exista (Money, Pet, Cosmetic, etc).
local grantHandlers = {
	Money = function(player, item)
		local leaderstats = player:FindFirstChild("leaderstats")
		local money = leaderstats and leaderstats:FindFirstChild("Money")
		if not money then
			return false
		end
		money.Value += (item.Amount or 0)
		return true
	end,

	Pet = function(player, item)
		if not item.Pet then
			return false
		end
		return PetManager.GrantSpecificPet(player, item.Pet) ~= nil
	end,

	-- Titlurile nu acorda nimic pe loc -- sunt permanente, marcate prin
	-- flag-ul OneTime standard (TokenShopBought_<id>), iar bonusul de
	-- Luck se recalculeaza mereu din Economy.TokenShop.GetTitleLuckBonus.
	Title = function(player, item)
		return true
	end,

	Cosmetic = function(player, item)
		if not item.CosmeticId then
			return false
		end
		return CosmeticManager.GrantSpecificCosmetic(player, item.CosmeticId) ~= nil
	end
}

local function grantItem(player, item)
	local handler = grantHandlers[item.Type]

	if not handler then
		warn("TokenShopManager: no grant handler for item type '" .. tostring(item.Type) .. "' (item " .. item.Id .. ")")
		return false
	end

	return handler(player, item)
end

local function doPurchase(player, itemId)
	local item = findItem(itemId)

	if not item then
		purchaseResultEvent:FireClient(player, {Success = false, Message = "Item indisponibil"})
		return
	end

	if hasAlreadyBought(player, item) then
		purchaseResultEvent:FireClient(player, {Success = false, Message = "Deja detii asta"})
		return
	end

	local tokens = getTokensValue(player)

	if not tokens or tokens.Value < item.Cost then
		purchaseResultEvent:FireClient(player, {Success = false, Message = "Nu ai destule Rebirth Tokens"})
		showNotificationEvent:FireClient(player, "❌ Nu ai destule Rebirth Tokens pentru " .. item.Name)
		return
	end

	local granted = grantItem(player, item)

	if not granted then
		purchaseResultEvent:FireClient(player, {Success = false, Message = "Eroare la acordarea recompensei"})
		warn("TokenShopManager: failed to grant item " .. item.Id .. " to " .. player.Name)
		return
	end

	tokens.Value -= item.Cost

	if item.OneTime then
		player:SetAttribute("TokenShopBought_" .. item.Id, true)
	end

	DataManager.SaveData(player)

	purchaseResultEvent:FireClient(player, {
		Success = true,
		ItemId = item.Id,
		RemainingTokens = tokens.Value
	})

	showNotificationEvent:FireClient(player, "✅ Ai cumparat " .. item.Name .. "!")

	print(player.Name .. " bought token shop item: " .. item.Id)
end

requestPurchaseEvent.OnServerEvent:Connect(doPurchase)
