-- Handles RollRequested: server-enforced cooldown, weighted rarity pick,
-- weighted item pick within that rarity, grants the item, pushes updates.
-- Luck/cooldown get boosted by VIP (permanent), an active Luck/Speed
-- Potion (temporary, via PotionConfig), and the Luck/Roll Speed Upgrade
-- tracks (permanent, via UpgradeConfig) -- all three stack multiplicatively.
--
-- The actual roll-performing logic is exposed as RollManager.TryRoll so
-- AutoRollManager's on/off state (see the loop at the bottom of this file)
-- can trigger the exact same roll a manual click would -- same cooldown
-- enforcement, same odds, no separate code path to drift out of sync.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local RollConfig = require(ReplicatedStorage.Modules.RollConfig)
local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local PotionConfig = require(ReplicatedStorage.Modules.PotionConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local VIPManager = require(ServerScriptService.Managers.VIPManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)
local SellManager = require(ServerScriptService.Managers.SellManager)
local AutoRollManager = require(ServerScriptService.Managers.AutoRollManager)

local rollRequested = RemotesBootstrap:WaitForChild("RollRequested")
local rollResult = RemotesBootstrap:WaitForChild("RollResult")
local inventoryUpdated = RemotesBootstrap:WaitForChild("InventoryUpdated")

local RollManager = {}

local AUTO_ROLL_TICK_SECONDS = 0.2

local random = Random.new()
local lastRollAt: { [Player]: number } = {}

local function pickRarity(session, isVIP: boolean, nowUnix: number): string
	local totalWeight = 0
	local weights: { [string]: number } = {}
	for _, rarity in RarityConfig.Order do
		local weight = RarityConfig.Tiers[rarity].Weight
		if isVIP then
			weight *= VIPConfig.LuckWeightMultiplier[rarity]
		end
		weight *= PotionConfig.GetLuckMultiplier(session, rarity, nowUnix)
		weight *= UpgradeConfig.GetLuckMultiplier(session.Upgrades.Luck or 0, rarity)
		weights[rarity] = weight
		totalWeight += weight
	end

	local roll = random:NextNumber() * totalWeight
	local cumulative = 0
	for _, rarity in RarityConfig.Order do
		cumulative += weights[rarity]
		if roll <= cumulative then
			return rarity
		end
	end
	return RarityConfig.Order[1]
end

local function pickItem(session, isVIP: boolean, nowUnix: number)
	local rarity = pickRarity(session, isVIP, nowUnix)
	local candidates = ItemDatabase.GetRollableItemsByRarity(rarity)
	if #candidates == 0 then
		return nil
	end

	-- Weighted, not uniform -- pricier items within the same rarity are
	-- rarer pulls (see ItemDatabase.GetRollWeight).
	local totalWeight = 0
	for _, item in candidates do
		totalWeight += ItemDatabase.GetRollWeight(item)
	end

	local roll = random:NextNumber() * totalWeight
	local cumulative = 0
	for _, item in candidates do
		cumulative += ItemDatabase.GetRollWeight(item)
		if roll <= cumulative then
			return item
		end
	end
	return candidates[#candidates]
end

-- Performs exactly one roll for `player` if their cooldown has elapsed --
-- returns false (no-op) if there's no session, no items matched, or still
-- on cooldown. Used by both the RollRequested handler (manual click) and
-- the auto-roll loop below (AutoRollManager's on/off state) -- one code
-- path, so auto-rolling can never get different odds/behavior than a
-- manual roll.
function RollManager.TryRoll(player: Player): boolean
	local session = DataManager.Get(player)
	if not session then
		return false
	end

	local isVIP = VIPManager.IsVIP(player)
	local nowUnix = os.time()
	local baseCooldown = isVIP and VIPConfig.RollCooldownSeconds or RollConfig.BaseCooldownSeconds
	local cooldown = baseCooldown
		* PotionConfig.GetCooldownMultiplier(session, nowUnix)
		* UpgradeConfig.GetCooldownMultiplier(session.Upgrades.RollSpeed or 0)

	local nowClock = os.clock()
	local last = lastRollAt[player]
	if last and nowClock - last < cooldown then
		return false
	end
	lastRollAt[player] = nowClock

	local item = pickItem(session, isVIP, nowUnix)
	if not item then
		return false
	end

	-- Auto-sell duplicates (opt-in per rarity via SettingsPanel): if the
	-- player already owns at least one of this exact item AND has that
	-- rarity's toggle on, credit cash instead of adding a second copy to
	-- the inventory. Still fires RollResult either way so the reveal
	-- animation always shows what was actually rolled.
	if session.AutoSellDuplicates[item.Rarity] then
		local alreadyOwned = false
		for _, invEntry in session.Inventory do
			if invEntry.ItemId == item.Id then
				alreadyOwned = true
				break
			end
		end

		if alreadyOwned then
			session.Cash += SellManager.ComputeSellValue(session, isVIP, item)
			session.TotalRolls += 1

			rollResult:FireClient(player, item)
			StatsManager.Recompute(player)
			LeaderboardManager.MarkDirty(player)
			return true
		end
	end

	local entry = InventoryManager.AddItem(player, item.Id)
	if not entry then
		return false
	end

	session.TotalRolls += 1

	rollResult:FireClient(player, item)
	inventoryUpdated:FireClient(player, session.Inventory)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
	return true
end

rollRequested.OnServerEvent:Connect(function(player: Player)
	RollManager.TryRoll(player)
end)

Players.PlayerRemoving:Connect(function(player)
	lastRollAt[player] = nil
end)

-- Auto Roll gamepass loop: every tick, try a roll for whichever players
-- currently have it enabled (AutoRollManager.GetEnabledPlayers) -- TryRoll
-- itself is a no-op if that player's cooldown hasn't elapsed yet, so this
-- tick rate is just an upper bound on latency, not the actual roll rate.
task.spawn(function()
	while true do
		task.wait(AUTO_ROLL_TICK_SECONDS)
		for player in AutoRollManager.GetEnabledPlayers() do
			RollManager.TryRoll(player)
		end
	end
end)

return RollManager
