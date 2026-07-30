-- Auto Roll gamepass ownership, cached per session. Ownership check
-- mirrors VIPManager's shape exactly. The actual auto-rolling loop lives
-- entirely on the client (RollPanel.luau) once it's confirmed enabled here
-- -- this module only validates the SetAutoRoll toggle (rejecting it if
-- the player doesn't actually own the gamepass) and echoes the real state
-- back via AutoRollUpdated; it doesn't need to remember whether a player
-- currently has it on for anything else. Deliberately does NOT require
-- RollManager -- StatsManager needs to read Owns() for the StatsUpdated
-- payload, and RollManager already requires StatsManager, so this module
-- has to stay a leaf or that becomes a require cycle (StatsManager ->
-- AutoRollManager -> RollManager -> StatsManager).

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

	autoRollUpdated:FireClient(player, enabled)
end)

Players.PlayerRemoving:Connect(function(player)
	AutoRollManager.Release(player)
end)

return AutoRollManager
