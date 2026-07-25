-- Pure active-potion-effect lookups, shared by RollManager/SellManager/
-- IncomeManager/StatsManager (all read effects) and PotionManager (applies
-- purchases) -- kept as a leaf module (no DataManager require) specifically
-- so those server managers can all use it without requiring PotionManager
-- into a circular dependency. Same reasoning as IncomeConfig.luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PotionDatabase = require(ReplicatedStorage.Modules.PotionDatabase)

local PotionConfig = {}

type SessionSlice = {
	ActivePotions: { [string]: number },
}

local function findActive(session: SessionSlice, now: number, predicate: (PotionDatabase.Potion) -> boolean): PotionDatabase.Potion?
	for potionId, expiresAt in session.ActivePotions do
		if expiresAt > now then
			local potion = PotionDatabase.GetPotion(potionId)
			if potion and predicate(potion) then
				return potion
			end
		end
	end
	return nil
end

function PotionConfig.IsActive(session: SessionSlice, potionId: string, now: number): boolean
	local expiresAt = session.ActivePotions[potionId]
	return expiresAt ~= nil and expiresAt > now
end

function PotionConfig.GetLuckMultiplier(session: SessionSlice, rarity: string, now: number): number
	local potion = findActive(session, now, function(p)
		return p.LuckWeightMultiplier ~= nil
	end)
	if not potion or not potion.LuckWeightMultiplier then
		return 1
	end
	return potion.LuckWeightMultiplier[rarity] or 1
end

function PotionConfig.GetCooldownMultiplier(session: SessionSlice, now: number): number
	local potion = findActive(session, now, function(p)
		return p.CooldownMultiplier ~= nil
	end)
	if not potion or not potion.CooldownMultiplier then
		return 1
	end
	return potion.CooldownMultiplier
end

function PotionConfig.GetCashBonusPercent(session: SessionSlice, now: number): number
	local potion = findActive(session, now, function(p)
		return p.CashBonusPercent ~= nil
	end)
	if not potion or not potion.CashBonusPercent then
		return 0
	end
	return potion.CashBonusPercent
end

return PotionConfig
