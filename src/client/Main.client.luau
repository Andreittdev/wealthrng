-- Named Main (not init) so it syncs as an ordinary LocalScript child of
-- StarterPlayerScripts, sibling to the UI folder -- avoids any ambiguity
-- around Rojo's init-file convention when $path targets a fixed-class service.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local LoadingScreen = require(script.Parent.UI:WaitForChild("LoadingScreen"))
local MainUI = require(script.Parent.UI:WaitForChild("MainUI"))
local NotificationToast = require(script.Parent.UI:WaitForChild("NotificationToast"))
local HideOtherPlayers = require(script.Parent.UI:WaitForChild("HideOtherPlayers"))
local BattlePanel = require(script.Parent.UI:WaitForChild("BattlePanel"))
local ButtonClickSound = require(script.Parent.UI:WaitForChild("ButtonClickSound"))
local BackgroundMusic = require(script.Parent.UI:WaitForChild("BackgroundMusic"))

-- Before LoadingScreen/MainUI -- hooks every button game-wide via
-- PlayerGui:GetDescendants()/DescendantAdded (see its own header comment),
-- so it needs to start listening before MainUI.Init() builds every panel's
-- buttons, not after.
ButtonClickSound.Init()
-- Starts during the loading screen too -- no reason to wait for the rest
-- of the UI to finish building first.
BackgroundMusic.Init()

-- Called directly (not backgrounded) so the rest of the game's UI only
-- starts building AFTER the loading screen has fully held its 6s and faded
-- -- simpler to reason about than racing it against MainUI.Init() in a
-- separate coroutine, and matches how a loading screen is expected to
-- behave: nothing else happens until it's done.
LoadingScreen.Run()

local mainUIHandle = MainUI.Init()
NotificationToast.Init()
-- NextUpdateCountdown.Init() -- disabled, see MapBuilder.luau's matching note
HideOtherPlayers.Init()
BattlePanel.Init(mainUIHandle.SetBattleZoneActive)

-- Most SystemMessage pushes (rank changes, purchases, gamepass grants,
-- etc.) target one specific player via FireClient -- DisplaySystemMessage
-- called from the client only shows locally, which is exactly what a
-- personal "you're #67 now" notice should do. RollManager.luau's Ultra-item
-- unlock callout is the one exception: it's fired to everyone via
-- FireAllClients, since seeing someone else pull something rare is the
-- whole point of that one.
local systemMessage = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SystemMessage")
systemMessage.OnClientEvent:Connect(function(text: string)
	local ok = pcall(function()
		TextChatService.TextChannels.RBXGeneral:DisplaySystemMessage(text)
	end)
	if not ok then
		warn("[SystemMessage] " .. tostring(text))
	end
end)

-- Fire-and-forget: every rolled item's icon gets fetched into the client's
-- asset cache once, up front, instead of each ImageLabel triggering its
-- own fresh download the first time it's shown (roll spin cycles through
-- images every 0.06s -- without this they'd mostly render blank/pop-in
-- mid-spin). Backgrounded with task.spawn so a slow/failed fetch never
-- blocks MainUI or gameplay; "rbxassetid://0" placeholders are skipped,
-- nothing to preload there yet.
task.spawn(function()
	local imageIds = {}
	for _, item in ItemDatabase.GetAllItems() do
		if item.Image and item.Image ~= "" and item.Image ~= "rbxassetid://0" then
			table.insert(imageIds, item.Image)
		end
	end
	ContentProvider:PreloadAsync(imageIds)
end)
