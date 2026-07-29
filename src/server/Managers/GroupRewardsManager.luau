-- One-time free item for being in the game's Roblox group (see
-- GroupRewardsConfig.luau) -- claimed by standing near the plaza's blue
-- "Group Rewards" floor marker (MapBuilder's buildFloorMarker) and pressing
-- Claim in GroupRewardsProximityPanel.luau. Player:IsInGroup is checked
-- again here (never trust the client's own copy of that check) and
-- session.ClaimedGroupReward gates it to exactly once per save, even if the
-- player leaves the group afterward.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GroupRewardsConfig = require(ReplicatedStorage.Modules.GroupRewardsConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local claimGroupReward = RemotesBootstrap:WaitForChild("ClaimGroupReward")
local groupRewardStateUpdated = RemotesBootstrap:WaitForChild("GroupRewardStateUpdated")
local inventoryUpdated = RemotesBootstrap:WaitForChild("InventoryUpdated")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

claimGroupReward.OnServerEvent:Connect(function(player: Player)
	local session = DataManager.Get(player)
	if not session then
		return
	end

	if session.ClaimedGroupReward then
		return
	end

	local ok, inGroup = pcall(function()
		return player:IsInGroup(GroupRewardsConfig.GroupId)
	end)
	if not ok or not inGroup then
		return
	end

	local entry = InventoryManager.AddItem(player, GroupRewardsConfig.RewardItemId)
	if not entry then
		return
	end

	session.ClaimedGroupReward = true
	systemMessage:FireClient(player, "Group Rewards Claimed!")
	groupRewardStateUpdated:FireClient(player, true)
	inventoryUpdated:FireClient(player, session.Inventory)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
