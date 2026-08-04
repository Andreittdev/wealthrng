-- Fills in and ticks the "NEXT UPDATE IN: ..." sign (MapBuilder's
-- buildNextUpdateBoard) with a live countdown to the next Saturday 18:00
-- GMT+3 -- reuses BattlePointsConfig's already-tested week-boundary math
-- (the exact same reset moment LARP Battles' weekly leaderboard uses)
-- instead of re-deriving separate weekday/timezone math here, so the two
-- can never silently drift apart. Pure wall-clock math (os.time() is UTC,
-- same on every client) -- no server/remote involved, the value is
-- identical for everyone.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BattlePointsConfig = require(ReplicatedStorage.Modules.BattlePointsConfig)

local NextUpdateCountdown = {}

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
			countdownLabel.Text = formatCountdown(BattlePointsConfig.GetSecondsUntilReset(nowUtc))
			task.wait(1)
		end
	end)
end

return NextUpdateCountdown
