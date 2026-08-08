-- Global "how many of this Estate exist across the whole game" counter --
-- every Estate, every rarity tier (EstateExistenceConfig.luau) -- shown as
-- a flex stat on InventoryPanel's Estate detail view. Assets are never
-- sellable/destroyed (see IndexRewardConfig.luau's header), so this is a
-- plain monotonic +1-per-grant counter, never decremented -- "how many
-- exist" and "how many were ever granted" are the same number.
--
-- Also assigns each individual COPY its own permanent SERIAL number --
-- IncrementAndGetSerial's return value IS the new running total, which
-- doubles as "you got the Nth one ever" (AssetManager.luau/
-- StadiumOfferManager.luau/CashPackManager.luau append it to that player's
-- session.AssetSerialNumbers[assetId]). Most Estates can only ever be owned
-- once per player (one serial, ever), but Top1Estate/Top2Estate/Top3Estate
-- ("Sol Stadium") can be granted repeatedly (repeat weekly leaderboard wins,
-- extra Sol Stadium purchases) -- each grant still gets its own distinct,
-- permanent serial, appended to that same per-asset list.
--
-- Cross-server safe: one shared DataStore key holding {[assetId]: count},
-- incremented via atomic UpdateAsync (same compare-and-swap idiom as
-- StadiumOfferManager's stock pool) so two servers granting the same asset
-- at once can't hand out the same serial twice. IncrementAndGetSerial
-- YIELDS on the real DataStore call (unlike a fire-and-forget bump) --
-- necessary since callers need the exact assigned serial back to persist
-- it; acceptable since Estate grants are rare, deliberate actions, not a
-- hot path.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EstateExistenceConfig = require(ReplicatedStorage.Modules.EstateExistenceConfig)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)

local estateExistenceCountsUpdated = RemotesBootstrap:WaitForChild("EstateExistenceCountsUpdated")

local EstateExistenceManager = {}

local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2
local COUNTS_KEY = "Counts"
local REFRESH_INTERVAL_SECONDS = 60

local countsStore = DataStoreService:GetDataStore("WealthRNG_EstateExistenceCounts")

local cachedCounts: { [string]: number } = {}

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

local function broadcastCounts()
	for _, player in Players:GetPlayers() do
		if DataManager.Get(player) then
			estateExistenceCountsUpdated:FireClient(player, cachedCounts)
		end
	end
end

local function refreshFromStore()
	local ok, stored = attempt(function()
		return countsStore:GetAsync(COUNTS_KEY)
	end)
	if ok and stored then
		cachedCounts = stored
		broadcastCounts()
	end
end

-- Call the instant a tracked Estate is newly granted to anyone -- a no-op
-- (returns nil) for anything not in EstateExistenceConfig, so callers don't
-- need to pre-check membership themselves. Returns the serial number
-- assigned to THIS specific copy (the new running total), or nil if every
-- retry failed (a transient DataStore outage) -- callers should treat nil
-- as "the grant itself still succeeded, we just couldn't stamp a serial on
-- it," not abort the grant.
function EstateExistenceManager.IncrementAndGetSerial(assetId: string): number?
	if not EstateExistenceConfig.IsTracked(assetId) then
		return nil
	end

	local newSerial: number? = nil
	local ok = attempt(function()
		countsStore:UpdateAsync(COUNTS_KEY, function(stored)
			stored = stored or {}
			local next = (stored[assetId] or 0) + 1
			stored[assetId] = next
			newSerial = next
			return stored
		end)
	end)

	if ok and newSerial then
		cachedCounts[assetId] = newSerial
		broadcastCounts()
	end

	return newSerial
end

-- Same dev/test-account exemption StadiumOfferManager.luau's own stock pool
-- already uses -- this account's grants don't bump the shared "X exist"
-- total or get a serial at all, so dev testing can't pollute either stat
-- for real players.
local EXCLUDED_USERNAMES: { [string]: boolean } = {
	fizzknot1 = true,
}

-- Shared by every grant path (AssetManager.luau's GrantAsset/buyAsset,
-- StadiumOfferManager.luau, CashPackManager.luau, DailyRewardsManager.luau)
-- instead of each duplicating "increment, then append to
-- session.AssetSerialNumbers" inline -- one place to change if that ever
-- needs to grow an extra step. Mutates session directly; returns the
-- assigned serial (or nil, same meaning as IncrementAndGetSerial above) so
-- callers can still use it in their own SystemMessage text.
function EstateExistenceManager.GrantSerial(player: Player, session, assetId: string): number?
	if EXCLUDED_USERNAMES[string.lower(player.Name)] then
		return nil
	end

	local serial = EstateExistenceManager.IncrementAndGetSerial(assetId)
	if serial then
		session.AssetSerialNumbers[assetId] = session.AssetSerialNumbers[assetId] or {}
		table.insert(session.AssetSerialNumbers[assetId], serial)
	end
	return serial
end

function EstateExistenceManager.PushState(player: Player)
	estateExistenceCountsUpdated:FireClient(player, cachedCounts)
end

-- One-time-per-player catch-up so returning players who already owned
-- Estates before this system shipped get BOTH counted toward the global
-- "X exist" total AND stamped with a permanent serial -- called once right
-- after DataManager.Load (Main.server.luau). This serial is NOT their true
-- historical purchase order (there's no record of that, see AssetManager
-- .luau's header) -- it's just "whoever reconnects first after this update
-- gets the lower numbers," a permanent collector ID from here on, not a
-- claim about when they actually bought it.
--
-- Self-healing, not flag-gated: compares how many serials this assetId
-- already has recorded (session.AssetSerialNumbers) against how many
-- copies they actually own, and only backfills the DIFFERENCE. Safe to
-- call on every single login forever -- a fully caught-up player is a true
-- no-op, and a transient DataStore failure that left them short just gets
-- retried (and topped up, never double-counted) next time.
function EstateExistenceManager.BackfillOwnedAssets(player: Player, session)
	if EXCLUDED_USERNAMES[string.lower(player.Name)] then
		return
	end

	-- Sol Stadium's OwnedAssets flag was never actually set by EITHER of
	-- its purchase paths before today (StadiumOfferManager.luau/
	-- CashPackManager.luau's own header comments) -- a pre-fix buyer's
	-- session.OwnedAssets["Top3Estate"] is still false/missing even though
	-- session.SolStadiumOwned > 0, which would otherwise make the loop
	-- below (which only walks OwnedAssets) skip them entirely.
	if (session.SolStadiumOwned or 0) > 0 then
		session.OwnedAssets["Top3Estate"] = true
	end

	for assetId, owned in session.OwnedAssets do
		if owned then
			local trueCopies = 1
			if assetId == "Top3Estate" then
				trueCopies = math.max(session.SolStadiumOwned or 1, 1)
			end

			local existingSerials = session.AssetSerialNumbers[assetId]
			local existingCount = existingSerials and #existingSerials or 0
			for _ = 1, trueCopies - existingCount do
				EstateExistenceManager.GrantSerial(player, session, assetId)
			end
		end
	end
end

task.spawn(function()
	while true do
		refreshFromStore()
		task.wait(REFRESH_INTERVAL_SECONDS)
	end
end)

return EstateExistenceManager
