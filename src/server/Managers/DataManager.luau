-- Vanilla DataStore persistence. One in-memory Lua session table per player
-- (Cash, Inventory, NextUid) instead of Instance Values -- a single field
-- list instead of duplicating each field across load/save/apply/default.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

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
	-- Per-rarity opt-in: missing/false means off. Defaults to all-off for
	-- new players (see newDefaultSession) -- auto-selling is something a
	-- player should turn on deliberately, not discover has been silently
	-- eating their rolls.
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
	-- Playtime Rewards (PlaytimeRewardsManager.luau) -- PlaytimeSeconds
	-- accumulates by 1 every second the player is online (persists across
	-- sessions, never resets). ClaimedPlaytimeMilestones is keyed by
	-- tostring(1-based index into PlaytimeRewardsConfig.Milestones) --
	-- string keys, not number, same convention as AutoSellDuplicates/
	-- Upgrades below (every other persisted dict in this Session is
	-- string-keyed; DataStore round-tripping of number-keyed tables isn't
	-- worth relying on). Unlike Daily Rewards' single "next day" pointer,
	-- every milestone here unlocks independently once PlaytimeSeconds
	-- reaches CycleStartSeconds + its own ThresholdSeconds, so several can
	-- be claimable (or sitting claimed) at once. Once every milestone in
	-- the list is claimed, PlaytimeRewardsManager resets
	-- ClaimedPlaytimeMilestones and advances PlaytimeRewardCycleStartSeconds
	-- to the current PlaytimeSeconds, so the whole ladder loops instead of
	-- being a one-time list.
	PlaytimeSeconds: number,
	ClaimedPlaytimeMilestones: { [string]: boolean },
	PlaytimeRewardCycleStartSeconds: number,
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
		AutoSellDuplicates = {},
		Preferences = { Music = true, SFX = true, VFX = true },
		Upgrades = {},
		ClaimedGroupReward = false,
		DailyRewardDay = 1,
		LastDailyRewardClaimAt = 0,
		PlaytimeSeconds = 0,
		ClaimedPlaytimeMilestones = {},
		PlaytimeRewardCycleStartSeconds = 0,
		LoadedOk = true,
	}
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

			session = {
				Cash = data.Cash or 0,
				Inventory = data.Inventory or {},
				NextUid = data.NextUid or 1,
				EquippedItemUids = data.EquippedItemUids or {},
				TotalRolls = data.TotalRolls or 0,
				OwnedAssets = data.OwnedAssets or {},
				EquippedAssets = data.EquippedAssets or {},
				Investments = investments,
				NextInvestmentUid = data.NextInvestmentUid or 1,
				ActivePotions = data.ActivePotions or {},
				AutoSellDuplicates = data.AutoSellDuplicates or {},
				Preferences = data.Preferences or { Music = true, SFX = true, VFX = true },
				Upgrades = data.Upgrades or {},
				ClaimedGroupReward = data.ClaimedGroupReward or false,
				DailyRewardDay = data.DailyRewardDay or 1,
				LastDailyRewardClaimAt = data.LastDailyRewardClaimAt or 0,
				PlaytimeSeconds = data.PlaytimeSeconds or 0,
				ClaimedPlaytimeMilestones = data.ClaimedPlaytimeMilestones or {},
				PlaytimeRewardCycleStartSeconds = data.PlaytimeRewardCycleStartSeconds or 0,
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
		PlaytimeSeconds = session.PlaytimeSeconds,
		ClaimedPlaytimeMilestones = session.ClaimedPlaytimeMilestones,
		PlaytimeRewardCycleStartSeconds = session.PlaytimeRewardCycleStartSeconds,
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

return DataManager
