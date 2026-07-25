-- Flex-purchase collection ("Invest" in the UI): buy any number of
-- Investments, sell any owned one back at a 50% loss. Server-authoritative
-- price lookups, same shape as AssetManager. Never required by
-- StatsManager -- see IncomeConfig's header.

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

buyInvestment.OnServerEvent:Connect(function(player: Player, investmentId: string)
	if typeof(investmentId) ~= "string" then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	local investment = InvestmentDatabase.GetInvestment(investmentId)
	if not investment or session.Cash < investment.Price then
		return
	end

	session.Cash -= investment.Price

	local uid = session.NextInvestmentUid
	session.NextInvestmentUid += 1
	table.insert(session.Investments, { Uid = uid, Id = investment.Id, PurchasedAt = os.time() })

	investmentUpdated:FireClient(player, session.Investments)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

sellInvestment.OnServerEvent:Connect(function(player: Player, uid: number)
	if typeof(uid) ~= "number" then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	for index, entry in session.Investments do
		if entry.Uid == uid then
			table.remove(session.Investments, index)

			local currentValue = InvestmentDatabase.ComputeCurrentValue(entry.Id, entry.PurchasedAt, os.time())
			session.Cash += math.floor(currentValue * 0.5)

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
