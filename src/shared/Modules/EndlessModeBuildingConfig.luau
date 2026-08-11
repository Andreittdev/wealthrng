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
-- handling) -- 0.5x at level 0 up to 1.2x at MaxUpgradeLevel, linear in
-- between. Placeholder curve, easy to retune.
local MIN_SCALE_MULTIPLIER = 0.5
local MAX_SCALE_MULTIPLIER = 1.2

function EndlessModeBuildingConfig.GetScaleMultiplier(upgradeLevel: number): number
	local progress = math.clamp(upgradeLevel / EndlessModeBuildingConfig.MaxUpgradeLevel, 0, 1)
	return MIN_SCALE_MULTIPLIER + progress * (MAX_SCALE_MULTIPLIER - MIN_SCALE_MULTIPLIER)
end

return EndlessModeBuildingConfig
