local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TokenShopKeeper = require(script.Parent:WaitForChild("TokenShopKeeper"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local openTokenShopEvent = remotes:FindFirstChild("OpenTokenShop")
if not openTokenShopEvent then
	openTokenShopEvent = Instance.new("RemoteEvent")
	openTokenShopEvent.Name = "OpenTokenShop"
	openTokenShopEvent.Parent = remotes
end

-- Pozitia standului fizic in lume (coordonate primite de la jucator, ajustate
-- pe Y ca baza standului sa stea pe sol, nu la inaltimea HumanoidRootPart-ului
-- unui personaj in picioare).
local STALL_POSITION = Vector3.new(-36.116424560546875, 5.8, 683.343505859375)

-- Standul e construit "brut" (fara CFrame de rotatie), cu fata deschisa
-- (fara BackWall) spre +Z local. Standul e acum pe partea de Vest a strazii
-- (X negativ), deci il rotim cu fata spre Est (+X), catre strada.
local ROTATION_Y_DEGREES = 90

-- Aceeasi textura "bloxy" folosita pe strada/trotuare/iarba (TownMapBuilder),
-- tentata auriu -- ca standul sa arate mai premium si sa se lege vizual de
-- restul hartii.
local GRID_TEXTURE_ID = "rbxassetid://6372755229"
local GOLD = Color3.fromRGB(212, 175, 55)

local function addGridTexture(part, color, tileStuds)
	local texture = Instance.new("Texture")
	texture.Name = "GridTexture"
	texture.Face = Enum.NormalId.Top
	texture.Texture = GRID_TEXTURE_ID
	texture.Color3 = color
	texture.StudsPerTileU = tileStuds or 2
	texture.StudsPerTileV = tileStuds or 2
	texture.Parent = part
end

-- SurfaceGui, LIPIT direct pe fata piesei -- NU BillboardGui (acelasi fix
-- ca la standurile de Leaderboard/Egg Shop -- BillboardGui parea "taiat"/
-- plutind in functie de unghi, indiferent cat ajustam StudsOffset).
-- Pe toate cele 4 fete laterale, ca sa fie garantat vizibil din orice
-- directie te apropii, fara sa fim nevoiti sa calculam exact orientarea
-- dupa rotatia standului.
local function addSignSurface(part, face, text)
	local existing = part:FindFirstChild("TokenShopSignSurface" .. face.Name)
	if existing then
		existing:Destroy()
	end

	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "TokenShopSignSurface" .. face.Name
	surfaceGui.Face = face
	surfaceGui.Adornee = part
	surfaceGui.AlwaysOnTop = false
	surfaceGui.LightInfluence = 0
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 50
	surfaceGui.Parent = part

	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, 0, 1, 0)
	contentFrame.BackgroundTransparency = 1
	contentFrame.Parent = surfaceGui

	-- UIPadding NU functioneaza pus direct pe un SurfaceGui (nu e GuiObject)
	-- -- trebuie un Frame intermediar.
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.08, 0)
	padding.PaddingBottom = UDim.new(0.08, 0)
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.Parent = contentFrame

	-- Text inchis, gros, pe fundal galben aprins -- alb pe galben e aproape
	-- ilizibil (contrast slab); negru/maro inchis cu contur deschis e
	-- combinatia clasica, foarte lizibila, pentru panouri galbene.
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = text
	signLabel.TextColor3 = Color3.fromRGB(30, 20, 10)
	signLabel.TextStrokeColor3 = Color3.fromRGB(255, 241, 168)
	signLabel.TextStrokeTransparency = 0.4
	signLabel.Font = Enum.Font.FredokaOne
	signLabel.TextScaled = true
	signLabel.TextWrapped = true
	signLabel.Parent = contentFrame

	return signLabel
end

local SIGN_FACES = {Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right}

local stall = Workspace:FindFirstChild("TokenShopStall")

if not stall then
	stall = Instance.new("Model")
	stall.Name = "TokenShopStall"
	stall.Parent = Workspace

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Size = Vector3.new(11, 1, 9)
	base.Anchored = true
	base.Material = Enum.Material.Marble
	base.Color = Color3.fromRGB(28, 26, 32)
	base.Position = STALL_POSITION
	base.Parent = stall
	addGridTexture(base, GOLD, 2)

	-- Bordura aurie, subtire, chiar sub baza -- iese usor in afara, ca un
	-- soclu de piedestal premium.
	local baseTrim = Instance.new("Part")
	baseTrim.Name = "BaseTrim"
	baseTrim.Size = Vector3.new(11.6, 0.3, 9.6)
	baseTrim.Anchored = true
	baseTrim.Material = Enum.Material.Neon
	baseTrim.Color = GOLD
	baseTrim.Position = STALL_POSITION - Vector3.new(0, 0.65, 0)
	baseTrim.Parent = stall

	local backWall = Instance.new("Part")
	backWall.Name = "BackWall"
	backWall.Size = Vector3.new(10, 8, 1)
	backWall.Anchored = true
	backWall.Material = Enum.Material.Marble
	backWall.Color = Color3.fromRGB(22, 20, 26)
	backWall.Position = STALL_POSITION + Vector3.new(0, 4.5, -3.5)
	backWall.Parent = stall

	local wallStroke = Instance.new("SelectionBox")
	wallStroke.Adornee = backWall
	wallStroke.Color3 = GOLD
	wallStroke.LineThickness = 0.08
	wallStroke.Transparency = 0.35
	wallStroke.Parent = backWall

	-- Doua coloane subtiri, aurii, care sustin copertina de deasupra --
	-- accent vizual premium (gen chiosc de lux), nu doar un panou plat.
	for _, sideX in ipairs({-4.5, 4.5}) do
		local pillar = Instance.new("Part")
		pillar.Name = "Pillar"
		pillar.Size = Vector3.new(0.5, 8, 0.5)
		pillar.Anchored = true
		pillar.Material = Enum.Material.Neon
		pillar.Color = GOLD
		pillar.Position = STALL_POSITION + Vector3.new(sideX, 4.5, -3.5)
		pillar.Parent = stall
	end

	-- Copertina de sus, aurie, deasupra firmei -- acopera intreg standul,
	-- accentul principal de "premium".
	local canopy = Instance.new("Part")
	canopy.Name = "Canopy"
	canopy.Size = Vector3.new(11.5, 0.4, 9)
	canopy.Anchored = true
	canopy.Material = Enum.Material.Neon
	canopy.Color = GOLD
	canopy.Position = STALL_POSITION + Vector3.new(0, 8.7, -1)
	canopy.Parent = stall

	local sign = Instance.new("Part")
	sign.Name = "Sign"
	sign.Size = Vector3.new(8, 2.2, 0.3)
	sign.Anchored = true
	sign.Material = Enum.Material.Neon
	sign.Color = Color3.fromRGB(255, 140, 45)
	sign.Position = STALL_POSITION + Vector3.new(0, 7.4, -2.9)
	sign.Parent = stall

	for _, face in ipairs(SIGN_FACES) do
		addSignSurface(sign, face, "TOKEN SHOP")
	end

	local desk = Instance.new("Part")
	desk.Name = "Desk"
	desk.Size = Vector3.new(6, 3, 2)
	desk.Anchored = true
	desk.Material = Enum.Material.Marble
	desk.Color = Color3.fromRGB(28, 26, 32)
	desk.Position = STALL_POSITION + Vector3.new(0, 2, -1)
	desk.Parent = stall
	addGridTexture(desk, GOLD, 1.5)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Token Shop"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = desk

	stall.PrimaryPart = base
end

-- Self-heal: daca standul a fost deja creat intr-o sesiune anterioara
-- (inainte de fix-ul de mai sus), stergem orice BillboardGui vechi (ramas
-- gigantic/plutind/taiat in functie de unghi) si punem SurfaceGui-urile noi,
-- ca sa nu fie nevoie sa stergi manual modelul din Workspace.
local sign = stall:FindFirstChild("Sign")
if sign then
	local oldBillboard = sign:FindFirstChildOfClass("BillboardGui")
	if oldBillboard then
		oldBillboard:Destroy()
	end

	for _, face in ipairs(SIGN_FACES) do
		addSignSurface(sign, face, "TOKEN SHOP")
	end
end

-- Relocam standul intreg (pastrand aranjarea relativa a partilor) la
-- STALL_POSITION de fiecare data -- si daca a fost creat acum, si daca
-- exista deja dintr-o sesiune anterioara (ex: mutat acum la inceputul strazii).
if stall.PrimaryPart then
	stall:PivotTo(CFrame.new(STALL_POSITION) * CFrame.Angles(0, math.rad(ROTATION_Y_DEGREES), 0))
end

-- Abia ACUM, dupa ce standul e la pozitia lui finala, punem NPC-ul --
-- altfel el si-ar calcula pozitia dupa Desk-ul inca nemutat (race condition
-- intre cele doua scripturi ce ruleaza in paralel la pornirea serverului).
TokenShopKeeper.Spawn(stall)

local desk = stall:WaitForChild("Desk")
local prompt = desk:WaitForChild("OpenPrompt")
prompt.ObjectText = "Token Shop"

prompt.Triggered:Connect(function(player)
	openTokenShopEvent:FireClient(player)
end)
