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
local GOLDEN_SLOT = 600
local CRASH_SLOT = 2400
local lastSlotProcessed = nil

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

function MarketManager.GetClientData()
	return {
		Categories = MarketManager.CategoryData,
		SpecialEvent = MarketManager.SpecialEvent
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

		local cycleTime = now % CYCLE_LENGTH
		local currentSlot = math.floor(cycleTime / SLOT_INTERVAL) * SLOT_INTERVAL

		if currentSlot ~= lastSlotProcessed then
			lastSlotProcessed = currentSlot

			if currentSlot == GOLDEN_SLOT then
				startGoldenHour()
			elseif currentSlot == CRASH_SLOT then
				startMarketCrash()
			else
				applyNormalUpdate()
			end

			broadcastMarket()
		end

		task.wait(1)
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