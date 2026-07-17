-- Placuta "Your Rank" de pe standurile de Leaderboard (Most Cash Earned,
-- Most Time Played) -- PERSONALIZATA per jucator (fiecare vede locul LUI,
-- nu al altcuiva), de-aia se face aici, pe client, nu pe server -- un
-- SurfaceGui creat de un LocalScript e local (nu se propaga la alti
-- jucatori), spre deosebire de unul creat de server (care ar fi identic
-- pentru toata lumea).
--
-- Un singur script, generic, ca sa nu duplicam aceeasi logica pentru fiecare
-- stand nou -- doar adaugam o intrare noua in BOARDS.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local function formatMinutes(totalMinutes)
	totalMinutes = totalMinutes or 0
	local hours = math.floor(totalMinutes / 60)
	local minutes = totalMinutes % 60
	return hours .. "h " .. minutes .. "m"
end

local BOARDS = {
	{
		StandName = "LeaderboardStand",
		RemoteName = "GetMyCashRank",
		FormatScore = function(score)
			return "$" .. tostring(score)
		end
	},
	{
		StandName = "TimePlayedStand",
		RemoteName = "GetMyTimeRank",
		FormatScore = formatMinutes
	},
	{
		StandName = "RobuxSpentStand",
		RemoteName = "GetMyRobuxRank",
		FormatScore = function(score)
			return "R$" .. tostring(score)
		end
	}
}

local CHECK_DISTANCE = 25
local REFRESH_INTERVAL = 20

local function addSurfaceLabel(placard, face)
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "MyRankSurface" .. face.Name
	surfaceGui.Face = face
	surfaceGui.Adornee = placard
	-- AlwaysOnTop=false -- cu true, textul se vedea prin pereti/alte piese.
	surfaceGui.AlwaysOnTop = false
	surfaceGui.LightInfluence = 0
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 50
	surfaceGui.Parent = placard

	-- UIPadding NU functioneaza pus direct pe un SurfaceGui (nu e GuiObject)
	-- -- trebuie un Frame intermediar.
	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, 0, 1, 0)
	contentFrame.BackgroundTransparency = 1
	contentFrame.Parent = surfaceGui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.Parent = contentFrame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "Your Rank: -"
	label.TextColor3 = Color3.fromRGB(255, 220, 130)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = contentFrame

	return label
end

local function setupBoard(config)
	local stand = Workspace:WaitForChild(config.StandName, 30)
	if not stand then
		return
	end

	local placard = stand:WaitForChild("RankPlacard", 30)
	if not placard then
		return
	end

	local getMyRankFunction = remotes:WaitForChild(config.RemoteName)

	local labelFront = addSurfaceLabel(placard, Enum.NormalId.Front)
	local labelBack = addSurfaceLabel(placard, Enum.NormalId.Back)

	-- Nu interogam serverul in continuu -- doar cand jucatorul e suficient
	-- de aproape sa citeasca placuta, si nu mai des decat REFRESH_INTERVAL.
	local lastFetch = -math.huge
	local fetching = false

	RunService.Heartbeat:Connect(function()
		if fetching then
			return
		end

		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return
		end

		local distance = (rootPart.Position - placard.Position).Magnitude
		if distance > CHECK_DISTANCE then
			return
		end

		local now = os.clock()
		if now - lastFetch < REFRESH_INTERVAL then
			return
		end

		lastFetch = now
		fetching = true

		task.spawn(function()
			local ok, rank, score = pcall(function()
				return getMyRankFunction:InvokeServer()
			end)

			fetching = false

			if not ok then
				return
			end

			local text
			if rank then
				text = "Your Rank: #" .. tostring(rank) .. " - " .. config.FormatScore(score)
			else
				text = "Your Rank: -"
			end

			labelFront.Text = text
			labelBack.Text = text
		end)
	end)
end

for _, config in ipairs(BOARDS) do
	task.spawn(setupBoard, config)
end
