-- Double Cash gamepass ownership, cached per session -- identical shape to
-- LuckPassManager/UltraLuckPassManager/FastRollManager (Load/Owns/Grant/
-- Release). Passive always-on perk once owned, no toggle. Deliberately does
-- NOT require SellManager/StatsManager/IncomeManager -- same leaf-module
-- reasoning as every other pass manager's header.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DoubleCashConfig = require(ReplicatedStorage.Modules.DoubleCashConfig)

local DoubleCashManager = {}

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

function DoubleCashManager.Load(player: Player)
	local ok, owns = attempt(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, DoubleCashConfig.GamepassId)
	end)

	if ok then
		ownsCache[player] = owns == true
	else
		ownsCache[player] = false
		warn(string.format("[DoubleCashManager] Failed to check Double Cash gamepass for %s (%d) after %d attempts", player.Name, player.UserId, RETRY_COUNT))
	end
end

function DoubleCashManager.Owns(player: Player): boolean
	return ownsCache[player] == true
end

-- Convenience for the bonus-stacking call sites (SellManager/IncomeManager/
-- StatsManager) -- they all want "0 or BonusPercent", not a raw boolean.
function DoubleCashManager.GetBonusPercent(player: Player): number
	if DoubleCashManager.Owns(player) then
		return DoubleCashConfig.BonusPercent
	end
	return 0
end

function DoubleCashManager.Grant(player: Player)
	ownsCache[player] = true
end

function DoubleCashManager.Release(player: Player)
	ownsCache[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	DoubleCashManager.Release(player)
end)

return DoubleCashManager
