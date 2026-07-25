-- Handles RollRequested: server-enforced cooldown, weighted rarity pick,
-- weighted item pick within that rarity, grants the item, pushes updates.
-- Luck/cooldown get boosted by both VIP (permanent) and an active Luck/
-- Speed Potion (temporary, via PotionConfig) -- the two stack.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local RollConfig = require(ReplicatedStorage.Modules.RollConfig)
local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local PotionConfig = require(ReplicatedStorage.Modules.PotionConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local VIPManager = require(ServerScriptService.Managers.VIPManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

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
	return candidates[random:NextInteger(1, #candidates)]
end

rollRequested.OnServerEvent:Connect(function(player: Player)
	local session = DataManager.Get(player)
	if not session then
		return
	end

	local isVIP = VIPManager.IsVIP(player)
	local nowUnix = os.time()
	local baseCooldown = isVIP and VIPConfig.RollCooldownSeconds or RollConfig.BaseCooldownSeconds
	local cooldown = baseCooldown * PotionConfig.GetCooldownMultiplier(session, nowUnix)

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
