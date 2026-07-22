local Workspace = game:GetService("Workspace")

-- Pozitia data de jucator (X/Z) -- Y recalculat sa stea EXACT pe iarba
-- (TownMapBuilder: Grass e la GROUND_Y - 0.5 = 4.5, inaltime 0.8, deci
-- suprafata ei e la Y=4.9; discul (inaltime 0.4) trebuie centrat la
-- 4.9 + 0.2 = 5.1 ca sa stea lipit pe iarba, nici ingropat, nici plutind).
local STAND_POSITION = Vector3.new(40.2373848, 5.1, 574.862061)

local CYLINDER_DIAMETER = 20
local YELLOW = Color3.fromRGB(255, 210, 40)

local stall = Workspace:FindFirstChild("VIPPerksStand")

if not stall then
	stall = Instance.new("Model")
	stall.Name = "VIPPerksStand"
	stall.Parent = Workspace

	-- Cerc galben, mare, plat pe sol. Part cu Shape=Cylinder: axa cilindrului
	-- e local X -- rotit 90 pe Z, axa X ajunge pe verticala (Y global), deci
	-- fetele rotunde (plate) ajung sus/jos, culcat pe pamant ca un disc, nu
	-- in picioare ca o roata.
	local disc = Instance.new("Part")
	disc.Name = "Disc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.4, CYLINDER_DIAMETER, CYLINDER_DIAMETER)
	disc.Anchored = true
	disc.Material = Enum.Material.Neon
	disc.Color = YELLOW
	disc.CFrame = CFrame.new(STAND_POSITION) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = stall

	-- Text simplu "VIP", plutind deasupra cercului -- fara fundal/cutie,
	-- BillboardGui ca sa ramana mereu cu fata la camera.
	local sign = Instance.new("BillboardGui")
	sign.Name = "SignBillboard"
	sign.Size = UDim2.new(0, 90, 0, 34)
	sign.StudsOffset = Vector3.new(0, 6, 0)
	sign.AlwaysOnTop = false
	sign.MaxDistance = 100
	sign.LightInfluence = 0
	sign.Adornee = disc
	sign.Parent = disc

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "VIP"
	label.TextColor3 = YELLOW
	label.TextStrokeColor3 = Color3.fromRGB(20, 15, 5)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Parent = sign

	stall.PrimaryPart = disc
end

-- Relocam standul (pastrand aranjarea relativa) de fiecare data cand
-- porneste serverul -- acelasi tipar ca la Index/Rebirth/Token/Egg Shop.
if stall.PrimaryPart then
	stall:PivotTo(CFrame.new(STAND_POSITION) * CFrame.Angles(0, 0, math.rad(90)))
end
