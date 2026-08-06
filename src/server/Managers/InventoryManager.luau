-- Pure table manipulation over a player's DataManager session -- no
-- Instance-per-item, the client just gets a payload over InventoryUpdated.
--
-- Also the ONLY place that mutates session.Inventory/EquippedItemUids, so
-- it's the one place responsible for keeping the 3 derived fields
-- (OwnedItemCounts, InventoryTotalValue, EquippedItemId -- see DataManager.
-- Session's comment) in sync incrementally, rather than every caller
-- (RollManager's auto-sell-duplicates check, IncomeConfig's item-income
-- lookup, StatsManager's Net Worth) re-scanning the full Inventory array
-- on every single roll. Get out of sync here and every one of those goes
-- quietly wrong, so every mutation below updates them in the same breath
-- as the underlying array.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local DataManager = require(ServerScriptService.Managers.DataManager)

local InventoryManager = {}

-- Fired whenever session.EquippedItemId actually changes (Equip/Unequip
-- succeeding, or RemoveItem force-unequipping a sold equipped item) --
-- PetManager.luau listens for this the same way it listens to
-- AssetManager.EquippedAssetsChanged, to float a pet for an equipped
-- Crate-exclusive Estate item too, not just equipped Assets.
InventoryManager.EquippedItemChanged = Instance.new("BindableEvent")

function InventoryManager.AddItem(player: Player, itemId: string)
	local session = DataManager.Get(player)
	if not session then
		return nil
	end

	local uid = session.NextUid
	session.NextUid += 1

	local entry = { Uid = uid, ItemId = itemId }
	table.insert(session.Inventory, entry)

	session.OwnedItemCounts[itemId] = (session.OwnedItemCounts[itemId] or 0) + 1
	local item = ItemDatabase.GetItem(itemId)
	if item then
		session.InventoryTotalValue += item.Value
	end

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

			local currentCount = session.OwnedItemCounts[entry.ItemId]
			if currentCount then
				if currentCount <= 1 then
					session.OwnedItemCounts[entry.ItemId] = nil
				else
					session.OwnedItemCounts[entry.ItemId] = currentCount - 1
				end
			end
			local item = ItemDatabase.GetItem(entry.ItemId)
			if item then
				session.InventoryTotalValue -= item.Value
			end

			-- A sold item can't stay "equipped" earning income it no
			-- longer holds -- drop it from the equipped set too.
			local equippedIndex = table.find(session.EquippedItemUids, uid)
			if equippedIndex then
				table.remove(session.EquippedItemUids, equippedIndex)
				session.EquippedItemId = nil
				InventoryManager.EquippedItemChanged:Fire(player)
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

	local ownedItemId: string? = nil
	for _, entry in session.Inventory do
		if entry.Uid == uid then
			ownedItemId = entry.ItemId
			break
		end
	end
	if not ownedItemId then
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
	-- Only meaningful while MaxEquipped stays 1 -- see EquippedItemId's
	-- comment in DataManager.luau.
	session.EquippedItemId = ownedItemId
	InventoryManager.EquippedItemChanged:Fire(player)
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
	session.EquippedItemId = nil
	InventoryManager.EquippedItemChanged:Fire(player)
	return true
end

-- O(1) -- session.InventoryTotalValue is kept in sync incrementally by
-- AddItem/RemoveItem above instead of re-summing the full Inventory array
-- on every call (this runs via StatsManager.Recompute on every roll).
function InventoryManager.GetValue(player: Player): number
	local session = DataManager.Get(player)
	if not session then
		return 0
	end
	return session.InventoryTotalValue
end

return InventoryManager
