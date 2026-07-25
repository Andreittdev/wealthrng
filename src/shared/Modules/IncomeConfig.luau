-- Pure passive-income-rate math, shared by IncomeManager (applies it) and
-- StatsManager (displays it) -- kept as a leaf module (no DataManager/
-- VIPManager/AssetManager requires) specifically so those server managers
-- can all use it without requiring each other into a circular dependency.
-- Takes a duck-typed slice of DataManager's Session shape rather than
-- requiring that module directly, since this file lives in ReplicatedStorage
-- and must stay safely requirable from the client too.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)

local IncomeConfig = {}

type SessionSlice = {
	Inventory: { { Uid: number, ItemId: string } },
	EquippedAssets: { string },
}

function IncomeConfig.ComputeRate(session: SessionSlice, isVIP: boolean, vipBonusPercent: number, potionBonusPercent: number): number
	local total = 0

	for _, entry in session.Inventory do
		local item = ItemDatabase.GetItem(entry.ItemId)
		if item then
			total += item.IncomePerSecond
		end
	end

	for _, assetId in session.EquippedAssets do
		local asset = AssetDatabase.GetAsset(assetId)
		if asset then
			total += asset.IncomePerSecond
		end
	end

	-- VIP's permanent bonus and a Fortune Potion's temporary one stack
	-- additively (25% + 40% = +65%), not overwrite each other.
	local bonusPercent = potionBonusPercent
	if isVIP then
		bonusPercent += vipBonusPercent
	end
	total *= 1 + bonusPercent / 100

	return total
end

return IncomeConfig
