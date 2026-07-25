-- Handles SellItem: server-authoritative, validates the uid actually
-- belongs to the requesting player's inventory before crediting cash.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local VIPManager = require(ServerScriptService.Managers.VIPManager)

local sellItem = RemotesBootstrap:WaitForChild("SellItem")
local inventoryUpdated = RemotesBootstrap:WaitForChild("InventoryUpdated")

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
		local value = item.Value
		if VIPManager.IsVIP(player) then
			value = math.floor(value * (1 + VIPConfig.SellBonusPercent / 100))
		end
		session.Cash += value
	end

	inventoryUpdated:FireClient(player, session.Inventory)
	StatsManager.Recompute(player)
end)
