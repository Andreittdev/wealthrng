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

return EndlessModeBuildingConfig
