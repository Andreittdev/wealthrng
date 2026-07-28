-- Handles BuyUpgrade: server-authoritative level-up, one level per call.
-- Never required by RollManager/PotionManager (which read effects via the
-- shared UpgradeConfig) -- same circular-require avoidance as VIP/Potions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local buyUpgrade = RemotesBootstrap:WaitForChild("BuyUpgrade")
local upgradesUpdated = RemotesBootstrap:WaitForChild("UpgradesUpdated")

buyUpgrade.OnServerEvent:Connect(function(player: Player, trackId: unknown)
	if typeof(trackId) ~= "string" or not UpgradeConfig.Tracks[trackId] then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	local currentLevel = session.Upgrades[trackId] or 0
	local cost = UpgradeConfig.GetCost(trackId, currentLevel)
	if not cost or session.Cash < cost then
		return
	end

	session.Cash -= cost
	session.Upgrades[trackId] = currentLevel + 1

	upgradesUpdated:FireClient(player, session.Upgrades)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
