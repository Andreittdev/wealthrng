-- Per-building stats for a PLACED Estate in Endless Mode (PetManager.luau
-- owns the actual placement/selection state) -- HP for now, per explicit
-- request ("momentan"), 5 upgrade levels that each add more max HP.
-- Placeholder numbers, easy to retune.

local EndlessModeBuildingConfig = {}

EndlessModeBuildingConfig.BaseHP = 100
EndlessModeBuildingConfig.HPPerUpgrade = 40
EndlessModeBuildingConfig.MaxUpgradeLevel = 5

-- Index N = cost to go from level N-1 to level N.
local UPGRADE_COSTS = { 500, 1000, 2000, 4000, 8000 }

-- nil once already at MaxUpgradeLevel -- nothing left to buy.
function EndlessModeBuildingConfig.GetUpgradeCost(currentLevel: number): number?
	local nextLevel = currentLevel + 1
	if nextLevel > EndlessModeBuildingConfig.MaxUpgradeLevel then
		return nil
	end
	return UPGRADE_COSTS[nextLevel]
end

function EndlessModeBuildingConfig.GetMaxHP(upgradeLevel: number): number
	return EndlessModeBuildingConfig.BaseHP + upgradeLevel * EndlessModeBuildingConfig.HPPerUpgrade
end

-- Per explicit request: a freshly-placed Estate (level 0) starts visually
-- SMALL and grows with every upgrade, instead of being full-size from the
-- first click. Multiplies whatever size the building would otherwise render
-- at (PetManager.luau's own template-scale/ENDLESS_MODE_PET_SCALE
-- handling). A flat per-level curve (not a linear formula) per explicit
-- follow-up request: levels 1-2 grow mildly like before, but 3/4/5 jump up
-- MUCH more, so a maxed Estate reads as filling almost the whole grid tile
-- ("aproape cat patratul") instead of just being modestly bigger. Placeholder
-- numbers, easy to retune.
local SCALE_MULTIPLIER_BY_LEVEL = {
	[0] = 0.5,
	[1] = 0.65,
	[2] = 0.8,
	[3] = 1.6,
	[4] = 2,
	[5] = 2.4,
}

function EndlessModeBuildingConfig.GetScaleMultiplier(upgradeLevel: number): number
	local level = math.clamp(upgradeLevel, 0, EndlessModeBuildingConfig.MaxUpgradeLevel)
	return SCALE_MULTIPLIER_BY_LEVEL[level]
end

-- Placing an Estate now costs EndlessModeCash, per explicit request --
-- pricier the rarer it is, same "hard-to-get tier costs/does more" shape
-- the combat multipliers (EndlessModeUnitRoleConfig) already use. Keyed on
-- AssetDatabase's own Rarity field (Common/Rare/Epic/Legendary/Godly/
-- Leaderboards/Exclusive) -- includes the 4 Crate-exclusive Estates
-- (Storage Unit/Premium Restaurant/Central Bank/Dream Castle), which are
-- real Assets now (Rarity = "Exclusive"), not a separate rarity vocabulary.
-- Ultra/Luxury are still here for any other purely-ItemDatabase-sourced
-- lookup that might reuse this table. New players start with 1000
-- EndlessModeCash (see DataManager.luau), enough for a couple of Common/Rare
-- placements before ever landing a kill.
local PLACEMENT_COST_BY_RARITY: { [string]: number } = {
	Common = 100,
	Rare = 400,
	Epic = 900,
	Legendary = 2000,
	Godly = 4000,
	Ultra = 4000,
	Leaderboards = 6000,
	Exclusive = 8000,
	Luxury = 10000,
}

-- Per-asset override, layered on top of the rarity table above -- Old Farm
-- is deliberately priced far below what its Exclusive rarity would
-- otherwise put it at, per explicit request: the cheapest AOE-capable
-- Estate in the game, paired with correspondingly weaker combat stats
-- (EndlessModeUnitRoleConfig's DAMAGE_AMOUNT_MULTIPLIER/DAMAGE_RANGE_
-- MULTIPLIER for OldFarm) so the bargain price isn't a strictly-better
-- pick over the other two Explosion-tier Estates.
local PLACEMENT_COST_OVERRIDE: { [string]: number } = {
	OldFarm = 250,
}

-- TEMPORARY testing toggle, per explicit "fa toate Estateurile gratis ca sa
-- le testez" request -- makes every Estate free to place while testing.
-- Flip back to false to restore the real rarity-based pricing above (left
-- untouched, not deleted, so nothing else needs to change when this does).
local FREE_PLACEMENT_FOR_TESTING = true

function EndlessModeBuildingConfig.GetPlacementCost(assetId: string, rarity: string?): number
	if FREE_PLACEMENT_FOR_TESTING then
		return 0
	end
	return PLACEMENT_COST_OVERRIDE[assetId] or (rarity and PLACEMENT_COST_BY_RARITY[rarity]) or PLACEMENT_COST_BY_RARITY.Common
end

return EndlessModeBuildingConfig
