-- Flex-purchase collection ("Invest" in the UI): buy any number of
-- Investments (via x1/x10/x100 quantity buttons -- one purchase = one
-- entry with a Quantity, not N separate entries), sell any owned entry
-- back at a 50% loss (before VIP's permanent + an active Fortune Potion's
-- temporary cash bonus, same as SellManager.ComputeSellValue -- see the
-- sellInvestment handler below). Server-authoritative price lookups, same
-- shape as AssetManager. Never required by StatsManager -- see
-- IncomeConfig's header.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local InvestmentDatabase = require(ReplicatedStorage.Modules.InvestmentDatabase)
local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local PotionConfig = require(ReplicatedStorage.Modules.PotionConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local VIPManager = require(ServerScriptService.Managers.VIPManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local buyInvestment = RemotesBootstrap:WaitForChild("BuyInvestment")
local sellInvestment = RemotesBootstrap:WaitForChild("SellInvestment")
local investmentUpdated = RemotesBootstrap:WaitForChild("InvestmentUpdated")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local MAX_QUANTITY_PER_PURCHASE = 1000

buyInvestment.OnServerEvent:Connect(function(player: Player, investmentId: string, quantity: unknown)
	if typeof(investmentId) ~= "string" then
		return
	end
	if typeof(quantity) ~= "number" or quantity ~= math.floor(quantity) or quantity < 1 or quantity > MAX_QUANTITY_PER_PURCHASE then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	local investment = InvestmentDatabase.GetInvestment(investmentId)
	if not investment then
		return
	end

	local totalCost = investment.Price * quantity
	if session.Cash < totalCost then
		return
	end

	session.Cash -= totalCost

	local uid = session.NextInvestmentUid
	session.NextInvestmentUid += 1
	table.insert(session.Investments, { Uid = uid, Id = investment.Id, PurchasedAt = os.time(), Quantity = quantity })

	systemMessage:FireClient(player, string.format("Bought %dx %s for %s!", quantity, investment.Name, NumberFormat.FormatCash(totalCost)))
	investmentUpdated:FireClient(player, session.Investments)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

-- `quantity` is how many units of this entry to sell -- omit/invalid means
-- "all of it" (whole-entry sell, the original behavior). Selling fewer
-- than the entry holds just shrinks its Quantity in place (same Uid, same
-- PurchasedAt -- the remaining units keep whatever appreciation they'd
-- already built up); selling all of it (or more than it holds) removes
-- the entry entirely, same as before.
sellInvestment.OnServerEvent:Connect(function(player: Player, uid: number, quantity: unknown)
	if typeof(uid) ~= "number" then
		return
	end
	-- nil (omitted) means "sell the whole entry" -- the original call
	-- shape, kept for backward compatibility. Anything else must be a
	-- valid positive integer; a PRESENT but invalid value (0, negative,
	-- non-integer, wrong type) is rejected outright instead of silently
	-- falling back to "sell everything" -- that used to be the behavior
	-- for any invalid value, which meant an accidental bad value (e.g. a
	-- UI bug computing quantity = 0) could sell a player's entire
	-- investment instead of just failing as a no-op.
	if quantity ~= nil and (typeof(quantity) ~= "number" or quantity ~= math.floor(quantity) or quantity < 1) then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	for index, entry in session.Investments do
		if entry.Uid == uid then
			local sellQuantity = entry.Quantity
			if quantity ~= nil then
				sellQuantity = math.min(quantity :: number, entry.Quantity)
			end

			-- VIP's permanent sell bonus and an active Fortune Potion's
			-- temporary one now apply here too (same formula as SellManager.
			-- ComputeSellValue) -- Investments used to be the one payout path
			-- that ignored both entirely, which made Fortune Potion feel
			-- pointless for anyone whose main income was Investments rather
			-- than Item sells/Asset rent.
			local perUnitValue = InvestmentDatabase.ComputeCurrentValue(entry.Id, entry.PurchasedAt, os.time())
			local bonusPercent = PotionConfig.GetCashBonusPercent(session, os.time())
			if VIPManager.IsVIP(player) then
				bonusPercent += VIPConfig.SellBonusPercent
			end
			local payout = math.floor(perUnitValue * sellQuantity * 0.5 * (1 + bonusPercent / 100))
			session.Cash += payout

			if sellQuantity >= entry.Quantity then
				table.remove(session.Investments, index)
			else
				entry.Quantity -= sellQuantity
			end

			local investment = InvestmentDatabase.GetInvestment(entry.Id)
			if investment then
				systemMessage:FireClient(player, string.format("Sold %dx %s for %s!", sellQuantity, investment.Name, NumberFormat.FormatCash(payout)))
			end

			investmentUpdated:FireClient(player, session.Investments)
			StatsManager.Recompute(player)
			LeaderboardManager.MarkDirty(player)
			return
		end
	end
end)

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
