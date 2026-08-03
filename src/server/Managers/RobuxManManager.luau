-- "Robux Man" NPC dialogue -- MapBuilder.luau positions the model and
-- attaches its "RobuxManPrompt" ProximityPrompt; this owns what happens
-- when it's triggered. No real chat/AI -- a classic branching NPC Dialog:
-- a bubble-chat greeting (Chat:Chat, the plain white Roblox bubble, same
-- as any NPC "talking" without a real player behind it), then a small set
-- of reply choices sent to just that one player (RobuxManDialogChoices.luau
-- shows them as floating buttons, not a big modal panel). Picking a real
-- question answers with another bubble AND a single "End this
-- conversation" button that stays up for ANSWER_DISPLAY_SECONDS (auto-
-- dismissing on its own if the player never clicks it) -- picking "End the
-- conversation" from the first choice screen just closes it immediately,
-- no bubble.
--
-- Runs after MapBuilder.Build() (see Main.server.luau's require order), so
-- "Robux Man" and its prompt already exist by the time this looks for them.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Chat = game:GetService("Chat")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ServerScriptService = game:GetService("ServerScriptService")

local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)

local robuxManShowChoices = RemotesBootstrap:WaitForChild("RobuxManShowChoices")
local robuxManChoiceSelected = RemotesBootstrap:WaitForChild("RobuxManChoiceSelected")

local GREETING = "Hello, how can I help you?"
local ANSWER_DISPLAY_SECONDS = 15

-- Answer is nil for "just end the conversation" -- no follow-up bubble.
local CHOICES = {
	{
		Id = "LarpBattlesLeaderboard",
		Text = "What is the point of Larp Battles Leaderboard?",
		Answer = "The Leaderboard resets weekly and it gives the Top 3 Players a Rare Estate that can't be obtained from anywhere else! You get points from Casual and Multiplayer gamemode!",
	},
	{ Id = "End", Text = "End the conversation", Answer = nil },
}

local robuxMan = Workspace:FindFirstChild("Robux Man")
local bubbleAnchor = robuxMan and (robuxMan:FindFirstChild("Head") or robuxMan.PrimaryPart)

if robuxMan and bubbleAnchor then
	-- Guards the delayed auto-hide below against a stale conversation
	-- clobbering a NEWER one -- e.g. the player re-triggers Talk (or picks
	-- another question) well within the 15s window; only the most recent
	-- answer's own timer is allowed to hide the End button.
	local activeAnswerToken: { [Player]: {} } = {}

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if prompt.Name ~= "RobuxManPrompt" then
			return
		end

		activeAnswerToken[player] = nil
		Chat:Chat(bubbleAnchor, GREETING, Enum.ChatColor.White)

		local choicesPayload = {}
		for _, choice in CHOICES do
			table.insert(choicesPayload, { Id = choice.Id, Text = choice.Text })
		end
		robuxManShowChoices:FireClient(player, choicesPayload)
	end)

	robuxManChoiceSelected.OnServerEvent:Connect(function(player: Player, choiceId: string)
		for _, choice in CHOICES do
			if choice.Id == choiceId then
				if choice.Answer then
					Chat:Chat(bubbleAnchor, choice.Answer, Enum.ChatColor.White)

					local token = {}
					activeAnswerToken[player] = token
					robuxManShowChoices:FireClient(player, { { Id = "End", Text = "End this conversation" } })

					task.delay(ANSWER_DISPLAY_SECONDS, function()
						if activeAnswerToken[player] == token then
							activeAnswerToken[player] = nil
							robuxManShowChoices:FireClient(player, {})
						end
					end)
				else
					activeAnswerToken[player] = nil
					robuxManShowChoices:FireClient(player, {})
				end
				return
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		activeAnswerToken[player] = nil
	end)
end

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
