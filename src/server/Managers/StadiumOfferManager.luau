-- Meshy Stadium's limited-stock vendor -- the physical model (placed
-- directly in Workspace, positioned by MapBuilder.luau) that
-- StadiumOfferPanel.luau's proximity popup is triggered near. Sells Sol
-- Stadium (AssetDatabase's Top3Estate) from a shared GLOBAL stock pool
-- (StadiumOfferConfig.TotalStock, currently 200 -- one server-wide count,
-- not per-player), the one Estate that can be owned more than once (see
-- session.SolStadiumOwned's own comment in DataManager.luau).
--
-- Cross-server safe: Roblox runs many parallel servers, so decrementing
-- the shared stock has to be a single atomic DataStore UpdateAsync (same
-- compare-and-swap shape used elsewhere in this codebase, e.g.
-- BattleLeaderboardRewardManager), not a read-then-write that could let 2
-- servers both sell the "last" copy at once.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StadiumOfferConfig = require(ReplicatedStorage.Modules.StadiumOfferConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local LeaderboardManager = require(ServerScriptService.Managers.LeaderboardManager)

local requestStadiumOfferState = RemotesBootstrap:WaitForChild("RequestStadiumOfferState")
local stadiumOfferStateUpdated = RemotesBootstrap:WaitForChild("StadiumOfferStateUpdated")
local buyStadiumOffer = RemotesBootstrap:WaitForChild("BuyStadiumOffer")
local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")

local StadiumOfferManager = {}

local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2
local STOCK_KEY = "RemainingStock"

local stockStore = DataStoreService:GetDataStore("WealthRNG_StadiumOffer")

-- Guards against a fast double/triple-click firing BuyStadiumOffer
-- multiple times before the FIRST purchase's stockStore:UpdateAsync call
-- (a yielding DataStore call) has resolved -- session.SolStadiumOwned only
-- gets incremented at the very end, so without this, every concurrent
-- in-flight request reads the SAME pre-increment count and passes the
-- MaxCashPurchases check, letting a player end up with e.g. 4/3 owned.
local purchaseInProgress: { [Player]: boolean } = {}

-- Same dev/test-account exemption LeaderboardManager.luau already uses
-- (EXCLUDED_USERNAMES) -- this account can buy (to test the purchase flow)
-- without eating into the real, shared, limited stock pool.
local UNLIMITED_STOCK_USERNAMES: { [string]: boolean } = {
	fizzknot1 = true,
}

local function hasUnlimitedStock(player: Player): boolean
	return UNLIMITED_STOCK_USERNAMES[string.lower(player.Name)] == true
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

local function getRemainingStock(): number?
	local ok, stored = attempt(function()
		return stockStore:GetAsync(STOCK_KEY)
	end)
	if not ok then
		return nil
	end
	-- Never explicitly set yet (brand new game) -- the full pool is still
	-- available.
	if stored == nil then
		return StadiumOfferConfig.TotalStock
	end
	return stored
end

local function pushStateTo(player: Player, remainingStock: number)
	local session = DataManager.Get(player)
	if not session then
		return
	end
	stadiumOfferStateUpdated:FireClient(player, {
		RemainingStock = remainingStock,
		TotalStock = StadiumOfferConfig.TotalStock,
		-- Cash-sourced count specifically (not session.SolStadiumOwned's
		-- total) -- StadiumOfferPanel.luau's "OWNED X/3" gate is only about
		-- the cash cap, and Robux purchases are unlimited, so mixing them
		-- into one total would wrongly show the cash button as maxed out
		-- for a player who only ever bought via Robux.
		OwnedCount = StadiumOfferConfig.CountCashOwned(session),
		MaxCashPurchases = StadiumOfferConfig.MaxCashPurchases,
	})
end

-- Finds MapBuilder.luau's floating "STOCK X/Y" world-space label above the
-- Meshy Stadium model -- cached after the first successful lookup (cleared
-- if the label ever goes away, e.g. a map rebuild) since a full descendant
-- search on every single purchase would be wasteful otherwise.
local cachedStockLine: TextLabel? = nil
local function getStockLineLabel(): TextLabel?
	if cachedStockLine and cachedStockLine.Parent then
		return cachedStockLine
	end
	local meshyStadium = Workspace:FindFirstChild("Meshy Stadium")
	if not meshyStadium then
		return nil
	end
	local billboard = meshyStadium:FindFirstChild("StadiumInfoLabel", true)
	cachedStockLine = billboard and billboard:FindFirstChild("StockLine") :: TextLabel?
	return cachedStockLine
end

local function updateStadiumInfoLabel(remainingStock: number)
	local label = getStockLineLabel()
	if label then
		label.Text = string.format("STOCK %d/%d", remainingStock, StadiumOfferConfig.TotalStock)
	end
end

local function broadcastState(remainingStock: number)
	for _, player in Players:GetPlayers() do
		pushStateTo(player, remainingStock)
	end
	updateStadiumInfoLabel(remainingStock)
end

requestStadiumOfferState.OnServerEvent:Connect(function(player: Player)
	if not DataManager.Get(player) then
		return
	end
	local remainingStock = getRemainingStock()
	if remainingStock then
		pushStateTo(player, remainingStock)
	end
end)

buyStadiumOffer.OnServerEvent:Connect(function(player: Player)
	if purchaseInProgress[player] then
		return
	end
	purchaseInProgress[player] = true

	-- Every subsequent early-return below must go through this instead of
	-- a bare `return`, or the lock stays stuck "in progress" forever for
	-- this player (they'd never be able to buy again this session).
	local function finish()
		purchaseInProgress[player] = nil
	end

	local session = DataManager.Get(player)
	if not session then
		finish()
		return
	end

	if StadiumOfferConfig.CountCashOwned(session) >= StadiumOfferConfig.MaxCashPurchases then
		systemMessage:FireClient(player, "You've already bought the max Sol Stadium copies with Cash!")
		finish()
		return
	end

	local price = StadiumOfferConfig.GetCashPrice()
	if price <= 0 or session.Cash < price then
		finish()
		return
	end

	local claimed: boolean
	local newRemainingStock: number

	if hasUnlimitedStock(player) then
		-- Doesn't touch stockStore at all -- the shared pool stays exactly
		-- where it was, as if this purchase never happened.
		claimed = true
		newRemainingStock = getRemainingStock() or StadiumOfferConfig.TotalStock
	else
		-- Atomic claim on the shared stock -- only decrements (and only this
		-- server's request succeeds) if stock is still > 0 at the moment of
		-- the compare-and-swap, regardless of how many servers/players are
		-- racing to buy the last copies at once.
		claimed = false
		newRemainingStock = 0
		local updateOk = attempt(function()
			stockStore:UpdateAsync(STOCK_KEY, function(stored)
				local current = stored or StadiumOfferConfig.TotalStock
				if current <= 0 then
					return stored
				end
				claimed = true
				newRemainingStock = current - 1
				return newRemainingStock
			end)
		end)

		-- A transient DataStore failure (all 3 retries threw) is NOT the
		-- same as the callback running and genuinely finding 0 stock --
		-- `claimed` stays false either way, but only the latter means
		-- stock is really out. Broadcasting "0 remaining" to the whole
		-- server off the back of one unrelated write failure would wrongly
		-- disable everyone else's Cash button until the next real update.
		if not updateOk then
			systemMessage:FireClient(player, "Something went wrong -- try again!")
			finish()
			return
		end
	end

	if not claimed then
		systemMessage:FireClient(player, "Sol Stadium is sold out!")
		broadcastState(0)
		finish()
		return
	end

	session.Cash -= price
	session.SolStadiumOwned += 1

	-- Charge + grant above are already final at this point -- wrapping
	-- everything else in pcall so a rare error in any of these (a bad
	-- Instance reference, a client that disconnected mid-call, etc.) can
	-- never leave `finish()` unreached, which would otherwise lock this
	-- player out of ever buying Sol Stadium with Cash again for the rest
	-- of the session despite having already paid.
	local notifyOk = pcall(function()
		systemMessage:FireClient(player, string.format("Bought Sol Stadium for %s! (%d/%d Cash owned)", NumberFormat.FormatCash(price), StadiumOfferConfig.CountCashOwned(session), StadiumOfferConfig.MaxCashPurchases))
		StatsManager.Recompute(player)
		LeaderboardManager.MarkDirty(player)
		-- Broadcast, not just pushStateTo(player, ...) -- the stock count is
		-- a shared global pool, so every other player currently looking at
		-- the popup needs to see the new remaining count too, not just the
		-- buyer.
		broadcastState(newRemainingStock)
	end)
	if not notifyOk then
		warn(string.format("[StadiumOfferManager] Post-purchase notify/recompute failed for %s -- purchase itself already succeeded.", player.Name))
	end
	finish()
end)

-- Reconciles the 3D world label with the REAL cross-server stock count on
-- every server start -- without this, MapBuilder.luau seeds it with a
-- hardcoded "STOCK TotalStock/TotalStock" that only ever gets corrected by
-- the next purchase/migration event on THIS particular server, so a freshly
-- booted server could show a stale "200/200" indefinitely on a quiet day
-- even though the true DataStore value is lower.
task.spawn(function()
	local remainingStock = getRemainingStock()
	if remainingStock then
		updateStadiumInfoLabel(remainingStock)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	purchaseInProgress[player] = nil
end)

-- ONE-TIME correction: testing (rapid-click race condition, now fixed
-- above, plus general dev testing) ate into the shared stock pool before
-- launch -- reset it back to the full TotalStock exactly once. Guarded by
-- a claim (same pattern as OneTimeBattlePointsMerge.luau) so it can only
-- ever apply once, across every server, ever -- safe to leave this in
-- permanently.
do
	local migrationStateStore = DataStoreService:GetDataStore("WealthRNG_OneTimeMigrations")
	local MIGRATION_KEY = "ResetStadiumStock_pretesting_v2"

	task.spawn(function()
		local ok, alreadyDone = attempt(function()
			return migrationStateStore:GetAsync(MIGRATION_KEY)
		end)
		if not ok or alreadyDone then
			return
		end

		local claimed = false
		attempt(function()
			migrationStateStore:UpdateAsync(MIGRATION_KEY, function(stored)
				if stored then
					return stored
				end
				claimed = true
				return true
			end)
		end)
		if not claimed then
			return
		end

		local resetOk = attempt(function()
			stockStore:SetAsync(STOCK_KEY, StadiumOfferConfig.TotalStock)
		end)
		if resetOk then
			broadcastState(StadiumOfferConfig.TotalStock)
		end
	end)
end

return StadiumOfferManager
