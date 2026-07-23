local Workspace = game:GetService("Workspace")

-- CFrame exact, luat din Command Bar (pozitie + rotatie), unde jucatorul
-- statea cu fata cand a cerut plasarea Chest-ului. Y e inaltimea
-- HumanoidRootPart-ului jucatorului, nu neaparat unde ar trebui sa stea baza
-- modelului Chest -- ridicat cu CHEST_Y_OFFSET, ca sa nu mai fie ingropat.
local CHEST_Y_OFFSET = 2

local CHEST_CFRAME = CFrame.new(
	-43.3782654, 7.59999895 + CHEST_Y_OFFSET, 579.857483,
	0.839429855, 5.75653658e-08, -0.543467999,
	-5.55616602e-08, 1, 2.01028367e-08,
	0.543467999, 1.33210625e-08, 0.839429855
)

-- Pozitia cercului (X/Z din Chest-ul de mai sus) -- Y recalculat sa stea
-- EXACT pe iarba (acelasi calcul ca la VIPPerksStand: TownMapBuilder are
-- Grass la GROUND_Y - 0.5 = 4.5, inaltime 0.8, deci suprafata ei e la
-- Y=4.9; discul, inalt 0.4, trebuie centrat la 4.9 + 0.2 = 5.1).
local CIRCLE_POSITION = Vector3.new(CHEST_CFRAME.Position.X, 5.1, CHEST_CFRAME.Position.Z)

local CYLINDER_DIAMETER = 20
local GOLD = Color3.fromRGB(255, 210, 40)

-- Chest-ul e un Part adaugat manual de jucator in Explorer (nu vine din
-- Rojo) -- doar il repozitionam, nu-l cream.
local chest = Workspace:FindFirstChild("Chest")
if chest then
	chest.CFrame = CHEST_CFRAME
end

local stall = Workspace:FindFirstChild("ChestRewardsStand")

if not stall then
	stall = Instance.new("Model")
	stall.Name = "ChestRewardsStand"
	stall.Parent = Workspace

	-- Cerc auriu, mare, plat pe sol -- acelasi tipar ca la VIPPerksStand.
	local disc = Instance.new("Part")
	disc.Name = "Disc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.4, CYLINDER_DIAMETER, CYLINDER_DIAMETER)
	disc.Anchored = true
	disc.Material = Enum.Material.Neon
	disc.Color = GOLD
	disc.CFrame = CFrame.new(CIRCLE_POSITION) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = stall

	-- Text "GROUP REWARDS", plutind deasupra cercului -- fara fundal/cutie,
	-- BillboardGui ca sa ramana mereu cu fata la camera.
	local sign = Instance.new("BillboardGui")
	sign.Name = "SignBillboard"
	sign.Size = UDim2.new(0, 170, 0, 36)
	sign.StudsOffset = Vector3.new(0, 14, 0)
	sign.AlwaysOnTop = false
	sign.MaxDistance = 100
	sign.LightInfluence = 0
	sign.Adornee = disc
	sign.Parent = disc

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "GROUP REWARDS"
	label.TextColor3 = GOLD
	label.TextStrokeColor3 = Color3.fromRGB(20, 15, 5)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = sign

	stall.PrimaryPart = disc
end

-- Relocam standul (pastrand aranjarea relativa) de fiecare data cand
-- porneste serverul -- acelasi tipar ca la VIPPerksStand/Index/Rebirth.
if stall.PrimaryPart then
	stall:PivotTo(CFrame.new(CIRCLE_POSITION) * CFrame.Angles(0, 0, math.rad(90)))
end
