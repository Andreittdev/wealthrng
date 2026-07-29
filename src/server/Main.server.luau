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
local AutoRollConfig = require(ReplicatedStorage.Modules.AutoRollConfig)

-- The Emitter2D particle system (src/client/Emitter2D.rbxm) blocks forever
-- on require() waiting for this attribute -- it's normally set by the
-- Emitter2D Studio plugin, but plugins don't run during Play-test/live
-- gameplay, only in Studio's own edit-mode. Setting it low (not the real
-- installed version) is safe: the module only errors if this is HIGHER
-- than its own bundled version, never if it's lower.
ReplicatedStorage:SetAttribute("Emitter2D_Version", 0)

local remotesFolder = require(ServerScriptService.RemotesBootstrap)
require(ServerScriptService.MapBuilder).Build()

local inventoryUpdated = remotesFolder:WaitForChild("InventoryUpdated")
local equippedItemsUpdated = remotesFolder:WaitForChild("EquippedItemsUpdated")
local assetUpdated = remotesFolder:WaitForChild("AssetUpdated")
local investmentUpdated = remotesFolder:WaitForChild("InvestmentUpdated")
local potionUpdated = remotesFolder:WaitForChild("PotionUpdated")
local autoSellDuplicatesUpdated = remotesFolder:WaitForChild("AutoSellDuplicatesUpdated")
local preferencesUpdated = remotesFolder:WaitForChild("PreferencesUpdated")
local upgradesUpdated = remotesFolder:WaitForChild("UpgradesUpdated")
local groupRewardStateUpdated = remotesFolder:WaitForChild("GroupRewardStateUpdated")
local systemMessage = remotesFolder:WaitForChild("SystemMessage")
local clientReady = remotesFolder:WaitForChild("ClientReady")

local DataManager = require(ServerScriptService.Managers.DataManager)
local Leaderstats = require(ServerScriptService.Managers.Leaderstats)
local VIPManager = require(ServerScriptService.Managers.VIPManager)
local AutoRollManager = require(ServerScriptService.Managers.AutoRollManager)
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
require(ServerScriptService.Managers.UpgradeManager)
require(ServerScriptService.Managers.GroupRewardsManager)
local DailyRewardsManager = require(ServerScriptService.Managers.DailyRewardsManager)
local PlaytimeRewardsManager = require(ServerScriptService.Managers.PlaytimeRewardsManager)

-- Initial pushes (saved Inventory/Assets/Investments/etc.) fire TWICE, on
-- purpose: once immediately after DataManager.Load (the old behavior --
-- fast, but can race MainUI still constructing panels client-side and get
-- silently dropped for whichever panels hadn't connected their
-- OnClientEvent listener yet), and again whenever the client's own
-- ClientReady signal arrives (fires once MainUI has finished building
-- everything, so it can't be dropped that way -- but waiting on it
-- EXCLUSIVELY would mean one missed/failed signal loses the data
-- entirely, worse than the original race). Receiving the same snapshot
-- twice is harmless -- every panel just overwrites its local copy -- so
-- "send twice, whichever lands is enough" is strictly safer than either
-- one alone.
local function sendInitialState(player: Player)
	local session = DataManager.Get(player)
	if not session then
		return
	end

	inventoryUpdated:FireClient(player, session.Inventory)
	equippedItemsUpdated:FireClient(player, session.EquippedItemUids)
	assetUpdated:FireClient(player, { Owned = session.OwnedAssets, Equipped = session.EquippedAssets })
	investmentUpdated:FireClient(player, session.Investments)
	potionUpdated:FireClient(player, session.ActivePotions)
	autoSellDuplicatesUpdated:FireClient(player, session.AutoSellDuplicates)
	preferencesUpdated:FireClient(player, session.Preferences)
	upgradesUpdated:FireClient(player, session.Upgrades)
	groupRewardStateUpdated:FireClient(player, session.ClaimedGroupReward)
	DailyRewardsManager.PushState(player)
	PlaytimeRewardsManager.PushState(player)
end

local function onPlayerAdded(player: Player)
	DataManager.Load(player)
	VIPManager.Load(player)
	AutoRollManager.Load(player)
	Leaderstats.Create(player)
	StatsManager.Recompute(player)
	-- So a player shows up on the boards from their very first stats
	-- submission instead of waiting until their first roll/sell/etc.
	-- marks them dirty.
	LeaderboardManager.MarkDirty(player)

	sendInitialState(player)
end

clientReady.OnServerEvent:Connect(function(player: Player)
	sendInitialState(player)
end)

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, wasPurchased: boolean)
	if not wasPurchased then
		return
	end
	if gamePassId == VIPConfig.GamepassId then
		VIPManager.Grant(player)
		systemMessage:FireClient(player, "VIP Gamepass Activated!")
		StatsManager.Recompute(player)
	elseif gamePassId == AutoRollConfig.GamepassId then
		AutoRollManager.Grant(player)
		systemMessage:FireClient(player, "Auto Roll Gamepass Activated!")
		StatsManager.Recompute(player)
	end
end)
