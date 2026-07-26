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
	Inventory: { { Uid: number, ItemId: string } },
	EquippedItemUids: { number },
	EquippedAssets: { string },
}

local function combineBonusPercent(isVIP: boolean, vipBonusPercent: number, potionBonusPercent: number): number
	-- VIP's permanent bonus and a Fortune Potion's temporary one stack
	-- additively (25% + 40% = +65%), not overwrite each other.
	local bonusPercent = potionBonusPercent
	if isVIP then
		bonusPercent += vipBonusPercent
	end
	return bonusPercent
end

function IncomeConfig.ComputeItemsRatePerSecond(session: SessionSlice, isVIP: boolean, vipBonusPercent: number, potionBonusPercent: number): number
	local total = 0

	-- Only equipped items earn income -- unequipped ones still count their
	-- Value toward Net Worth via InventoryManager.GetValue, just not this.
	local equippedItemUids: { [number]: boolean } = {}
	for _, uid in session.EquippedItemUids do
		equippedItemUids[uid] = true
	end

	for _, entry in session.Inventory do
		if equippedItemUids[entry.Uid] then
			local item = ItemDatabase.GetItem(entry.ItemId)
			if item then
				total += item.IncomePerSecond
			end
		end
	end

	total *= 1 + combineBonusPercent(isVIP, vipBonusPercent, potionBonusPercent) / 100
	return total
end

function IncomeConfig.ComputeAssetsRatePerMinute(session: SessionSlice, isVIP: boolean, vipBonusPercent: number, potionBonusPercent: number): number
	local total = 0

	for _, assetId in session.EquippedAssets do
		local asset = AssetDatabase.GetAsset(assetId)
		if asset then
			total += asset.IncomePerMinute
		end
	end

	total *= 1 + combineBonusPercent(isVIP, vipBonusPercent, potionBonusPercent) / 100
	return total
end

return IncomeConfig
