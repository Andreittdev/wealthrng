-- Fast Roll gamepass ownership, cached per session -- identical shape to
-- LuckPassManager/UltraLuckPassManager (Load/Owns/Grant/Release). Passive
-- always-on perk once owned, no toggle. RollManager reads Owns() to apply
-- FastRollConfig.CooldownMultiplier; the client independently reads
-- OwnsFastRoll off StatsUpdated (see StatsManager.luau) to shorten its own
-- spin/display timing.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FastRollConfig = require(ReplicatedStorage.Modules.FastRollConfig)

local FastRollManager = {}

local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2

local ownsCache: { [Player]: boolean } = {}

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

function FastRollManager.Load(player: Player)
	local ok, owns = attempt(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, FastRollConfig.GamepassId)
	end)

	if ok then
		ownsCache[player] = owns == true
	else
		ownsCache[player] = false
		warn(string.format("[FastRollManager] Failed to check Fast Roll gamepass for %s (%d) after %d attempts", player.Name, player.UserId, RETRY_COUNT))
	end
end

function FastRollManager.Owns(player: Player): boolean
	return ownsCache[player] == true
end

function FastRollManager.Grant(player: Player)
	ownsCache[player] = true
end

function FastRollManager.Release(player: Player)
	ownsCache[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	FastRollManager.Release(player)
end)

return FastRollManager
