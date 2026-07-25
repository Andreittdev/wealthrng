-- Passive income: every TICK_INTERVAL_SECONDS, each online player earns
-- cash from whatever's currently sitting unsold in their inventory (rate
-- math lives in the shared IncomeConfig so StatsManager can display the
-- same number without requiring this module -- see IncomeConfig's header
-- for why). Online-only -- no offline/away-time accrual in this pass.

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

local IncomeManager = {}

local TICK_INTERVAL_SECONDS = 3

task.spawn(function()
	while true do
		task.wait(TICK_INTERVAL_SECONDS)
		for _, player in Players:GetPlayers() do
			local session = DataManager.Get(player)
			if session then
				local rate = IncomeConfig.ComputeRate(session, VIPManager.IsVIP(player), VIPConfig.SellBonusPercent, PotionConfig.GetCashBonusPercent(session, os.time()))
				if rate > 0 then
					session.Cash += math.floor(rate * TICK_INTERVAL_SECONDS)
					StatsManager.Recompute(player)
					LeaderboardManager.MarkDirty(player)
				end
			end
		end
	end
end)

return IncomeManager
