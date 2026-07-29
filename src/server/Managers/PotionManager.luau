-- Handles BuyPotion: server-authoritative price lookup, activates
-- immediately. Re-buying an already-active potion extends its remaining
-- time by a full duration instead of resetting it. Never required by
-- StatsManager/RollManager/SellManager/IncomeManager (which read active
-- effects via the shared PotionConfig) -- see PotionConfig's header.

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

	local now = os.time()
	local currentExpiry = session.ActivePotions[potionId] or 0
	local duration = potion.DurationSeconds * UpgradeConfig.GetPotionDurationMultiplier(session.Upgrades.PotionBoost or 0)
	session.ActivePotions[potionId] = math.max(currentExpiry, now) + duration

	systemMessage:FireClient(player, string.format("Bought %s for %s!", potion.Name, NumberFormat.FormatCash(potion.Price)))
	potionUpdated:FireClient(player, session.ActivePotions)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

return true
