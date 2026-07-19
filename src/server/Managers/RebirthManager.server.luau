local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local showNotificationEvent = remotes:WaitForChild("ShowNotification")

local requestRebirthEvent = remotes:FindFirstChild("RequestRebirth")
if not requestRebirthEvent then
	requestRebirthEvent = Instance.new("RemoteEvent")
	requestRebirthEvent.Name = "RequestRebirth"
	requestRebirthEvent.Parent = remotes
end

local rebirthResultEvent = remotes:FindFirstChild("RebirthResult")
if not rebirthResultEvent then
	rebirthResultEvent = Instance.new("RemoteEvent")
	rebirthResultEvent.Name = "RebirthResult"
	rebirthResultEvent.Parent = remotes
end

local function getMoneyValue(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("Money")
end

local function getRebirthsValue(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("Rebirths")
end

local function getOrCreateTokens(player)
	local tokens = player:FindFirstChild("RebirthTokens")

	if not tokens then
		tokens = Instance.new("IntValue")
		tokens.Name = "RebirthTokens"
		tokens.Value = 0
		tokens.Parent = player
	end

	return tokens
end

local function getNextRequiredMoney(player)
	local rebirths = getRebirthsValue(player)
	local nextRebirthNumber = (rebirths and rebirths.Value or 0) + 1

	return Economy.Rebirth.GetRequiredMoney(nextRebirthNumber)
end

local function canRebirth(player)
	local standLevel = player:FindFirstChild("StandLevel")
	local money = getMoneyValue(player)
	local requiredMoney = getNextRequiredMoney(player)

	if not standLevel or standLevel.Value < Economy.Rebirth.RequiredStandLevel then
		return false, "Ai nevoie de Stand Level " .. Economy.Rebirth.RequiredStandLevel
	end

	if not money or money.Value < requiredMoney then
		return false, "Ai nevoie de cel putin $" .. requiredMoney
	end

	return true
end

local function maybeGrantExclusivePet(player, tokens)
	if player:GetAttribute("RebirthPetClaimed") then
		return
	end

	if tokens.Value < Economy.Rebirth.TokensForExclusivePet then
		return
	end

	local petData = Economy.Rebirth.ExclusivePet
	local granted = PetManager.GrantSpecificPet(player, petData)

	if not granted then
		warn("Failed to grant exclusive Rebirth pet to " .. player.Name)
		return
	end

	player:SetAttribute("RebirthPetClaimed", true)

	showNotificationEvent:FireClient(
		player,
		"🔥 " .. Economy.Rebirth.TokensForExclusivePet .. " Rebirth Tokens! You unlocked " .. petData.DisplayName .. "!"
	)

	print(player.Name .. " unlocked the exclusive Rebirth pet: " .. petData.DisplayName)
end

-- Recompensa permanenta de Rebirth (Sell%): se citeste din leaderstats.Rebirths
-- de oriunde e nevoie (SellManager), nu se calculeaza/stocheaza separat aici.
local function doRebirth(player)
	local ok, reason = canRebirth(player)

	if not ok then
		rebirthResultEvent:FireClient(player, {Success = false, Message = reason})
		showNotificationEvent:FireClient(player, "❌ " .. reason)
		return
	end

	local money = getMoneyValue(player)
	local standLevel = player:FindFirstChild("StandLevel")
	local rebirths = getRebirthsValue(player)
	local tokens = getOrCreateTokens(player)
	local inventory = player:FindFirstChild("Inventory")

	money.Value = 1000
	standLevel.Value = 1

	if inventory then
		inventory:ClearAllChildren()
	end

	if rebirths then
		rebirths.Value += 1
	end

	tokens.Value += 1

	maybeGrantExclusivePet(player, tokens)

	DataManager.SaveData(player)

	local newCount = rebirths and rebirths.Value or 1
	local perks = Economy.Rebirth.GetPerks(newCount)

	rebirthResultEvent:FireClient(player, {
		Success = true,
		RebirthCount = newCount,
		Tokens = tokens.Value,
		Perks = perks
	})

	showNotificationEvent:FireClient(
		player,
		"✨ Rebirth #" .. newCount .. "! +" .. perks.Sell .. "% Sell, +" .. perks.Luck .. "% Luck, +" .. perks.Speed .. "% Speed (+1 Token)"
	)

	print(player.Name .. " did rebirth #" .. newCount .. " (tokens: " .. tokens.Value .. ")")
end

requestRebirthEvent.OnServerEvent:Connect(doRebirth)

-- ================= Auto Rebirth Pass =================
-- Cumpararea pass-ului = consimtamant explicit sa se sara complet peste
-- dialogul de confirmare (obligatoriu altfel, vezi RebirthShop.client.luau) --
-- de indata ce jucatorul e eligibil (Stand 5 + bani suficienti), rebirth-ul
-- se declanseaza singur. Poate fi oprit temporar din Settings
-- (AutoRebirthEnabled, implicit true), ex: daca vrei sa acumulezi bani peste
-- prag ca sa cumperi ceva din Token Shop inainte sa se resetize totul.
local function isAutoRebirthActive(player)
	if not player:GetAttribute("HasAutoRebirthPass") then
		return false
	end

	return player:GetAttribute("AutoRebirthEnabled") ~= false
end

local function maybeAutoRebirth(player)
	if not isAutoRebirthActive(player) then
		return
	end

	local ok = canRebirth(player)
	if ok then
		doRebirth(player)
	end
end

local function watchAutoRebirth(player)
	local leaderstats = player:WaitForChild("leaderstats", 10)
	local money = leaderstats and leaderstats:WaitForChild("Money", 10)
	local standLevel = player:WaitForChild("StandLevel", 10)

	if not money or not standLevel then
		return
	end

	money:GetPropertyChangedSignal("Value"):Connect(function()
		maybeAutoRebirth(player)
	end)

	standLevel:GetPropertyChangedSignal("Value"):Connect(function()
		maybeAutoRebirth(player)
	end)

	player:GetAttributeChangedSignal("HasAutoRebirthPass"):Connect(function()
		maybeAutoRebirth(player)
	end)

	player:GetAttributeChangedSignal("AutoRebirthEnabled"):Connect(function()
		maybeAutoRebirth(player)
	end)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(watchAutoRebirth, player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(watchAutoRebirth, player)
end
