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
			return entry
		end
	end
	return nil
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
