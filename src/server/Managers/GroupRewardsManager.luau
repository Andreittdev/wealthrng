-- One-time free item for being in the game's Roblox group (see
-- GroupRewardsConfig.luau) -- claimed by standing near the plaza's blue
-- "Group Rewards" floor marker (MapBuilder's buildFloorMarker) and pressing
-- Claim in GroupRewardsProximityPanel.luau. Player:IsInGroup is checked
-- again here (never trust the client's own copy of that check) and
-- session.ClaimedGroupReward gates it to exactly once per save, even if the
-- player leaves the group afterward.

local Players = game:GetService("Players")
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

-- player:IsInGroup below yields (a real network call, often slow on a
-- player's very first check) -- without this lock, firing ClaimGroupReward
-- twice in quick succession let BOTH calls pass the session.ClaimedGroupReward
-- check before either had written it back, granting the item twice. The
-- lock is set before the yield and only released on a rejected/failed
-- attempt, never on success (success permanently sets ClaimedGroupReward
-- instead).
local claimInProgress: { [Player]: boolean } = {}

claimGroupReward.OnServerEvent:Connect(function(player: Player)
	local session = DataManager.Get(player)
	if not session then
		return
	end

	if session.ClaimedGroupReward or claimInProgress[player] then
		return
	end
	claimInProgress[player] = true

	local ok, inGroup = pcall(function()
		return player:IsInGroup(GroupRewardsConfig.GroupId)
	end)
	if not ok or not inGroup then
		claimInProgress[player] = nil
		return
	end

	local entry = InventoryManager.AddItem(player, GroupRewardsConfig.RewardItemId)
	if not entry then
		claimInProgress[player] = nil
		return
	end

	session.ClaimedGroupReward = true
	claimInProgress[player] = nil
	systemMessage:FireClient(player, "Group Rewards Claimed!")
	groupRewardStateUpdated:FireClient(player, true)
	inventoryUpdated:FireClient(player, session.Inventory)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

Players.PlayerRemoving:Connect(function(player)
	claimInProgress[player] = nil
end)

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
