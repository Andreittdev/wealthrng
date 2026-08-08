-- Fills in and ticks the "NEXT UPDATE IN: ..." sign (MapBuilder's
-- buildNextUpdateBoard) with a live countdown to the next Saturday 18:00
-- GMT+3 -- its OWN boundary, deliberately independent from
-- BattlePointsConfig's week-start (LARP Battles' weekly leaderboard reset,
-- which moved to 18:10 per explicit request) -- "next update" and "weekly
-- leaderboard reset" just happened to share the same clock before, they're
-- unrelated concepts and don't have to stay in sync. Pure wall-clock math
-- (os.time() is UTC, same on every client) -- no server/remote involved,
-- the value is identical for everyone.

local Workspace = game:GetService("Workspace")

local NextUpdateCountdown = {}

-- Saturday 18:00 GMT+3 (= Saturday 15:00 UTC) of the week containing
-- `nowUtc` -- same shape as BattlePointsConfig.GetWeekStart, just this
-- board's own fixed 18:00 anchor instead of that module's 18:10 one.
local RESET_HOUR_UTC = 15

local function getWeekStart(nowUtc: number): number
	local info = os.date("!*t", nowUtc)
	local daysSinceSaturday = (info.wday - 7) % 7
	local mostRecentSaturdayMidnight = nowUtc - (info.hour * 3600 + info.min * 60 + info.sec) - daysSinceSaturday * 86400
	local candidate = mostRecentSaturdayMidnight + RESET_HOUR_UTC * 3600

	if candidate > nowUtc then
		candidate -= 7 * 86400
	end

	return candidate
end

local function getSecondsUntilReset(nowUtc: number): number
	return getWeekStart(nowUtc) + 7 * 86400 - nowUtc
end

local function formatCountdown(totalSeconds: number): string
	totalSeconds = math.max(math.floor(totalSeconds), 0)
	local days = totalSeconds // 86400
	local hours = (totalSeconds % 86400) // 3600
	local minutes = (totalSeconds % 3600) // 60
	local seconds = totalSeconds % 60

	if days > 0 then
		return string.format("%dd %02dh %02dm %02ds", days, hours, minutes, seconds)
	end
	return string.format("%02dh %02dm %02ds", hours, minutes, seconds)
end

function NextUpdateCountdown.Init()
	task.spawn(function()
		-- Same self-healing retry as the reward proximity panels --
		-- re-resolves Workspace.Map itself (not just the child lookup) in
		-- case a stale Map existed at t=0 and got destroyed/rebuilt out
		-- from under a cached reference.
		local countdownLabel: TextLabel? = nil
		while not countdownLabel do
			local mapFolder = Workspace:WaitForChild("Map")
			local board = mapFolder:WaitForChild("NextUpdateBoard_Board", 5)
			if board then
				local display = board:FindFirstChild("Display")
				local label = display and display:FindFirstChild("CountdownLabel")
				if label and label:IsA("TextLabel") then
					countdownLabel = label
				end
			end
		end

		while true do
			local nowUtc = os.time()
			countdownLabel.Text = formatCountdown(getSecondsUntilReset(nowUtc))
			task.wait(1)
		end
	end)
end

return NextUpdateCountdown
