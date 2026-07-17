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

-- Prompt-ul "The Bank / Open" era agatat de PrimaryPart-ul modelului (sau
-- prima piesa gasita) -- o piesa mare, arbitrara, din interiorul cladirii.
-- Roblox pozitioneaza automat GUI-ul deasupra piesei de care e agatat, deci
-- pe o piesa mare (perete/acoperis) prompt-ul apare sus de tot, departe de
-- jucator. Fix: o piesa mica, invizibila, pusa chiar la intrare (fata
-- cladirii, spre strada), la inaltime de om -- prompt-ul apare "aproape".
local function findOrCreatePromptAnchor(model)
	local existingAnchor = model:FindFirstChild("BankPromptAnchor")
	if existingAnchor then
		existingAnchor:Destroy()
	end

	-- Pozitie fixa, primita direct de la jucator (coordonatele HumanoidRootPart
	-- din Studio, chiar unde vrea sa apara promptul).
	local ANCHOR_POSITION = Vector3.new(52.744178771972656, 9.916838645935059, 738.1323852539062)

	local anchor = Instance.new("Part")
	anchor.Name = "BankPromptAnchor"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Anchored = true
	anchor.Position = ANCHOR_POSITION
	anchor.Parent = model

	return anchor
end

-- Pozitie fixa pe orizontala (X/Z), primita direct de la jucator (coordonatele
-- HumanoidRootPart din Studio, in noua extindere a hartii). Y-ul NU se ia de
-- la jucator (HumanoidRootPart sta cu ~2-3 studs deasupra solului, si nu are
-- nicio legatura cu unde e pivotul intern al modelului din Toolbox) -- il
-- calculam din bounding box, ca baza modelului sa stea exact pe sol
-- (GROUND_Y), la fel ca in varianta veche (positionNearStand).
local BANK_X = 45.847381591796875
local BANK_Z = 737.329345703125

-- Banca e pe partea de Est a strazii (X pozitiv), la fel ca Egg Shop-ul --
-- aceeasi rotatie (90) o pune cu fata spre Vest (-X), catre strada.
local ROTATION_Y_DEGREES = 90

local function positionAtFixedSpot(model)
	local _, modelSize = model:GetBoundingBox()
	local halfHeight = modelSize.Y / 2

	local newCFrame = CFrame.new(BANK_X, GROUND_Y + halfHeight, BANK_Z) * CFrame.Angles(0, math.rad(ROTATION_Y_DEGREES), 0)

	model:PivotTo(newCFrame)

	print("BankBuilding: banca mutata la (" .. BANK_X .. ", " .. (GROUND_Y + halfHeight) .. ", " .. BANK_Z .. ").")
end

local function setupPrompt(model)
	local anchorPart = findOrCreatePromptAnchor(model)

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
		positionAtFixedSpot(model)
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
