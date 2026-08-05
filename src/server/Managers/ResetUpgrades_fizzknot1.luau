-- ONE-TIME test reset, explicitly requested: wipe fizzknot1's 3 Upgrade
-- tracks back to level 0 so the new "grape cluster" Upgrades UI can be
-- tested growing from scratch. Guarded by a claim (same cross-server
-- UpdateAsync compare-and-swap pattern used elsewhere in this codebase) so
-- it can only ever actually apply once, across every server, ever -- safe
-- to leave this module in permanently.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)

local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2

local TARGET_USERNAME = "fizzknot1"

local migrationStateStore = DataStoreService:GetDataStore("WealthRNG_OneTimeMigrations")
local MIGRATION_KEY = "ResetUpgrades_fizzknot1_v1"

local upgradesUpdated = RemotesBootstrap:WaitForChild("UpgradesUpdated")

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
		warn("[ResetUpgrades_fizzknot1] Could not resolve " .. TARGET_USERNAME .. " to a UserId -- releasing claim to retry later.")
		attempt(function()
			migrationStateStore:RemoveAsync(MIGRATION_KEY)
		end)
		return
	end

	local onlinePlayer = Players:GetPlayerByUserId(userId)
	local session = onlinePlayer and DataManager.Get(onlinePlayer)

	if session then
		session.Upgrades = {}
		upgradesUpdated:FireClient(onlinePlayer, session.Upgrades)
		StatsManager.Recompute(onlinePlayer)
	else
		DataManager.PatchOfflineSession(userId, function(data)
			data.Upgrades = {}
		end)
	end
end)

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
