local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local remotes = ReplicatedStorage:WaitForChild("Remotes")

local openIndexEvent = remotes:FindFirstChild("OpenIndex")
if not openIndexEvent then
	openIndexEvent = Instance.new("RemoteEvent")
	openIndexEvent.Name = "OpenIndex"
	openIndexEvent.Parent = remotes
end

-- Pozitie exacta, data de jucator (X/Z) -- Y ramane 5.8, calibrat sa stea pe
-- sol (nu inaltimea HumanoidRootPart-ului primita de la jucator).
local STAND_POSITION = Vector3.new(104.87107849121094, 5.8, 676.2765502929688)

local CYLINDER_HEIGHT = 8
local CYLINDER_DIAMETER = 5

local stall = Workspace:FindFirstChild("IndexStand")

if not stall then
	stall = Instance.new("Model")
	stall.Name = "IndexStand"
	stall.Parent = Workspace

	-- Part cu Shape=Cylinder: axa cilindrului e local X. Rotit 90 pe Z,
	-- axa X ajunge pe verticala (Y global), deci cilindrul sta in picioare,
	-- nu culcat pe o parte.
	local pillar = Instance.new("Part")
	pillar.Name = "Pillar"
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(CYLINDER_HEIGHT, CYLINDER_DIAMETER, CYLINDER_DIAMETER)
	pillar.Anchored = true
	pillar.Material = Enum.Material.Marble
	pillar.Color = Color3.fromRGB(35, 30, 45)
	pillar.CFrame = CFrame.new(STAND_POSITION) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Parent = stall

	-- Disc lucios pe partea de sus a cilindrului, ca o "masa" de unde se
	-- deschide indexul (ProximityPrompt-ul sta pe el).
	local topDisc = Instance.new("Part")
	topDisc.Name = "TopDisc"
	topDisc.Shape = Enum.PartType.Cylinder
	topDisc.Size = Vector3.new(0.6, CYLINDER_DIAMETER + 0.6, CYLINDER_DIAMETER + 0.6)
	topDisc.Anchored = true
	topDisc.Material = Enum.Material.Neon
	topDisc.Color = Color3.fromRGB(170, 120, 255)
	topDisc.CFrame = CFrame.new(STAND_POSITION + Vector3.new(0, CYLINDER_HEIGHT / 2 + 0.3, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	topDisc.Parent = stall

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = "Index"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = topDisc

	-- O carte, asezata pe disc -- coperta + pagini + cotor auriu, ca decor
	-- pentru standul de Index.
	local topDiscTopY = STAND_POSITION.Y + CYLINDER_HEIGHT / 2 + 0.6

	local bookCover = Instance.new("Part")
	bookCover.Name = "BookCover"
	bookCover.Size = Vector3.new(3, 0.4, 2.2)
	bookCover.Anchored = true
	bookCover.Material = Enum.Material.Marble
	bookCover.Color = Color3.fromRGB(90, 30, 140)
	bookCover.Position = STAND_POSITION + Vector3.new(0, topDiscTopY - STAND_POSITION.Y + 0.2, 0)
	bookCover.Parent = stall

	local bookPages = Instance.new("Part")
	bookPages.Name = "BookPages"
	bookPages.Size = Vector3.new(2.6, 0.3, 1.9)
	bookPages.Anchored = true
	bookPages.Material = Enum.Material.Fabric
	bookPages.Color = Color3.fromRGB(245, 235, 210)
	bookPages.Position = bookCover.Position + Vector3.new(0, 0.35, 0)
	bookPages.Parent = stall

	local bookSpine = Instance.new("Part")
	bookSpine.Name = "BookSpine"
	bookSpine.Size = Vector3.new(0.15, 0.42, 2.2)
	bookSpine.Anchored = true
	bookSpine.Material = Enum.Material.Neon
	bookSpine.Color = Color3.fromRGB(212, 175, 55)
	bookSpine.Position = bookCover.Position
	bookSpine.Parent = stall

	-- BillboardGui (nu SurfaceGui) -- ramane mereu cu fata la camera,
	-- indiferent din ce unghi te apropii de cilindru (acelasi fix aplicat
	-- si la firma de Rebirth/Egg Shop).
	local signBillboard = Instance.new("BillboardGui")
	signBillboard.Name = "SignBillboard"
	signBillboard.Size = UDim2.new(0, 78, 0, 24)
	signBillboard.StudsOffset = Vector3.new(0, CYLINDER_HEIGHT / 2 + 2, 0)
	signBillboard.AlwaysOnTop = true
	signBillboard.MaxDistance = 100
	signBillboard.LightInfluence = 0
	signBillboard.Adornee = pillar
	signBillboard.Parent = pillar

	local signBg = Instance.new("Frame")
	signBg.BackgroundColor3 = Color3.fromRGB(20, 16, 28)
	signBg.BackgroundTransparency = 0.15
	signBg.Size = UDim2.new(1, 0, 1, 0)
	signBg.Parent = signBillboard

	Instance.new("UICorner", signBg).CornerRadius = UDim.new(0, 10)

	local signStroke = Instance.new("UIStroke")
	signStroke.Color = Color3.fromRGB(170, 120, 255)
	signStroke.Thickness = 2
	signStroke.Parent = signBg

	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, -8, 1, -8)
	signLabel.Position = UDim2.new(0, 4, 0, 4)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = "INDEX"
	signLabel.TextColor3 = Color3.fromRGB(230, 210, 255)
	signLabel.Font = Enum.Font.FredokaOne
	signLabel.TextScaled = true
	signLabel.Parent = signBg

	stall.PrimaryPart = pillar
end

-- Relocam standul (pastrand aranjarea relativa) de fiecare data cand
-- porneste serverul -- acelasi tipar ca la Rebirth/Token Shop/Egg Shop.
if stall.PrimaryPart then
	stall:PivotTo(CFrame.new(STAND_POSITION) * CFrame.Angles(0, 0, math.rad(90)))
end

local topDisc = stall:WaitForChild("TopDisc")
local prompt = topDisc:WaitForChild("OpenPrompt")

prompt.Triggered:Connect(function(player)
	openIndexEvent:FireClient(player)
end)
