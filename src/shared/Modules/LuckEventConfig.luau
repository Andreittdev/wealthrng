-- Recurring server-wide "X2 Luck" event -- every IntervalSeconds (30 min),
-- a DurationSeconds (10 min) window opens where every non-Common rarity's
-- roll weight is doubled, for EVERY player at once (not a per-player timer
-- like Potions -- one shared clock, so it can be broadcast/countdown
-- together and every server agrees on the same schedule with zero
-- cross-server coordination needed).
--
-- Anchored to the real Unix epoch (os.time() % IntervalSeconds), not a
-- stored "event started at" timestamp -- same "deterministic off the
-- clock alone" idea as BattlePointsConfig.GetWeekStart, just on a much
-- shorter cycle. A server restart mid-window doesn't reset or skip
-- anything; it just re-derives the same answer from the current time.
--
-- Common stays at 1 -- weighted-pick normalization means a FLAT
-- multiplier on every tier does literally nothing to the odds (it cancels
-- out against the shared total), so only rarer tiers get boosted for the
-- event to actually change anything, same shape as VIPConfig/LuckPassConfig's
-- LuckWeightMultiplier tables.

local LuckEventConfig = {}

LuckEventConfig.IntervalSeconds = 30 * 60
LuckEventConfig.DurationSeconds = 10 * 60

-- TESTING ONLY -- forces IsActive to always return true (with a rolling
-- DurationSeconds-long window) so the banner/luck boost can be checked
-- without waiting for a real cycle. Flip back to false before shipping.
LuckEventConfig.TESTING_FORCE_ACTIVE = false

-- Must have an entry for every RarityConfig.Order tier -- RollManager.
-- pickRarity does `weight *= LuckEventConfig.LuckWeightMultiplier[rarity]`
-- with no `or 1` fallback, same contract VIPConfig's table already uses.
LuckEventConfig.LuckWeightMultiplier = {
	Common = 1,
	Rare = 2,
	Epic = 2,
	Legendary = 2,
	Ultra = 2,
	Luxury = 2,
}

-- Active for the first DurationSeconds of every IntervalSeconds cycle,
-- dormant for the rest.
function LuckEventConfig.IsActive(now: number): boolean
	if LuckEventConfig.TESTING_FORCE_ACTIVE then
		return true
	end
	return (now % LuckEventConfig.IntervalSeconds) < LuckEventConfig.DurationSeconds
end

-- Unix timestamp the CURRENTLY active window ends at -- only meaningful
-- while IsActive(now) is true, callers shouldn't call this otherwise.
function LuckEventConfig.GetActiveWindowEnd(now: number): number
	-- TESTING_FORCE_ACTIVE can make IsActive true OUTSIDE the real cycle's
	-- first DurationSeconds -- the plain cycle-position math below would
	-- then return a timestamp in the PAST (e.g. "ended 5 minutes ago"),
	-- which made the banner appear and immediately disappear again within
	-- the same frame client-side. Just give it a fresh DurationSeconds from
	-- now instead while forced on.
	if LuckEventConfig.TESTING_FORCE_ACTIVE then
		return now + LuckEventConfig.DurationSeconds
	end
	local cyclePos = now % LuckEventConfig.IntervalSeconds
	return now - cyclePos + LuckEventConfig.DurationSeconds
end

-- Unix timestamp the NEXT window starts at -- only meaningful while
-- IsActive(now) is false.
function LuckEventConfig.GetNextWindowStart(now: number): number
	local cyclePos = now % LuckEventConfig.IntervalSeconds
	return now - cyclePos + LuckEventConfig.IntervalSeconds
end

-- 1 while inactive (no-op) -- RollManager.pickRarity multiplies this in
-- unconditionally, same as every other luck-source lookup there.
function LuckEventConfig.GetLuckMultiplier(rarity: string, now: number): number
	if not LuckEventConfig.IsActive(now) then
		return 1
	end
	return LuckEventConfig.LuckWeightMultiplier[rarity] or 1
end

return LuckEventConfig
