local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FONT_DISPLAY = Enum.Font.LuckiestGuy
local FONT_BODY = Enum.Font.FredokaOne

local BG_DARK = Color3.fromRGB(18, 16, 22)
local BG_MID = Color3.fromRGB(40, 32, 52)
local GOLD = Color3.fromRGB(255, 215, 90)
local TEXT_DIM = Color3.fromRGB(180, 175, 190)
local OUTLINE_DARK = Color3.fromRGB(10, 8, 12)

-- Chiar daca totul e gata instant (server "cald", jucator cu conexiune buna),
-- ecranul ramane vizibil macar atat -- altfel ar clipi doar o fractiune de
-- secunda, ceea ce arata neingrijit ("ca la jocurile mari" inseamna si un
-- loading screen care se simte intentionat, nu un artefact vizual).
local MIN_DISPLAY_TIME = 5.5

-- Viteza MAXIMA cu care bara se umple vizual (fractiune/secunda) -- verificarile
-- reale (Character/DataApplied/GUI) se rezolva de multe ori aproape instant,
-- ceea ce facea bara sa SARA direct la fiecare prag (0.05 -> 0.35 -> 0.7 -> 1),
-- nu sa se umple organic. Acum bara se apropie CONTINUU de pragul curent, cu
-- viteza plafonata -- chiar daca verificarile reale termina instant, umplerea
-- vizuala tot dureaza natural. 0.18/s -> ~5.5s sa umple 0->100%, in linie cu
-- MIN_DISPLAY_TIME, ca ecranul sa dureze constant 5-6 secunde.
local FILL_SPEED_PER_SECOND = 0.18

-- ================= ScreenGui =================
-- DisplayOrder foarte mare -- randat DEASUPRA absolut a tot restul UI-ului
-- (StoreGui foloseste 100, cel mai mare din restul jocului) -- si
-- IgnoreGuiInset, ca sa acopere tot ecranul, inclusiv bara de sus pe mobil.

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingScreenGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 1000
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.new(1, 0, 1, 0)
background.BackgroundColor3 = BG_DARK
background.BorderSizePixel = 0
background.Active = true
background.ZIndex = 1
background.Parent = screenGui

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, BG_MID),
	ColorSequenceKeypoint.new(1, BG_DARK)
})
gradient.Rotation = 90
gradient.Parent = background

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
titleLabel.Position = UDim2.new(0.5, 0, 0.42, 0)
titleLabel.Size = UDim2.new(0.92, 0, 0.16, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.RichText = true
-- RGB-urile de mai jos trebuie sa ramana literali (nu round-trip prin
-- Color3.R*255) -- Color3 stocheaza 0-1, iar inmultirea inapoi la 255 poate
-- da valori ne-intregi (219.999...) din imprecizie float, ceea ce ar strica
-- tag-ul RichText.
titleLabel.Text = '<font color="rgb(220,70,80)">BUY LOW</font> <font color="rgb(90,230,130)">SELL HIGH</font>'
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextStrokeColor3 = OUTLINE_DARK
titleLabel.TextStrokeTransparency = 0
titleLabel.Font = FONT_DISPLAY
titleLabel.TextScaled = true
titleLabel.ZIndex = 2
titleLabel.Parent = background

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "SubtitleLabel"
subtitleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
subtitleLabel.Position = UDim2.new(0.5, 0, 0.55, 0)
subtitleLabel.Size = UDim2.new(0.7, 0, 0.05, 0)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text = "Loading..."
subtitleLabel.TextColor3 = TEXT_DIM
subtitleLabel.Font = FONT_BODY
subtitleLabel.TextScaled = true
subtitleLabel.ZIndex = 2
subtitleLabel.Parent = background

local barTrack = Instance.new("Frame")
barTrack.AnchorPoint = Vector2.new(0.5, 0.5)
barTrack.Position = UDim2.new(0.5, 0, 0.63, 0)
barTrack.Size = UDim2.new(0.5, 0, 0, 22)
barTrack.BackgroundColor3 = Color3.fromRGB(50, 44, 62)
barTrack.BorderSizePixel = 0
barTrack.ZIndex = 2
barTrack.Parent = background

Instance.new("UICorner", barTrack).CornerRadius = UDim.new(0.5, 0)

local barFill = Instance.new("Frame")
barFill.BackgroundColor3 = GOLD
barFill.Size = UDim2.new(0, 0, 1, 0)
barFill.BorderSizePixel = 0
barFill.ZIndex = 3
barFill.Parent = barTrack

Instance.new("UICorner", barFill).CornerRadius = UDim.new(0.5, 0)

-- targetProgress = pragul PANA la care are voie sa ajunga bara acum (creste
-- pe masura ce pasii reali se termina). displayedProgress = ce se vede
-- efectiv, mereu urmarind targetProgress cu viteza plafonata la
-- FILL_SPEED_PER_SECOND -- niciodata un salt brusc, doar o miscare continua.
local targetProgress = 0
local displayedProgress = 0
local running = true

local function setTarget(fraction, text)
	targetProgress = math.clamp(fraction, targetProgress, 1)
	if text then
		subtitleLabel.Text = text
	end
end

local fillConnection
fillConnection = RunService.Heartbeat:Connect(function(dt)
	if not running then
		fillConnection:Disconnect()
		return
	end

	if displayedProgress < targetProgress then
		displayedProgress = math.min(displayedProgress + FILL_SPEED_PER_SECOND * dt, targetProgress)
		barFill.Size = UDim2.new(displayedProgress, 0, 1, 0)
	end
end)

-- Verificare cu plafon -- fara asta, un caz neasteptat (ex: MainHUD/ItemsGui
-- nu apar niciodata, dintr-un motiv necunoscut) ar bloca jucatorul pe
-- ecranul de loading la NESFARSIT. Se continua oricum dupa maxSeconds, chiar
-- daca acel pas nu s-a incheiat cu adevarat.
local function waitUntil(checkFn, maxSeconds)
	local elapsed = 0

	while not checkFn() and elapsed < maxSeconds do
		task.wait(0.1)
		elapsed += 0.1
	end
end

task.spawn(function()
	local startTime = os.clock()

	setTarget(0.25, "Loading character...")
	waitUntil(function()
		return player.Character ~= nil
	end, 10)

	setTarget(0.55, "Loading your data...")
	waitUntil(function()
		return player:GetAttribute("DataApplied") == true
	end, 15)

	setTarget(0.85, "Preparing the market...")
	waitUntil(function()
		return playerGui:FindFirstChild("MainHUD") ~= nil and playerGui:FindFirstChild("ItemsGui") ~= nil
	end, 15)

	setTarget(1, "Ready!")

	-- Asteapta sa treaca MIN_DISPLAY_TIME SI ca bara sa se fi umplut chiar
	-- vizual (nu doar ca verificarile reale sa se fi terminat) -- altfel, pe
	-- o conexiune foarte rapida, am putea incepe fade-out-ul inainte ca bara
	-- sa ajunga la capat.
	while displayedProgress < 0.995 or (os.clock() - startTime) < MIN_DISPLAY_TIME do
		task.wait(0.05)
	end

	running = false

	local fadeInfo = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	TweenService:Create(background, fadeInfo, {BackgroundTransparency = 1}):Play()
	TweenService:Create(titleLabel, fadeInfo, {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
	TweenService:Create(subtitleLabel, fadeInfo, {TextTransparency = 1}):Play()
	TweenService:Create(barTrack, fadeInfo, {BackgroundTransparency = 1}):Play()
	local fillFade = TweenService:Create(barFill, fadeInfo, {BackgroundTransparency = 1})
	fillFade:Play()

	fillFade.Completed:Wait()
	background.Active = false
	screenGui:Destroy()
end)
