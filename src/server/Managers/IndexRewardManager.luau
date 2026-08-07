-- Handles ClaimIndexReward (CatalogPanel.luau's Claim button, shown once a
-- Roll rarity or Estates tier is 100% complete) -- server-authoritative:
-- re-validates the tier is ACTUALLY complete (IndexRewardConfig.
-- IsTierComplete/IsEstateTierComplete) and not already claimed before
-- marking it claimed, exactly like every other one-shot grant in this
-- codebase. Claiming doesn't hand out a separate lump-sum reward -- it's
-- what turns the tier's permanent Luck%/Cash Earnings% bonus on (see
-- IndexRewardConfig.luau's Get*TotalBonusPercent, which only sum CLAIMED
-- tiers), so the only visible effect here is the SystemMessage + a
-- StatsManager.Recompute to make the new bonus take effect immediately.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local IndexRewardConfig = require(ReplicatedStorage.Modules.IndexRewardConfig)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)

local claimIndexReward = RemotesBootstrap:WaitForChild("ClaimIndexReward")
local claimedIndexRewardsUpdated = RemotesBootstrap:WaitForChild("ClaimedIndexRewardsUpdated")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local IndexRewardManager = {}

-- Membership sets, so an arbitrary/garbage tier string can't be marked
-- claimed even though the bonus lookup itself already has an `or 0`
-- fallback for unknown keys -- same defensive-validation convention every
-- other client-supplied-string remote in this codebase follows.
local ROLL_TIER_SET: { [string]: boolean } = {}
for _, rarity in RarityConfig.Order do
	ROLL_TIER_SET[rarity] = true
end
local ESTATE_TIER_SET: { [string]: boolean } = {}
for _, tier in IndexRewardConfig.EstateTierOrder do
	ESTATE_TIER_SET[tier] = true
end

local function pushClaimed(player: Player, session)
	claimedIndexRewardsUpdated:FireClient(player, {
		Roll = session.ClaimedRollIndexTiers,
		Estate = session.ClaimedEstateIndexTiers,
	})
end

function IndexRewardManager.PushState(player: Player, session)
	pushClaimed(player, session)
end

claimIndexReward.OnServerEvent:Connect(function(player: Player, category: unknown, tier: unknown)
	if typeof(category) ~= "string" or typeof(tier) ~= "string" then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	if category == "Roll" then
		if not ROLL_TIER_SET[tier] or session.ClaimedRollIndexTiers[tier] then
			return
		end
		if not IndexRewardConfig.IsTierComplete(session.DiscoveredItemIds, tier) then
			return
		end
		session.ClaimedRollIndexTiers[tier] = true
		local bonus = IndexRewardConfig.CompletionBonusPercent[tier] or 0
		systemMessage:FireClient(player, string.format("Index Reward Claimed: %s +%d%% Luck!", tier, bonus))
	elseif category == "Estate" then
		if not ESTATE_TIER_SET[tier] or session.ClaimedEstateIndexTiers[tier] then
			return
		end
		if not IndexRewardConfig.IsEstateTierComplete(session.OwnedAssets, session.DiscoveredItemIds, tier) then
			return
		end
		session.ClaimedEstateIndexTiers[tier] = true
		local bonus = IndexRewardConfig.EstateCompletionBonusPercent[tier] or 0
		systemMessage:FireClient(player, string.format("Index Reward Claimed: %s +%d%% Cash Earnings!", tier, bonus))
	else
		return
	end

	pushClaimed(player, session)
	StatsManager.Recompute(player)
end)

return IndexRewardManager
