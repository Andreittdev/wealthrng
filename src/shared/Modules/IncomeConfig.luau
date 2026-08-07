-- Pure passive-income-rate math, shared by IncomeManager (applies it) and
-- StatsManager (displays it) -- kept as a leaf module (no DataManager/
-- VIPManager/AssetManager requires) specifically so those server managers
-- can all use it without requiring each other into a circular dependency.
-- Takes a duck-typed slice of DataManager's Session shape rather than
-- requiring that module directly, since this file lives in ReplicatedStorage
-- and must stay safely requirable from the client too.
--
-- Two separate rates, not one combined number -- items pay out
-- continuously (IncomeManager ticks every few seconds) while Assets pay
-- out as a lump sum once a minute ("collect rent"), so they can't be
-- merged into a single per-second figure without lying about the cadence.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)

local IncomeConfig = {}

type SessionSlice = {
	EquippedItemId: string?,
	EquippedAssets: { string },
}

local function combineBonusPercent(
	isVIP: boolean,
	vipBonusPercent: number,
	potionBonusPercent: number,
	friendBonusPercent: number,
	doubleCashBonusPercent: number,
	estateIndexBonusPercent: number
): number
	-- VIP's permanent bonus, a Fortune Potion's temporary one, Friend Boost
	-- (FriendBoostConfig.luau -- online with 1+ Roblox friends on the same
	-- server), the Double Cash gamepass (DoubleCashConfig.luau), and the
	-- Estates Index's completion reward (IndexRewardConfig.luau) all stack
	-- additively (25% + 40% + 20% + 100% + 190% = +375%), not overwrite
	-- each other -- same "stack, don't replace" shape used everywhere else
	-- in this economy.
	local bonusPercent = potionBonusPercent + friendBonusPercent + doubleCashBonusPercent + estateIndexBonusPercent
	if isVIP then
		bonusPercent += vipBonusPercent
	end
	return bonusPercent
end

function IncomeConfig.ComputeItemsRatePerSecond(
	session: SessionSlice,
	isVIP: boolean,
	vipBonusPercent: number,
	potionBonusPercent: number,
	friendBonusPercent: number,
	doubleCashBonusPercent: number,
	estateIndexBonusPercent: number
): number
	-- Only equipped items earn income -- unequipped ones still count their
	-- Value toward Net Worth via InventoryManager.GetValue, just not this.
	-- Reads session.EquippedItemId directly (kept in sync by
	-- InventoryManager.Equip/Unequip/RemoveItem) instead of scanning the
	-- full Inventory array for whichever entry matches EquippedItemUids --
	-- this ran on every single roll (via StatsManager.Recompute), so an
	-- O(n)-over-Inventory scan here got measurably slower the longer a
	-- session went on. Only valid because ItemDatabase.MaxEquipped is 1 --
	-- would need to go back to a real list if that ever changes.
	local total = 0
	local item = session.EquippedItemId and ItemDatabase.GetItem(session.EquippedItemId)
	if item then
		total = item.IncomePerSecond
	end

	total *= 1 + combineBonusPercent(isVIP, vipBonusPercent, potionBonusPercent, friendBonusPercent, doubleCashBonusPercent, estateIndexBonusPercent) / 100
	return total
end

function IncomeConfig.ComputeAssetsRatePerMinute(
	session: SessionSlice,
	isVIP: boolean,
	vipBonusPercent: number,
	potionBonusPercent: number,
	friendBonusPercent: number,
	doubleCashBonusPercent: number,
	estateIndexBonusPercent: number
): number
	local total = 0

	for _, assetId in session.EquippedAssets do
		local asset = AssetDatabase.GetAsset(assetId)
		if asset then
			total += asset.IncomePerMinute
		end
	end

	total *= 1 + combineBonusPercent(isVIP, vipBonusPercent, potionBonusPercent, friendBonusPercent, doubleCashBonusPercent, estateIndexBonusPercent) / 100
	return total
end

return IncomeConfig
