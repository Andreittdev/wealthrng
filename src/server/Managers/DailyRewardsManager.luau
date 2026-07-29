-- Handles ClaimDailyReward: server-authoritative cooldown + payout over a
-- 7-day cycle with mixed reward types (DailyRewardsConfig.Days -- see its
-- header for what each Type grants). Claimed by standing near the plaza's
-- red "Daily Rewards" floor marker (MapBuilder's buildFloorMarker) and
-- pressing Claim in DailyRewardsProximityPanel.luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DailyRewardsConfig = require(ReplicatedStorage.Modules.DailyRewardsConfig)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local AutoRollManager = require(ServerScriptService.Managers.AutoRollManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local claimDailyReward = RemotesBootstrap:WaitForChild("ClaimDailyReward")
local dailyRewardStateUpdated = RemotesBootstrap:WaitForChild("DailyRewardStateUpdated")
local inventoryUpdated = RemotesBootstrap:WaitForChild("InventoryUpdated")
local assetUpdated = RemotesBootstrap:WaitForChild("AssetUpdated")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local DailyRewardsManager = {}

local random = Random.new()

-- Shared by the initial push (Main.server.luau) and after a successful
-- claim, so both always agree on the exact same CanClaim/SecondsRemaining
-- math.
function DailyRewardsManager.PushState(player: Player)
	local session = DataManager.Get(player)
	if not session then
		return
	end

	local elapsed = os.time() - session.LastDailyRewardClaimAt
	local canClaim = session.LastDailyRewardClaimAt == 0 or elapsed >= DailyRewardsConfig.ClaimIntervalSeconds
	local secondsRemaining = canClaim and 0 or (DailyRewardsConfig.ClaimIntervalSeconds - elapsed)

	dailyRewardStateUpdated:FireClient(player, { Day = session.DailyRewardDay, CanClaim = canClaim, SecondsRemaining = secondsRemaining })
end

-- Grants `reward` to `player`/`session` and returns a short description for
-- the "Day N Reward Claimed: ..." toast -- nil means the grant failed (bad
-- config, e.g. an AssetId that doesn't exist), which aborts the whole claim
-- so nothing is half-applied.
local function grantReward(player: Player, session, reward): string?
	if reward.Type == "Cash" then
		session.Cash += reward.Amount
		return NumberFormat.FormatCash(reward.Amount)
	elseif reward.Type == "RandomEpicItem" then
		local candidates = ItemDatabase.GetRollableItemsByRarity("Epic")
		if #candidates == 0 then
			return nil
		end
		local item = candidates[random:NextInteger(1, #candidates)]
		local entry = InventoryManager.AddItem(player, item.Id)
		if not entry then
			return nil
		end
		inventoryUpdated:FireClient(player, session.Inventory)
		return item.Name
	elseif reward.Type == "Asset" then
		local asset = AssetDatabase.GetAsset(reward.AssetId)
		if not asset then
			return nil
		end
		session.OwnedAssets[reward.AssetId] = true
		assetUpdated:FireClient(player, { Owned = session.OwnedAssets, Equipped = session.EquippedAssets })
		return asset.Name
	elseif reward.Type == "AutoRollGamepass" then
		AutoRollManager.Grant(player)
		return "Auto Roll Gamepass"
	end
	return nil
end

claimDailyReward.OnServerEvent:Connect(function(player: Player)
	local session = DataManager.Get(player)
	if not session then
		return
	end

	local elapsed = os.time() - session.LastDailyRewardClaimAt
	if session.LastDailyRewardClaimAt ~= 0 and elapsed < DailyRewardsConfig.ClaimIntervalSeconds then
		return
	end

	local day = session.DailyRewardDay
	local reward = DailyRewardsConfig.Days[day]
	if not reward then
		return
	end

	local description = grantReward(player, session, reward)
	if not description then
		return
	end

	session.LastDailyRewardClaimAt = os.time()
	session.DailyRewardDay = (day % #DailyRewardsConfig.Days) + 1

	systemMessage:FireClient(player, string.format("Day %d Reward Claimed: %s!", day, description))
	DailyRewardsManager.PushState(player)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

return DailyRewardsManager
