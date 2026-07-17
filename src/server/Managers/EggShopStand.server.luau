local Workspace = game:GetService("Workspace")

local EggShopKeeper = require(script.Parent:WaitForChild("EggShopKeeper"))

-- PetShop e un model asezat manual in Studio (nu e construit procedural aici,
-- spre deosebire de TokenShopStall) -- doar il relocam si ii adaugam firma,
-- la fel cum am facut cu standul de Rebirth Token Shop.
local NEW_POSITION = Vector3.new(36.57196807861328, 5.8, 649.1923828125)

-- Rotatia standului pe Y (grade). Spune-mi daca nu e unghiul potrivit si
-- ajustez (0/90/180/270 sau orice alta valoare). Standul e acum pe partea de
-- Est a strazii (X pozitiv), deci il rotim cu fata spre Vest (-X), catre
-- centrul strazii/trotuar.
local ROTATION_Y_DEGREES = 90

-- Aceeasi marime calibrata ca la firma de Rebirth Shop -- 260x70 iesise
-- gigantic de aproape; 90x24 se potriveste pentru un panou obisnuit.
local SIGN_TEXT_SIZE = UDim2.new(0, 90, 0, 24)

local petShop = Workspace:WaitForChild("PetShop")
local trigger = petShop:WaitForChild("EggShopTrigger")

-- Panoul negru de sub acoperis, gasit de jucator prin Selection in Studio
-- (numele lui real -- nu era ghicibil din script, PetShop nefiind sincronizat
-- prin Rojo).
local signBoard = petShop:FindFirstChild("Sign", true)

-- Relocam intreg modelul (pastrand aranjarea relativa a partilor) de fiecare
-- data cand porneste serverul, la fel ca la standul de Rebirth Token Shop.
-- BillboardGui-ul de mai jos e mereu cu fata la camera, deci rotatia asta
-- afecteaza doar structura fizica (nu are cum sa "roteasca" textul in sine).
petShop:PivotTo(CFrame.new(NEW_POSITION) * CFrame.Angles(0, math.rad(ROTATION_Y_DEGREES), 0))

-- Firma cu "EGG SHOP", montata direct pe panoul negru (nu pe trigger, care
-- doar plutea deasupra lui). BillboardGui, nu SurfaceGui, ca sa ramana mereu
-- drept si lizibil indiferent de unghi (acelasi fix ca la Rebirth Token Shop).
local billboardParent = signBoard or trigger

local existingBillboard = billboardParent:FindFirstChild("EggShopSignBillboard")
if existingBillboard then
	existingBillboard:Destroy()
end

local signBillboard = Instance.new("BillboardGui")
signBillboard.Name = "EggShopSignBillboard"
signBillboard.Size = SIGN_TEXT_SIZE
signBillboard.StudsOffset = Vector3.new(0, 0, 0)
signBillboard.AlwaysOnTop = true
signBillboard.MaxDistance = 100
signBillboard.LightInfluence = 0
signBillboard.Adornee = billboardParent
signBillboard.Parent = billboardParent

-- Panoul e negru, nu galben ca la Rebirth Shop -- text deschis (alb/auriu)
-- cu contur inchis, nu invers, altfel textul devine invizibil pe fundal negru.
local signLabel = Instance.new("TextLabel")
signLabel.Size = UDim2.new(1, 0, 1, 0)
signLabel.BackgroundTransparency = 1
signLabel.Text = "EGG SHOP"
signLabel.TextColor3 = Color3.fromRGB(255, 236, 179)
signLabel.TextStrokeColor3 = Color3.fromRGB(20, 14, 8)
signLabel.TextStrokeTransparency = 0.2
signLabel.Font = Enum.Font.FredokaOne
signLabel.TextScaled = true
signLabel.Parent = signBillboard

-- NPC langa stand, fara text deasupra (doar cel de la Token Shop are badge).
-- Pozitie fixa, primita direct de la jucator (coordonatele HumanoidRootPart
-- din Studio).
local KEEPER_POSITION = Vector3.new(34.76914978027344, 9.114848136901855, 649.40869140625)
EggShopKeeper.Spawn(petShop, KEEPER_POSITION)

-- Aceeasi textura "bloxy" de pe strada/iarba (TownMapBuilder), tentata verde
-- -- aplicata pe podeaua standului. PetShop nu e sincronizat prin Rojo, deci
-- nu stim numele exact al partii de podea -- o gasim automat: partea cu cea
-- mai mare suprafata orizontala (Size.X * Size.Z) e aproape sigur podeaua,
-- nu un perete/acoperis.
local GRID_TEXTURE_ID = "rbxassetid://6372755229"

local function findFloorPart(model)
	local bestPart, bestArea = nil, 0

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local area = descendant.Size.X * descendant.Size.Z
			if area > bestArea then
				bestArea = area
				bestPart = descendant
			end
		end
	end

	return bestPart
end

local floorPart = findFloorPart(petShop)

if floorPart then
	local existingTexture = floorPart:FindFirstChild("GridTexture")
	if existingTexture then
		existingTexture:Destroy()
	end

	local floorTexture = Instance.new("Texture")
	floorTexture.Name = "GridTexture"
	floorTexture.Face = Enum.NormalId.Top
	floorTexture.Texture = GRID_TEXTURE_ID
	floorTexture.Color3 = Color3.fromRGB(30, 200, 40)
	floorTexture.StudsPerTileU = 2
	floorTexture.StudsPerTileV = 2
	floorTexture.Parent = floorPart
end
