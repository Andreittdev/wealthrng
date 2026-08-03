-- Handles BuyPotion (Cash) and, via GrantPotionFree, the 2 R$ "instant buy"
-- Developer Products (see PotionDatabase's InstantProductId) -- both paths
-- share the same activation logic below. Re-buying an already-active potion
-- extends its remaining time by a full duration instead of resetting it.
-- Never required by StatsManager/RollManager/SellManager/IncomeManager
-- (which read active effects via the shared PotionConfig) -- see
-- PotionConfig's header.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PotionDatabase = require(ReplicatedStorage.Modules.PotionDatabase)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local buyPotion = RemotesBootstrap:WaitForChild("BuyPotion")
local potionUpdated = RemotesBootstrap:WaitForChild("PotionUpdated")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local PotionManager = {}

-- Extends session.ActivePotions[potionId] by a full duration (stacking on
-- top of any remaining time, not resetting it), applying the Potion Boost
-- Upgrade's duration multiplier -- shared by both the Cash purchase below
-- and the Robux instant-buy path (CashPackManager.luau's ProcessReceipt).
-- Does NOT touch session.Cash -- callers that charge Cash do that
-- themselves first (see buyPotion's handler), the instant-buy path skips
-- it entirely by design.
local function activatePotion(player: Player, session, potion)
	local now = os.time()
	local currentExpiry = session.ActivePotions[potion.Id] or 0
	local duration = potion.DurationSeconds * UpgradeConfig.GetPotionDurationMultiplier(session.Upgrades.PotionBoost or 0)
	session.ActivePotions[potion.Id] = math.max(currentExpiry, now) + duration

	potionUpdated:FireClient(player, session.ActivePotions)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end

-- Called from CashPackManager.luau's shared ProcessReceipt once a 2 R$
-- instant-buy receipt is confirmed -- grants the potion for free (the
-- Robux payment already happened), same activation as a normal Cash buy.
function PotionManager.GrantPotionFree(player: Player, session, potionId: string)
	local potion = PotionDatabase.GetPotion(potionId)
	if not potion then
		return
	end

	activatePotion(player, session, potion)
	systemMessage:FireClient(player, string.format("%s activated!", potion.Name))
end

buyPotion.OnServerEvent:Connect(function(player: Player, potionId: string)
	if typeof(potionId) ~= "string" then
		return
	end

	local session = DataManager.Get(player)
	if not session then
		return
	end

	local potion = PotionDatabase.GetPotion(potionId)
	if not potion or session.Cash < potion.Price then
		return
	end

	session.Cash -= potion.Price
	activatePotion(player, session, potion)
	systemMessage:FireClient(player, string.format("Bought %s for %s!", potion.Name, NumberFormat.FormatCash(potion.Price)))
end)

return PotionManager
