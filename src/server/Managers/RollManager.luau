-- Handles RollRequested: server-enforced cooldown, weighted rarity pick,
-- weighted item pick within that rarity, grants the item, pushes updates.
-- Luck/cooldown get boosted by VIP (permanent), an active Luck/Speed
-- Potion (temporary, via PotionConfig), and the Luck/Roll Speed Upgrade
-- tracks (permanent, via UpgradeConfig) -- all three stack multiplicatively.

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

local rollRequested = RemotesBootstrap:WaitForChild("RollRequested")
local rollResult = RemotesBootstrap:WaitForChild("RollResult")
local inventoryUpdated = RemotesBootstrap:WaitForChild("InventoryUpdated")

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
	local candidates = ItemDatabase.GetItemsByRarity(rarity)
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

rollRequested.OnServerEvent:Connect(function(player: Player)
	local session = DataManager.Get(player)
	if not session then
		return
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
		return
	end
	lastRollAt[player] = nowClock

	local item = pickItem(session, isVIP, nowUnix)
	if not item then
		return
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
			return
		end
	end

	local entry = InventoryManager.AddItem(player, item.Id)
	if not entry then
		return
	end

	session.TotalRolls += 1

	rollResult:FireClient(player, item)
	inventoryUpdated:FireClient(player, session.Inventory)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
end)

Players.PlayerRemoving:Connect(function(player)
	lastRollAt[player] = nil
end)

-- Side-effect-only module (just connects OnServerEvent above) -- nothing to
-- export, but ModuleScripts must still return exactly one value or
-- require() errors and aborts the rest of Main.server.luau's execution.
return true
