local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local CodesConfig = require(modulesFolder:WaitForChild("CodesConfig"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local showNotificationEvent = remotes:WaitForChild("ShowNotification")

local redeemCodeEvent = remotes:FindFirstChild("RedeemCode")
if not redeemCodeEvent then
	redeemCodeEvent = Instance.new("RemoteEvent")
	redeemCodeEvent.Name = "RedeemCode"
	redeemCodeEvent.Parent = remotes
end

local codeResultEvent = remotes:FindFirstChild("CodeResult")
if not codeResultEvent then
	codeResultEvent = Instance.new("RemoteEvent")
	codeResultEvent.Name = "CodeResult"
	codeResultEvent.Parent = remotes
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

-- Aici se leaga acordarea efectiva a recompensei, dupa Type -- acelasi tipar
-- ca grantHandlers din TokenShopManager.server.luau.
local grantHandlers = {
	Money = function(player, code)
		local leaderstats = player:FindFirstChild("leaderstats")
		local money = leaderstats and leaderstats:FindFirstChild("Money")
		if not money then
			return false
		end
		money.Value += (code.Amount or 0)
		return true
	end,

	RebirthTokens = function(player, code)
		local tokens = getOrCreateTokens(player)
		tokens.Value += (code.Amount or 0)
		return true
	end,

	Pet = function(player, code)
		if not code.Pet then
			return false
		end
		return PetManager.GrantSpecificPet(player, code.Pet) ~= nil
	end,

	RandomPet = function(player, code)
		return PetManager.GrantRandomPetByRarity(player, code.Rarity) ~= nil
	end
}

local function grantCode(player, code)
	local handler = grantHandlers[code.Type]

	if not handler then
		warn("CodesManager: no grant handler for code type '" .. tostring(code.Type) .. "'")
		return false
	end

	return handler(player, code)
end

-- Normalizam intrarea (majuscule, fara spatii la capete) ca jucatorul sa
-- poata scrie orice capitalizare/whitespace si tot sa gaseasca codul.
local function normalizeCode(rawInput)
	if typeof(rawInput) ~= "string" then
		return nil
	end

	local trimmed = rawInput:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then
		return nil
	end

	return trimmed:upper()
end

local function hasAlreadyRedeemed(player, codeKey)
	return player:GetAttribute("CodeRedeemed_" .. codeKey) == true
end

-- Asteapta pana cand DataManager a terminat de aplicat datele salvate (acelasi
-- tipar ca StarterPackManager.server.luau) -- fara asta, un client putea
-- trimite RedeemCode chiar la join, INAINTE ca CodeRedeemed_<COD> sa fi fost
-- restaurat din salvarea reala (LoadData/ApplyData pot dura cateva secunde),
-- iar hasAlreadyRedeemed vedea atributul ca nefolosit (nil) desi codul era
-- deja folosit intr-o sesiune anterioara -- redare gratuita, repetabila la
-- fiecare rejoin.
local function waitForDataApplied(player)
	if player:GetAttribute("DataApplied") then
		return
	end

	local changedSignal = player:GetAttributeChangedSignal("DataApplied")

	while player.Parent and not player:GetAttribute("DataApplied") do
		changedSignal:Wait()
	end
end

local function doRedeem(player, rawInput)
	waitForDataApplied(player)

	if not player.Parent then
		return
	end

	local codeKey = normalizeCode(rawInput)

	if not codeKey then
		codeResultEvent:FireClient(player, {Success = false, Message = "Introdu un cod"})
		return
	end

	local code = CodesConfig.Active[codeKey]

	if not code or code.Active == false then
		codeResultEvent:FireClient(player, {Success = false, Message = "Cod invalid"})
		return
	end

	if hasAlreadyRedeemed(player, codeKey) then
		codeResultEvent:FireClient(player, {Success = false, Message = "Ai folosit deja acest cod"})
		return
	end

	local granted = grantCode(player, code)

	if not granted then
		codeResultEvent:FireClient(player, {Success = false, Message = "Eroare la acordarea recompensei"})
		warn("CodesManager: failed to grant code " .. codeKey .. " to " .. player.Name)
		return
	end

	player:SetAttribute("CodeRedeemed_" .. codeKey, true)
	DataManager.SaveData(player)

	codeResultEvent:FireClient(player, {Success = true, Code = codeKey})
	showNotificationEvent:FireClient(player, "🎁 Code redeemed: " .. codeKey .. "!")

	print(player.Name .. " redeemed code: " .. codeKey)
end

redeemCodeEvent.OnServerEvent:Connect(doRedeem)
