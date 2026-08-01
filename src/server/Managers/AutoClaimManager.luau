-- Auto Claim gamepass ownership, cached per session -- mirrors
-- AutoRollManager's shape exactly (Load/Owns/Grant/Release, same retry
-- logic). UNLIKE Auto Roll's toggle (pure client-side state, no server
-- memory needed -- RollPanel.luau just stops requesting rolls), Auto
-- Claim's on/off state (SetAutoClaim below) has to be persisted
-- server-side in session.AutoClaimEnabled, because the actual claiming
-- happens in RollManager.luau's server-side per-second loop, which needs
-- to know the toggle state independent of whether the player's client is
-- even open. Deliberately does NOT require RollManager, same reasoning as
-- AutoRollManager -- StatsManager needs to read Owns() for the StatsUpdated
-- payload, and RollManager already requires StatsManager, so this module
-- has to stay a leaf or that becomes a require cycle.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AutoClaimConfig = require(ReplicatedStorage.Modules.AutoClaimConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)

local setAutoClaim = RemotesBootstrap:WaitForChild("SetAutoClaim")
local autoClaimUpdated = RemotesBootstrap:WaitForChild("AutoClaimUpdated")

local AutoClaimManager = {}

local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2

local ownsCache: { [Player]: boolean } = {}

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

function AutoClaimManager.Load(player: Player)
	local ok, owns = attempt(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, AutoClaimConfig.GamepassId)
	end)

	if ok then
		ownsCache[player] = owns == true
	else
		ownsCache[player] = false
		warn(string.format("[AutoClaimManager] Failed to check Auto Claim gamepass for %s (%d) after %d attempts", player.Name, player.UserId, RETRY_COUNT))
	end
end

function AutoClaimManager.Owns(player: Player): boolean
	return ownsCache[player] == true
end

function AutoClaimManager.Grant(player: Player)
	ownsCache[player] = true
end

function AutoClaimManager.Release(player: Player)
	ownsCache[player] = nil
end

-- What RollManager.luau's per-second loop actually checks -- ownership
-- AND the persisted toggle both have to be true. A non-owner's toggle
-- state is irrelevant (never even reaches "on" since SetAutoClaim rejects
-- them below), but checking both here means RollManager never has to know
-- there are two separate conditions.
function AutoClaimManager.IsEnabled(player: Player): boolean
	if not AutoClaimManager.Owns(player) then
		return false
	end
	local session = DataManager.Get(player)
	return session ~= nil and session.AutoClaimEnabled == true
end

-- Pushes the current toggle state -- used both for the initial-join push
-- (Main.server.luau) and after a successful SetAutoClaim, so the client's
-- ON/OFF badge (LuckyRollProximityPanel.luau) can't drift from reality.
function AutoClaimManager.PushState(player: Player)
	local session = DataManager.Get(player)
	if session then
		autoClaimUpdated:FireClient(player, session.AutoClaimEnabled)
	end
end

setAutoClaim.OnServerEvent:Connect(function(player: Player, enabled: unknown)
	if typeof(enabled) ~= "boolean" then
		return
	end
	local session = DataManager.Get(player)
	if not session then
		return
	end
	if enabled and not AutoClaimManager.Owns(player) then
		return
	end

	session.AutoClaimEnabled = enabled
	AutoClaimManager.PushState(player)
end)

Players.PlayerRemoving:Connect(function(player)
	AutoClaimManager.Release(player)
end)

return AutoClaimManager
