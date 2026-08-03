-- Group Rewards: stand near the plaza's blue "Group Rewards" floor marker
-- (MapBuilder's buildFloorMarker) to claim a one-time free item for being
-- in the game's Roblox group. Group = "Become Wealthy"
-- (https://www.roblox.com/communities/13443306).

local GroupRewardsConfig = {}

GroupRewardsConfig.GroupId = 13443306
GroupRewardsConfig.RewardItemId = "GroupRewardChest"
-- Real, immediately-spendable Cash on top of the item -- separate from
-- ItemDatabase.GroupRewardChest's own Value ($50,000, just that item's
-- stat if sold/appraised), not a replacement for it.
GroupRewardsConfig.RewardCashAmount = 100000

return GroupRewardsConfig
