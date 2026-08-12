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

return EndlessModeBuildingConfig
