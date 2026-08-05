-- Persists whether a player has clicked through the new-player onboarding
-- walkthrough (OnboardingTutorial.luau client-side: roll -> equip ->
-- explore) so it never shows again once seen. Deliberately dumb/passive,
-- same shape as TutorialHintManager.luau: the client decides when to show
-- each step, this just remembers "done" for next time.

local ServerScriptService = game:GetService("ServerScriptService")

local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)

local markOnboardingComplete = RemotesBootstrap:WaitForChild("MarkOnboardingComplete")

local OnboardingManager = {}

markOnboardingComplete.OnServerEvent:Connect(function(player: Player)
	local session = DataManager.Get(player)
	if not session then
		return
	end

	session.CompletedOnboarding = true
end)

return OnboardingManager
