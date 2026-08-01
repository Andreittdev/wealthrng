-- Handles SellItem: server-authoritative, validates the uid actually
-- belongs to the requesting player's inventory before crediting cash.
-- ComputeSellValue is exported so RollManager's auto-sell-duplicates path
-- (see SetAutoSellDuplicate below) credits the exact same VIP/Potion-boosted
-- amount a manual sell would, without duplicating the formula.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local PotionConfig = require(ReplicatedStorage.Modules.PotionConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local VIPManager = require(ServerScriptService.Managers.VIPManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)
local DoubleCashManager = require(ServerScriptService.Managers.DoubleCashManager)

local sellItem = RemotesBootstrap:WaitForChild("SellItem")
local setAutoSellDuplicate = RemotesBootstrap:WaitForChild("SetAutoSellDuplicate")
local inventoryUpdated = RemotesBootstrap:WaitForChild("InventoryUpdated")
local equippedItemsUpdated = RemotesBootstrap:WaitForChild("EquippedItemsUpdated")
local autoSellDuplicatesUpdated = RemotesBootstrap:WaitForChild("AutoSellDuplicatesUpdated")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local SellManager = {}

function SellManager.ComputeSellValue(session, isVIP: boolean, item: ItemDatabase.Item, doubleCashBonusPercent: number): number
	local bonusPercent = PotionConfig.GetCashBonusPercent(session, os.time()) + doubleCashBonusPercent
	if isVIP then
		bonusPercent += VIPConfig.SellBonusPercent
	end
	return math.floor(item.Value * (1 + bonusPercent / 100))
end

sellItem.OnServerEvent:Connect(function(player: Player, uid: number)
	if typeof(uid) ~= "number" then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	local removed = InventoryManager.RemoveItem(player, uid)
	if not removed then
		return
	end

	local item = ItemDatabase.GetItem(removed.ItemId)
	if item then
		local payout = SellManager.ComputeSellValue(session, VIPManager.IsVIP(player), item, DoubleCashManager.GetBonusPercent(player))
		session.Cash += payout
		systemMessage:FireClient(player, string.format("Sold %s for %s!", item.Name, NumberFormat.FormatCash(payout)))
	end

	inventoryUpdated:FireClient(player, session.Inventory)
	-- Selling an equipped item silently drops it from EquippedItemUids too
	-- (InventoryManager.RemoveItem's cleanup) -- keep the client's equipped
	-- set in sync, not just the inventory list.
	equippedItemsUpdated:FireClient(player, session.EquippedItemUids)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

local raritySet: { [string]: boolean } = {}
for _, rarity in RarityConfig.Order do
	raritySet[rarity] = true
end

setAutoSellDuplicate.OnServerEvent:Connect(function(player: Player, rarity: unknown, enabled: unknown)
	if typeof(rarity) ~= "string" or typeof(enabled) ~= "boolean" or not raritySet[rarity] then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	session.AutoSellDuplicates[rarity] = enabled
	autoSellDuplicatesUpdated:FireClient(player, session.AutoSellDuplicates)
end)

return SellManager
