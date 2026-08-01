-- Passive income, two independent timers (see IncomeConfig's header for
-- why they're not merged): items tick continuously every
-- ITEMS_TICK_INTERVAL_SECONDS, Assets pay out a lump sum once every
-- ASSETS_PAYOUT_INTERVAL_SECONDS ("collect rent"). Rate math lives in the
-- shared IncomeConfig so StatsManager can display the same numbers without
-- requiring this module -- see IncomeConfig's header for why.
-- Online-only -- no offline/away-time accrual in this pass.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local IncomeConfig = require(ReplicatedStorage.Modules.IncomeConfig)
local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local PotionConfig = require(ReplicatedStorage.Modules.PotionConfig)
local DataManager = require(ServerScriptService.Managers.DataManager)
local VIPManager = require(ServerScriptService.Managers.VIPManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)
local FriendBoostManager = require(ServerScriptService.Managers.FriendBoostManager)
local DoubleCashManager = require(ServerScriptService.Managers.DoubleCashManager)

local IncomeManager = {}

local ITEMS_TICK_INTERVAL_SECONDS = 3
local ASSETS_PAYOUT_INTERVAL_SECONDS = 60

task.spawn(function()
	while true do
		task.wait(ITEMS_TICK_INTERVAL_SECONDS)
		for _, player in Players:GetPlayers() do
			local session = DataManager.Get(player)
			if session then
				local rate = IncomeConfig.ComputeItemsRatePerSecond(
					session,
					VIPManager.IsVIP(player),
					VIPConfig.SellBonusPercent,
					PotionConfig.GetCashBonusPercent(session, os.time()),
					FriendBoostManager.GetBonusPercent(player),
					DoubleCashManager.GetBonusPercent(player)
				)
				if rate > 0 then
					session.Cash += math.floor(rate * ITEMS_TICK_INTERVAL_SECONDS)
					StatsManager.Recompute(player)
					LeaderboardManager.MarkDirty(player)
				end
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(ASSETS_PAYOUT_INTERVAL_SECONDS)
		for _, player in Players:GetPlayers() do
			local session = DataManager.Get(player)
			if session then
				local payout = IncomeConfig.ComputeAssetsRatePerMinute(
					session,
					VIPManager.IsVIP(player),
					VIPConfig.SellBonusPercent,
					PotionConfig.GetCashBonusPercent(session, os.time()),
					FriendBoostManager.GetBonusPercent(player),
					DoubleCashManager.GetBonusPercent(player)
				)
				if payout > 0 then
					session.Cash += math.floor(payout)
					StatsManager.Recompute(player)
					LeaderboardManager.MarkDirty(player)
				end
			end
		end
	end
end)

return IncomeManager
