-- Endless Mode's wave clock -- ticks session.EndlessModeElapsedSeconds up by
-- roughly 1 per second, ONLY while a player is physically standing in
-- Endless Mode (paused the instant they're back in the hub or offline), per
-- explicit request. Current wave (WaveConfig.GetWaveForElapsedSeconds) is
-- pushed to that player every tick so their HUD stays live.
--
-- "In Endless Mode" is EndlessModeConfig's plain world-position check, not
-- tied to PortalManager.luau's teleport event -- self-contained and correct
-- regardless of exactly how they got there (portal, a future TeleportService
-- hop, admin teleport, whatever), same "each manager watches its own thing
-- independently" shape as EndlessModeClaimManager.luau/StadiumOfferManager.luau.
--
-- Self-runs on require -- no Init() call needed, same convention as every
-- other pure-background-watcher manager.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WaveConfig = require(ReplicatedStorage.Modules.WaveConfig)
local EndlessModeConfig = require(ReplicatedStorage.Modules.EndlessModeConfig)
local DataManager = require(ServerScriptService.Managers.DataManager)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)

local endlessModeWaveUpdated = RemotesBootstrap:WaitForChild("EndlessModeWaveUpdated")

local EndlessModeWaveManager = {}

local TICK_SECONDS = 1

local function isInEndlessMode(player: Player): boolean
	return EndlessModeConfig.IsCharacterInEndlessMode(player.Character)
end

task.spawn(function()
	while true do
		task.wait(TICK_SECONDS)

		for _, player in Players:GetPlayers() do
			if not isInEndlessMode(player) then
				continue
			end

			local session = DataManager.Get(player)
			if not session then
				continue
			end

			-- Committed every tick (not just on enter/leave) so at most
			-- ~1s of progress is ever at risk of being lost to a crash/
			-- ungraceful disconnect -- DataManager's own autosave picks
			-- this field up like any other session field from here.
			session.EndlessModeElapsedSeconds += TICK_SECONDS
			endlessModeWaveUpdated:FireClient(player, WaveConfig.GetWaveForElapsedSeconds(session.EndlessModeElapsedSeconds))
		end
	end
end)

return EndlessModeWaveManager
