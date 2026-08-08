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
local EstateExistenceManager = require(ServerScriptService.Managers.EstateExistenceManager)

local buyAsset = RemotesBootstrap:WaitForChild("BuyAsset")
local equipAsset = RemotesBootstrap:WaitForChild("EquipAsset")
local unequipAsset = RemotesBootstrap:WaitForChild("UnequipAsset")
local assetUpdated = RemotesBootstrap:WaitForChild("AssetUpdated")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local AssetManager = {}

-- Fired (player) whenever session.EquippedAssets actually changes (equip OR
-- unequip) -- PetManager.luau listens to this to know when to rebuild a
-- player's floating estate pets, without requiring AssetManager to know
-- anything about pets itself (same "expose a Bindable, don't require the
-- listener" shape as AutoRollManager.FreeGranted).
AssetManager.EquippedAssetsChanged = Instance.new("BindableEvent")

-- Top1Estate/Top2Estate (weekly LARP Battles leaderboard reward) and
-- Top3Estate ("Sol Stadium", the Meshy Stadium vendor) are the only Estates
-- that can be granted to the SAME player more than once -- a repeat weekly
-- winner, or an extra Sol Stadium purchase, gets a brand new copy (with its
-- own serial, see EstateExistenceManager.luau) instead of the grant being a
-- no-op. Every other Estate stays capped at 1 total, ever, per player.
local MULTI_OWNABLE_ASSET_IDS: { [string]: boolean } = {
	Top1Estate = true,
	Top2Estate = true,
	Top3Estate = true,
}
-- Exposed so TradeManager.luau's own ownership-validity check can allow
-- trading one of these TO a receiver who already owns a copy, instead of
-- treating every Estate as strictly 1-per-player like the rest.
AssetManager.MultiOwnableAssetIds = MULTI_OWNABLE_ASSET_IDS

local function pushUpdate(player: Player, session)
	assetUpdated:FireClient(player, {
		Owned = session.OwnedAssets,
		Equipped = session.EquippedAssets,
		SerialNumbers = session.AssetSerialNumbers,
	})
end
-- Exposed so StadiumOfferManager.luau/CashPackManager.luau (Sol Stadium's
-- own purchase flows, which don't go through GrantAsset/buyAsset below
-- since they have their own stock-pool/Robux-cap rules) can refresh
-- InventoryPanel's copy of Owned/Equipped/SerialNumbers too, instead of
-- duplicating this remote-firing shape.
AssetManager.PushUpdate = pushUpdate

-- Grants an Asset for free -- no Cash deducted, no ownership/price checks
-- (unlike buyAsset below). Used by BattleLeaderboardRewardManager.luau to
-- hand out the LARP Battles Top 3 reward estates, and RankRewardManager.luau
-- for the Rank Rewards Estates. Idempotent for single-copy Estates (a no-op
-- if already owned) -- MULTI_OWNABLE_ASSET_IDS above grant an additional
-- copy instead every time.
function AssetManager.GrantAsset(player: Player, session, assetId: string)
	local alreadyOwned = session.OwnedAssets[assetId] == true
	if alreadyOwned and not MULTI_OWNABLE_ASSET_IDS[assetId] then
		return
	end

	local asset = AssetDatabase.GetAsset(assetId)
	if not asset then
		return
	end

	session.OwnedAssets[assetId] = true
	local serial = EstateExistenceManager.GrantSerial(player, session, assetId)

	systemMessage:FireClient(player, serial and string.format("You won %s! (#%d)", asset.Name, serial) or string.format("You won %s!", asset.Name))
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
	if not asset then
		return
	end
	if session.Cash < asset.Price then
		systemMessage:FireClient(player, "You don't have enough money!")
		return
	end

	session.Cash -= asset.Price
	session.OwnedAssets[assetId] = true
	local serial = EstateExistenceManager.GrantSerial(player, session, assetId)

	systemMessage:FireClient(player, serial and string.format("Bought %s for %s! (#%d)", asset.Name, NumberFormat.FormatCash(asset.Price), serial) or string.format("Bought %s for %s!", asset.Name, NumberFormat.FormatCash(asset.Price)))
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
	AssetManager.EquippedAssetsChanged:Fire(player)
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
	AssetManager.EquippedAssetsChanged:Fire(player)
end)

return AssetManager
