-- LARP Battles Rank Rewards -- automatic (no Claim button, unlike Index
-- Rewards) Cash + Estate grant the moment a player's rank reaches Silver/
-- Gold/Platinum/Diamond (BattleRankConfig.luau tiers). Called from
-- BattleManager.luau right after BattleRankPoints changes, both on the real
-- Multiplayer path and the Casual-vs-bot path (Casual affects RP too, see
-- that file's header comment).
--
-- Walks every tier up to and including whichever one the player currently
-- qualifies for (not just the single newly-crossed one) -- covers a player
-- who jumps straight from Bronze to Gold in one RP change (e.g. after a
-- rebalance, or if this system ships after they've already been grinding),
-- so they don't miss Silver's reward just because they blew past it.
-- session.GrantedRankRewards permanently gates each tier to exactly once,
-- so dropping back below a rank on a losing streak and re-crossing it later
-- never double-grants.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BattleRankConfig = require(ReplicatedStorage.Modules.BattleRankConfig)
local RankRewardConfig = require(ReplicatedStorage.Modules.RankRewardConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local AssetManager = require(ServerScriptService.Managers.AssetManager)

local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")
local grantedRankRewardsUpdated = RemotesBootstrap:WaitForChild("GrantedRankRewardsUpdated")

local RankRewardManager = {}

-- Pushed on join (Main.server.luau's sendInitialState) and again after any
-- new grant below -- BattlePanel.luau's Rank Rewards popup checkmark reads
-- this REAL server state instead of recomputing "have I reached this rank"
-- from StatsUpdated, which could show a tier as claimed before this manager
-- actually got a chance to grant it (e.g. NetWorth crosses a tier's gate
-- from buying an Estate, not from a battle -- GrantNewlyReachedRewards only
-- runs from BattleManager.luau's battle-resolution paths).
function RankRewardManager.PushState(player: Player, session)
	grantedRankRewardsUpdated:FireClient(player, session.GrantedRankRewards)
end

function RankRewardManager.GrantNewlyReachedRewards(player: Player, session)
	local netWorth = StatsManager.ComputeNetWorth(player)
	local reachedTier = BattleRankConfig.GetTier(session.BattleRankPoints, netWorth)
	local reachedIndex = table.find(BattleRankConfig.Tiers, reachedTier) or 1

	local grantedAny = false
	for i = 1, reachedIndex do
		local tier = BattleRankConfig.Tiers[i]
		if not session.GrantedRankRewards[tier.Name] then
			session.GrantedRankRewards[tier.Name] = true
			grantedAny = true

			local cashReward = RankRewardConfig.GetCashReward(tier.Name)
			if cashReward > 0 then
				session.Cash += cashReward
			end

			local estateId = RankRewardConfig.GetEstateReward(tier.Name)
			if estateId then
				-- Fires its own "You won X!" SystemMessage + pushUpdate +
				-- StatsManager.Recompute + LeaderboardManager.MarkDirty.
				AssetManager.GrantAsset(player, session, estateId)
			end

			systemMessage:FireClient(player, string.format("Rank Reward Unlocked: %s!", tier.Name))
		end
	end

	if grantedAny then
		StatsManager.Recompute(player)
		RankRewardManager.PushState(player, session)
	end
end

return RankRewardManager
