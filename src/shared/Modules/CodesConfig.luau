-- Promo codes, redeemable at the plaza's "Codes" floor marker
-- (CodesProximityPanel.luau client-side, CodesManager.luau server-side).
-- Keyed UPPERCASE -- redemption is case-insensitive (CodesManager uppercases
-- whatever the player typed before looking it up here), so the key is
-- always the canonical/display form too.
--
local CodesConfig = {}

CodesConfig.Codes = {
	LAUNCH = { CashAmount = 25000 },
	UPDATESWEEKLY = { CashAmount = 35000 },
	LARPBATTLES = { CashAmount = 20000 },
}

return CodesConfig
