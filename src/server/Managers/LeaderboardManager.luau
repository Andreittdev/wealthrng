-- Global, cross-server rankings via OrderedDataStore (regular DataStore, used
-- by DataManager, has no sorted-query API). Two loops:
--   - submit (every ~20s): pushes dirty players' current stats into the 3
--     ordered stores. Throttled via a dirty-flag instead of writing on every
--     roll/sell, to stay well inside OrderedDataStore write-rate budgets.
--   - refresh (every ~60s): pulls top N from each store and paints the
--     result onto the matching board's SurfaceGui rows (built by MapBuilder).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.Managers.DataManager)
local InventoryManager = require(ServerScriptService.Managers.InventoryManager)

local LeaderboardManager = {}

local SUBMIT_INTERVAL_SECONDS = 20
local REFRESH_INTERVAL_SECONDS = 60
local TOP_N = 8
local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2

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

local function getCash(player: Player): number?
	local session = DataManager.Get(player)
	return session and session.Cash
end

local function getNetWorth(player: Player): number?
	local session = DataManager.Get(player)
	if not session then
		return nil
	end
	return session.Cash + InventoryManager.GetValue(player)
end

local function getTotalRolls(player: Player): number?
	local session = DataManager.Get(player)
	return session and session.TotalRolls
end

-- BoardIndex matches MapBuilder's LEADERBOARD_LABELS order (1=Cash, 2=NetWorth, 3=Rolls).
local categories = {
	{ BoardIndex = 1, Store = DataStoreService:GetOrderedDataStore("WealthRNG_TopCash"), GetValue = getCash },
	{ BoardIndex = 2, Store = DataStoreService:GetOrderedDataStore("WealthRNG_TopNetWorth"), GetValue = getNetWorth },
	{ BoardIndex = 3, Store = DataStoreService:GetOrderedDataStore("WealthRNG_TopRolls"), GetValue = getTotalRolls },
}

local dirtyPlayers: { [Player]: boolean } = {}
local nameCache: { [number]: string } = {}

function LeaderboardManager.MarkDirty(player: Player)
	dirtyPlayers[player] = true
end

local function submitPlayer(player: Player)
	for _, category in categories do
		local value = category.GetValue(player)
		if value then
			attempt(function()
				category.Store:SetAsync(tostring(player.UserId), math.floor(value))
			end)
		end
	end
end

local function getDisplayName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end

	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)

	local resolved = (ok and name) or ("Player_" .. userId)
	nameCache[userId] = resolved
	return resolved
end

local function refreshBoard(boardIndex: number, store: OrderedDataStore)
	local mapFolder = Workspace:FindFirstChild("Map")
	if not mapFolder then
		return
	end

	local board = mapFolder:FindFirstChild("Leaderboard" .. boardIndex .. "_Board")
	if not board then
		return
	end

	local displayGui = board:FindFirstChild("Display")
	if not displayGui then
		return
	end

	local ok, pages = attempt(function()
		return store:GetSortedAsync(false, TOP_N)
	end)
	if not ok then
		return
	end

	local top = pages:GetCurrentPage()

	for i = 1, TOP_N do
		local row = displayGui:FindFirstChild("Row" .. i)
		if row then
			local entry = top[i]
			if entry then
				local userId = tonumber(entry.key)
				local name = userId and getDisplayName(userId) or entry.key
				row.Text = string.format("%d. %s - %s", i, name, tostring(entry.value))
			else
				row.Text = "-"
			end
		end
	end
end

task.spawn(function()
	while true do
		task.wait(SUBMIT_INTERVAL_SECONDS)
		for player in dirtyPlayers do
			submitPlayer(player)
			dirtyPlayers[player] = nil
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(REFRESH_INTERVAL_SECONDS)
		for _, category in categories do
			refreshBoard(category.BoardIndex, category.Store)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if dirtyPlayers[player] then
		submitPlayer(player)
		dirtyPlayers[player] = nil
	end
end)

return LeaderboardManager
