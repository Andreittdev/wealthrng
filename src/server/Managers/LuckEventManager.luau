-- Broadcasts LuckEventConfig's recurring server-wide "X2 Luck" window to
-- every connected client -- LuckEventBanner.luau (client) shows "X2 LUCK
-- ACTIVE! Ends in MM:SS" while it's on. RollManager.luau applies the
-- actual odds boost independently by reading LuckEventConfig directly off
-- the clock; this manager only exists to tell clients WHEN to show the
-- banner, it never gates the roll odds itself.
--
-- Sleeps until the exact next transition (window end or next window
-- start) instead of polling on an interval -- LuckEventConfig's schedule
-- is fully deterministic off os.time(), so the next transition instant is
-- always known in advance.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LuckEventConfig = require(ReplicatedStorage.Modules.LuckEventConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)

local luckEventStateUpdated = RemotesBootstrap:WaitForChild("LuckEventStateUpdated")

local LuckEventManager = {}

local function currentState()
	local now = os.time()
	if LuckEventConfig.IsActive(now) then
		return { Active = true, EndsAt = LuckEventConfig.GetActiveWindowEnd(now) }
	end
	return { Active = false }
end

-- Called from Main.server.luau's sendInitialState (same "PushState once
-- the client's listeners actually exist" convention DailyRewardsManager/
-- AutoClaimManager/RollManager use) -- NOT PlayerAdded, which fires way
-- before LuckEventBanner.luau's OnClientEvent connection exists on a
-- freshly-joined client, silently dropping the very first push.
function LuckEventManager.PushState(player: Player)
	luckEventStateUpdated:FireClient(player, currentState())
end

task.spawn(function()
	while true do
		local now = os.time()
		local secondsUntilNextTransition: number
		if LuckEventConfig.IsActive(now) then
			secondsUntilNextTransition = LuckEventConfig.GetActiveWindowEnd(now) - now
		else
			secondsUntilNextTransition = LuckEventConfig.GetNextWindowStart(now) - now
		end
		-- Guards against a would-be zero/negative wait landing exactly on a
		-- boundary (task.wait(0) is fine, but a negative value from clock
		-- weirdness isn't) -- always wait at least a moment forward.
		task.wait(math.max(secondsUntilNextTransition, 1))

		luckEventStateUpdated:FireAllClients(currentState())
	end
end)

return LuckEventManager
