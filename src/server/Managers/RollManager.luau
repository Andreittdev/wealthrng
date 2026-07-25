-- Handles RollRequested: server-enforced cooldown, weighted rarity pick,
-- weighted item pick within that rarity, grants the item, pushes updates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local RollConfig = require(ReplicatedStorage.Modules.RollConfig)
local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local VIPManager = require(ServerScriptService.Managers.VIPManager)

local rollRequested = RemotesBootstrap:WaitForChild("RollRequested")
local rollResult = RemotesBootstrap:WaitForChild("RollResult")
local inventoryUpdated = RemotesBootstrap:WaitForChild("InventoryUpdated")

local random = Random.new()
local lastRollAt: { [Player]: number } = {}

local function pickRarity(isVIP: boolean): string
	local totalWeight = 0
	local weights: { [string]: number } = {}
	for _, rarity in RarityConfig.Order do
		local weight = RarityConfig.Tiers[rarity].Weight
		if isVIP then
			weight *= VIPConfig.LuckWeightMultiplier[rarity]
		end
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

local function pickItem(isVIP: boolean)
	local rarity = pickRarity(isVIP)
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
	local cooldown = isVIP and VIPConfig.RollCooldownSeconds or RollConfig.BaseCooldownSeconds

	local now = os.clock()
	local last = lastRollAt[player]
	if last and now - last < cooldown then
		return
	end
	lastRollAt[player] = now

	local item = pickItem(isVIP)
	if not item then
		return
	end

	local entry = InventoryManager.AddItem(player, item.Id)
	if not entry then
		return
	end

	rollResult:FireClient(player, item)
	inventoryUpdated:FireClient(player, session.Inventory)
	StatsManager.Recompute(player)
end)

Players.PlayerRemoving:Connect(function(player)
	lastRollAt[player] = nil
end)
