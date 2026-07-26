-- Handles SellItem: server-authoritative, validates the uid actually
-- belongs to the requesting player's inventory before crediting cash.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local PotionConfig = require(ReplicatedStorage.Modules.PotionConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local VIPManager = require(ServerScriptService.Managers.VIPManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local sellItem = RemotesBootstrap:WaitForChild("SellItem")
local inventoryUpdated = RemotesBootstrap:WaitForChild("InventoryUpdated")
local equippedItemsUpdated = RemotesBootstrap:WaitForChild("EquippedItemsUpdated")

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
		local bonusPercent = PotionConfig.GetCashBonusPercent(session, os.time())
		if VIPManager.IsVIP(player) then
			bonusPercent += VIPConfig.SellBonusPercent
		end
		local value = math.floor(item.Value * (1 + bonusPercent / 100))
		session.Cash += value
	end

	inventoryUpdated:FireClient(player, session.Inventory)
	-- Selling an equipped item silently drops it from EquippedItemUids too
	-- (InventoryManager.RemoveItem's cleanup) -- keep the client's equipped
	-- set in sync, not just the inventory list.
	equippedItemsUpdated:FireClient(player, session.EquippedItemUids)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
