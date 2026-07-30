-- Handles RollRequested: server-enforced cooldown, weighted rarity pick,
-- weighted item pick within that rarity, grants the item, pushes updates.
-- Luck/cooldown get boosted by VIP (permanent), an active Luck/Speed
-- Potion (temporary, via PotionConfig), and the Luck/Roll Speed Upgrade
-- tracks (permanent, via UpgradeConfig) -- all three stack multiplicatively.
--
-- TryRoll/TrySpecialRoll are exposed as functions (not folded directly
-- into the remote handlers) purely so they read as one obvious code path
-- regardless of caller -- there's no separate Auto Roll loop on the
-- server anymore; RollPanel.luau (client) requests each roll itself, one
-- at a time, once the previous one's reveal has finished (see the remote
-- handlers near the bottom of this file for the full reasoning).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local RollConfig = require(ReplicatedStorage.Modules.RollConfig)
local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local PotionConfig = require(ReplicatedStorage.Modules.PotionConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local SpecialRollConfig = require(ReplicatedStorage.Modules.SpecialRollConfig)
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
local rollSpecial = RemotesBootstrap:WaitForChild("RollSpecial")
local specialRollStateUpdated = RemotesBootstrap:WaitForChild("SpecialRollStateUpdated")

local RollManager = {}

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

-- Shared by both a normal roll (rarity from pickRarity) and a Special Roll
-- (rarity from pickRarityFromWeights) -- picking an item within a known
-- rarity doesn't care which one chose the rarity.
local function pickItemForRarity(rarity: string)
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

local function pickItem(session, isVIP: boolean, nowUnix: number)
	local rarity = pickRarity(session, isVIP, nowUnix)
	return pickItemForRarity(rarity)
end

-- Advances every Special Roll tier's progress by 1, independently, capped
-- at that tier's own Threshold once reached (so it just sits "ready"
-- instead of overflowing past it) -- called once per successful normal
-- roll. A tier's progress only resets back to 0 when THAT tier is
-- actually claimed (see RollManager.TrySpecialRoll), never here.
local function advanceSpecialRollProgress(session)
	for _, tier in SpecialRollConfig.Milestones do
		local current = session.SpecialRollProgress[tier.Id] or 0
		if current < tier.Threshold then
			session.SpecialRollProgress[tier.Id] = current + 1
		end
	end
end

-- Special Roll tiers use their own fixed absolute weight table (see
-- SpecialRollConfig.luau) instead of RarityConfig's base weights -- no VIP/
-- Potion/Upgrade luck multiplier stacking, the tier's odds ARE the reward.
local function pickRarityFromWeights(weights: { [string]: number }): string
	local totalWeight = 0
	for _, rarity in RarityConfig.Order do
		totalWeight += weights[rarity] or 0
	end

	local roll = random:NextNumber() * totalWeight
	local cumulative = 0
	for _, rarity in RarityConfig.Order do
		cumulative += weights[rarity] or 0
		if roll <= cumulative then
			return rarity
		end
	end
	return RarityConfig.Order[1]
end

-- One entry per tier -- Golden/Diamond/Ruby/Emerald progress independently,
-- so more than one can be Available at the same time. Pure snapshot, no
-- FireClient here: the per-roll case (see TryRoll/TrySpecialRoll below)
-- rides along as a 2nd argument on the SAME RollResult fire instead of a
-- separate remote, specifically so the client can apply this snapshot to
-- the progress badges at the exact moment IT actually shows that roll's
-- reveal (see RollPanel.luau's resultQueue) rather than the instant the
-- server processed it -- under Auto Roll, the server can easily finish
-- several rolls' worth of work while the client is still mid-animation on
-- an earlier one, and pushing this immediately made the badge numbers
-- visibly race ahead of what was on screen (e.g. jump by several while
-- only one reveal had actually played).
local function buildSpecialRollTiers(session)
	local tiers = {}
	for _, tier in SpecialRollConfig.Milestones do
		local progress = session.SpecialRollProgress[tier.Id] or 0
		table.insert(tiers, {
			TierId = tier.Id,
			TierName = tier.Name,
			Threshold = tier.Threshold,
			Color = tier.Color,
			Image = tier.Image,
			Progress = progress,
			Available = progress >= tier.Threshold,
		})
	end
	return tiers
end

-- Only used for the initial-join push (Main.server.luau's sendInitialState)
-- -- there's no roll/reveal to piggyback the snapshot on at that point, so
-- it's the one case that still needs its own remote fire.
local function pushSpecialRollState(player: Player, session)
	specialRollStateUpdated:FireClient(player, buildSpecialRollTiers(session))
end

-- Performs exactly one roll for `player` if their cooldown has elapsed --
-- returns false (no-op) if there's no session, no items matched, or still
-- on cooldown. The RollRequested handler below calls this for every
-- request regardless of whether it came from a manual click or Auto
-- Roll's client-side continuation loop -- one code path, so auto-rolling
-- can never get different odds/behavior than a manual roll.
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
			advanceSpecialRollProgress(session)

			rollResult:FireClient(player, item, buildSpecialRollTiers(session), false)
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
	advanceSpecialRollProgress(session)

	rollResult:FireClient(player, item, buildSpecialRollTiers(session), false)
	inventoryUpdated:FireClient(player, session.Inventory)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
	return true
end

-- Claims a specific Special Roll tier (by Id, e.g. "Golden"), if it's
-- actually unlocked (session.SpecialRollProgress[tierId] has reached that
-- tier's own Threshold) -- rejects otherwise, same "no-op if not valid"
-- contract as TryRoll. Not gated by the normal roll cooldown (lastRollAt)
-- -- it's an independent bonus action, not a faster way to spam normal
-- rolls. Only the claimed tier's progress resets -- every other tier keeps
-- counting/sitting ready untouched.
function RollManager.TrySpecialRoll(player: Player, tierId: string): boolean
	local session = DataManager.Get(player)
	if not session then
		return false
	end

	local tier = nil
	for _, t in SpecialRollConfig.Milestones do
		if t.Id == tierId then
			tier = t
			break
		end
	end
	if not tier then
		return false
	end

	local progress = session.SpecialRollProgress[tier.Id] or 0
	if progress < tier.Threshold then
		return false
	end

	local rarity = pickRarityFromWeights(tier.Weights)
	local item = pickItemForRarity(rarity)
	if not item then
		return false
	end

	local isVIP = VIPManager.IsVIP(player)

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
			session.SpecialRollProgress[tier.Id] = 0

			rollResult:FireClient(player, item, buildSpecialRollTiers(session), true)
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
	session.SpecialRollProgress[tier.Id] = 0

	rollResult:FireClient(player, item, buildSpecialRollTiers(session), true)
	inventoryUpdated:FireClient(player, session.Inventory)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
	return true
end

RollManager.PushSpecialRollState = pushSpecialRollState

-- Auto Roll has no server-side timer of its own -- RollPanel.luau (client)
-- requests one roll (or one ready Special Roll claim) at a time, only
-- once the previous one's reveal has fully finished, exactly mirroring a
-- player spamming the ROLL button as fast as it re-enables. Both
-- RollRequested and RollSpecial below are the SAME handlers regardless of
-- whether the request came from a manual click or Auto Roll's own
-- continuation loop -- one code path, and the cooldown check inside
-- TryRoll/TrySpecialRoll is what actually protects against a modified
-- client requesting faster than that, same as it always has for manual
-- clicking.
rollRequested.OnServerEvent:Connect(function(player: Player)
	RollManager.TryRoll(player)
end)

rollSpecial.OnServerEvent:Connect(function(player: Player, tierId: unknown)
	if typeof(tierId) ~= "string" then
		return
	end
	RollManager.TrySpecialRoll(player, tierId)
end)

Players.PlayerRemoving:Connect(function(player)
	lastRollAt[player] = nil
end)

return RollManager
