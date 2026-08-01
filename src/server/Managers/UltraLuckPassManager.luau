-- Ultra Luck Pass gamepass ownership, cached per session -- identical shape
-- to LuckPassManager (Load/Owns/Grant/Release), just a separate gamepass/
-- cache. Passive always-on perk once owned, no toggle.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UltraLuckPassConfig = require(ReplicatedStorage.Modules.UltraLuckPassConfig)

local UltraLuckPassManager = {}

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

function UltraLuckPassManager.Load(player: Player)
	local ok, owns = attempt(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, UltraLuckPassConfig.GamepassId)
	end)

	if ok then
		ownsCache[player] = owns == true
	else
		ownsCache[player] = false
		warn(string.format("[UltraLuckPassManager] Failed to check Ultra Luck Pass gamepass for %s (%d) after %d attempts", player.Name, player.UserId, RETRY_COUNT))
	end
end

function UltraLuckPassManager.Owns(player: Player): boolean
	return ownsCache[player] == true
end

function UltraLuckPassManager.Grant(player: Player)
	ownsCache[player] = true
end

function UltraLuckPassManager.Release(player: Player)
	ownsCache[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	UltraLuckPassManager.Release(player)
end)

return UltraLuckPassManager
