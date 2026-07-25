local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(script.Parent:WaitForChild("DataManager"))
local SFXServer = require(script.Parent:WaitForChild("SFXServer"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local showNotificationEvent = remotes:WaitForChild("ShowNotification")

-- Punct de start luat din Command Bar (pozitia jucatorului cu fata spre
-- iarba, langa oras) -- Y e inaltimea HumanoidRootPart-ului, deci prima
-- platforma sta putin mai jos, la nivelul solului.
local START_POSITION = Vector3.new(-31.808496475219727, 5.4, 766.2428588867188)

-- Directia obby-ului -- initial +X mergea spre un zid (gresit), corectat spre
-- iarba, apoi rotit 180 de grade la cererea explicita a jucatorului -- acum
-- -X.
local DIRECTION = Vector3.new(-1, 0, 0)

local PLATFORM_COUNT = 12
local PLATFORM_SIZE = Vector3.new(6, 1, 6)
local STEP_DISTANCE = 11
local STEP_HEIGHT = 1.8
local ZIGZAG_AMPLITUDE = 3

local REWARD_AMOUNT = 1000
local COOLDOWN_SECONDS = 20 * 60

local PLATFORM_COLOR = Color3.fromRGB(70, 150, 90)
local DOLLAR_COLOR = Color3.fromRGB(255, 215, 60)
local REWARD_COLOR = Color3.fromRGB(255, 220, 0)
local REWARD_DIAMETER = 8

-- Cooldown-ul ramane DOAR in memorie (per sesiune de server), NU se salveaza
-- in DataStore -- recompensa (1000 cash / 20 min) e neglijabila economic, nu
-- merita complexitatea/riscul unui camp nou persistat.
local lastClaimTime = {}
local lastNotifyTime = {}

local function addDollarSign(platform)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "DollarSign"
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.AlwaysOnTop = true
	gui.Parent = platform

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0.95, 0, 0.95, 0)
	label.Position = UDim2.new(0.025, 0, 0.025, 0)
	label.BackgroundTransparency = 1
	label.Text = "$"
	label.TextColor3 = DOLLAR_COLOR
	label.TextStrokeColor3 = Color3.fromRGB(20, 15, 5)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = gui
end

local function buildPlatforms(obbyFolder)
	local position = START_POSITION

	for index = 1, PLATFORM_COUNT do
		position = position + (DIRECTION * STEP_DISTANCE)

		local zigzag = (index % 2 == 0) and ZIGZAG_AMPLITUDE or -ZIGZAG_AMPLITUDE
		local height = STEP_HEIGHT * index

		local platform = Instance.new("Part")
		platform.Name = "Platform" .. index
		platform.Size = PLATFORM_SIZE
		platform.Anchored = true
		platform.Material = Enum.Material.SmoothPlastic
		platform.Color = PLATFORM_COLOR
		platform.CFrame = CFrame.new(position.X, START_POSITION.Y + height, position.Z + zigzag)
		platform.Parent = obbyFolder

		addDollarSign(platform)
	end

	return position, START_POSITION.Y + (STEP_HEIGHT * PLATFORM_COUNT)
end

local function buildRewardPad(obbyFolder, lastPosition, lastHeight)
	local padPosition = lastPosition + (DIRECTION * STEP_DISTANCE)

	local pad = Instance.new("Part")
	pad.Name = "RewardPad"
	pad.Shape = Enum.PartType.Cylinder
	pad.Size = Vector3.new(0.6, REWARD_DIAMETER, REWARD_DIAMETER)
	pad.Anchored = true
	pad.Material = Enum.Material.Neon
	pad.Color = REWARD_COLOR
	pad.CFrame = CFrame.new(padPosition.X, lastHeight, padPosition.Z) * CFrame.Angles(0, 0, math.rad(90))
	pad.Parent = obbyFolder

	local sign = Instance.new("BillboardGui")
	sign.Name = "SignBillboard"
	sign.Size = UDim2.new(0, 200, 0, 50)
	sign.StudsOffset = Vector3.new(0, 6, 0)
	sign.AlwaysOnTop = false
	sign.MaxDistance = 100
	sign.LightInfluence = 0
	sign.Adornee = pad
	sign.Parent = pad

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "+$" .. REWARD_AMOUNT .. "\nevery 20 min"
	label.TextColor3 = REWARD_COLOR
	label.TextStrokeColor3 = Color3.fromRGB(20, 15, 5)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = sign

	return pad
end

local function onRewardTouched(hit)
	local character = hit.Parent
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local now = os.time()
	local last = lastClaimTime[player]

	if last and (now - last) < COOLDOWN_SECONDS then
		-- Evitam spam de notificari cat timp jucatorul sta pe disc (Touched
		-- se declanseaza de mai multe ori pe secunda) -- un mesaj o data la 5s
		-- e suficient.
		local lastNotify = lastNotifyTime[player]
		if not lastNotify or (now - lastNotify) >= 5 then
			lastNotifyTime[player] = now
			local remainingMinutes = math.ceil((COOLDOWN_SECONDS - (now - last)) / 60)
			showNotificationEvent:FireClient(player, "⏳ Obby reward again in ~" .. remainingMinutes .. " min")
		end
		return
	end

	-- BUG rezolvat anterior: verificam ca leaderstats/Money exista INAINTE sa
	-- consumam cooldown-ul -- altfel un jucator care calca pe disc inainte sa
	-- i se incarce datele pierdea cele 20 de minute degeaba, fara recompensa.
	local leaderstats = player:FindFirstChild("leaderstats")
	local money = leaderstats and leaderstats:FindFirstChild("Money")
	if not money then
		return
	end

	money.Value += REWARD_AMOUNT

	-- Setat INAINTE de DataManager.SaveData (care face un yield spre
	-- DataStore) -- altfel o a doua atingere in aceeasi fereastra ar trece
	-- de verificarea de mai sus si ar da recompensa de doua ori.
	lastClaimTime[player] = now

	showNotificationEvent:FireClient(player, "🏁 Obby completed! +$" .. REWARD_AMOUNT .. " (again in 20 min)")
	SFXServer.Play(player, "CodeRedeemed")

	DataManager.SaveData(player)
end

local obbyFolder = Workspace:FindFirstChild("Obby")

if not obbyFolder then
	obbyFolder = Instance.new("Folder")
	obbyFolder.Name = "Obby"
	obbyFolder.Parent = Workspace

	local lastPosition, lastHeight = buildPlatforms(obbyFolder)
	local pad = buildRewardPad(obbyFolder, lastPosition, lastHeight)

	pad.Touched:Connect(onRewardTouched)
end

Players.PlayerRemoving:Connect(function(player)
	lastClaimTime[player] = nil
	lastNotifyTime[player] = nil
end)
