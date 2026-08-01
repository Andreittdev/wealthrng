-- Handles SetPreference: Music/SFX/VFX on-off toggles from SettingsPanel.
-- Purely persisted state for now -- nothing in the game actually reads
-- these yet (no sounds/particles exist), this just saves the toggle so
-- it's ready the moment something does.

local ServerScriptService = game:GetService("ServerScriptService")

local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)

local setPreference = RemotesBootstrap:WaitForChild("SetPreference")
local preferencesUpdated = RemotesBootstrap:WaitForChild("PreferencesUpdated")

-- HideOtherPlayers is purely a client-side rendering toggle (see
-- HideOtherPlayers.luau) -- persisted here the same way as Music/SFX/VFX
-- just so the choice survives across sessions, nothing server-side reads it.
local VALID_KEYS = { Music = true, SFX = true, VFX = true, HideOtherPlayers = true }

setPreference.OnServerEvent:Connect(function(player: Player, key: unknown, enabled: unknown)
	if typeof(key) ~= "string" or typeof(enabled) ~= "boolean" or not VALID_KEYS[key] then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	session.Preferences[key] = enabled
	preferencesUpdated:FireClient(player, session.Preferences)
end)

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
