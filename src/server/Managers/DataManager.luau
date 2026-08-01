-- Vanilla DataStore persistence. One in-memory Lua session table per player
-- (Cash, Inventory, NextUid) instead of Instance Values -- a single field
-- list instead of duplicating each field across load/save/apply/default.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)

local DataManager = {}

local store = DataStoreService:GetDataStore("WealthRNG_PlayerData_V1")

local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2
local AUTOSAVE_INTERVAL_SECONDS = 120

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
	-- Developer Product receipts (CashPackManager.luau) already granted,
	-- keyed by PurchaseId -- Roblox retries ProcessReceipt (even across
	-- server restarts) until it gets PurchaseGranted back, so this has to
	-- be persisted, not just an in-memory set, or a retry after a crash
	-- between "grant the cash" and "acknowledge the receipt" would grant
	-- it a second time.
	GrantedCashPackPurchaseIds: { [string]: boolean },
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
		GrantedCashPackPurchaseIds = {},
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
				GrantedCashPackPurchaseIds = data.GrantedCashPackPurchaseIds or {},
				LoadedOk = true,
			}
		else
			session = newDefaultSession()
		end
	else
		-- Load failed: fall back to an in-memory-only default session and
		-- never let Save() persist over the player's real saved data.
		session = newDefaultSession()
		session.LoadedOk = false
		warn(string.format("[DataManager] Failed to load data for %s (%d) after %d attempts", player.Name, player.UserId, RETRY_COUNT))
	end

	sessions[player] = session
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
		GrantedCashPackPurchaseIds = session.GrantedCashPackPurchaseIds,
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

Players.PlayerRemoving:Connect(function(player)
	DataManager.Save(player)
	DataManager.Release(player)
end)

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		DataManager.Save(player)
	end
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
