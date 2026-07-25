-- Standard Roblox leaderboard convention: a `leaderstats` folder with value
-- objects under it. Cash lives here so the built-in Roblox leaderboard shows it.

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

	folder.Parent = player
end

function Leaderstats.SetCash(player: Player, amount: number)
	local folder = player:FindFirstChild("leaderstats")
	local cash = folder and folder:FindFirstChild("Cash")
	if cash then
		cash.Value = amount
	end
end

return Leaderstats
