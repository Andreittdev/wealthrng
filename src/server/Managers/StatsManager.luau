-- Recomputes Cash / NetWorth / Title / IsVIP / OwnsAutoRoll /
-- ItemsIncomePerSecond / AssetsIncomePerMinute after any
-- mutation (roll, sell, VIP purchase, income tick, asset/investment trade)
-- and pushes to the client + leaderstats only when something actually
-- changed. Reads AssetDatabase/InvestmentDatabase directly (pure shared
-- lookups against session.OwnedAssets/session.Investments) instead of requiring
-- AssetManager/InvestmentManager, since those call StatsManager.Recompute
-- themselves -- same cycle-avoidance as IncomeConfig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TitleConfig = require(ReplicatedStorage.Modules.TitleConfig)
local IncomeConfig = require(ReplicatedStorage.Modules.IncomeConfig)
local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local PotionConfig = require(ReplicatedStorage.Modules.PotionConfig)
local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local InvestmentDatabase = require(ReplicatedStorage.Modules.InvestmentDatabase)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local Leaderstats = require(ServerScriptService.Managers.Leaderstats)
local VIPManager = require(ServerScriptService.Managers.VIPManager)
local AutoRollManager = require(ServerScriptService.Managers.AutoRollManager)
local AutoClaimManager = require(ServerScriptService.Managers.AutoClaimManager)

local statsUpdated = RemotesBootstrap:WaitForChild("StatsUpdated")

local StatsManager = {}

local lastStats: { [Player]: { Cash: number, NetWorth: number, Title: string, IsVIP: boolean, OwnsAutoRoll: boolean, OwnsAutoClaim: boolean, ItemsIncomePerSecond: number, AssetsIncomePerMinute: number } } = {}

local function getAssetsValue(session): number
	local total = 0
	for id, owned in session.OwnedAssets do
		if owned then
			local asset = AssetDatabase.GetAsset(id)
			if asset then
				total += asset.Price
			end
		end
	end
	return total
end

local function getInvestmentValue(session): number
	local total = 0
	local now = os.time()
	for _, entry in session.Investments do
		total += InvestmentDatabase.ComputeEntryValue(entry, now)
	end
	return total
end

-- Exposed so other managers (e.g. TradeManager's Net Worth gate) can read
-- a fresh Net Worth without duplicating this formula -- read-only, doesn't
-- push anything or touch lastStats, unlike Recompute.
function StatsManager.ComputeNetWorth(player: Player): number
	local session = DataManager.Get(player)
	if not session then
		return 0
	end
	return session.Cash + InventoryManager.GetValue(player) + getAssetsValue(session) + getInvestmentValue(session)
end

function StatsManager.Recompute(player: Player)
	local session = DataManager.Get(player)
	if not session then
		return
	end

	local netWorth = StatsManager.ComputeNetWorth(player)
	local title = TitleConfig.GetTitleForNetWorth(netWorth)
	local isVIP = VIPManager.IsVIP(player)
	local ownsAutoRoll = AutoRollManager.Owns(player)
	local ownsAutoClaim = AutoClaimManager.Owns(player)
	local bonusArgs = { isVIP, VIPConfig.SellBonusPercent, PotionConfig.GetCashBonusPercent(session, os.time()) }
	local itemsIncomePerSecond = IncomeConfig.ComputeItemsRatePerSecond(session, table.unpack(bonusArgs))
	local assetsIncomePerMinute = IncomeConfig.ComputeAssetsRatePerMinute(session, table.unpack(bonusArgs))

	local previous = lastStats[player]
	if
		previous
		and previous.Cash == session.Cash
		and previous.NetWorth == netWorth
		and previous.Title == title
		and previous.IsVIP == isVIP
		and previous.OwnsAutoRoll == ownsAutoRoll
		and previous.OwnsAutoClaim == ownsAutoClaim
		and previous.ItemsIncomePerSecond == itemsIncomePerSecond
		and previous.AssetsIncomePerMinute == assetsIncomePerMinute
	then
		return
	end

	lastStats[player] = {
		Cash = session.Cash,
		NetWorth = netWorth,
		Title = title,
		IsVIP = isVIP,
		OwnsAutoRoll = ownsAutoRoll,
		OwnsAutoClaim = ownsAutoClaim,
		ItemsIncomePerSecond = itemsIncomePerSecond,
		AssetsIncomePerMinute = assetsIncomePerMinute,
	}
	Leaderstats.SetCash(player, session.Cash)
	statsUpdated:FireClient(player, lastStats[player])
end

return StatsManager
