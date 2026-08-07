-- Floating title tag ("Millionaire", "Billionaire", etc. -- see
-- TitleConfig.luau) above every player's head, visible to EVERYONE
-- including the player themself -- server-authored BillboardGui parented
-- under the real Character, so it replicates automatically to every
-- client like any other part (same idiom PetManager.luau uses for its
-- floating pets). Replaces Roblox's default username nametag, which
-- Main.server.luau explicitly disables per-Humanoid, per explicit request
-- ("only the title, not the username").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TitleConfig = require(ReplicatedStorage.Modules.TitleConfig)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)

local TitleTagManager = {}

local TAG_COLOR = Color3.fromRGB(255, 221, 0)

local function applyTitleTag(character: Model, title: string)
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end

	local billboard = head:FindFirstChild("TitleTag") :: BillboardGui?
	if not billboard then
		billboard = Instance.new("BillboardGui")
		billboard.Name = "TitleTag"
		billboard.Size = UDim2.new(0, 160, 0, 24)
		billboard.StudsOffset = Vector3.new(0, 2.6, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = head

		local label = Instance.new("TextLabel")
		label.Name = "TitleLabel"
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.LuckiestGuy
		label.TextScaled = true
		label.TextColor3 = TAG_COLOR
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.Parent = billboard
	end

	local label = billboard:FindFirstChild("TitleLabel") :: TextLabel
	label.Text = title
end

local function refresh(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local session = DataManager.Get(player)
	if not session then
		return
	end

	local netWorth = StatsManager.ComputeNetWorth(player)
	local title = TitleConfig.GetTitleForNetWorth(netWorth)
	applyTitleTag(character, title)
end

-- Only fires when the title actually changed (see StatsManager.Recompute),
-- not on every Cash tick -- no need to poll every player on a timer.
StatsManager.TitleChanged.Event:Connect(function(player: Player)
	refresh(player)
end)

local function onCharacterAdded(player: Player, character: Model)
	character:WaitForChild("Head", 10)
	refresh(player)
end

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
end)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

return TitleTagManager
