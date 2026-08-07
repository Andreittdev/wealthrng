-- Fills in and ticks the "X2 LUCK EVENT IN: ..." sign (MapBuilder's
-- buildLuckEventBoard) with a live countdown to the next window --
-- LuckEventConfig's schedule is fully deterministic off os.time() (same
-- clock on every client), so this needs no remote/server round-trip at
-- all, same idea as NextUpdateCountdown.luau. Shows "ACTIVE NOW!" instead
-- of a countdown while the window is actually open (counting down "time
-- until it starts" makes no sense once it's already running).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LuckEventConfig = require(ReplicatedStorage.Modules.LuckEventConfig)

local LuckEventCountdown = {}

local ACTIVE_COLOR = Color3.fromRGB(90, 255, 130)
local COUNTDOWN_COLOR = Color3.new(1, 1, 1)

local function formatCountdown(totalSeconds: number): string
	totalSeconds = math.max(math.floor(totalSeconds), 0)
	local minutes = totalSeconds // 60
	local seconds = totalSeconds % 60
	return string.format("%02dm %02ds", minutes, seconds)
end

function LuckEventCountdown.Init()
	task.spawn(function()
		-- Same self-healing retry as NextUpdateCountdown/the reward
		-- proximity panels -- re-resolves Workspace.Map itself in case a
		-- stale Map existed at t=0 and got destroyed/rebuilt out from under
		-- a cached reference.
		local countdownLabel: TextLabel? = nil
		while not countdownLabel do
			local mapFolder = Workspace:WaitForChild("Map")
			local board = mapFolder:WaitForChild("LuckEventBoard_Board", 5)
			if board then
				local display = board:FindFirstChild("Display")
				local label = display and display:FindFirstChild("CountdownLabel")
				if label and label:IsA("TextLabel") then
					countdownLabel = label
				end
			end
		end

		while true do
			local now = os.time()
			if LuckEventConfig.IsActive(now) then
				countdownLabel.Text = "ACTIVE NOW!"
				countdownLabel.TextColor3 = ACTIVE_COLOR
			else
				countdownLabel.Text = formatCountdown(LuckEventConfig.GetNextWindowStart(now) - now)
				countdownLabel.TextColor3 = COUNTDOWN_COLOR
			end
			task.wait(1)
		end
	end)
end

return LuckEventCountdown
