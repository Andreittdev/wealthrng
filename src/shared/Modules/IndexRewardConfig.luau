-- Index (CatalogPanel.luau) completion rewards -- discovering EVERY item
-- in a Roll rarity tier (session.DiscoveredItemIds, permanent even after
-- selling) makes that tier CLAIMABLE, not automatically rewarded --
-- IndexRewardManager.luau grants the actual Luck%/Cash Earnings% bonus
-- only once the player presses Claim on it (session.ClaimedRollIndexTiers/
-- ClaimedEstateIndexTiers), which is what every Get*TotalBonusPercent
-- function below actually sums over. Every claimed tier's bonus stacks
-- additively into ONE running total (Roll: Common 10% + Rare 20% + ... +
-- Luxury 60% = +210% at full completion+claim).
--
-- Common's own bonus is still earned/counted in the Roll total, but the
-- total itself is only ever applied to non-Common rarities -- a flat
-- multiplier across EVERY tier (Common included) does literally nothing
-- in a weighted pick, since it cancels out against the shared total (same
-- reasoning as LuckEventConfig.luau's header). Same shape as VIPConfig/
-- LuckPassConfig's LuckWeightMultiplier tables: Common stays at 1x,
-- everything else gets boosted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local EstateRarityConfig = require(ReplicatedStorage.Modules.EstateRarityConfig)

local IndexRewardConfig = {}

local COMPLETION_BONUS_PERCENT: { [string]: number } = {
	Common = 10,
	Rare = 20,
	Epic = 30,
	Legendary = 40,
	Ultra = 50,
	Luxury = 60,
}
IndexRewardConfig.CompletionBonusPercent = COMPLETION_BONUS_PERCENT

-- True once every ROLLABLE Item of this rarity has been discovered at
-- least once, ever (session.DiscoveredItemIds) -- i.e. the tier is
-- CLAIMABLE, not necessarily claimed yet. Deliberately GetRollableItemsByRarity,
-- not GetItemsByRarity: the latter also includes NotRollable/CrateExclusive
-- specials (GroupRewardChest, the 4 Crate items), which would otherwise
-- gate a purely-roll-based reward behind joining a Discord/group or
-- spending Robux on Crates.
function IndexRewardConfig.IsTierComplete(discoveredItemIds: { [string]: boolean }, rarity: string): boolean
	local items = ItemDatabase.GetRollableItemsByRarity(rarity)
	if #items == 0 then
		return false
	end
	for _, item in items do
		if not discoveredItemIds[item.Id] then
			return false
		end
	end
	return true
end

-- Sum of CompletionBonusPercent for every CLAIMED tier (session.
-- ClaimedRollIndexTiers, NOT just completed -- see IndexRewardManager.luau)
-- -- 0 to 210.
function IndexRewardConfig.GetTotalBonusPercent(claimedTiers: { [string]: boolean }): number
	local total = 0
	for _, rarity in RarityConfig.Order do
		if claimedTiers[rarity] then
			total += COMPLETION_BONUS_PERCENT[rarity] or 0
		end
	end
	return total
end

-- 1x for Common (see header) -- RollManager.pickRarity multiplies this in
-- unconditionally, same as every other luck-source lookup there.
function IndexRewardConfig.GetLuckMultiplier(claimedTiers: { [string]: boolean }, rarity: string): number
	if rarity == "Common" then
		return 1
	end
	return 1 + IndexRewardConfig.GetTotalBonusPercent(claimedTiers) / 100
end

-- ===== Estates tab -- Cash Earnings% rewards =====
-- Same additive-stacking, claim-gated shape as the Roll rewards above,
-- just a different stat (Cash Earnings%, not Luck%) and Estates' own
-- 7-tier scheme (see AssetDatabase.luau's Asset.Rarity comment). Common
-- 5% + Rare 10% + Epic 15% + Legendary 20% + Godly 30% + Exclusive 60% +
-- Leaderboards 50% = +190% at full completion+claim. Unlike the Roll
-- rewards, there's no "Common does nothing" carve-out needed here -- this
-- bonus feeds into IncomeConfig/SellManager's plain additive bonusPercent
-- stack (same shape VIP's SellBonusPercent already uses), not a
-- weighted-pick multiplier, so it's never a no-op regardless of which
-- tier earned it.
local ESTATE_TIER_ORDER = EstateRarityConfig.Order
local ESTATE_COMPLETION_BONUS_PERCENT: { [string]: number } = {
	Common = 5,
	Rare = 10,
	Epic = 15,
	Legendary = 20,
	Godly = 30,
	Exclusive = 60,
	Leaderboards = 50,
}
IndexRewardConfig.EstateTierOrder = ESTATE_TIER_ORDER
IndexRewardConfig.EstateCompletionBonusPercent = ESTATE_COMPLETION_BONUS_PERCENT

-- The 4 Crate-exclusive Estates fold into the "Exclusive" tier alongside
-- Top3Estate ("Sol Stadium") -- same split CatalogPanel.luau's Estates
-- tab renders, kept here too since the reward calc needs the identical
-- membership rule.
local CRATE_EXCLUSIVE_ITEM_IDS = { "CrateVilla", "CrateManor", "CratePalace", "CrateCastle" }

-- True once the tier is CLAIMABLE (fully owned/discovered), not
-- necessarily claimed yet. Assets are never sellable in this game --
-- ownership (session.OwnedAssets) is already permanent, no separate
-- "discovered" tracking needed for them the way rollable/sellable Items
-- require.
function IndexRewardConfig.IsEstateTierComplete(ownedAssetIds: { [string]: boolean }, discoveredItemIds: { [string]: boolean }, tier: string): boolean
	if tier == "Exclusive" then
		if not ownedAssetIds["Top3Estate"] then
			return false
		end
		for _, itemId in CRATE_EXCLUSIVE_ITEM_IDS do
			if not discoveredItemIds[itemId] then
				return false
			end
		end
		return true
	end

	local hasAny = false
	for _, asset in AssetDatabase.GetAllAssets() do
		if asset.Rarity == tier and asset.Id ~= "Top3Estate" then
			hasAny = true
			if not ownedAssetIds[asset.Id] then
				return false
			end
		end
	end
	return hasAny
end

-- Sum of EstateCompletionBonusPercent for every CLAIMED tier (session.
-- ClaimedEstateIndexTiers) -- 0 to 190.
function IndexRewardConfig.GetEstateTotalBonusPercent(claimedTiers: { [string]: boolean }): number
	local total = 0
	for _, tier in ESTATE_TIER_ORDER do
		if claimedTiers[tier] then
			total += ESTATE_COMPLETION_BONUS_PERCENT[tier] or 0
		end
	end
	return total
end

return IndexRewardConfig
