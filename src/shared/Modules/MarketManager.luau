local Economy = require(script.Parent:WaitForChild("EconomyConfig"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local marketUpdateEvent = remotes:WaitForChild("MarketUpdate")

local MarketManager = {}

local CATEGORIES = {"Clothing", "Shoes", "Electronics", "Luxury", "Collectibles"}

MarketManager.CategoryData = {}
MarketManager.Categories = MarketManager.CategoryData

MarketManager.SpecialEvent = {Type = "None"}

for _, category in ipairs(CATEGORIES) do
	MarketManager.CategoryData[category] = {
		Multiplier = 1,
		Percent = 0,
		Trend = "Stable"
	}
end

local CYCLE_LENGTH = 3600
local SLOT_INTERVAL = 600
local SLOTS = {0, 600, 1200, 1800, 2400, 3000}
local lastSlotProcessed = nil

-- Golden Hour si Market Crash NU mai sunt mereu pe aceleasi sloturi (:10 si
-- :40 din fiecare ora) -- fiecare "ciclu" (ora) de CYCLE_LENGTH secunde are
-- doua sloturi alese ALEATORIU (diferite intre ele) din cele 6 disponibile.
-- Random.new(cycleIndex) e determinist -- acelasi index de ciclu produce
-- MEREU aceeasi alegere, deci orice cod poate recalcula "ce e programat in
-- ciclul N" oricand, fara sa tina stare separata (functioneaza corect si
-- daca serverul reporneste la mijlocul unui ciclu).
local function getCycleSlots(cycleIndex)
	local rng = Random.new(cycleIndex)
	local shuffled = table.clone(SLOTS)

	for i = #shuffled, 2, -1 do
		local j = rng:NextInteger(1, i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	return {GoldenHour = shuffled[1], MarketCrash = shuffled[2]}
end

local function getCycleIndex(time)
	return math.floor(time / CYCLE_LENGTH)
end

local function getTrendFromPercent(percent)
	if percent > 3 then
		return "Rising"
	elseif percent < -3 then
		return "Falling"
	else
		return "Stable"
	end
end

local function clamp(value, min, max)
	return math.max(min, math.min(max, value))
end

local function setCategoryPercent(category, percent)
	local data = MarketManager.CategoryData[category]
	if not data then return end

	percent = clamp(percent, -Economy.Market.MaxPriceDeviation, Economy.Market.MaxPriceDeviation)

	data.Percent = percent
	data.Multiplier = 1 + percent / 100
	data.Trend = getTrendFromPercent(percent)
end

local function applyNormalUpdate()
	for _, category in ipairs(CATEGORIES) do
		local change = math.random(-Economy.Market.NormalVariance, Economy.Market.NormalVariance)
		setCategoryPercent(category, change)
		print("MARKET:", category, change, MarketManager.CategoryData[category].Trend)
	end
end

local function startGoldenHour()
	for _, category in ipairs(CATEGORIES) do
		setCategoryPercent(category, 0)
	end

	local category = CATEGORIES[math.random(1, #CATEGORIES)]
	setCategoryPercent(category, Economy.Market.GoldenHour.Boost)

	MarketManager.SpecialEvent = {
		Type = "GoldenHour",
		Category = category,
		StartTime = os.time(),
		EndTime = os.time() + Economy.Market.GoldenHour.Duration
	}

	print("[Market] GOLDEN HOUR:", category, "+" .. Economy.Market.GoldenHour.Boost .. "%")
end

local function startMarketCrash()
	for _, category in ipairs(CATEGORIES) do
		setCategoryPercent(category, 0)
	end

	local category = CATEGORIES[math.random(1, #CATEGORIES)]
	setCategoryPercent(category, -Economy.Market.MarketCrash.Drop)

	MarketManager.SpecialEvent = {
		Type = "MarketCrash",
		Category = category,
		StartTime = os.time(),
		EndTime = os.time() + Economy.Market.MarketCrash.Duration
	}

	print("[Market] MARKET CRASH:", category, "-" .. Economy.Market.MarketCrash.Drop .. "%")
end

local function endEvent()
	print("[Market] Event ended:", MarketManager.SpecialEvent.Type)
	MarketManager.SpecialEvent = {Type = "None"}
end

function MarketManager.GetCategoryMultiplier(category)
	local data = MarketManager.CategoryData[category]
	return data and data.Multiplier or 1
end

function MarketManager.GetMultiplier(category)
	return MarketManager.GetCategoryMultiplier(category)
end

-- Procentul BRUT (poate fi negativ) -- folosit de Auto Sell Pass ca sa
-- decida daca o categorie e chiar "pe plus" (>= +1%) inainte sa vanda
-- automat un item din ea, nu doar multiplicatorul (1 + percent/100).
function MarketManager.GetCategoryPercent(category)
	local data = MarketManager.CategoryData[category]
	return data and data.Percent or 0
end

function MarketManager.GetTrend(category)
	local data = MarketManager.CategoryData[category]
	return data and data.Trend or "Stable"
end

function MarketManager.GetTrendName(category)
	return MarketManager.GetTrend(category)
end

function MarketManager.GetSpecialEvent()
	return MarketManager.SpecialEvent
end

function MarketManager.GetFinalMarketMultiplier(category, purchaseTime)
	local multiplier = MarketManager.GetCategoryMultiplier(category)
	local event = MarketManager.SpecialEvent

	if event.Type ~= "None" and event.Category == category then
		local eligible = false

		if purchaseTime and purchaseTime > 0 then
			eligible = (os.time() - purchaseTime) >= (Economy.Market.AntiAbuseHoldTime or 900)
		end

		if not eligible then
			multiplier = 1
		end
	end

	return multiplier
end

function MarketManager.GetSellPrice(baseValue, category, purchaseTime)
	return math.floor(baseValue * MarketManager.GetFinalMarketMultiplier(category, purchaseTime))
end

function MarketManager.GetNews()
	local event = MarketManager.SpecialEvent

	if event.Type == "GoldenHour" then
		return "✨ Golden Hour: " .. (event.Category or "") .. " is booming!"
	elseif event.Type == "MarketCrash" then
		return "📉 Market Crash: " .. (event.Category or "") .. " is crashing!"
	end

	return ""
end

-- Timpul real ramas pana la urmatorul slot (orice update, nu doar
-- Golden Hour/Crash) -- clientul (MarketGui) foloseste asta ca sa isi
-- porneasca countdown-ul de la valoarea CORECTA, nu de la un 10:00 fix.
-- BUG vechi: MarketGui reseta mereu la marketUpdateTime (600) fix, in loc sa
-- afle cat a mai ramas cu adevarat din slot-ul curent -- daca jucatorul se
-- alatura sau deschide market-ul la mijlocul unui slot, countdown-ul lui
-- arata gresit (prea mult), desincronizat fata de orarul real al serverului.
function MarketManager.GetSecondsUntilNextUpdate()
	local cycleTime = os.time() % SLOT_INTERVAL
	return SLOT_INTERVAL - cycleTime
end

-- Cat mai e pana la urmatoarea aparitie a lui `eventType` (GoldenHour sau
-- MarketCrash) -- se poate intampla in ciclul curent (daca slotul lui nu a
-- trecut inca) sau in ciclul URMATOR (daca a trecut deja) -- ambele cazuri
-- calculate direct, fara sa fie nevoie sa "stim dinainte" ciclul urmator,
-- pentru ca getCycleSlots e determinist.
local function secondsUntilEvent(eventType)
	local now = os.time()
	local cycleIndex = getCycleIndex(now)
	local cycleTime = now % CYCLE_LENGTH
	local targetSlot = getCycleSlots(cycleIndex)[eventType]

	if cycleTime < targetSlot then
		return targetSlot - cycleTime
	end

	local nextTargetSlot = getCycleSlots(cycleIndex + 1)[eventType]
	return (CYCLE_LENGTH - cycleTime) + nextTargetSlot
end

-- SINGURA sursa de adevar pentru countdown-ul de Golden Hour/Market Crash --
-- folosita DIRECT atat de tunel (server) cat si trimisa la MarketGui
-- (client), ca sa arate EXACT acelasi numar, mereu. Fara asta, fiecare parte
-- isi calcula propriul countdown, separat -- usor sa ajunga desincronizate.
function MarketManager.GetEventCountdown()
	local event = MarketManager.SpecialEvent

	if event.Type ~= "None" and event.EndTime then
		return {
			Active = true,
			Type = event.Type,
			SecondsLeft = math.max(0, math.floor(event.EndTime - os.time()))
		}
	end

	local goldenIn = secondsUntilEvent("GoldenHour")
	local crashIn = secondsUntilEvent("MarketCrash")

	if goldenIn <= crashIn then
		return {Active = false, Type = "GoldenHour", SecondsLeft = goldenIn}
	end

	return {Active = false, Type = "MarketCrash", SecondsLeft = crashIn}
end

function MarketManager.GetClientData()
	return {
		Categories = MarketManager.CategoryData,
		SpecialEvent = MarketManager.SpecialEvent,
		SecondsUntilNextUpdate = MarketManager.GetSecondsUntilNextUpdate(),
		EventCountdown = MarketManager.GetEventCountdown()
	}
end

local function broadcastMarket()
	marketUpdateEvent:FireAllClients(MarketManager.GetClientData())
end

local function marketLoop()
	while true do
		local now = os.time()

		if MarketManager.SpecialEvent.Type ~= "None"
			and MarketManager.SpecialEvent.EndTime
			and now >= MarketManager.SpecialEvent.EndTime
		then
			endEvent()
			broadcastMarket()
		end

		local cycleIndex = getCycleIndex(now)
		local cycleTime = now % CYCLE_LENGTH
		local currentSlot = math.floor(cycleTime / SLOT_INTERVAL) * SLOT_INTERVAL
		local slots = getCycleSlots(cycleIndex)

		if currentSlot ~= lastSlotProcessed then
			lastSlotProcessed = currentSlot

			if currentSlot == slots.GoldenHour then
				startGoldenHour()
			elseif currentSlot == slots.MarketCrash then
				startMarketCrash()
			else
				applyNormalUpdate()
			end

			broadcastMarket()
		end

		-- 0.25s (nu 1s) -- GetEventCountdown poate fi interogat de un client
		-- chiar in secunda in care cycleTime trece de un slot, dar INAINTE ca
		-- bucla asta sa fi apucat sa seteze SpecialEvent -- fereastra aia de
		-- lag e cat intervalul de poll. Micsorata la 0.25s ca sa nu mai fie
		-- vizibila (flicker de countdown la inceputul fiecarui eveniment).
		task.wait(0.25)
	end
end

applyNormalUpdate()
task.spawn(marketLoop)

local getMarketDataFunction = remotes:FindFirstChild("GetMarketData")
if not getMarketDataFunction then
	getMarketDataFunction = Instance.new("RemoteFunction")
	getMarketDataFunction.Name = "GetMarketData"
	getMarketDataFunction.Parent = remotes
end

getMarketDataFunction.OnServerInvoke = function(player)
	return MarketManager.GetClientData()
end

return MarketManager