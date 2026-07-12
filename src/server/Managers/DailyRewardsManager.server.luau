local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local showNotificationEvent = remotes:WaitForChild("ShowNotification")

local requestStatusEvent = remotes:FindFirstChild("RequestDailyStatus")
if not requestStatusEvent then
	requestStatusEvent = Instance.new("RemoteEvent")
	requestStatusEvent.Name = "RequestDailyStatus"
	requestStatusEvent.Parent = remotes
end

local statusResultEvent = remotes:FindFirstChild("DailyStatusResult")
if not statusResultEvent then
	statusResultEvent = Instance.new("RemoteEvent")
	statusResultEvent.Name = "DailyStatusResult"
	statusResultEvent.Parent = remotes
end

local requestClaimEvent = remotes:FindFirstChild("RequestDailyClaim")
if not requestClaimEvent then
	requestClaimEvent = Instance.new("RemoteEvent")
	requestClaimEvent.Name = "RequestDailyClaim"
	requestClaimEvent.Parent = remotes
end

local claimResultEvent = remotes:FindFirstChild("DailyClaimResult")
if not claimResultEvent then
	claimResultEvent = Instance.new("RemoteEvent")
	claimResultEvent.Name = "DailyClaimResult"
	claimResultEvent.Parent = remotes
end

local COOLDOWN_SECONDS = Economy.DailyRewards.CooldownHours * 3600
local RESET_WINDOW_SECONDS = Economy.DailyRewards.ResetWindowHours * 3600
local CYCLE_LENGTH = Economy.DailyRewards.CycleLength

-- Nu ne bazam pe "miezul noptii" (fus orar diferit per jucator) -- in schimb,
-- trebuie sa treaca macar COOLDOWN_SECONDS de la ultima revendicare ca sa
-- poti revendica din nou, iar daca a trecut mai mult de RESET_WINDOW_SECONDS,
-- inseamna ca ai ratat o zi intreaga si seria se reseteaza la ziua 1.
local function getDailyState(player)
	local lastClaim = player:GetAttribute("DailyLastClaimTimestamp") or 0
	local streakDay = player:GetAttribute("DailyStreakDay") or 0
	local now = os.time()
	local elapsed = now - lastClaim

	if streakDay == 0 then
		return {CanClaim = true, NextDay = 1, SecondsRemaining = 0}
	end

	-- BUG gasit: cand jucatorul e in cooldown, NextDay era setat la
	-- `streakDay` (ziua tocmai revendicata), nu la ziua care urmeaza -- asa
	-- ca ziua abia bifata aparea in UI ca "in curs" (highlight cyan), nu ca
	-- "bifata" (checkmark), fiindca refreshDayCells foloseste NextDay ca
	-- separator intre "bifat" (< NextDay) si "curent" (== NextDay). NextDay
	-- trebuie sa insemne mereu "ziua urmatoare de revendicat", indiferent
	-- daca poate fi revendicata ACUM sau nu -- CanClaim e un flag separat.
	local nextDay = (streakDay % CYCLE_LENGTH) + 1

	if elapsed < COOLDOWN_SECONDS then
		return {CanClaim = false, NextDay = nextDay, SecondsRemaining = COOLDOWN_SECONDS - elapsed}
	end

	if elapsed > RESET_WINDOW_SECONDS then
		return {CanClaim = true, NextDay = 1, SecondsRemaining = 0}
	end

	return {CanClaim = true, NextDay = nextDay, SecondsRemaining = 0}
end

local grantHandlers = {
	Money = function(player, day)
		local leaderstats = player:FindFirstChild("leaderstats")
		local money = leaderstats and leaderstats:FindFirstChild("Money")
		if not money then
			return false
		end
		money.Value += (day.Amount or 0)
		return true
	end,

	RebirthTokens = function(player, day)
		local tokens = player:FindFirstChild("RebirthTokens")
		if not tokens then
			return false
		end
		tokens.Value += (day.Amount or 0)
		return true
	end,

	RandomPet = function(player, day)
		return PetManager.GrantRandomPetByRarity(player, day.Rarity) ~= nil
	end,

	SpecificPet = function(player, day)
		if not day.Pet then
			return false
		end
		return PetManager.GrantSpecificPet(player, day.Pet) ~= nil
	end
}

local function grantReward(player, day)
	local handler = grantHandlers[day.Type]
	if not handler then
		warn("DailyRewardsManager: no grant handler for type '" .. tostring(day.Type) .. "'")
		return false
	end
	return handler(player, day)
end

local function sendStatus(player)
	local state = getDailyState(player)
	statusResultEvent:FireClient(player, {
		CanClaim = state.CanClaim,
		NextDay = state.NextDay,
		SecondsRemaining = state.SecondsRemaining,
		StreakDay = player:GetAttribute("DailyStreakDay") or 0
	})
end

local function doClaim(player)
	local state = getDailyState(player)

	if not state.CanClaim then
		claimResultEvent:FireClient(player, {Success = false, Message = "Not ready yet", SecondsRemaining = state.SecondsRemaining})
		return
	end

	local day = Economy.DailyRewards.Days[state.NextDay]
	if not day then
		claimResultEvent:FireClient(player, {Success = false, Message = "Invalid day"})
		return
	end

	local granted = grantReward(player, day)

	if not granted then
		claimResultEvent:FireClient(player, {Success = false, Message = "Reward grant failed"})
		warn("DailyRewardsManager: failed to grant day " .. state.NextDay .. " reward to " .. player.Name)
		return
	end

	player:SetAttribute("DailyStreakDay", state.NextDay)
	player:SetAttribute("DailyLastClaimTimestamp", os.time())

	DataManager.SaveData(player)

	claimResultEvent:FireClient(player, {
		Success = true,
		Day = state.NextDay,
		Reward = day
	})

	showNotificationEvent:FireClient(player, "🎁 Day " .. state.NextDay .. " reward claimed: " .. (day.Description or ""))

	sendStatus(player)
end

-- Nu impingem status-ul proactiv la PlayerAdded -- ar insemna o cursa cu
-- NPCManager.server.luau (care apeleaza DataManager.ApplyData la randul lui
-- pe PlayerAdded, in alt script, in ordine negarantata). In schimb, clientul
-- cere activ statusul dupa ce stie sigur ca datele au fost aplicate (acelasi
-- WaitForChild("RebirthTokens") folosit si de RebirthShop.client.luau).
requestStatusEvent.OnServerEvent:Connect(sendStatus)
requestClaimEvent.OnServerEvent:Connect(doClaim)
