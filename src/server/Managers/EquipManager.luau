-- Handles EquipItem/UnequipItem: picks which held/rolled items (capped at
-- ItemDatabase.MaxEquipped) actively earn IncomePerSecond. Unequipped
-- items still count their Value toward Net Worth (via
-- InventoryManager.GetValue) -- they just stop generating passive income.
-- Mirrors AssetManager's Equip/Unequip pattern, but for rolled items
-- instead of Assets. Never required by StatsManager -- see IncomeConfig's
-- header for why that would cycle.

local ServerScriptService = game:GetService("ServerScriptService")

local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local equipItem = RemotesBootstrap:WaitForChild("EquipItem")
local unequipItem = RemotesBootstrap:WaitForChild("UnequipItem")
local equippedItemsUpdated = RemotesBootstrap:WaitForChild("EquippedItemsUpdated")

equipItem.OnServerEvent:Connect(function(player: Player, uid: number)
	if typeof(uid) ~= "number" then
		return
	end

	if not InventoryManager.Equip(player, uid) then
		return
	end

	local session = DataManager.Get(player)
	equippedItemsUpdated:FireClient(player, session.EquippedItemUids)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

unequipItem.OnServerEvent:Connect(function(player: Player, uid: number)
	if typeof(uid) ~= "number" then
		return
	end

	if not InventoryManager.Unequip(player, uid) then
		return
	end

	local session = DataManager.Get(player)
	equippedItemsUpdated:FireClient(player, session.EquippedItemUids)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
