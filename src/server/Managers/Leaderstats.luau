-- Standard Roblox leaderboard convention: a `leaderstats` folder with value
-- objects under it, shown by the built-in Roblox PlayerList right next to
-- each player's name. Cash lives here; Rank does too (the player's global
-- Top Net Worth position, kept in sync by LeaderboardManager.SetRank) so
-- "your leaderboard place next to your name" doesn't need a custom GUI.

local Leaderstats = {}

function Leaderstats.Create(player: Player)
	if player:FindFirstChild("leaderstats") then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"

	local cash = Instance.new("IntValue")
	cash.Name = "Cash"
	cash.Value = 0
	cash.Parent = folder

	local rank = Instance.new("StringValue")
	rank.Name = "Rank"
	rank.Value = "-"
	rank.Parent = folder

	folder.Parent = player
end

function Leaderstats.SetCash(player: Player, amount: number)
	local folder = player:FindFirstChild("leaderstats")
	local cash = folder and folder:FindFirstChild("Cash")
	if cash then
		cash.Value = amount
	end
end

-- `rank` nil means "not in the top 100 (right now)" -- shown as "-".
function Leaderstats.SetRank(player: Player, rank: number?)
	local folder = player:FindFirstChild("leaderstats")
	local rankValue = folder and folder:FindFirstChild("Rank")
	if rankValue then
		rankValue.Value = rank and ("#" .. rank) or "-"
	end
end

return Leaderstats
