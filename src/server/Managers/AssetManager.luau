-- Multi-owned Assets: buy any number of asset types outright (no upgrade
-- ladder), but only AssetDatabase.MaxEquipped of them actively generate
-- income at once -- Equip/Unequip picks which. Server-authoritative:
-- price/ownership/equip-cap checks are all re-derived here, never trusted
-- from the client. No Sell -- once bought (or won), an Estate is yours for
-- good.
-- Never required by StatsManager (which needs Asset value/income for its
-- own display) -- see IncomeConfig's header for why that would cycle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local buyAsset = RemotesBootstrap:WaitForChild("BuyAsset")
local equipAsset = RemotesBootstrap:WaitForChild("EquipAsset")
local unequipAsset = RemotesBootstrap:WaitForChild("UnequipAsset")
local assetUpdated = RemotesBootstrap:WaitForChild("AssetUpdated")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local AssetManager = {}

local function pushUpdate(player: Player, session)
	assetUpdated:FireClient(player, { Owned = session.OwnedAssets, Equipped = session.EquippedAssets })
end

-- Grants an Asset for free -- no Cash deducted, no ownership/price checks
-- (unlike buyAsset below). Used by BattleLeaderboardRewardManager.luau to
-- hand out the LARP Battles Top 3 reward estates. Idempotent -- a no-op if
-- the player already owns it (can't happen twice for the same week, but
-- safe regardless).
function AssetManager.GrantAsset(player: Player, session, assetId: string)
	if session.OwnedAssets[assetId] then
		return
	end

	local asset = AssetDatabase.GetAsset(assetId)
	if not asset then
		return
	end

	session.OwnedAssets[assetId] = true

	systemMessage:FireClient(player, string.format("You won %s!", asset.Name))
	pushUpdate(player, session)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
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

	systemMessage:FireClient(player, string.format("Bought %s for %s!", asset.Name, NumberFormat.FormatCash(asset.Price)))
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

return AssetManager
