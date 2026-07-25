-- VIP gamepass ownership, cached per session. Mirrors DataManager's
-- retry-wrapped-async + in-memory-cache shape, applied to
-- MarketplaceService instead of DataStoreService. No internal event
-- connections here (kept a leaf module) -- Main.server.luau owns
-- PromptGamePassPurchaseFinished to avoid a VIPManager <-> StatsManager
-- circular require.

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)

local VIPManager = {}

local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2

local vipCache: { [Player]: boolean } = {}

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

function VIPManager.Load(player: Player)
	local ok, owns = attempt(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, VIPConfig.GamepassId)
	end)

	if ok then
		vipCache[player] = owns == true
	else
		vipCache[player] = false
		warn(string.format("[VIPManager] Failed to check VIP gamepass for %s (%d) after %d attempts", player.Name, player.UserId, RETRY_COUNT))
	end
end

function VIPManager.IsVIP(player: Player): boolean
	return vipCache[player] == true
end

function VIPManager.Grant(player: Player)
	vipCache[player] = true
end

function VIPManager.Release(player: Player)
	vipCache[player] = nil
end

return VIPManager
