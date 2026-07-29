-- Pure "1 in N" odds math for the reveal animation (RollPanel.luau) --
-- matches RollManager's weighted-rarity-then-uniform-item-within-rarity
-- picking logic (see RollManager.pickRarity/pickItem), just without the
-- VIP/Potion luck multipliers. Those change per-player and per-moment
-- (whether a Luck Potion is active right now); this is the flat,
-- advertised base rate, same idea as a gacha game listing its base drop
-- rates rather than a live per-pull number.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)

local RollOdds = {}

-- nil if the item/rarity can't be found (shouldn't happen for a real
-- rolled item, but callers should treat nil as "don't show odds text").
function RollOdds.GetOneInN(itemId: string): number?
	local item = ItemDatabase.GetItem(itemId)
	if not item then
		return nil
	end

	local tier = RarityConfig.Tiers[item.Rarity]
	if not tier or tier.Weight <= 0 then
		return nil
	end

	local totalWeight = 0
	for _, rarity in RarityConfig.Order do
		totalWeight += RarityConfig.Tiers[rarity].Weight
	end

	local itemsInRarity = ItemDatabase.GetRollableItemsByRarity(item.Rarity)
	if #itemsInRarity == 0 then
		return nil
	end

	-- Items within a rarity aren't uniform anymore -- pricier ones are
	-- rarer pulls (see ItemDatabase.GetRollWeight), so this has to weigh
	-- them the same way RollManager.pickItem actually does, or the
	-- displayed odds would lie.
	local rarityWeightTotal = 0
	for _, candidate in itemsInRarity do
		rarityWeightTotal += ItemDatabase.GetRollWeight(candidate)
	end
	if rarityWeightTotal <= 0 then
		return nil
	end

	local withinRarityProbability = ItemDatabase.GetRollWeight(item) / rarityWeightTotal
	local probability = (tier.Weight / totalWeight) * withinRarityProbability
	if probability <= 0 then
		return nil
	end

	return 1 / probability
end

return RollOdds
