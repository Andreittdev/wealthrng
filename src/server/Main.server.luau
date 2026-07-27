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

local remotesFolder = require(ServerScriptService.RemotesBootstrap)
require(ServerScriptService.MapBuilder).Build()

local inventoryUpdated = remotesFolder:WaitForChild("InventoryUpdated")
local equippedItemsUpdated = remotesFolder:WaitForChild("EquippedItemsUpdated")
local assetUpdated = remotesFolder:WaitForChild("AssetUpdated")
local investmentUpdated = remotesFolder:WaitForChild("InvestmentUpdated")
local potionUpdated = remotesFolder:WaitForChild("PotionUpdated")
local autoSellDuplicatesUpdated = remotesFolder:WaitForChild("AutoSellDuplicatesUpdated")
local preferencesUpdated = remotesFolder:WaitForChild("PreferencesUpdated")

local DataManager = require(ServerScriptService.Managers.DataManager)
local Leaderstats = require(ServerScriptService.Managers.Leaderstats)
local VIPManager = require(ServerScriptService.Managers.VIPManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)

local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)
require(ServerScriptService.Managers.IncomeManager)
require(ServerScriptService.Managers.RollManager)
require(ServerScriptService.Managers.SellManager)
require(ServerScriptService.Managers.AssetManager)
require(ServerScriptService.Managers.InvestmentManager)
require(ServerScriptService.Managers.PotionManager)
require(ServerScriptService.Managers.EquipManager)
require(ServerScriptService.Managers.TradeManager)
require(ServerScriptService.Managers.PreferencesManager)

local function onPlayerAdded(player: Player)
	local session = DataManager.Load(player)
	VIPManager.Load(player)
	Leaderstats.Create(player)
	StatsManager.Recompute(player)
	-- So a player shows up on the boards from their very first stats
	-- submission instead of waiting until their first roll/sell/etc.
	-- marks them dirty.
	LeaderboardManager.MarkDirty(player)

	-- Initial pushes so a returning player sees their saved Inventory/
	-- EquippedItemUids/Asset/Investments/ActivePotions immediately instead
	-- of an empty list until their next action.
	inventoryUpdated:FireClient(player, session.Inventory)
	equippedItemsUpdated:FireClient(player, session.EquippedItemUids)
	assetUpdated:FireClient(player, { Owned = session.OwnedAssets, Equipped = session.EquippedAssets })
	investmentUpdated:FireClient(player, session.Investments)
	potionUpdated:FireClient(player, session.ActivePotions)
	autoSellDuplicatesUpdated:FireClient(player, session.AutoSellDuplicates)
	preferencesUpdated:FireClient(player, session.Preferences)
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
