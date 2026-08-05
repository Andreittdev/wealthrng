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
local LuckPassConfig = require(ReplicatedStorage.Modules.LuckPassConfig)
local UltraLuckPassConfig = require(ReplicatedStorage.Modules.UltraLuckPassConfig)
local FastRollConfig = require(ReplicatedStorage.Modules.FastRollConfig)
local SpecialRollConfig = require(ReplicatedStorage.Modules.SpecialRollConfig)
local RollOdds = require(ReplicatedStorage.Modules.RollOdds)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local VIPManager = require(ServerScriptService.Managers.VIPManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)
local SellManager = require(ServerScriptService.Managers.SellManager)
local AutoClaimManager = require(ServerScriptService.Managers.AutoClaimManager)
local LuckPassManager = require(ServerScriptService.Managers.LuckPassManager)
local UltraLuckPassManager = require(ServerScriptService.Managers.UltraLuckPassManager)
local FastRollManager = require(ServerScriptService.Managers.FastRollManager)
local DoubleCashManager = require(ServerScriptService.Managers.DoubleCashManager)

local rollRequested = RemotesBootstrap:WaitForChild("RollRequested")
local rollResult = RemotesBootstrap:WaitForChild("RollResult")
local inventoryUpdated = RemotesBootstrap:WaitForChild("InventoryUpdated")
local rollSpecial = RemotesBootstrap:WaitForChild("RollSpecial")
local specialRollStateUpdated = RemotesBootstrap:WaitForChild("SpecialRollStateUpdated")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local RollManager = {}

local random = Random.new()
local lastRollAt: { [Player]: number } = {}

local function colorToHex(color: Color3): string
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

-- Server-wide "look what X just got" callout for Ultra/Luxury pulls
-- specifically (not Legendary or below -- just the top 2 tiers), broadcast
-- to every client (not just the roller) via SystemMessage's underlying
-- RemoteEvent -- every client's own OnClientEvent handler (Main.client.luau)
-- already knows how to show it via TextChatService AND as a toast, so this
-- needs no new client-side code. Colored to match that item's own rarity
-- color (RarityConfig) via a rich-text <font> tag, same as the odds text
-- uses in the reveal window -- turquoise for Ultra, magenta for Luxury.
local RARE_ANNOUNCE_RARITIES = { Ultra = true, Luxury = true }

local function announceRareUnlock(player: Player, item)
	local colorHex = colorToHex(RarityConfig.GetColor(item.Rarity))
	local oneInN = RollOdds.GetOneInN(item.Id)
	local oddsText = oneInN and string.format(" (1 in %d)", math.floor(oneInN + 0.5)) or ""
	local text = string.format("<font color=\"%s\">%s unlocked %s!%s</font>", colorHex, player.Name, item.Name, oddsText)
	systemMessage:FireAllClients(text)
end

-- `restrictToCommonRare` is only true for a brand-new player's very first
-- roll ever (see pickItem below) -- part of the new-player onboarding
-- walkthrough (OnboardingTutorial.luau), so their first pull is always
-- something manageable to equip, never an Epic+ before they've even seen
-- the Inventory panel.
local function pickRarity(
	session,
	isVIP: boolean,
	nowUnix: number,
	ownsLuckPass: boolean,
	ownsUltraLuckPass: boolean,
	restrictToCommonRare: boolean?
): string
	local totalWeight = 0
	local weights: { [string]: number } = {}
	for _, rarity in RarityConfig.Order do
		if restrictToCommonRare and rarity ~= "Common" and rarity ~= "Rare" then
			continue
		end
		local weight = RarityConfig.Tiers[rarity].Weight
		if isVIP then
			weight *= VIPConfig.LuckWeightMultiplier[rarity]
		end
		weight *= PotionConfig.GetLuckMultiplier(session, rarity, nowUnix)
		weight *= UpgradeConfig.GetLuckMultiplier(session.Upgrades.Luck or 0, rarity)
		if ownsLuckPass then
			weight *= LuckPassConfig.LuckWeightMultiplier[rarity]
		end
		if ownsUltraLuckPass then
			weight *= UltraLuckPassConfig.LuckWeightMultiplier[rarity]
		end
		weights[rarity] = weight
		totalWeight += weight
	end

	local roll = random:NextNumber() * totalWeight
	local cumulative = 0
	for _, rarity in RarityConfig.Order do
		if weights[rarity] then
			cumulative += weights[rarity]
			if roll <= cumulative then
				return rarity
			end
		end
	end
	return restrictToCommonRare and "Common" or RarityConfig.Order[1]
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

local function pickItem(session, isVIP: boolean, nowUnix: number, ownsLuckPass: boolean, ownsUltraLuckPass: boolean)
	-- A brand-new player's very first roll ever (see OnboardingTutorial.luau)
	-- is always Common/Rare -- keeps the guided "roll -> equip" walkthrough
	-- predictable instead of risking an Epic+ before they've even opened
	-- Inventory once.
	local restrictToCommonRare = session.TotalRolls == 0
	local rarity = pickRarity(session, isVIP, nowUnix, ownsLuckPass, ownsUltraLuckPass, restrictToCommonRare)
	return pickItemForRarity(rarity)
end

-- Advances every "Rolls"-kind Special Roll tier's progress by 1,
-- independently, capped at that tier's own Threshold once reached (so it
-- just sits "ready" instead of overflowing past it) -- called once per
-- successful normal roll. "SecondsStage" tiers (Lucky Roll's 6-stage
-- ladder) advance separately, see the per-second loop near the bottom of
-- this file. A "Rolls" tier's progress only resets back to 0 when THAT
-- tier is actually claimed (see markTierClaimed below), never here.
local function advanceSpecialRollProgress(session)
	for _, tier in SpecialRollConfig.Milestones do
		if tier.Kind == "Rolls" then
			local current = session.SpecialRollProgress[tier.Id] or 0
			if current < tier.Threshold then
				session.SpecialRollProgress[tier.Id] = current + 1
			end
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
--
-- Lucky Roll's 6 "SecondsStage" tiers read progress from the SHARED
-- counter (session.SpecialRollProgress[tier.ProgressKey], all six point
-- at "Lucky") instead of their own Id, and Available also has to check
-- session.ClaimedLuckyStages -- unlike the "Rolls" tiers, the shared
-- counter does NOT reset when an individual stage is claimed (it needs to
-- keep climbing for the later stages), so "progress reached the
-- threshold" alone isn't enough to know a stage is still claimable.
local function buildSpecialRollTiers(session)
	local tiers = {}
	for _, tier in SpecialRollConfig.Milestones do
		local progress
		local available
		if tier.Kind == "SecondsStage" then
			progress = session.SpecialRollProgress[tier.ProgressKey] or 0
			local claimed = session.ClaimedLuckyStages[tier.Id] == true
			available = not claimed and progress >= tier.Threshold
		else
			progress = session.SpecialRollProgress[tier.Id] or 0
			available = progress >= tier.Threshold
		end
		table.insert(tiers, {
			TierId = tier.Id,
			TierName = tier.Name,
			Kind = tier.Kind,
			Threshold = tier.Threshold,
			Color = tier.Color,
			Image = tier.Image,
			Progress = progress,
			Available = available,
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
	if FastRollManager.Owns(player) then
		cooldown *= FastRollConfig.CooldownMultiplier
	end

	local nowClock = os.clock()
	local last = lastRollAt[player]
	if last and nowClock - last < cooldown then
		return false
	end
	lastRollAt[player] = nowClock

	local item = pickItem(session, isVIP, nowUnix, LuckPassManager.Owns(player), UltraLuckPassManager.Owns(player))
	if not item then
		return false
	end

	-- Auto-sell duplicates (opt-in per rarity via SettingsPanel): if the
	-- player already owns at least one of this exact item AND has that
	-- rarity's toggle on, credit cash instead of adding a second copy to
	-- the inventory. Still fires RollResult either way so the reveal
	-- animation always shows what was actually rolled. O(1) lookup via
	-- session.OwnedItemCounts (kept in sync by InventoryManager) instead of
	-- scanning the full Inventory array on every roll.
	if session.AutoSellDuplicates[item.Rarity] then
		local alreadyOwned = (session.OwnedItemCounts[item.Id] or 0) > 0

		if alreadyOwned then
			session.Cash += SellManager.ComputeSellValue(session, isVIP, item, DoubleCashManager.GetBonusPercent(player))
			session.TotalRolls += 1
			advanceSpecialRollProgress(session)

			rollResult:FireClient(player, item, buildSpecialRollTiers(session), false)
			StatsManager.Recompute(player)
			LeaderboardManager.MarkDirty(player)
			return true
		end
	end

	-- Captured BEFORE AddItem (which increments OwnedItemCounts) -- this is
	-- the player's very first copy of this exact item ever, not just this
	-- session. Fired as a SystemMessage, same as every other toast here --
	-- notably NOT gated by Hide Rolls (that only skips RollPanel's reveal
	-- animation client-side, never SystemMessage), so it always shows.
	local isNewDiscovery = (session.OwnedItemCounts[item.Id] or 0) == 0

	local entry = InventoryManager.AddItem(player, item.Id)
	if not entry then
		return false
	end

	if RARE_ANNOUNCE_RARITIES[item.Rarity] then
		announceRareUnlock(player, item)
	end
	if isNewDiscovery then
		systemMessage:FireClient(player, "New item discovered!")
	end

	session.TotalRolls += 1
	advanceSpecialRollProgress(session)

	rollResult:FireClient(player, item, buildSpecialRollTiers(session), false)
	inventoryUpdated:FireClient(player, session.Inventory)
	StatsManager.Recompute(player)
	LeaderboardManager.MarkDirty(player)
	return true
end

-- Marks a tier as claimed for this cycle. "Rolls" tiers (Golden/Diamond/
-- Ruby/Emerald) reset their own progress straight back to 0 -- simple,
-- self-contained. "SecondsStage" tiers (Lucky I-VI) share ONE progress
-- counter across all 6 stages, so claiming stage N must NOT reset it (the
-- later stages still need it climbing) -- only flip that stage's own
-- ClaimedLuckyStages entry. Claiming the FINAL stage (IsFinalStage) is the
-- one exception: that's the actual end of the 90-minute cycle, so it
-- resets the shared counter AND every stage's claimed flag together,
-- starting a fresh climb from Stage I.
local function markTierClaimed(session, tier)
	if tier.Kind == "SecondsStage" then
		session.ClaimedLuckyStages[tier.Id] = true
		if tier.IsFinalStage then
			session.SpecialRollProgress[tier.ProgressKey] = 0
			for _, t in SpecialRollConfig.Milestones do
				if t.ProgressKey == tier.ProgressKey then
					session.ClaimedLuckyStages[t.Id] = nil
				end
			end
		end
	else
		session.SpecialRollProgress[tier.Id] = 0
	end
end

-- Claims a specific Special Roll tier (by Id, e.g. "Golden" or "Lucky3"),
-- if it's actually unlocked and not already claimed this cycle -- rejects
-- otherwise, same "no-op if not valid" contract as TryRoll. Not gated by
-- the normal roll cooldown (lastRollAt) -- it's an independent bonus
-- action, not a faster way to spam normal rolls.
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

	if tier.Kind == "SecondsStage" then
		if session.ClaimedLuckyStages[tier.Id] then
			return false
		end
		local progress = session.SpecialRollProgress[tier.ProgressKey] or 0
		if progress < tier.Threshold then
			return false
		end
	else
		local progress = session.SpecialRollProgress[tier.Id] or 0
		if progress < tier.Threshold then
			return false
		end
	end

	local rarity = pickRarityFromWeights(tier.Weights)
	local item = pickItemForRarity(rarity)
	if not item then
		return false
	end

	local isVIP = VIPManager.IsVIP(player)

	if session.AutoSellDuplicates[item.Rarity] then
		local alreadyOwned = (session.OwnedItemCounts[item.Id] or 0) > 0

		if alreadyOwned then
			session.Cash += SellManager.ComputeSellValue(session, isVIP, item, DoubleCashManager.GetBonusPercent(player))
			session.TotalRolls += 1
			markTierClaimed(session, tier)

			rollResult:FireClient(player, item, buildSpecialRollTiers(session), true)
			StatsManager.Recompute(player)
			LeaderboardManager.MarkDirty(player)
			return true
		end
	end

	-- Same "first copy ever" check as TryRoll above.
	local isNewDiscovery = (session.OwnedItemCounts[item.Id] or 0) == 0

	local entry = InventoryManager.AddItem(player, item.Id)
	if not entry then
		return false
	end

	if RARE_ANNOUNCE_RARITIES[item.Rarity] then
		announceRareUnlock(player, item)
	end
	if isNewDiscovery then
		systemMessage:FireClient(player, "New item discovered!")
	end

	session.TotalRolls += 1
	markTierClaimed(session, tier)

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

-- Which Lucky stage (if any) an Auto Claim gamepass owner should be
-- auto-claimed into right now -- same "earliest not-yet-claimed, ready"
-- rule LuckyRollProximityPanel.luau's client-side pickCurrentStage uses,
-- just reading session state directly instead of a pushed snapshot.
-- SpecialRollConfig.Milestones already lists Lucky1..Lucky6 in ascending
-- Threshold order, so a plain left-to-right scan is already "claim in
-- order," no separate sort needed.
local function findAutoClaimableLuckyStage(session): SpecialRollConfig.Tier?
	for _, tier in SpecialRollConfig.Milestones do
		if tier.Kind == "SecondsStage" then
			local progress = session.SpecialRollProgress[tier.ProgressKey] or 0
			local claimed = session.ClaimedLuckyStages[tier.Id] == true
			if not claimed and progress >= tier.Threshold then
				return tier
			end
		end
	end
	return nil
end

-- Drives "SecondsStage" tiers (Lucky Roll's 6-stage ladder) -- +1 progress
-- per second per connected player to the SHARED counter each stage's
-- ProgressKey points at, capped at that shared cycle's overall length (90
-- min), not any single stage's own Threshold -- the counter has to keep
-- climbing past Stage I-V's thresholds for the later stages to ever
-- become reachable. Only advances while actually online, same convention
-- the old Playtime Rewards system used (not real-world wall-clock time).
-- `advancedKeys` stops this from incrementing the same shared counter 6
-- times in one tick (once per stage that shares it).
--
-- Auto Claim gamepass owners also get checked here, right after advancing
-- -- the same TrySpecialRoll a manual Claim tap would fire, just triggered
-- server-side instead of waiting for the player to walk up and press the
-- button. Runs at most once per tick per player (TrySpecialRoll itself is
-- the source of truth for what's actually claimable, this is just what
-- decides WHEN to call it).
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in Players:GetPlayers() do
			local session = DataManager.Get(player)
			if session then
				local advancedKeys: { [string]: boolean } = {}
				for _, tier in SpecialRollConfig.Milestones do
					if tier.Kind == "SecondsStage" and tier.ProgressKey and not advancedKeys[tier.ProgressKey] then
						advancedKeys[tier.ProgressKey] = true
						local current = session.SpecialRollProgress[tier.ProgressKey] or 0
						local cap = tier.CycleLengthSeconds or tier.Threshold
						if current < cap then
							session.SpecialRollProgress[tier.ProgressKey] = current + 1
						end
					end
				end

				if AutoClaimManager.IsEnabled(player) then
					local claimableTier = findAutoClaimableLuckyStage(session)
					if claimableTier then
						RollManager.TrySpecialRoll(player, claimableTier.Id)
					end
				end
			end
		end
	end
end)

-- Keeps the Lucky Roll badge's countdown roughly live for players who
-- aren't actively rolling (the other 4 tiers only need a push when a roll
-- actually happens -- this one ticks up every second regardless).
local SPECIAL_ROLL_PUSH_INTERVAL_SECONDS = 5
task.spawn(function()
	while true do
		task.wait(SPECIAL_ROLL_PUSH_INTERVAL_SECONDS)
		for _, player in Players:GetPlayers() do
			local session = DataManager.Get(player)
			if session then
				pushSpecialRollState(player, session)
			end
		end
	end
end)

return RollManager
