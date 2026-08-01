-- Pure weekly-period math for LARP Battles' "Most Points" leaderboard --
-- shared leaf module (no DataManager/other manager requires) specifically
-- so both BattleManager.luau (awards points) and LeaderboardManager.luau
-- (submits/displays them, and needs the same week key to pick which
-- OrderedDataStore to read/write) can agree on the exact same week
-- boundary without requiring each other into a circular dependency.

local BattlePointsConfig = {}

-- Monday 00:00 UTC of the week containing `nowUtc` -- a stable,
-- deterministic boundary every server agrees on (pure UTC math, no
-- per-server clock/timezone drift).
function BattlePointsConfig.GetWeekStart(nowUtc: number): number
	local info = os.date("!*t", nowUtc)
	local secondsSinceMidnight = info.hour * 3600 + info.min * 60 + info.sec
	-- os.date's wday: 1=Sunday..7=Saturday -> days since Monday (0..6).
	local daysSinceMonday = (info.wday + 5) % 7
	return nowUtc - secondsSinceMidnight - daysSinceMonday * 86400
end

-- Feeds the OrderedDataStore name (LeaderboardManager.luau) -- a fresh
-- store name every week means the leaderboard "resets" for free, no bulk
-- clear/cron job needed. Old weeks' stores just stop being read/written.
function BattlePointsConfig.GetWeekKey(nowUtc: number): string
	return os.date("!%Y-%m-%d", BattlePointsConfig.GetWeekStart(nowUtc))
end

-- Zeroes a session's BattlePoints the moment they're found to belong to a
-- past week -- called before EITHER reading them (leaderboard submit) OR
-- crediting a new one (a Battle win), so a stale total from last week can
-- never leak into the new week through either path.
function BattlePointsConfig.EnsureCurrentWeek(session: { BattlePoints: number, BattlePointsWeekStart: number })
	local currentWeekStart = BattlePointsConfig.GetWeekStart(os.time())
	if session.BattlePointsWeekStart ~= currentWeekStart then
		session.BattlePoints = 0
		session.BattlePointsWeekStart = currentWeekStart
	end
end

return BattlePointsConfig
