-- Grants LARP Battles' weekly "Most Points" leaderboard Top 3 their
-- exclusive reward estates (AssetDatabase's Top1Estate/Top2Estate/
-- Top3Estate) the moment a week rolls over (BattlePointsConfig.
-- GetWeekStart -- Saturday 18:10 GMT+3).
--
-- Cross-server safe: Roblox runs many parallel servers for the same game,
-- so "the week just changed" needs a single shared claim (a small
-- dedicated DataStore, NOT the per-week OrderedDataStore the points
-- themselves live in) so only ONE server actually processes a given
-- week's rewards, not every server that happens to notice the rollover
-- around the same time. Offline players at the exact reset moment get a
-- "pending grant" written to their own key in a separate DataStore,
-- applied the next time they join (see PlayerAdded below).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BattlePointsConfig = require(ReplicatedStorage.Modules.BattlePointsConfig)
local DataManager = require(ServerScriptService.Managers.DataManager)
local AssetManager = require(ServerScriptService.Managers.AssetManager)

local CHECK_INTERVAL_SECONDS = 300
local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2
local POINTS_STORE_PREFIX = "WealthRNG_MostPoints_"

local rewardStateStore = DataStoreService:GetDataStore("WealthRNG_BattleRewardState")
local pendingGrantsStore = DataStoreService:GetDataStore("WealthRNG_PendingAssetGrants")

-- Rank 1/2/3 -> which reward Asset -- kept here (not AssetDatabase) since
-- it's specifically about THIS reward flow, not a general asset property.
-- Only 2 entries -- 3rd place no longer gets a reward Estate. Top3Estate
-- (AssetDatabase.luau's "Sol Stadium") stays in the database as-is (any
-- past winner keeps theirs) -- it's just no longer granted going forward.
local RANK_REWARD_ASSET_IDS = { "Top1Estate", "Top2Estate" }

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

-- Grants immediately if the winner is online right now, else queues it for
-- their next join.
local function grantOrQueue(userId: number, assetId: string)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		local session = DataManager.Get(player)
		if session then
			AssetManager.GrantAsset(player, session, assetId)
			return
		end
	end

	attempt(function()
		pendingGrantsStore:UpdateAsync(tostring(userId), function(existing)
			existing = existing or {}
			table.insert(existing, assetId)
			return existing
		end)
	end)
end

local function processFinishedWeek(finishedWeekKey: string)
	local store = DataStoreService:GetOrderedDataStore(POINTS_STORE_PREFIX .. finishedWeekKey)
	local ok, pages = attempt(function()
		return store:GetSortedAsync(false, 3)
	end)
	if not ok then
		return
	end

	local top = pages:GetCurrentPage()
	for i, entry in top do
		local assetId = RANK_REWARD_ASSET_IDS[i]
		local userId = tonumber(entry.key)
		if assetId and userId then
			grantOrQueue(userId, assetId)
		end
	end
end

-- Timestamp of the most recent week START whose Top 3 rewards have already
-- been processed -- NOT the old key-name/shape ("LastProcessedWeekKey", a
-- date STRING), which could only ever look at the single week right before
-- "now" and silently skipped every other week if a maintenance window (or
-- just no server being up) spanned 2+ Saturday-18:00-GMT+3 boundaries at
-- once. A numeric weekStart can be walked forward in exact 7-day steps
-- instead, so every skipped week in between gets processed too.
local LAST_PROCESSED_KEY = "LastProcessedWeekStart"
local SECONDS_PER_WEEK = 7 * 86400

task.spawn(function()
	while true do
		local currentWeekStart = BattlePointsConfig.GetWeekStart(os.time())

		local ok, lastProcessedWeekStart = attempt(function()
			return rewardStateStore:GetAsync(LAST_PROCESSED_KEY)
		end)

		if ok and lastProcessedWeekStart ~= currentWeekStart then
			if lastProcessedWeekStart then
				-- Atomic claim via UpdateAsync -- if several servers notice
				-- the rollover in the same CHECK_INTERVAL_SECONDS window,
				-- only the one whose write actually lands (stored value
				-- still matches what we just read) proceeds to grant
				-- anything.
				local claimed = false
				attempt(function()
					rewardStateStore:UpdateAsync(LAST_PROCESSED_KEY, function(stored)
						if stored == lastProcessedWeekStart then
							claimed = true
							return currentWeekStart
						end
						return stored
					end)
				end)

				if claimed then
					-- Process every finished week between the last one we
					-- handled and the one that just started -- not just the
					-- single most recent one.
					local weekStart = lastProcessedWeekStart
					while weekStart < currentWeekStart do
						processFinishedWeek(BattlePointsConfig.GetWeekKey(weekStart))
						weekStart += SECONDS_PER_WEEK
					end
				end
			else
				-- First time THIS KEY has ever been set -- NOT necessarily a
				-- brand new game (this key was renamed from the old
				-- "LastProcessedWeekKey" string-keyed version, so an
				-- existing live game hits this branch exactly once too).
				-- Treating it as "nothing to grant yet" would silently skip
				-- the Top 3 for whatever week just finished right before
				-- this first run -- process that one most-recent finished
				-- week (but no further back than that; there's no reliable
				-- way to know how many were actually skipped on a truly
				-- brand new game, and a brand new game has no BattlePoints
				-- yet anyway, so processFinishedWeek finds nothing to grant).
				local claimed = false
				local previousWeekStart = currentWeekStart - SECONDS_PER_WEEK
				attempt(function()
					rewardStateStore:UpdateAsync(LAST_PROCESSED_KEY, function(stored)
						if stored == nil then
							claimed = true
							return currentWeekStart
						end
						return stored
					end)
				end)

				if claimed then
					processFinishedWeek(BattlePointsConfig.GetWeekKey(previousWeekStart))
				end
			end
		end

		task.wait(CHECK_INTERVAL_SECONDS)
	end
end)

-- Applies any pending grant(s) from a week this player was offline for.
local function onPlayerAdded(player: Player)
	task.spawn(function()
		local session
		for _ = 1, 20 do
			session = DataManager.Get(player)
			if session then
				break
			end
			task.wait(0.5)
		end
		if not session then
			return
		end

		local ok, pending = attempt(function()
			return pendingGrantsStore:GetAsync(tostring(player.UserId))
		end)
		if ok and pending then
			for _, assetId in pending do
				AssetManager.GrantAsset(player, session, assetId)
			end
			attempt(function()
				pendingGrantsStore:RemoveAsync(tostring(player.UserId))
			end)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
