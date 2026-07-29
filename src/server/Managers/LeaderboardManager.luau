-- Global, cross-server rankings via OrderedDataStore (regular DataStore, used
-- by DataManager, has no sorted-query API). Two loops:
--   - submit (every ~20s): pushes dirty players' current stats into the 3
--     ordered stores. Throttled via a dirty-flag instead of writing on every
--     roll/sell, to stay well inside OrderedDataStore write-rate budgets.
--   - refresh (every ~60s): pulls top 100 from each store, (re)paints them
--     into the matching board's scrolling row list (built by MapBuilder,
--     ranks 1/2/3 colored gold/silver/bronze), and -- reusing that same
--     fetch, no extra DataStore calls -- tells any online player whose rank
--     changed via a personal chat system message.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)
local DataManager = require(ServerScriptService.Managers.DataManager)
local Leaderstats = require(ServerScriptService.Managers.Leaderstats)
local StatsManager = require(ServerScriptService.Managers.StatsManager)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)

-- Which BoardIndex's rank gets mirrored onto leaderstats.Rank (shown next
-- to the player's name in Roblox's built-in PlayerList) -- Net Worth is
-- the closest thing this game has to an "overall" ranking.
local RANK_LEADERSTAT_BOARD_INDEX = 2

local systemMessage = RemotesBootstrap:WaitForChild("SystemMessage")
local playerRankUpdated = RemotesBootstrap:WaitForChild("PlayerRankUpdated")

local LeaderboardManager = {}

local SUBMIT_INTERVAL_SECONDS = 20
local REFRESH_INTERVAL_SECONDS = 60
local TOP_N = 100
-- In SurfaceGui pixels, not studs -- MapBuilder's boards render at 100
-- PixelsPerStud (explicit, see buildLeaderboard), so 110px =~ 1.1 studs
-- tall per row. Tall enough for TextScaled to wrap a long "1. Name -
-- $Value" onto 2 lines and still render at a legible size -- forcing
-- everything onto one line in a narrow board was squeezing the font down
-- to near-unreadable. Fewer rows fit on screen at once, but the list
-- already scrolls (ScrollingFrame), so that's a fine trade for actually
-- being able to read it.
local ROW_HEIGHT = 110
local RETRY_COUNT = 3
local RETRY_BACKOFF_SECONDS = 2

local RANK_COLORS: { [number]: Color3 } = {
	[1] = Color3.fromRGB(255, 215, 0), -- gold
	[2] = Color3.fromRGB(210, 210, 220), -- silver
	[3] = Color3.fromRGB(205, 127, 50), -- bronze
}
local DEFAULT_ROW_COLOR = Color3.fromRGB(255, 255, 255)

local warnedAboutApiAccess = false

local function attempt(fn): (boolean, any)
	local lastError: string? = nil
	for i = 1, RETRY_COUNT do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = tostring(result)
		if i < RETRY_COUNT then
			task.wait(RETRY_BACKOFF_SECONDS)
		end
	end

	-- The single most common reason this fails in Studio: DataStore API
	-- access is off by default for local testing. Warn once (not every
	-- failed attempt -- that'd spam Output every 20-60s) with the fix.
	if not warnedAboutApiAccess then
		warnedAboutApiAccess = true
		warn(
			"[LeaderboardManager] DataStore call failed: "
				.. tostring(lastError)
				.. " -- in Studio, check Game Settings > Security > "
				.. "'Enable Studio Access to API Services' is ON."
		)
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
	-- Was Cash + rolled-items value only -- silently missing Assets and
	-- Investments, which for any established player are the majority of
	-- their real net worth. Delegate to the one authoritative formula
	-- (StatsManager, same as the client's Net Worth panel/stat) instead of
	-- re-deriving a second, incomplete copy of it here.
	return StatsManager.ComputeNetWorth(player)
end

local function getTotalRolls(player: Player): number?
	local session = DataManager.Get(player)
	return session and session.TotalRolls
end

-- BoardIndex matches MapBuilder's LEADERBOARD_LABELS order (1=Cash, 2=NetWorth, 3=Rolls).
local categories = {
	{ BoardIndex = 1, Label = "Cash", Store = DataStoreService:GetOrderedDataStore("WealthRNG_TopCash"), GetValue = getCash, Format = NumberFormat.FormatCash },
	{ BoardIndex = 2, Label = "Net Worth", Store = DataStoreService:GetOrderedDataStore("WealthRNG_TopNetWorth"), GetValue = getNetWorth, Format = NumberFormat.FormatCash },
	{ BoardIndex = 3, Label = "Rolls", Store = DataStoreService:GetOrderedDataStore("WealthRNG_TopRolls"), GetValue = getTotalRolls, Format = NumberFormat.Format },
}

local dirtyPlayers: { [Player]: boolean } = {}
local nameCache: { [number]: string } = {}
-- [player][boardIndex] = last rank we sent a chat message for -- only
-- re-announce when it actually changes, not on every 60s refresh.
local lastAnnouncedRank: { [Player]: { [number]: number } } = {}

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

local function announceRankIfChanged(player: Player, boardIndex: number, rank: number, label: string)
	local playerRanks = lastAnnouncedRank[player]
	if not playerRanks then
		playerRanks = {}
		lastAnnouncedRank[player] = playerRanks
	end

	if playerRanks[boardIndex] == rank then
		return
	end
	playerRanks[boardIndex] = rank

	systemMessage:FireClient(player, string.format("You're #%d on the Top %s leaderboard!", rank, label))
end

local function clearRows(rowsFrame: ScrollingFrame)
	for _, child in rowsFrame:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function refreshBoard(boardIndex: number, label: string, store: OrderedDataStore, format: (number) -> string)
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

	local rowsFrame = displayGui:FindFirstChild("Rows")
	if not rowsFrame then
		return
	end

	local ok, pages = attempt(function()
		return store:GetSortedAsync(false, TOP_N)
	end)
	if not ok then
		return
	end

	local top = pages:GetCurrentPage()

	clearRows(rowsFrame)

	-- Reset everyone first -- otherwise a player who drops out of the top
	-- 100 between refreshes would keep showing their last rank forever.
	local mirrorsToLeaderstat = boardIndex == RANK_LEADERSTAT_BOARD_INDEX
	if mirrorsToLeaderstat then
		for _, onlinePlayer in Players:GetPlayers() do
			Leaderstats.SetRank(onlinePlayer, nil)
		end
	end

	for i, entry in top do
		local userId = tonumber(entry.key)
		local name = userId and getDisplayName(userId) or entry.key

		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
		row.BackgroundTransparency = 1
		row.TextColor3 = RANK_COLORS[i] or DEFAULT_ROW_COLOR
		-- LuckiestGuy (the game's one decorative font, see Theme.luau) is too
		-- bold/chunky to stay legible at this size crammed onto a 3D board
		-- viewed from a distance/angle -- unlike the 2D screen UI, rows here
		-- need a plain, high-legibility font instead.
		row.Font = Enum.Font.GothamBold
		row.TextScaled = true
		row.TextWrapped = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = string.format("%d. %s - %s", i, name, format(entry.value))
		row.Parent = rowsFrame

		if userId then
			local player = Players:GetPlayerByUserId(userId)
			if player then
				announceRankIfChanged(player, boardIndex, i, label)
				if mirrorsToLeaderstat then
					Leaderstats.SetRank(player, i)
				end
				playerRankUpdated:FireClient(player, boardIndex, label, i, entry.value)
			end
		end
	end
end

-- Both loops do their work immediately on startup, THEN wait -- waiting
-- first (the original shape) meant a freshly started server showed
-- completely empty boards for a full 60s even with players already
-- online, which read as "the leaderboard doesn't work" rather than "it
-- just hasn't run yet".
task.spawn(function()
	while true do
		for player in dirtyPlayers do
			submitPlayer(player)
			dirtyPlayers[player] = nil
		end
		task.wait(SUBMIT_INTERVAL_SECONDS)
	end
end)

task.spawn(function()
	-- Small stagger so the very first refresh has a chance to see
	-- whatever the very first submit pass (above) just wrote, instead of
	-- racing it and painting empty boards anyway.
	task.wait(5)
	while true do
		for _, category in categories do
			refreshBoard(category.BoardIndex, category.Label, category.Store, category.Format)
		end
		task.wait(REFRESH_INTERVAL_SECONDS)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if dirtyPlayers[player] then
		submitPlayer(player)
		dirtyPlayers[player] = nil
	end
	lastAnnouncedRank[player] = nil
end)

return LeaderboardManager
