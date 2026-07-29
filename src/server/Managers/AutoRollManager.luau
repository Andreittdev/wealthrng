-- Auto Roll gamepass ownership + on/off toggle state, cached per session.
-- Ownership check mirrors VIPManager's shape exactly. Deliberately does NOT
-- require RollManager (which is what actually performs the repeated rolls,
-- via a loop living in RollManager.luau itself) -- StatsManager needs to
-- read Owns() for the StatsUpdated payload, and RollManager already
-- requires StatsManager, so this module has to stay a leaf or that becomes
-- a require cycle (StatsManager -> AutoRollManager -> RollManager ->
-- StatsManager).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AutoRollConfig = require(ReplicatedStorage.Modules.AutoRollConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)

local AutoRollManager = {}

local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2

local ownsCache: { [Player]: boolean } = {}
local enabledCache: { [Player]: boolean } = {}

local setAutoRoll = RemotesBootstrap:WaitForChild("SetAutoRoll")
local autoRollUpdated = RemotesBootstrap:WaitForChild("AutoRollUpdated")

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

function AutoRollManager.Load(player: Player)
	local ok, owns = attempt(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, AutoRollConfig.GamepassId)
	end)

	if ok then
		ownsCache[player] = owns == true
	else
		ownsCache[player] = false
		warn(string.format("[AutoRollManager] Failed to check Auto Roll gamepass for %s (%d) after %d attempts", player.Name, player.UserId, RETRY_COUNT))
	end
end

function AutoRollManager.Owns(player: Player): boolean
	return ownsCache[player] == true
end

function AutoRollManager.Grant(player: Player)
	ownsCache[player] = true
end

function AutoRollManager.Release(player: Player)
	ownsCache[player] = nil
	enabledCache[player] = nil
end

function AutoRollManager.IsEnabled(player: Player): boolean
	return enabledCache[player] == true
end

-- Exposes the full { [Player]: true } table (enabled players only, not a
-- copy) so RollManager's loop can iterate it directly without this module
-- needing to know anything about how rolling actually happens.
function AutoRollManager.GetEnabledPlayers(): { [Player]: boolean }
	return enabledCache
end

setAutoRoll.OnServerEvent:Connect(function(player: Player, enabled: unknown)
	if typeof(enabled) ~= "boolean" then
		return
	end
	if not DataManager.Get(player) then
		return
	end
	if enabled and not AutoRollManager.Owns(player) then
		return
	end

	if enabled then
		enabledCache[player] = true
	else
		enabledCache[player] = nil
	end
	autoRollUpdated:FireClient(player, enabled)
end)

Players.PlayerRemoving:Connect(function(player)
	AutoRollManager.Release(player)
end)

return AutoRollManager
