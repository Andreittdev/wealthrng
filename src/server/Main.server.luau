-- The only auto-run Script in src/server (named Main, not init, so it syncs
-- as an ordinary child of ServerScriptService with no init-file ambiguity).
-- Requires every manager in a fixed order (RemotesBootstrap first, so
-- remotes exist before anything listens on them), owns PlayerAdded
-- sequencing, and owns MarketplaceService.PromptGamePassPurchaseFinished
-- (kept out of VIPManager to avoid a VIPManager <-> StatsManager circular require).

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)

require(ServerScriptService.RemotesBootstrap)
require(ServerScriptService.MapBuilder).BuildIfMissing()

local DataManager = require(ServerScriptService.Managers.DataManager)
local Leaderstats = require(ServerScriptService.Managers.Leaderstats)
local VIPManager = require(ServerScriptService.Managers.VIPManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)

require(ServerScriptService.Managers.RollManager)
require(ServerScriptService.Managers.SellManager)

local function onPlayerAdded(player: Player)
	DataManager.Load(player)
	VIPManager.Load(player)
	Leaderstats.Create(player)
	StatsManager.Recompute(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, wasPurchased: boolean)
	if wasPurchased and gamePassId == VIPConfig.GamepassId then
		VIPManager.Grant(player)
		StatsManager.Recompute(player)
	end
end)
