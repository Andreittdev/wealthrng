-- Shared "distance to a marker part" poller. Every proximity popup
-- (VIPProximityPanel/GroupRewardsProximityPanel/DailyRewardsProximityPanel/
-- LuckyRollProximityPanel/BattlePanel) used to run its OWN
-- RunService.Heartbeat connection doing an almost-identical
-- Players.LocalPlayer.Character/HumanoidRootPart lookup, every single
-- frame, forever -- five redundant lookups + five separate connections
-- where one would do. This resolves the root part ONCE per frame and fans
-- the in-range result out to every registered watcher instead.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ProximityWatcher = {}

local watchers: { { Marker: BasePart, Radius: number, OnUpdate: (boolean) -> () } } = {}
local started = false

local function start()
	if started then
		return
	end
	started = true

	RunService.Heartbeat:Connect(function()
		local character = Players.LocalPlayer.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")

		for _, watcher in watchers do
			local inRange = rootPart ~= nil and (rootPart.Position - watcher.Marker.Position).Magnitude <= watcher.Radius
			watcher.OnUpdate(inRange)
		end
	end)
end

-- `onUpdate` is called every frame (not just on change) with the current
-- in-range state -- exactly like each caller's old inline Heartbeat body
-- received it, so callers keep whatever edge-detection (wasInRange, etc.)
-- they already had, unchanged.
function ProximityWatcher.Register(marker: BasePart, radiusStuds: number, onUpdate: (boolean) -> ())
	start()
	table.insert(watchers, { Marker = marker, Radius = radiusStuds, OnUpdate = onUpdate })
end

return ProximityWatcher
