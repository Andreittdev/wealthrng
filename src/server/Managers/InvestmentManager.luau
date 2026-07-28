-- Flex-purchase collection ("Invest" in the UI): buy any number of
-- Investments (via x1/x10/x100 quantity buttons -- one purchase = one
-- entry with a Quantity, not N separate entries), sell any owned entry
-- back at a 50% loss. Server-authoritative price lookups, same shape as
-- AssetManager. Never required by StatsManager -- see IncomeConfig's header.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local InvestmentDatabase = require(ReplicatedStorage.Modules.InvestmentDatabase)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local buyInvestment = RemotesBootstrap:WaitForChild("BuyInvestment")
local sellInvestment = RemotesBootstrap:WaitForChild("SellInvestment")
local investmentUpdated = RemotesBootstrap:WaitForChild("InvestmentUpdated")

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

	local session = DataManager.Get(player)
	if not session then
		return
	end

	for index, entry in session.Investments do
		if entry.Uid == uid then
			local sellQuantity = entry.Quantity
			if typeof(quantity) == "number" and quantity == math.floor(quantity) and quantity >= 1 then
				sellQuantity = math.min(quantity, entry.Quantity)
			end

			local perUnitValue = InvestmentDatabase.ComputeCurrentValue(entry.Id, entry.PurchasedAt, os.time())
			session.Cash += math.floor(perUnitValue * sellQuantity * 0.5)

			if sellQuantity >= entry.Quantity then
				table.remove(session.Investments, index)
			else
				entry.Quantity -= sellQuantity
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
