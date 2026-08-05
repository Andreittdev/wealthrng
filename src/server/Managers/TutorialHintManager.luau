-- Persists which one-time tutorial hint callouts (TutorialHint.luau
-- client-side) a player has already dismissed -- e.g. the "UPGRADES"
-- pointer shown the first time that panel opens -- so they never show
-- again once seen. Deliberately dumb/passive: the client decides which
-- hints exist and when to show them, this just remembers "seen" per id.

local ServerScriptService = game:GetService("ServerScriptService")

local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)

local markTutorialHintSeen = RemotesBootstrap:WaitForChild("MarkTutorialHintSeen")

local TutorialHintManager = {}

markTutorialHintSeen.OnServerEvent:Connect(function(player: Player, hintId: unknown)
	if typeof(hintId) ~= "string" then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	session.SeenTutorialHints[hintId] = true
end)

return TutorialHintManager
