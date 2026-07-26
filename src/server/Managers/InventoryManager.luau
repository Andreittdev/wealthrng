-- Pure table manipulation over a player's DataManager session -- no
-- Instance-per-item, the client just gets a payload over InventoryUpdated.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local DataManager = require(ServerScriptService.Managers.DataManager)

local InventoryManager = {}

function InventoryManager.AddItem(player: Player, itemId: string)
	local session = DataManager.Get(player)
	if not session then
		return nil
	end

	local uid = session.NextUid
	session.NextUid += 1

	local entry = { Uid = uid, ItemId = itemId }
	table.insert(session.Inventory, entry)
	return entry
end

function InventoryManager.RemoveItem(player: Player, uid: number)
	local session = DataManager.Get(player)
	if not session then
		return nil
	end

	for index, entry in session.Inventory do
		if entry.Uid == uid then
			table.remove(session.Inventory, index)

			-- A sold item can't stay "equipped" earning income it no
			-- longer holds -- drop it from the equipped set too.
			local equippedIndex = table.find(session.EquippedItemUids, uid)
			if equippedIndex then
				table.remove(session.EquippedItemUids, equippedIndex)
			end

			return entry
		end
	end
	return nil
end

-- Equip/Unequip pick which held items actively earn IncomePerSecond (see
-- ItemDatabase.MaxEquipped) -- pure state mutation only, no StatsManager/
-- remote calls here, so this stays a leaf callable from RollManager/
-- SellManager without risking a circular require; EquipManager.luau owns
-- the remote wiring + StatsManager.Recompute side effects.
function InventoryManager.Equip(player: Player, uid: number): boolean
	local session = DataManager.Get(player)
	if not session then
		return false
	end

	local owned = false
	for _, entry in session.Inventory do
		if entry.Uid == uid then
			owned = true
			break
		end
	end
	if not owned then
		return false
	end

	if table.find(session.EquippedItemUids, uid) then
		return false
	end

	-- Swap out the oldest equipped item(s) to make room instead of
	-- requiring a manual Unequip first -- with MaxEquipped at 1, picking a
	-- new item just replaces whatever was equipped before.
	while #session.EquippedItemUids >= ItemDatabase.MaxEquipped do
		table.remove(session.EquippedItemUids, 1)
	end

	table.insert(session.EquippedItemUids, uid)
	return true
end

function InventoryManager.Unequip(player: Player, uid: number): boolean
	local session = DataManager.Get(player)
	if not session then
		return false
	end

	local index = table.find(session.EquippedItemUids, uid)
	if not index then
		return false
	end

	table.remove(session.EquippedItemUids, index)
	return true
end

function InventoryManager.GetValue(player: Player): number
	local session = DataManager.Get(player)
	if not session then
		return 0
	end

	local total = 0
	for _, entry in session.Inventory do
		local item = ItemDatabase.GetItem(entry.ItemId)
		if item then
			total += item.Value
		end
	end
	return total
end

return InventoryManager
