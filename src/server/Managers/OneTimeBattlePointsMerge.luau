-- ONE-TIME correction, explicitly requested: xxPanick956xx had 12 points on
-- LARP Battles' "Most Points" weekly leaderboard right before it reset at
-- the normal Saturday 18:00 GMT+3 boundary -- this just gives that back to
-- him on the new week's board, once. The recurring weekly reset itself is
-- untouched -- next Saturday still resets everyone to 0 same as always.
-- Guarded by a claim (same cross-server UpdateAsync compare-and-swap
-- pattern used elsewhere in this codebase) so it can only ever actually
-- apply once, across every server, ever -- safe to leave this module in
-- permanently.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BattlePointsConfig = require(ReplicatedStorage.Modules.BattlePointsConfig)
local DataManager = require(ServerScriptService.Managers.DataManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2
local POINTS_STORE_PREFIX = "WealthRNG_MostPoints_"

local TARGET_USERNAME = "xxPanick956xx"
local TARGET_POINTS = 12

local migrationStateStore = DataStoreService:GetDataStore("WealthRNG_OneTimeMigrations")
local MIGRATION_KEY = "GivePoints_xxPanick956xx_12"

local function attempt(fn): (boolean, any)
	for i = 1, RETRY_COUNT do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if i < RETRY_COUNT then
			task.wait(RETRY_BACKOFF_SECONDS)
		end
	end
	return false, nil
end

task.spawn(function()
	local ok, alreadyDone = attempt(function()
		return migrationStateStore:GetAsync(MIGRATION_KEY)
	end)
	if not ok or alreadyDone then
		return
	end

	local claimed = false
	attempt(function()
		migrationStateStore:UpdateAsync(MIGRATION_KEY, function(stored)
			if stored then
				return stored
			end
			claimed = true
			return true
		end)
	end)
	if not claimed then
		return
	end

	local userIdOk, userId = attempt(function()
		return Players:GetUserIdFromNameAsync(TARGET_USERNAME)
	end)
	if not userIdOk or not userId then
		warn("[OneTimeBattlePointsMerge] Could not resolve " .. TARGET_USERNAME .. " to a UserId -- releasing claim to retry later.")
		attempt(function()
			migrationStateStore:RemoveAsync(MIGRATION_KEY)
		end)
		return
	end

	local currentWeekStart = BattlePointsConfig.GetWeekStart(os.time())
	local onlinePlayer = Players:GetPlayerByUserId(userId)
	local session = onlinePlayer and DataManager.Get(onlinePlayer)

	if session then
		BattlePointsConfig.EnsureCurrentWeek(session)
		session.BattlePoints = TARGET_POINTS
		LeaderboardManager.MarkDirty(onlinePlayer)
	else
		DataManager.PatchOfflineSession(userId, function(data)
			data.BattlePoints = TARGET_POINTS
			data.BattlePointsWeekStart = currentWeekStart
		end)

		-- PatchOfflineSession above only fixes what loads the NEXT time he
		-- logs in -- the physical board reads straight from the current
		-- week's OrderedDataStore, so it needs its own direct write too or
		-- it won't show up until then.
		local currentWeekStore = DataStoreService:GetOrderedDataStore(POINTS_STORE_PREFIX .. BattlePointsConfig.GetWeekKey(currentWeekStart))
		attempt(function()
			currentWeekStore:SetAsync(tostring(userId), TARGET_POINTS)
		end)
	end
end)

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
