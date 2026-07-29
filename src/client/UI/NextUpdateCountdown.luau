-- Fills in and ticks the "NEXT UPDATE IN: ..." sign (MapBuilder's
-- buildNextUpdateBoard) with a live countdown to the next Sunday 7 PM
-- GMT+3. Pure wall-clock math (os.time() is UTC, same on every client) --
-- no server/remote involved, the value is identical for everyone.

local Workspace = game:GetService("Workspace")

local NextUpdateCountdown = {}

local GMT_OFFSET_SECONDS = 3 * 3600 -- GMT+3
local TARGET_WEEKDAY = 1 -- os.date's wday: 1 = Sunday
local TARGET_HOUR = 19 -- 7 PM

-- Shifts `nowUtc` by the fixed GMT+3 offset and reads it back with the "!"
-- (UTC) prefix -- the standard trick for fixed-offset-timezone wall-clock
-- math without needing a real timezone database: the shifted timestamp's
-- UTC calendar fields ARE the GMT+3 wall-clock fields.
local function nextUpdateTimestampUtc(nowUtc: number): number
	local shifted = nowUtc + GMT_OFFSET_SECONDS
	local info = os.date("!*t", shifted)

	local daysUntilSunday = (TARGET_WEEKDAY - info.wday) % 7
	local secondsSinceLocalMidnight = info.hour * 3600 + info.min * 60 + info.sec
	local localMidnightThisSunday = shifted - secondsSinceLocalMidnight + daysUntilSunday * 86400
	local candidate = localMidnightThisSunday + TARGET_HOUR * 3600

	if candidate <= shifted then
		candidate += 7 * 86400
	end

	return candidate - GMT_OFFSET_SECONDS
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
			countdownLabel.Text = formatCountdown(nextUpdateTimestampUtc(nowUtc) - nowUtc)
			task.wait(1)
		end
	end)
end

return NextUpdateCountdown
