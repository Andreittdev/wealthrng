-- Luck Pass gamepass ownership, cached per session -- same shape as
-- AutoRollManager (Load/Owns/Grant/Release). No toggle: unlike Auto Roll/
-- Auto Claim, this is a passive always-on perk once owned, so there's no
-- SetXxx remote here, just the ownership cache RollManager.pickRarity reads.
-- Deliberately does NOT require RollManager or StatsManager -- same leaf-
-- module reasoning as AutoRollManager's header.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LuckPassConfig = require(ReplicatedStorage.Modules.LuckPassConfig)

local LuckPassManager = {}

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

function LuckPassManager.Load(player: Player)
	local ok, owns = attempt(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, LuckPassConfig.GamepassId)
	end)

	if ok then
		ownsCache[player] = owns == true
	else
		ownsCache[player] = false
		warn(string.format("[LuckPassManager] Failed to check Luck Pass gamepass for %s (%d) after %d attempts", player.Name, player.UserId, RETRY_COUNT))
	end
end

function LuckPassManager.Owns(player: Player): boolean
	return ownsCache[player] == true
end

function LuckPassManager.Grant(player: Player)
	ownsCache[player] = true
end

function LuckPassManager.Release(player: Player)
	ownsCache[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	LuckPassManager.Release(player)
end)

return LuckPassManager
