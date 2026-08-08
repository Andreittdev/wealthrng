-- Owns the game's ONE MarketplaceService.ProcessReceipt callback (Roblox
-- only ever fires the single most-recently-assigned one, so this can't
-- live split across multiple modules) -- despite the name, this now
-- handles every Developer Product in the game, not just Cash Packs:
--   - Cash Packs (CashPackConfig) -- credits the flat Cash amount.
--   - Potion instant-buys (PotionDatabase's InstantProductId, 2 R$) --
--     delegates to PotionManager.GrantPotionFree.
--   - Sol Stadium Robux purchases (StadiumOfferConfig.RobuxProductId) --
--     +1 session.SolStadiumOwned, unlimited (no MaxCashPurchases cap),
--     doesn't touch StadiumOfferManager.luau's shared stock pool.
--   - Exclusive Crate purchases (CrateConfig.PurchaseTiers) -- delegates to
--     CrateManager.OpenCrates for the actual item grants.
-- Each grant is marked in the player's own persisted session (a dedicated
-- Granted*PurchaseIds set per purchase TYPE, see DataManager) before
-- returning PurchaseGranted, so a retried receipt (Roblox resends until
-- acknowledged, even across server restarts) can never double-grant.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CashPackConfig = require(ReplicatedStorage.Modules.CashPackConfig)
local PotionDatabase = require(ReplicatedStorage.Modules.PotionDatabase)
local StadiumOfferConfig = require(ReplicatedStorage.Modules.StadiumOfferConfig)
local CrateConfig = require(ReplicatedStorage.Modules.CrateConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)
local PotionManager = require(ServerScriptService.Managers.PotionManager)
local CrateManager = require(ServerScriptService.Managers.CrateManager)
local EstateExistenceManager = require(ServerScriptService.Managers.EstateExistenceManager)
local AssetManager = require(ServerScriptService.Managers.AssetManager)

local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")
local stadiumOfferStateUpdated = RemotesBootstrap:WaitForChild("StadiumOfferStateUpdated")

local CashPackManager = {}

local function processCashPack(player: Player, session, purchaseId: string, pack): boolean
	if session.GrantedCashPackPurchaseIds[purchaseId] then
		return true
	end
	session.Cash += pack.CashAmount
	session.GrantedCashPackPurchaseIds[purchaseId] = true
	systemMessage:FireClient(player, string.format("+%s Cash Pack purchased!", NumberFormat.FormatCash(pack.CashAmount)))
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
	-- Force an immediate save instead of waiting for the next 120s autosave
	-- -- this is real Robux money already spent; a crash/shutdown in that
	-- window would otherwise be able to lose the purchase permanently
	-- (ProcessReceipt already returned PurchaseGranted, so Roblox won't
	-- retry it). Backgrounded so it can't delay ProcessReceipt's return.
	task.spawn(DataManager.Save, player)
	return true
end

local function processInstantPotion(player: Player, session, purchaseId: string, potionId: string): boolean
	if session.GrantedPotionPurchaseIds[purchaseId] then
		return true
	end
	session.GrantedPotionPurchaseIds[purchaseId] = true
	PotionManager.GrantPotionFree(player, session, potionId)
	-- Same immediate-save reasoning as processCashPack above.
	task.spawn(DataManager.Save, player)
	return true
end

local function processStadiumOfferPurchase(player: Player, session, purchaseId: string): boolean
	if session.GrantedStadiumOfferPurchaseIds[purchaseId] then
		return true
	end
	session.GrantedStadiumOfferPurchaseIds[purchaseId] = true
	session.SolStadiumOwned += 1
	session.OwnedAssets[StadiumOfferConfig.AssetId] = true
	local serial = EstateExistenceManager.GrantSerial(player, session, StadiumOfferConfig.AssetId)

	systemMessage:FireClient(player, serial and string.format("Bought Sol Stadium with Robux! (#%d) (%d owned)", serial, session.SolStadiumOwned) or string.format("Bought Sol Stadium with Robux! (%d owned)", session.SolStadiumOwned))
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
	AssetManager.PushUpdate(player, session)
	-- Refreshes StadiumOfferPanel.luau's own OwnedCount display if it's
	-- open -- doesn't touch the shared stock pool/RemainingStock at all,
	-- unlike a cash purchase (StadiumOfferManager.luau), so no broadcast
	-- to other players is needed.
	local ok, remainingStock = pcall(function()
		return DataStoreService:GetDataStore("WealthRNG_StadiumOffer"):GetAsync("RemainingStock")
	end)
	stadiumOfferStateUpdated:FireClient(player, {
		RemainingStock = (ok and remainingStock) or StadiumOfferConfig.TotalStock,
		TotalStock = StadiumOfferConfig.TotalStock,
		OwnedCount = session.SolStadiumOwned,
		MaxCashPurchases = StadiumOfferConfig.MaxCashPurchases,
	})
	-- Same immediate-save reasoning as processCashPack above.
	task.spawn(DataManager.Save, player)
	return true
end

local function processCratePurchase(player: Player, session, purchaseId: string, tier: CrateConfig.PurchaseTier): boolean
	if session.GrantedCratePurchaseIds[purchaseId] then
		return true
	end
	session.GrantedCratePurchaseIds[purchaseId] = true
	CrateManager.OpenCrates(player, session, tier.Quantity)
	systemMessage:FireClient(player, string.format("Opened %d Crate%s!", tier.Quantity, tier.Quantity == 1 and "" or "s"))
	-- Same immediate-save reasoning as processCashPack above.
	task.spawn(DataManager.Save, player)
	return true
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local pack = CashPackConfig.GetPack(receiptInfo.ProductId)
	local instantPotion = not pack and PotionDatabase.GetPotionByInstantProductId(receiptInfo.ProductId)
	local isStadiumOffer = not pack and not instantPotion and receiptInfo.ProductId == StadiumOfferConfig.RobuxProductId
	local crateTier = not pack and not instantPotion and not isStadiumOffer and CrateConfig.GetTierByProductId(receiptInfo.ProductId)
	if not pack and not instantPotion and not isStadiumOffer and not crateTier then
		return Enum.ProductPurchaseDecision.NotProcessed
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Player isn't online (left mid-purchase) -- Roblox will retry this
		-- same receipt automatically once they're back.
		return Enum.ProductPurchaseDecision.NotProcessed
	end

	local session = DataManager.Get(player)
	if not session or not session.LoadedOk then
		return Enum.ProductPurchaseDecision.NotProcessed
	end

	local purchaseId = receiptInfo.PurchaseId
	if pack then
		processCashPack(player, session, purchaseId, pack)
	elseif instantPotion then
		processInstantPotion(player, session, purchaseId, instantPotion.Id)
	elseif isStadiumOffer then
		processStadiumOfferPurchase(player, session, purchaseId)
	else
		processCratePurchase(player, session, purchaseId, crateTier)
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return CashPackManager
