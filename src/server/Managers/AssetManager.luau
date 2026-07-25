-- Multi-owned Assets: buy any number of asset types outright (no upgrade
-- ladder), but only AssetDatabase.MaxEquipped of them actively generate
-- income at once -- Equip/Unequip picks which. Server-authoritative:
-- price/ownership/equip-cap checks are all re-derived here, never trusted
-- from the client.
-- Never required by StatsManager (which needs Asset value/income for its
-- own display) -- see IncomeConfig's header for why that would cycle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local buyAsset = RemotesBootstrap:WaitForChild("BuyAsset")
local sellAsset = RemotesBootstrap:WaitForChild("SellAsset")
local equipAsset = RemotesBootstrap:WaitForChild("EquipAsset")
local unequipAsset = RemotesBootstrap:WaitForChild("UnequipAsset")
local assetUpdated = RemotesBootstrap:WaitForChild("AssetUpdated")

local function pushUpdate(player: Player, session)
	assetUpdated:FireClient(player, { Owned = session.OwnedAssets, Equipped = session.EquippedAssets })
end

buyAsset.OnServerEvent:Connect(function(player: Player, assetId: string)
	if typeof(assetId) ~= "string" then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	if session.OwnedAssets[assetId] then
		return
	end

	local asset = AssetDatabase.GetAsset(assetId)
	if not asset or session.Cash < asset.Price then
		return
	end

	session.Cash -= asset.Price
	session.OwnedAssets[assetId] = true

	pushUpdate(player, session)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

equipAsset.OnServerEvent:Connect(function(player: Player, assetId: string)
	if typeof(assetId) ~= "string" then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	if not session.OwnedAssets[assetId] then
		return
	end

	if table.find(session.EquippedAssets, assetId) then
		return
	end

	if #session.EquippedAssets >= AssetDatabase.MaxEquipped then
		return
	end

	table.insert(session.EquippedAssets, assetId)

	pushUpdate(player, session)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

unequipAsset.OnServerEvent:Connect(function(player: Player, assetId: string)
	if typeof(assetId) ~= "string" then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	local index = table.find(session.EquippedAssets, assetId)
	if not index then
		return
	end

	table.remove(session.EquippedAssets, index)

	pushUpdate(player, session)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

sellAsset.OnServerEvent:Connect(function(player: Player, assetId: string)
	if typeof(assetId) ~= "string" then
		return
	end

	local session = DataManager.Get(player)
	if not session or not session.OwnedAssets[assetId] then
		return
	end

	local asset = AssetDatabase.GetAsset(assetId)
	if asset then
		session.Cash += math.floor(asset.Price * 0.5)
	end

	session.OwnedAssets[assetId] = nil
	local equippedIndex = table.find(session.EquippedAssets, assetId)
	if equippedIndex then
		table.remove(session.EquippedAssets, equippedIndex)
	end

	pushUpdate(player, session)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

-- Side-effect-only module -- see RollManager.luau's tail comment for why
-- this return is required even though nothing is exported.
return true
