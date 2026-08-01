-- Cash Packs: owns the game's ONE MarketplaceService.ProcessReceipt
-- callback (Roblox only ever fires the single most-recently-assigned one,
-- so this can't live split across multiple modules) -- credits
-- CashPackConfig's flat Cash amount and marks the receipt granted in the
-- player's own persisted session (see DataManager's
-- GrantedCashPackPurchaseIds) before returning PurchaseGranted, so a
-- retried receipt (Roblox resends until acknowledged, even across server
-- restarts) can never double-grant.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CashPackConfig = require(ReplicatedStorage.Modules.CashPackConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local CashPackManager = {}

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local pack = CashPackConfig.GetPack(receiptInfo.ProductId)
	if not pack then
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
	if not session.GrantedCashPackPurchaseIds[purchaseId] then
		session.Cash += pack.CashAmount
		session.GrantedCashPackPurchaseIds[purchaseId] = true
		systemMessage:FireClient(player, string.format("+%s Cash Pack purchased!", NumberFormat.FormatCash(pack.CashAmount)))
		StatsManager.Recompute(player)
		LeaderboardManager.MarkDirty(player)
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return CashPackManager
