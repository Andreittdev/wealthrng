-- No 2D screen HUD -- the player's own rank is painted directly onto each
-- physical leaderboard board's reserved footer TextLabel (MapBuilder
-- builds it with placeholder text "You: Unranked" -- see buildLeaderboard's
-- YourRankLabel), same as the pinned personal-rank footer big Roblox
-- leaderboard games use. Setting Text from a LocalScript only changes what
-- THIS client sees -- it never replicates to the server or other players
-- -- so everyone standing at the same board sees their OWN rank there.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)

local BoardRankLabels = {}

-- BoardIndex -> whether that board's values are Cash-formatted ($) --
-- must match LeaderboardManager.luau's `categories` table (1=Cash,
-- 2=Net Worth, 3=Rolls).
local IS_CASH_BY_BOARD: { [number]: boolean } = { [1] = true, [2] = true, [3] = false }

local function findYourRankLabel(boardIndex: number): TextLabel?
	local mapFolder = Workspace:FindFirstChild("Map")
	if not mapFolder then
		return nil
	end

	local board = mapFolder:FindFirstChild("Leaderboard" .. boardIndex .. "_Board")
	if not board then
		return nil
	end

	local displayGui = board:FindFirstChild("Display")
	if not displayGui then
		return nil
	end

	local label = displayGui:FindFirstChild("YourRankLabel")
	return label and label:IsA("TextLabel") and label or nil
end

function BoardRankLabels.Init(remotes: Folder)
	local playerRankUpdated = remotes:WaitForChild("PlayerRankUpdated")

	playerRankUpdated.OnClientEvent:Connect(function(boardIndex: number, _label: string, rank: number, value: number)
		local target = findYourRankLabel(boardIndex)
		if not target then
			return
		end

		local formattedValue = IS_CASH_BY_BOARD[boardIndex] and NumberFormat.FormatCash(value) or NumberFormat.Format(value)
		target.Text = string.format("You: #%d (%s)", rank, formattedValue)
	end)
end

return BoardRankLabels
