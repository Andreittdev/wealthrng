-- Named Main (not init) so it syncs as an ordinary LocalScript child of
-- StarterPlayerScripts, sibling to the UI folder -- avoids any ambiguity
-- around Rojo's init-file convention when $path targets a fixed-class service.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local MainUI = require(script.Parent.UI:WaitForChild("MainUI"))
MainUI.Init()

-- LeaderboardManager fires this only at the affected player (a rank
-- change on one of the top-100 boards) -- DisplaySystemMessage called
-- from the client only shows locally, which is exactly what a personal
-- "you're #67 now" notice should do, not a server-wide broadcast.
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
