-- Auto Roll gamepass ownership, cached per session. Ownership check
-- mirrors VIPManager's shape exactly. The actual auto-rolling loop lives
-- entirely on the client (RollPanel.luau) once it's confirmed enabled here
-- -- this module only validates the SetAutoRoll toggle (rejecting it if
-- the player doesn't actually own the gamepass) and echoes the real state
-- back via AutoRollUpdated; it doesn't need to remember whether a player
-- currently has it on for anything else. Deliberately does NOT require
-- RollManager -- StatsManager needs to read Owns() for the StatsUpdated
-- payload, and RollManager already requires StatsManager, so this module
-- has to stay a leaf or that becomes a require cycle (StatsManager ->
-- AutoRollManager -> RollManager -> StatsManager).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AutoRollConfig = require(ReplicatedStorage.Modules.AutoRollConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)

local AutoRollManager = {}

local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2
local FREE_TIMER_CHECK_INTERVAL_SECONDS = 5

local ownsCache: { [Player]: boolean } = {}
-- In-memory only, on purpose -- os.time() this player's "Get Auto Roll
-- Free" wait started. Never persisted: the offer resets to 0 if they
-- disconnect before it completes (see PlayerRemoving below), so there's
-- nothing meaningful to save mid-wait -- only the final AutoRollFreeGranted
-- flag (DataManager) needs to survive a restart.
local freeTimerStart: { [Player]: number } = {}

local setAutoRoll = RemotesBootstrap:WaitForChild("SetAutoRoll")
local autoRollUpdated = RemotesBootstrap:WaitForChild("AutoRollUpdated")
local startAutoRollFreeTimer = RemotesBootstrap:WaitForChild("StartAutoRollFreeTimer")
local autoRollFreeTimerUpdated = RemotesBootstrap:WaitForChild("AutoRollFreeTimerUpdated")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

-- Fired the moment the free 30-min wait actually completes and the grant
-- is applied -- Main.server.luau listens and calls StatsManager.Recompute
-- (pushing the fresh StatsUpdated.OwnsAutoRoll=true that RollPanel.luau
-- reacts to). Can't call StatsManager directly from in here: StatsManager
-- already requires THIS module to read Owns() for its own payload (see
-- this file's header comment), so the reverse require would cycle.
AutoRollManager.FreeGranted = Instance.new("BindableEvent")

local function attempt(fn): (boolean, any)
	for i = 1, RETRY_COUNT do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if i < RETRY_COUNT then
			task.wait(RETRY_BACKOFF_SECONDS)
		end
	end
	return false, nil
end

function AutoRollManager.Load(player: Player)
	local ok, owns = attempt(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, AutoRollConfig.GamepassId)
	end)

	if ok then
		ownsCache[player] = owns == true
	else
		ownsCache[player] = false
		warn(string.format("[AutoRollManager] Failed to check Auto Roll gamepass for %s (%d) after %d attempts", player.Name, player.UserId, RETRY_COUNT))
	end
end

-- Real gamepass ownership OR the free 30-min offer having been completed
-- at some point in the past (permanent either way) -- every existing
-- caller (StatsManager, RollManager, SetAutoRoll below) already just wants
-- "can this player use Auto Roll", not which path got them there.
function AutoRollManager.Owns(player: Player): boolean
	if ownsCache[player] == true then
		return true
	end
	local session = DataManager.Get(player)
	return session ~= nil and session.AutoRollFreeGranted == true
end

function AutoRollManager.Grant(player: Player)
	ownsCache[player] = true
end

function AutoRollManager.Release(player: Player)
	ownsCache[player] = nil
	-- Disconnecting mid-wait forfeits progress -- see freeTimerStart's own
	-- comment for why nothing here needs to be persisted first.
	freeTimerStart[player] = nil
end

setAutoRoll.OnServerEvent:Connect(function(player: Player, enabled: unknown)
	if typeof(enabled) ~= "boolean" then
		return
	end
	if not DataManager.Get(player) then
		return
	end
	if enabled and not AutoRollManager.Owns(player) then
		return
	end

	autoRollUpdated:FireClient(player, enabled)
end)

startAutoRollFreeTimer.OnServerEvent:Connect(function(player: Player)
	if not DataManager.Get(player) then
		return
	end
	if AutoRollManager.Owns(player) then
		return
	end

	local startedAt = freeTimerStart[player]
	if not startedAt then
		startedAt = os.time()
		freeTimerStart[player] = startedAt
	end

	local remaining = AutoRollConfig.FreeUnlockSeconds - (os.time() - startedAt)
	autoRollFreeTimerUpdated:FireClient(player, math.max(remaining, 0))
end)

-- Polls active waits instead of one thread-per-player -- at most a handful
-- of players are ever mid-wait at once, so a shared 5s sweep is far
-- cheaper than N separate task.delay/task.wait chains, and naturally
-- self-cleans (PlayerRemoving already clears the entry on disconnect).
task.spawn(function()
	while true do
		task.wait(FREE_TIMER_CHECK_INTERVAL_SECONDS)
		local now = os.time()
		for player, startedAt in freeTimerStart do
			if now - startedAt >= AutoRollConfig.FreeUnlockSeconds then
				freeTimerStart[player] = nil
				local session = DataManager.Get(player)
				if session then
					session.AutoRollFreeGranted = true
					systemMessage:FireClient(player, "Auto Roll unlocked for free!")
					AutoRollManager.FreeGranted:Fire(player)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	AutoRollManager.Release(player)
end)

return AutoRollManager
