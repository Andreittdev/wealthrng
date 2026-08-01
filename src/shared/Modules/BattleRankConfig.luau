-- LARP Battles ranked ladder -- 5 tiers, Bronze to Diamond, no
-- sub-divisions (no Bronze I/II/III). Tier is derived purely from a
-- player's total BattleRankPoints (RP) via these thresholds -- no separate
-- "promotion series" state to track, one number is the whole system.
-- Permanent/season-long, unlike BattlePoints (the weekly-resetting "Most
-- Points" leaderboard) -- see BattlePointsConfig.luau for that one.
--
-- Deliberately grindy (RP thresholds this wide, +15/win -10/loss) --
-- climbing to Diamond on pure wins alone takes ~60 battles, by design, so
-- reaching it actually means something instead of being a first-session gimme.

local BattleRankConfig = {}

BattleRankConfig.WinRP = 15
BattleRankConfig.LossRP = -10
-- Draws are worth 0 RP -- no entry needed, GetRPChange below returns 0 for
-- anything that isn't a clean win/loss.

-- Ordered ascending by MinRP -- GetTier walks this from the top down to
-- find the highest tier `rp` still qualifies for. MinNetWorth is a SECOND,
-- separate gate on top of MinRP -- both must be met to hold that tier, not
-- just RP alone. Like the bot's hidden difficulty gate (BattleManager.luau's
-- BOT_EASY_NET_WORTH_THRESHOLD), MinNetWorth is never shown anywhere in the
-- UI -- a player who's grinded enough RP but hasn't grown their Net Worth
-- yet just sees themselves "stuck" at the tier below, with no on-screen
-- explanation of why.
local TIERS = {
	{ Name = "Bronze", MinRP = 0, MinNetWorth = 0, Color = Color3.fromRGB(176, 110, 54) },
	{ Name = "Silver", MinRP = 150, MinNetWorth = 500000000, Color = Color3.fromRGB(176, 176, 186) },
	{ Name = "Gold", MinRP = 350, MinNetWorth = 5000000000, Color = Color3.fromRGB(230, 190, 60) },
	{ Name = "Platinum", MinRP = 600, MinNetWorth = 100000000000, Color = Color3.fromRGB(100, 220, 210) },
	{ Name = "Diamond", MinRP = 900, MinNetWorth = 1000000000000, Color = Color3.fromRGB(120, 195, 255) },
}
BattleRankConfig.Tiers = TIERS

function BattleRankConfig.GetRPChange(won: boolean?): number
	if won == true then
		return BattleRankConfig.WinRP
	elseif won == false then
		return BattleRankConfig.LossRP
	end
	return 0
end

-- RP can never go negative -- a losing streak bottoms out at 0 (Bronze),
-- it doesn't dip below the ladder entirely.
function BattleRankConfig.ApplyRPChange(currentRP: number, won: boolean?): number
	return math.max(0, currentRP + BattleRankConfig.GetRPChange(won))
end

-- Sequential/cumulative gate, not independent per-tier checks -- stops at
-- the FIRST tier (walking up) whose RP or Net Worth requirement isn't met,
-- so a player can never "skip past" a failed gate into a higher tier just
-- because that higher tier's own thresholds happen to be met (e.g. enough
-- RP for Gold on its own doesn't matter if Silver's Net Worth gate below
-- it was never cleared -- the walk stops right there).
function BattleRankConfig.GetTier(rp: number, netWorth: number?)
	local nw = netWorth or 0
	local tier = TIERS[1]
	for _, candidate in TIERS do
		if rp >= candidate.MinRP and nw >= candidate.MinNetWorth then
			tier = candidate
		else
			break
		end
	end
	return tier
end

return BattleRankConfig
