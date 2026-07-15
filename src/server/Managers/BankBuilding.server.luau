local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local openBankEvent = remotes:WaitForChild("OpenBank")

-- NU mai construim noi cladirea din piese -- userul a pus modelul lui, din
-- Toolbox, direct in Workspace (numit "Bank"). Scriptul asta doar il
-- repozitioneaza langa un stand de jucator si ii adauga automat
-- ProximityPrompt-ul ("E" -> The Bank / Open), care deschide GUI-ul de Bank
-- existent.
local BANK_MODEL_NAME = "Bank"
local GROUND_Y = 5

-- Curatare automata: daca structura veche, construita de mine din piese
-- (VaultRing/Canopy/BackWall etc.), a mai ramas in Workspace de la o sesiune
-- anterioara (sub numele vechi "BankBuilding"), o stergem la pornirea
-- serverului.
local oldHandBuilt = Workspace:FindFirstChild("BankBuilding")
if oldHandBuilt and oldHandBuilt:FindFirstChild("VaultRing") then
	oldHandBuilt:Destroy()
	print("BankBuilding: am sters banca veche, construita de mine din piese.")
end

local function findAnchorPart(model)
	if model.PrimaryPart then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

-- Muta modelul langa un stand de jucator (primul gasit -- "oricare", cum a
-- cerut userul) -- pe iarba, la o distanta fixa in AFARA standului (nu peste
-- el), cu baza modelului asezata pe sol (GROUND_Y), fara sa ii schimbam
-- rotatia (pastram orientarea din Toolbox, doar il translatam).
local function positionNearStand(model)
	local standsFolder = Workspace:FindFirstChild("GeneratedStands")
	if not standsFolder then
		warn("BankBuilding: nu am gasit Workspace.GeneratedStands -- nu pot pozitiona banca langa un stand. Ramane unde a fost pus manual.")
		return
	end

	local referenceStand = standsFolder:FindFirstChild("Stand_1") or standsFolder:GetChildren()[1]
	if not referenceStand then
		warn("BankBuilding: GeneratedStands e gol -- nu am dupa ce sa ma ghidez.")
		return
	end

	local standBase = referenceStand:FindFirstChild("Base") or referenceStand.PrimaryPart
	if not standBase then
		warn("BankBuilding: standul de referinta nu are o piesa 'Base' -- nu pot calcula pozitia.")
		return
	end

	local standPosition = standBase.Position
	local sideSign = standPosition.X < 0 and -1 or 1

	-- STAND_OFFSET: cat de departe, pe orizontala (fata de stand), sa apara
	-- banca -- suficient cat sa nu se suprapuna cu standul (care are ~10-12
	-- studs latime) sau cu propriile ei dimensiuni (modelele din Toolbox pot
	-- fi mari, vezi BANK_CLEARANCE mai jos).
	local BANK_CLEARANCE = 30
	local bankX = standPosition.X + sideSign * BANK_CLEARANCE
	local bankZ = standPosition.Z

	local _, modelSize = model:GetBoundingBox()
	local halfHeight = modelSize.Y / 2

	local currentCFrame = model:GetPivot()
	local newCFrame = CFrame.new(bankX, GROUND_Y + halfHeight, bankZ) * (currentCFrame.Rotation)

	model:PivotTo(newCFrame)

	print("BankBuilding: banca mutata langa " .. referenceStand.Name .. ", la (" .. bankX .. ", " .. (GROUND_Y + halfHeight) .. ", " .. bankZ .. ").")
end

local function setupPrompt(model)
	local anchorPart = findAnchorPart(model)

	if not anchorPart then
		warn("BankBuilding: modelul '" .. model.Name .. "' nu are nicio piesa (BasePart) -- nu pot pune ProximityPrompt-ul. Verifica sa nu fie doar un Folder gol sau doar MeshPart-uri fara colisiune.")
		return
	end

	local prompt = anchorPart:FindFirstChild("OpenPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "OpenPrompt"
		prompt.Parent = anchorPart
	end

	prompt.ActionText = "Open"
	prompt.ObjectText = "The Bank"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false

	if not prompt:GetAttribute("Connected") then
		prompt:SetAttribute("Connected", true)

		prompt.Triggered:Connect(function(player)
			openBankEvent:FireClient(player)
		end)
	end

	print("BankBuilding: ProximityPrompt pus pe '" .. anchorPart:GetFullName() .. "'.")
end

local function setupBank(model)
	if not model:GetAttribute("BankPositioned") then
		positionNearStand(model)
		model:SetAttribute("BankPositioned", true)
	end

	setupPrompt(model)
end

local existing = Workspace:FindFirstChild(BANK_MODEL_NAME)

if existing then
	setupBank(existing)
else
	warn("BankBuilding: nu am gasit niciun Model numit '" .. BANK_MODEL_NAME .. "' in Workspace inca. Astept sa apara...")

	Workspace.ChildAdded:Connect(function(child)
		if child.Name == BANK_MODEL_NAME then
			setupBank(child)
		end
	end)
end
