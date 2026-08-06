-- Vanilla DataStore persistence. One in-memory Lua session table per player
-- (Cash, Inventory, NextUid) instead of Instance Values -- a single field
-- list instead of duplicating each field across load/save/apply/default.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local StadiumOfferConfig = require(ReplicatedStorage.Modules.StadiumOfferConfig)

local DataManager = {}

local store = DataStoreService:GetDataStore("WealthRNG_PlayerData_V1")

local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2
local AUTOSAVE_INTERVAL_SECONDS = 120

-- Awarded exactly once, the moment a genuinely new player (no prior save
-- found -- see Load's `else session = newDefaultSession()` branch) is
-- first created -- not on every join, and not for a returning player whose
-- Load merely failed (that path warns and falls back separately, see
-- LoadedOk = false below).
local NEW_PLAYER_BADGE_ID = 4105962588418819

export type Session = {
	Cash: number,
	Inventory: { { Uid: number, ItemId: string } },
	NextUid: number,
	EquippedItemUids: { number },
	TotalRolls: number,
	OwnedAssets: { [string]: boolean },
	EquippedAssets: { string },
	-- Quantity: how many units this one purchase (x1/x10/x100) bought --
	-- one entry per purchase action, not one per unit, so buying 100 at
	-- once doesn't create 100 separate rows to scroll through.
	Investments: { { Uid: number, Id: string, PurchasedAt: number, Quantity: number } },
	NextInvestmentUid: number,
	ActivePotions: { [string]: number },
	-- Per-rarity opt-in: missing/false means off. Common/Rare/Epic default
	-- to ON for new players (see newDefaultSession) -- those tiers are common
	-- enough that duplicates are just clutter, not a loss worth protecting
	-- against. Legendary/Ultra/Luxury default to OFF (missing) since those
	-- are rare enough a player should decide deliberately whether to
	-- auto-sell a repeat instead of it happening silently by default.
	AutoSellDuplicates: { [string]: boolean },
	-- Music/SFX/VFX on-off prefs -- default true (opposite of
	-- AutoSellDuplicates: there's no downside to leaving these on, so
	-- opt-out reads better than opt-in). Not wired to any actual
	-- sound/effect yet -- the game has none -- this just persists the
	-- toggle state so it's ready the moment one exists.
	Preferences: { [string]: boolean },
	-- [trackId] = level, 0..UpgradeConfig.Tracks[trackId].MaxLevel. Missing
	-- key means level 0 -- default empty table, not pre-filled zeros.
	Upgrades: { [string]: number },
	-- One-time claim, see GroupRewardsManager.luau -- true forever once
	-- claimed, even if the player later leaves the Roblox group.
	ClaimedGroupReward: boolean,
	-- Daily Rewards (DailyRewardsManager.luau) -- Day is 1..7, which
	-- reward is claimable next; wraps back to 1 after a Day-7 claim.
	-- LastDailyRewardClaimAt is 0 until the very first claim (never
	-- gated by the cooldown until then).
	DailyRewardDay: number,
	LastDailyRewardClaimAt: number,
	-- Special Roll ladder (SpecialRollConfig.luau) -- every tier counts up
	-- independently and simultaneously (keyed by tier Id, e.g. "Golden"),
	-- not one shared sequential counter. Roll-count tiers (Golden/Diamond/
	-- Ruby/Emerald) advance by 1 per normal roll; the time tier (Lucky)
	-- advances by 1 per second the player is online (see RollManager.luau's
	-- per-second loop) -- both kinds are capped at that tier's Threshold
	-- once reached, so it just sits "ready" instead of overflowing, until
	-- that specific tier is claimed, which resets ONLY that tier's entry
	-- back to 0. All 5 tiers can be sitting claimable at the same time,
	-- each on its own repeating cycle.
	SpecialRollProgress: { [string]: number },
	-- Lucky Roll's 6 SecondsStage tiers (SpecialRollConfig.luau) share ONE
	-- progress counter (SpecialRollProgress["Lucky"]) but each stage still
	-- needs its OWN "already claimed this cycle" flag -- otherwise nothing
	-- would stop claiming Stage I again once Stage III is reached, since
	-- the shared counter never resets between stages. Keyed by tier Id
	-- (e.g. "Lucky3"). Cleared entirely (see RollManager.TrySpecialRoll)
	-- only when the final stage (Lucky6) is claimed, alongside resetting
	-- the shared counter back to 0 -- that's what starts a fresh 90-min climb.
	ClaimedLuckyStages: { [string]: boolean },
	-- Total seconds ever spent online, across every session, never resets --
	-- +1/sec for every currently-loaded session (see the per-second loop
	-- near the bottom of this file). Backs the "Top Time" leaderboard
	-- (LeaderboardManager.luau) -- unlike SpecialRollProgress["Lucky"]
	-- (Lucky Roll's 90-min cycle, which resets), this is a lifetime total.
	TotalPlaytimeSeconds: number,
	-- Derived from Inventory/EquippedItemUids, NOT saved to the DataStore
	-- (recomputed once at Load, then kept in sync by InventoryManager.
	-- AddItem/RemoveItem/Equip/Unequip as the session goes on) -- exist
	-- purely so RollManager's auto-sell-duplicates check and IncomeConfig's
	-- item-income lookup don't have to linear-scan the full (only-ever-
	-- growing) Inventory array on literally every roll. See
	-- InventoryManager.luau's header.
	OwnedItemCounts: { [string]: number },
	InventoryTotalValue: number,
	-- Only valid because ItemDatabase.MaxEquipped is 1 -- the ItemId of
	-- whatever's currently in EquippedItemUids, or nil if nothing is.
	EquippedItemId: string?,
	-- Auto Claim gamepass's on/off toggle (SetAutoClaim remote) -- persisted
	-- (unlike Auto Roll's toggle, which is pure client-side state) because
	-- the actual auto-claiming happens in RollManager.luau's server-side
	-- per-second loop, which needs to remember this across a full session
	-- restart, not just while the player's client is open. Only matters at
	-- all if AutoClaimManager.Owns(player) is also true -- a non-owner
	-- toggling this does nothing. Defaults true (see newDefaultSession/Load)
	-- so a first-time buyer doesn't also have to remember to turn it on.
	AutoClaimEnabled: boolean,
	-- LARP Battles (BattleManager.luau) -- points reset weekly, not tracked
	-- via a separate cron/reset job. Instead, BattlePointsWeekStart records
	-- which week's Monday-00:00-UTC these points belong to; anything that
	-- reads or credits BattlePoints calls BattlePointsConfig.EnsureCurrentWeek
	-- first, which zeroes both fields the moment they're found to belong to
	-- a past week. See BattlePointsConfig.luau for why this is a shared
	-- leaf module instead of living in BattleManager.
	BattlePoints: number,
	BattlePointsWeekStart: number,
	-- LARP Battles ranked -- separate from BattlePoints above (that one's
	-- the weekly-resetting "Most Points" leaderboard). This is permanent,
	-- never resets -- +15 per win, -10 per loss (floored at 0), 0 on a
	-- draw. Tier (Bronze..Diamond) is derived live from this number via
	-- BattleRankConfig.GetTier, not stored separately.
	BattleRankPoints: number,
	-- Developer Product receipts (CashPackManager.luau) already granted,
	-- keyed by PurchaseId -- Roblox retries ProcessReceipt (even across
	-- server restarts) until it gets PurchaseGranted back, so this has to
	-- be persisted, not just an in-memory set, or a retry after a crash
	-- between "grant the cash" and "acknowledge the receipt" would grant
	-- it a second time.
	GrantedCashPackPurchaseIds: { [string]: boolean },
	-- Promo codes already redeemed this save (CodesManager.luau), keyed by
	-- the UPPERCASED code string -- one redemption per code, forever, same
	-- shape as GrantedCashPackPurchaseIds above.
	RedeemedCodes: { [string]: boolean },
	-- Robux "instant buy" potion purchases already granted (PotionManager.
	-- luau's GrantPotionFree, called from CashPackManager.luau's shared
	-- ProcessReceipt), keyed by PurchaseId -- same dedup shape/reasoning as
	-- GrantedCashPackPurchaseIds, kept as its own field since it's a
	-- distinct purchase flow.
	GrantedPotionPurchaseIds: { [string]: boolean },
	-- Permanent, once true -- earned via RollPanel.luau's "Get Auto Roll
	-- Free" 30-min-online offer (AutoRollManager.luau), functions exactly
	-- like owning the real gamepass from then on (AutoRollManager.Owns
	-- checks this OR the real MarketplaceService ownership). Never reset.
	AutoRollFreeGranted: boolean,
	-- How many extra copies of Sol Stadium (AssetDatabase's Top3Estate)
	-- this player has bought from the limited-stock Meshy Stadium vendor
	-- (StadiumOfferManager.luau) -- deliberately separate from
	-- session.OwnedAssets (a plain owned/not-owned flag every other Asset
	-- uses) since this is the one Estate that can be owned more than once.
	-- Capped at StadiumOfferConfig.MaxCashPurchases via cash; unlimited via
	-- Robux (not implemented yet).
	SolStadiumOwned: number,
	-- Robux Developer Product purchases of Sol Stadium already granted
	-- (CashPackManager.luau's ProcessReceipt), keyed by PurchaseId -- same
	-- dedup shape/reasoning as GrantedCashPackPurchaseIds. Unlike the cash
	-- path, Robux purchases are unlimited (no MaxCashPurchases cap) and
	-- don't touch the shared stock pool (StadiumOfferManager.luau).
	GrantedStadiumOfferPurchaseIds: { [string]: boolean },
	-- One-time tutorial hint callouts (TutorialHint.luau client-side, e.g.
	-- the "UPGRADES" pointer shown the first time that panel opens) --
	-- keyed by an arbitrary hint id, true once shown/dismissed so it never
	-- shows again for this player.
	SeenTutorialHints: { [string]: boolean },
	-- True once a player has clicked through the new-player onboarding
	-- overlay (OnboardingTutorial.luau: roll -> equip -> explore), so it
	-- never shows again on a later join.
	CompletedOnboarding: boolean,
	-- Robux Developer Product purchases of Exclusive Crates already granted
	-- (CrateManager.OpenCrates, called from CashPackManager.luau's
	-- ProcessReceipt), keyed by PurchaseId -- same dedup shape/reasoning as
	-- GrantedCashPackPurchaseIds/GrantedStadiumOfferPurchaseIds.
	GrantedCratePurchaseIds: { [string]: boolean },
	LoadedOk: boolean,
}

local sessions: { [Player]: Session } = {}

local function newDefaultSession(): Session
	return {
		Cash = 0,
		Inventory = {},
		NextUid = 1,
		EquippedItemUids = {},
		TotalRolls = 0,
		OwnedAssets = {},
		EquippedAssets = {},
		Investments = {},
		NextInvestmentUid = 1,
		ActivePotions = {},
		AutoSellDuplicates = { Common = true, Rare = true, Epic = true },
		Preferences = { Music = true, SFX = true, VFX = true },
		Upgrades = {},
		ClaimedGroupReward = false,
		DailyRewardDay = 1,
		LastDailyRewardClaimAt = 0,
		SpecialRollProgress = {},
		ClaimedLuckyStages = {},
		TotalPlaytimeSeconds = 0,
		OwnedItemCounts = {},
		InventoryTotalValue = 0,
		EquippedItemId = nil,
		AutoClaimEnabled = true,
		BattlePoints = 0,
		BattlePointsWeekStart = 0,
		BattleRankPoints = 0,
		GrantedCashPackPurchaseIds = {},
		RedeemedCodes = {},
		GrantedPotionPurchaseIds = {},
		AutoRollFreeGranted = false,
		SolStadiumOwned = 0,
		GrantedStadiumOfferPurchaseIds = {},
		SeenTutorialHints = {},
		CompletedOnboarding = false,
		GrantedCratePurchaseIds = {},
		LoadedOk = true,
	}
end

-- Recomputes the 3 Inventory-derived fields from scratch -- only ever
-- needed once, right after Load pulls a possibly-old save off the
-- DataStore (a brand new session already starts with the trivial empty
-- defaults above). O(n) over Inventory, but a one-time login cost, not a
-- per-roll one -- InventoryManager keeps these in sync incrementally from
-- here on.
local function deriveInventoryState(inventory, equippedItemUids: { number }): ({ [string]: number }, number, string?)
	local ownedItemCounts: { [string]: number } = {}
	local totalValue = 0
	for _, entry in inventory do
		ownedItemCounts[entry.ItemId] = (ownedItemCounts[entry.ItemId] or 0) + 1
		local item = ItemDatabase.GetItem(entry.ItemId)
		if item then
			totalValue += item.Value
		end
	end

	local equippedItemId: string? = nil
	local equippedUid = equippedItemUids[1]
	if equippedUid then
		for _, entry in inventory do
			if entry.Uid == equippedUid then
				equippedItemId = entry.ItemId
				break
			end
		end
	end

	return ownedItemCounts, totalValue, equippedItemId
end

local function attempt(fn): (boolean, any)
	for i = 1, RETRY_COUNT do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		if i < RETRY_COUNT then
			task.wait(RETRY_BACKOFF_SECONDS)
		end
	end
	return false, nil
end

function DataManager.Load(player: Player): Session
	local key = "Player_" .. player.UserId
	local ok, data = attempt(function()
		return store:GetAsync(key)
	end)

	local session: Session
	-- Set true by the Sol Stadium self-healing correction below if it
	-- actually changes anything -- forces an immediate save afterward (see
	-- that comment for why).
	local needsImmediateSave = false
	if ok then
		if data then
			-- Backfill Quantity = 1 on entries saved before that field
			-- existed, so old saves don't silently value themselves at 0.
			local investments = data.Investments or {}
			for _, entry in investments do
				entry.Quantity = entry.Quantity or 1
			end

			local inventory = data.Inventory or {}
			local equippedItemUids = data.EquippedItemUids or {}
			local ownedItemCounts, inventoryTotalValue, equippedItemId = deriveInventoryState(inventory, equippedItemUids)

			-- Common/Rare/Epic default ON (see newDefaultSession) -- but that
			-- only ever applied to BRAND NEW sessions. Backfill it here too,
			-- for existing saves, so it actually reaches everyone: a MISSING
			-- key (never explicitly toggled, whether because this is an old
			-- save from before the default existed, or the player just never
			-- touched the setting) becomes true. An explicit `false` (the
			-- player deliberately turned it off via SettingsPanel) or
			-- explicit `true` is left alone either way -- SetAutoSellDuplicate
			-- always writes a real boolean, never removes the key, so a
			-- deliberate off stays off.
			local autoSellDuplicates = data.AutoSellDuplicates or {}
			for _, rarity in { "Common", "Rare", "Epic" } do
				if autoSellDuplicates[rarity] == nil then
					autoSellDuplicates[rarity] = true
				end
			end

			session = {
				Cash = data.Cash or 0,
				Inventory = inventory,
				NextUid = data.NextUid or 1,
				EquippedItemUids = equippedItemUids,
				TotalRolls = data.TotalRolls or 0,
				OwnedAssets = data.OwnedAssets or {},
				EquippedAssets = data.EquippedAssets or {},
				Investments = investments,
				NextInvestmentUid = data.NextInvestmentUid or 1,
				ActivePotions = data.ActivePotions or {},
				AutoSellDuplicates = autoSellDuplicates,
				Preferences = data.Preferences or { Music = true, SFX = true, VFX = true },
				Upgrades = data.Upgrades or {},
				ClaimedGroupReward = data.ClaimedGroupReward or false,
				DailyRewardDay = data.DailyRewardDay or 1,
				LastDailyRewardClaimAt = data.LastDailyRewardClaimAt or 0,
				SpecialRollProgress = data.SpecialRollProgress or {},
				ClaimedLuckyStages = data.ClaimedLuckyStages or {},
				TotalPlaytimeSeconds = data.TotalPlaytimeSeconds or 0,
				OwnedItemCounts = ownedItemCounts,
				InventoryTotalValue = inventoryTotalValue,
				EquippedItemId = equippedItemId,
				AutoClaimEnabled = data.AutoClaimEnabled == nil and true or data.AutoClaimEnabled,
				BattlePoints = data.BattlePoints or 0,
				BattlePointsWeekStart = data.BattlePointsWeekStart or 0,
				BattleRankPoints = data.BattleRankPoints or 0,
				GrantedCashPackPurchaseIds = data.GrantedCashPackPurchaseIds or {},
				RedeemedCodes = data.RedeemedCodes or {},
				GrantedPotionPurchaseIds = data.GrantedPotionPurchaseIds or {},
				AutoRollFreeGranted = data.AutoRollFreeGranted or false,
				SolStadiumOwned = data.SolStadiumOwned or 0,
				GrantedStadiumOfferPurchaseIds = data.GrantedStadiumOfferPurchaseIds or {},
				SeenTutorialHints = data.SeenTutorialHints or {},
				CompletedOnboarding = data.CompletedOnboarding or false,
				GrantedCratePurchaseIds = data.GrantedCratePurchaseIds or {},
				LoadedOk = true,
			}

			-- Self-healing: a race condition (fixed in StadiumOfferManager.luau)
			-- let a fast double/triple-click buy more than
			-- StadiumOfferConfig.MaxCashPurchases CASH copies of Sol Stadium
			-- before the fix landed -- clamp the CASH-sourced portion back
			-- down to the max and refund the excess cash spent. Robux-sourced
			-- copies (GrantedStadiumOfferPurchaseIds, unlimited by design) are
			-- excluded from this check entirely, or a legitimate Robux buyer
			-- with e.g. 5 copies would get wrongly clamped down to 3. Doesn't
			-- restore the shared stock pool (StadiumOfferManager.luau owns
			-- that store, requiring it here would risk a circular require).
			local cashSourcedOwned = StadiumOfferConfig.CountCashOwned(session)
			if cashSourcedOwned > StadiumOfferConfig.MaxCashPurchases then
				local excess = cashSourcedOwned - StadiumOfferConfig.MaxCashPurchases
				session.SolStadiumOwned -= excess
				session.Cash += excess * StadiumOfferConfig.GetCashPrice()
				-- This correction only lives in memory until saved -- without
				-- forcing that save now, a crash/ungraceful shutdown before
				-- the next autosave would leave the on-disk copy still over
				-- the cap, so the NEXT Load would apply (and refund) this
				-- same correction all over again -- a repeatable cash dupe
				-- for any account this migration was meant to fix once.
				needsImmediateSave = true
			end
		else
			session = newDefaultSession()

			-- Fire-and-forget -- AwardBadge is a yielding network call, and
			-- a failed/slow badge award should never hold up the player's
			-- actual data loading.
			task.spawn(function()
				local ok = pcall(function()
					BadgeService:AwardBadge(player.UserId, NEW_PLAYER_BADGE_ID)
				end)
				if not ok then
					warn(string.format("[DataManager] Failed to award new-player badge to %s (%d)", player.Name, player.UserId))
				end
			end)
		end
	else
		-- Load failed: fall back to an in-memory-only default session and
		-- never let Save() persist over the player's real saved data.
		session = newDefaultSession()
		session.LoadedOk = false
		warn(string.format("[DataManager] Failed to load data for %s (%d) after %d attempts", player.Name, player.UserId, RETRY_COUNT))
	end

	sessions[player] = session
	if needsImmediateSave then
		task.spawn(DataManager.Save, player)
	end
	return session
end

function DataManager.Get(player: Player): Session?
	return sessions[player]
end

function DataManager.Save(player: Player)
	local session = sessions[player]
	if not session or not session.LoadedOk then
		return
	end

	local key = "Player_" .. player.UserId
	local payload = {
		Cash = session.Cash,
		Inventory = session.Inventory,
		NextUid = session.NextUid,
		EquippedItemUids = session.EquippedItemUids,
		TotalRolls = session.TotalRolls,
		OwnedAssets = session.OwnedAssets,
		EquippedAssets = session.EquippedAssets,
		Investments = session.Investments,
		NextInvestmentUid = session.NextInvestmentUid,
		ActivePotions = session.ActivePotions,
		AutoSellDuplicates = session.AutoSellDuplicates,
		Preferences = session.Preferences,
		Upgrades = session.Upgrades,
		ClaimedGroupReward = session.ClaimedGroupReward,
		DailyRewardDay = session.DailyRewardDay,
		LastDailyRewardClaimAt = session.LastDailyRewardClaimAt,
		SpecialRollProgress = session.SpecialRollProgress,
		ClaimedLuckyStages = session.ClaimedLuckyStages,
		TotalPlaytimeSeconds = session.TotalPlaytimeSeconds,
		AutoClaimEnabled = session.AutoClaimEnabled,
		BattlePoints = session.BattlePoints,
		BattlePointsWeekStart = session.BattlePointsWeekStart,
		BattleRankPoints = session.BattleRankPoints,
		GrantedCashPackPurchaseIds = session.GrantedCashPackPurchaseIds,
		RedeemedCodes = session.RedeemedCodes,
		GrantedPotionPurchaseIds = session.GrantedPotionPurchaseIds,
		AutoRollFreeGranted = session.AutoRollFreeGranted,
		SolStadiumOwned = session.SolStadiumOwned,
		GrantedStadiumOfferPurchaseIds = session.GrantedStadiumOfferPurchaseIds,
		SeenTutorialHints = session.SeenTutorialHints,
		CompletedOnboarding = session.CompletedOnboarding,
		GrantedCratePurchaseIds = session.GrantedCratePurchaseIds,
	}

	local ok = attempt(function()
		store:SetAsync(key, payload)
	end)

	if not ok then
		warn(string.format("[DataManager] Failed to save data for %s (%d) after %d attempts", player.Name, player.UserId, RETRY_COUNT))
	end
end

function DataManager.Release(player: Player)
	sessions[player] = nil
end

-- One-off/admin direct patch of a player's PERSISTED save, for a player who
-- is NOT currently online -- an online player's session lives in-memory
-- (see `sessions` above) and the next autosave would just overwrite
-- whatever this wrote underneath it. Callers must check
-- Players:GetPlayerByUserId/DataManager.Get first and mutate the live
-- Session directly in that case instead. `mutator` receives the raw saved
-- table (the same shape Save() writes) and edits it in place; a no-op if
-- this player has no save yet.
-- Read-only counterpart to PatchOfflineSession, for an offline player --
-- returns nil if this player has no save yet.
function DataManager.GetOfflineBattlePoints(userId: number): number?
	local key = "Player_" .. userId
	local ok, data = attempt(function()
		return store:GetAsync(key)
	end)
	if ok and data then
		return data.BattlePoints or 0
	end
	return nil
end

function DataManager.PatchOfflineSession(userId: number, mutator: (any) -> ())
	local key = "Player_" .. userId
	attempt(function()
		store:UpdateAsync(key, function(data)
			if not data then
				return nil
			end
			mutator(data)
			return data
		end)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	DataManager.Save(player)
	DataManager.Release(player)
end)

game:BindToClose(function()
	-- Saving players one at a time here used to mean a slow/throttled save
	-- for an early player in the list could eat most of Roblox's bounded
	-- shutdown window, leaving later players never saved at all (losing up
	-- to AUTOSAVE_INTERVAL_SECONDS of state, including any just-granted
	-- Cash Pack/Potion purchase). Running every player's Save in its own
	-- thread and waiting for all of them lets them race in parallel
	-- instead, so the total time is bounded by the SLOWEST single save, not
	-- the sum of all of them.
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end

	local remaining = #players
	local done = Instance.new("BindableEvent")
	for _, player in players do
		task.spawn(function()
			DataManager.Save(player)
			remaining -= 1
			if remaining == 0 then
				done:Fire()
			end
		end)
	end
	done.Event:Wait()
	done:Destroy()
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL_SECONDS)
		for _, player in Players:GetPlayers() do
			DataManager.Save(player)
		end
	end
end)

-- +1/sec for every currently-loaded session -- `sessions` only ever holds
-- online players (Release() drops them on leave), so this is naturally
-- "seconds spent online," no separate Players:GetPlayers() filter needed.
task.spawn(function()
	while true do
		task.wait(1)
		for _, session in sessions do
			session.TotalPlaytimeSeconds += 1
		end
	end
end)

return DataManager
