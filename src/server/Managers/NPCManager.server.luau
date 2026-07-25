local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")

local NPCDatabase = require(modulesFolder:WaitForChild("NPCDatabase"))
local TradeManager = require(script.Parent:WaitForChild("TradeManager"))
local InventoryManager = require(script.Parent:WaitForChild("InventoryManager"))
local SellManager = require(script.Parent:WaitForChild("SellManager"))
local DataManager = require(script.Parent:WaitForChild("DataManager"))
local MarketManager = require(modulesFolder:WaitForChild("MarketManager"))
local StandDisplayManager = require(script.Parent:WaitForChild("StandDisplayManager"))
local CosmeticManager = require(script.Parent:WaitForChild("CosmeticManager"))
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))
local SFXServer = require(script.Parent:WaitForChild("SFXServer"))

local showTradeEvent = remotesFolder:WaitForChild("ShowTrade")
local hideTradeEvent = remotesFolder:WaitForChild("HideTrade")
local buyItemEvent = remotesFolder:WaitForChild("BuyItem")
local skipTradeEvent = remotesFolder:WaitForChild("SkipTrade")
local sellFirstItemEvent = remotesFolder:WaitForChild("SellFirstItem")
local sellSelectedItemEvent = remotesFolder:WaitForChild("SellSelectedItem")
local requestInventoryEvent = remotesFolder:WaitForChild("RequestInventory")
local showInventoryEvent = remotesFolder:WaitForChild("ShowInventory")
local showNotificationEvent = remotesFolder:WaitForChild("ShowNotification")
local marketUpdateEvent = remotesFolder:WaitForChild("MarketUpdate")
local openPetCrateEvent = remotesFolder:WaitForChild("OpenPetCrate")
local petOpenedEvent = remotesFolder:WaitForChild("PetOpened")

local INVENTORY_PASS_ID = 1899734044
local DEFAULT_MAX_INVENTORY = 50
local PASS_MAX_INVENTORY = 150

local npcFolder = ServerStorage:WaitForChild("NPCs")
local fallbackNpcTemplate = npcFolder:WaitForChild("TestNPC")

-- Fiecare tip de NPC (vezi NPCDatabase.Types) poate avea propriul model,
-- pus manual in ServerStorage.NPCs, numit EXACT ca cheia din NPCDatabase
-- (ex: "StreetDealer", "Sneakerhead", "TechDealer", "LuxuryCollector",
-- "BlackMarketDealer") -- inainte, toate cele 5 tipuri foloseau acelasi
-- model placeholder ("TestNPC"), indiferent de persona lor. Daca un tip nu
-- are inca propriul model, cade pe placeholder, ca restul sa functioneze
-- normal cat timp adaugi modelele treptat.
--
-- Exceptii de nume -- modelul e pus in ServerStorage.NPCs sub numele lui
-- original (din Toolbox), nu redenumit dupa cheia din NPCDatabase.
local TEMPLATE_NAME_OVERRIDES = {
	LuxuryCollector = "Bobux Man",
	StreetDealer = "Traffic cone guy",
	Sneakerhead = "Monkey Spawn Kit",
	TechDealer = "Mr. Robot",
	BlackMarketDealer = "Gemeral"
}

-- Culoare de haine (Torso/Membre) per tip de NPC -- pielea ramane aceeasi
-- (un ton neutru), doar "hainele" difera, ca sa se distinga vizual unul de
-- altul chiar si fara model 3D custom.
local NPC_CLOTHING_COLORS = {
	StreetDealer = Color3.fromRGB(60, 60, 65),
	Sneakerhead = Color3.fromRGB(230, 120, 30),
	TechDealer = Color3.fromRGB(35, 65, 90),
	LuxuryCollector = Color3.fromRGB(40, 35, 20),
	BlackMarketDealer = Color3.fromRGB(70, 20, 20)
}
local SKIN_COLOR = Color3.fromRGB(205, 165, 125)
local DEFAULT_CLOTHING_COLOR = Color3.fromRGB(90, 90, 100)

-- Rig clasic R6, construit direct din Parts -- niciun asset extern, deci
-- functioneaza mereu, indiferent ce se intampla cu modelele custom din
-- Toolbox. Foloseste ca "corp" ori de cate ori un model custom nu are
-- Humanoid/HumanoidRootPart complet.
local function createBlockyCharacter(npcType)
	local clothingColor = NPC_CLOTHING_COLORS[npcType] or DEFAULT_CLOTHING_COLOR

	local model = Instance.new("Model")

	local function makePart(name, size, color, material)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		-- NPC-ul se misca doar prin Humanoid:MoveTo (nu fizica reala) --
		-- CanCollide/Massless oprite, ca sa nu coste deloc motorul de fizica
		-- (coliziuni cu solul/alte NPC-uri/jucatori, calcule de masa etc.)
		part.CanCollide = false
		part.Massless = true
		part.Parent = model
		return part
	end

	local rootPart = makePart("HumanoidRootPart", Vector3.new(2, 2, 1), clothingColor)
	rootPart.Transparency = 1

	local torso = makePart("Torso", Vector3.new(2, 2, 1), clothingColor)
	local head = makePart("Head", Vector3.new(2, 1, 1), SKIN_COLOR)
	Instance.new("SpecialMesh", head).MeshType = Enum.MeshType.Head

	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head

	local leftArm = makePart("Left Arm", Vector3.new(1, 2, 1), SKIN_COLOR)
	local rightArm = makePart("Right Arm", Vector3.new(1, 2, 1), SKIN_COLOR)
	local leftLeg = makePart("Left Leg", Vector3.new(1, 2, 1), clothingColor)
	local rightLeg = makePart("Right Leg", Vector3.new(1, 2, 1), clothingColor)

	rootPart.CFrame = CFrame.new(0, 0, 0)
	torso.CFrame = CFrame.new(0, 0, 0)
	head.CFrame = CFrame.new(0, 1.5, 0)
	leftArm.CFrame = CFrame.new(-1.5, 0, 0)
	rightArm.CFrame = CFrame.new(1.5, 0, 0)
	leftLeg.CFrame = CFrame.new(-0.5, -2, 0)
	rightLeg.CFrame = CFrame.new(0.5, -2, 0)

	local function weld(name, part0, part1, c0, c1)
		local motor = Instance.new("Motor6D")
		motor.Name = name
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C0 = c0
		motor.C1 = c1
		motor.Parent = part0
		return motor
	end

	weld("RootJoint", rootPart, torso, CFrame.new(0, 0, 0), CFrame.new(0, 0, 0))
	weld("Neck", torso, head, CFrame.new(0, 1, 0), CFrame.new(0, -0.5, 0))
	weld("Left Shoulder", torso, leftArm, CFrame.new(-1, 0.5, 0), CFrame.new(0.5, 0.5, 0))
	weld("Right Shoulder", torso, rightArm, CFrame.new(1, 0.5, 0), CFrame.new(-0.5, 0.5, 0))
	weld("Left Hip", torso, leftLeg, CFrame.new(-0.5, -1, 0), CFrame.new(0, 1, 0))
	weld("Right Hip", torso, rightLeg, CFrame.new(0.5, -1, 0), CFrame.new(0, 1, 0))

	-- Sneakerhead -- adidasi supradimensionati, sudati direct pe picioare
	-- (WeldConstraint, se misca odata cu ele), tematic pentru personaj.
	if npcType == "Sneakerhead" then
		local SHOE_COLOR = Color3.fromRGB(250, 250, 250)
		local SOLE_COLOR = Color3.fromRGB(230, 60, 40)

		local function makeShoe(legPart)
			local shoe = makePart("Shoe", Vector3.new(1.7, 0.9, 2.1), SHOE_COLOR)
			shoe.CFrame = legPart.CFrame * CFrame.new(0, -1.1, -0.35)

			local sole = makePart("Sole", Vector3.new(1.7, 0.3, 2.1), SOLE_COLOR)
			sole.CFrame = shoe.CFrame * CFrame.new(0, -0.55, 0)

			local shoeWeld = Instance.new("WeldConstraint")
			shoeWeld.Part0 = legPart
			shoeWeld.Part1 = shoe
			shoeWeld.Parent = legPart

			local soleWeld = Instance.new("WeldConstraint")
			soleWeld.Part0 = shoe
			soleWeld.Part1 = sole
			soleWeld.Parent = shoe
		end

		makeShoe(leftLeg)
		makeShoe(rightLeg)
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.Parent = model

	model.PrimaryPart = rootPart

	return model
end

local function getNpcTemplate(npcType)
	local overrideName = TEMPLATE_NAME_OVERRIDES[npcType]
	if overrideName then
		local overrideModel = npcFolder:FindFirstChild(overrideName)
		if overrideModel then
			return overrideModel
		end
	end

	return npcFolder:FindFirstChild(npcType) or fallbackNpcTemplate
end

local activeTrades = {}

-- Forward-declarate -- handleBuy/handleSkip sunt definite mai jos in fisier,
-- dar spawnNPCForPlayer (definit MAI SUS) trebuie sa le poata apela direct
-- (Auto Buy Pass, acceptare/respingere automata) dintr-un task.delay a carui
-- inchidere (closure) ruleaza mult dupa ce ambele au fost deja asignate --
-- fara declararea asta, numele ar rezolva la globale inexistente (nil) in
-- acel punct din fisier, nu la variabilele locale de mai jos.
local handleBuy
local handleSkip

-- NPC-urile pornesc din portalul cel mai APROAPE de standul jucatorului (Nord
-- sau Sud), nu mereu din acelasi -- altfel jucatorii cu stand langa Sud ar
-- astepta mult mai mult decat cei langa Nord, nedrept intre cei 6 jucatori.
-- Cautate o singura data la pornire, cu WaitForChild (NU FindFirstChild) --
-- TownMapBuilder.server.luau construieste harta ASINCRON, in cateva secunde,
-- iar ordinea de rulare intre scripturi de server NU e garantata. Cu
-- FindFirstChild (verificare instant), NPCManager verifica aproape mereu
-- INAINTE ca harta sa fie gata, cazand pe fallback la FIECARE pornire de
-- server, nu doar la o harta veche/lipsa cum anticipa comentariul original.
-- Cu WaitForChild + plafon, asteptam efectiv constructia hartii; fallback-ul
-- ramane doar pentru cazul cu adevarat exceptional (nimic dupa 30s).
local function findPortalPosition(name, fallback)
	local townMap = workspace:WaitForChild("TownMap", 30)
	local portalPanel = townMap and townMap:WaitForChild(name, 10)

	if portalPanel then
		return portalPanel.Position
	end

	warn("NPCManager: Workspace.TownMap." .. name .. " nu a fost gasit dupa asteptare -- folosesc o pozitie aproximativa.")
	return fallback
end

-- Cerut explicit: TOATE NPC-urile pornesc din tunelul de Sud (cel cu
-- panoul negru "NEXT MARKET SPECIAL EVENT"), indiferent de standul
-- jucatorului -- nu mai alegem cel mai apropiat dintre Nord/Sud. Conceptul
-- vizual al tunelului (panou + countdown) ramane neschimbat -- NPC-urile
-- oricum nu au coliziune reala (CanCollide=false), deci nu au nevoie de un
-- gol fizic in zid ca sa "iasa" vizual de acolo.
local portalSouthPosition = findPortalPosition("PortalSouth", Vector3.new(0, 5, 200))

local function getClosestPortalPosition(_targetPosition)
	return portalSouthPosition
end

local function getStandLevel(player)
	local standLevel = player:FindFirstChild("StandLevel")

	if standLevel then
		return standLevel.Value
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local levelValue = leaderstats:FindFirstChild("StandLevel")
		if levelValue then
			return levelValue.Value
		end
	end

	return 1
end

local function getStandBonuses(player)
	local level = getStandLevel(player)
	return Economy.StandBonuses[level] or Economy.StandBonuses[1]
end

local function getRebirthBonuses(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local rebirths = leaderstats and leaderstats:FindFirstChild("Rebirths")

	if not rebirths then
		return {Sell = 0, Luck = 0, Speed = 0}
	end

	return Economy.Rebirth.GetCumulativeBonuses(rebirths.Value)
end

local function getSpawnDelay(player)
	local bonuses = getStandBonuses(player)
	local cosmeticBonuses = CosmeticManager.GetBonuses(player)
	local petBonuses = PetManager.GetBonuses(player)
	local rebirthBonuses = getRebirthBonuses(player)

	local speedPassBonus = player:GetAttribute("HasSpeedPass") and Economy.SpeedPass.Speed or 0

	local totalSpeed = bonuses.Speed + (cosmeticBonuses.NpcSpeed or 0) + (petBonuses.NpcSpeed or 0) + rebirthBonuses.Speed + speedPassBonus
	totalSpeed = math.clamp(totalSpeed, 0, Economy.Caps.Speed)

	local reduction = 1 - (totalSpeed / 100)

	local minDelay = Economy.NPCSpawnInterval.Min * reduction
	local maxDelay = Economy.NPCSpawnInterval.Max * reduction

	return minDelay + math.random() * (maxDelay - minDelay)
end

local function sendInventory(player)
	local inventory = player:FindFirstChild("Inventory")
	local items = {}

	if inventory then
		for _, item in ipairs(inventory:GetChildren()) do
			table.insert(items, {
				Id = item.Name,
				ItemName = item:FindFirstChild("ItemName") and item.ItemName.Value or item.Name,
				Rarity = item:FindFirstChild("Rarity") and item.Rarity.Value or "Common",
				Category = item:FindFirstChild("Category") and item.Category.Value or "Unknown",
				BuyPrice = item:FindFirstChild("BuyPrice") and item.BuyPrice.Value or 0,
				Image = item:FindFirstChild("Image") and item.Image.Value or ""
			})
		end
	end

	showInventoryEvent:FireClient(player, items)
end

local function getMaxInventory(player)
	local maxInventory = DEFAULT_MAX_INVENTORY

	local success, ownsPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, INVENTORY_PASS_ID)
	end)

	-- GiftedInventoryPass (persistat de DataManager) -- Inventory Pass nu are
	-- un attribute dedicat, propriu, ca VIP/Speed/AutoSell (e verificat live,
	-- direct aici), deci gift-ul are nevoie de propriul lui flag, verificat
	-- alaturi de proprietatea reala.
	if (success and ownsPass) or player:GetAttribute("GiftedInventoryPass") == true then
		maxInventory = PASS_MAX_INVENTORY
	end

	-- VIP promite +25 sloturi (Economy.VIP.ExtraInventorySlots) -- se aduna
	-- aditiv peste orice ai deja (default sau Inventory Pass), nu il inlocuieste.
	if player:GetAttribute("IsVIP") then
		maxInventory += Economy.VIP.ExtraInventorySlots
	end

	return maxInventory
end

local function getRandomNPCType()
	local totalWeight = 0
	local pool = {}

	for npcType, npcData in pairs(NPCDatabase.Types) do
		local weight = npcData.SpawnChance or 0

		if weight > 0 then
			totalWeight += weight

			table.insert(pool, {
				Type = npcType,
				Weight = weight
			})
		end
	end

	if totalWeight <= 0 then
		warn("No NPC spawn weights found")
		return nil
	end

	local roll = math.random() * totalWeight
	local current = 0

	for _, npc in ipairs(pool) do
		current += npc.Weight

		if roll <= current then
			return npc.Type
		end
	end

	return pool[1].Type
end

local function getPlayerStand(player)
	local standsFolder = workspace:WaitForChild("GeneratedStands")

	for _, stand in ipairs(standsFolder:GetChildren()) do
		if stand:GetAttribute("OwnerUserId") == player.UserId then
			return stand
		end
	end

	return nil
end

-- NPCSpot sta chiar PE platforma standului -- NPC-ul ajungea sa mearga pe
-- stand, nu in fata lui. Mutam tinta spre strada (spre X=0) cu un offset
-- fix, ca sa se opreasca inainte de platforma, cu fata la jucator.
local FRONT_OF_STAND_OFFSET = 14

local function getNPCSpotPosition(stand)
	local base = stand:FindFirstChild("Base")
	if not base then
		return nil
	end

	local npcSpot = base:FindFirstChild("NPCSpot")
	if not npcSpot then
		return nil
	end

	local spotPosition = npcSpot.Position
	local towardStreetSign = spotPosition.X < 0 and 1 or -1

	return Vector3.new(
		spotPosition.X + towardStreetSign * FRONT_OF_STAND_OFFSET,
		spotPosition.Y,
		spotPosition.Z
	)
end

-- X-ul mijlocului strazii, citit direct din piesa "Street" a TownMapBuilder
-- (nu hardcodat) -- daca strada se muta vreodata, ramane corect.
local function getStreetCenterX()
	local townMap = workspace:FindFirstChild("TownMap")
	local street = townMap and townMap:FindFirstChild("Street")

	if street then
		return street.Position.X
	end

	return 0
end

local streetCenterX = getStreetCenterX()

-- PathfindingService genera multe waypoint-uri apropiate, iar NPC-ul se
-- oprea/reorienta la fiecare -- de-aia mersul parea sacadat ("merge si se
-- opreste"). Inlocuit cu un traseu simplu, in 2 pasi, GARANTAT pe strada:
-- 1) merge pe mijlocul strazii (X strazii) pana ajunge la Z-ul standului,
-- 2) abia apoi vireaza spre stand. Doar o singura cotitura, mers neted.
local function moveNPCTo(npc, destination)
	local humanoid = npc:WaitForChild("Humanoid")

	local streetWaypoint = Vector3.new(streetCenterX, destination.Y, destination.Z)

	humanoid:MoveTo(streetWaypoint)
	humanoid.MoveToFinished:Wait()

	humanoid:MoveTo(destination)
	humanoid.MoveToFinished:Wait()
end

-- Punct central pentru buy SI skip, manual SAU automat (Auto Buy Pass) --
-- clientul isi ascunde singur chenarul de oferta DOAR cand el insusi apasa
-- Buy/Skip (vezi TradeGui.rbxmx). Cand Auto Buy Pass cumpara/sare peste
-- automat, direct de pe server (fara niciun click de la client), clientul nu
-- avea de unde sa stie sa ascunda chenarul -- ramanea vizibil, aratand
-- oferta veche, deja cumparata/sarita, pana aparea urmatoarea (la cateva
-- secunde distanta). HideTrade rezolva asta pentru AMBELE cazuri deodata.
local function removeNPC(player)
	local trade = activeTrades[player]

	if trade and trade.NPC then
		trade.NPC:Destroy()
	end

	activeTrades[player] = nil
	hideTradeEvent:FireClient(player)
end

local function spawnNPCForPlayer(player, pendingDelay)
	if activeTrades[player] then
		return
	end

	local stand = getPlayerStand(player)
	if not stand then
		return
	end

	local npcSpotPosition = getNPCSpotPosition(stand)
	if not npcSpotPosition then
		return
	end

	local npcType = getRandomNPCType()
	if not npcType then
		return
	end

	local npcData = NPCDatabase.Types[npcType]
	if not npcData then
		return
	end

	-- Rezervam slotul IMEDIAT, inainte de orice yield -- altfel guard-ul de
	-- mai sus (activeTrades[player]) nu se seteaza decat mult mai tarziu (dupa
	-- task.wait + MoveToFinished, ~10-16s), lasand o fereastra in care doua
	-- apeluri concurente (ex: watchStandForClaim + spawn-ul de la join) trec
	-- amandoua de guard si creeaza doi NPC pentru acelasi jucator, unul orfan.
	activeTrades[player] = {Pending = true}

	-- BUG gasit: verificam validitatea DUPA ce clonam + WaitForChild(_, 5) --
	-- template-ul e deja complet incarcat in ServerStorage (nu se repliaza
	-- ca intre server/client), deci FindFirstChild pe TEMPLATE (nu pe clona)
	-- e instant, fara nicio asteptare. Inainte, orice tip cu model stricat
	-- (ex: Street Dealer, 45% sansa sa apara) bloca 5 secunde intregi la
	-- FIECARE spawn, plus un clone+destroy irosit.
	local template = getNpcTemplate(npcType)
	local templateIsValid = template:FindFirstChild("Humanoid") ~= nil
		and template:FindFirstChild("HumanoidRootPart") ~= nil

	local npc

	if templateIsValid then
		npc = template:Clone()
		npc.Name = npcData.DisplayName
		npc.Parent = workspace
	else
		warn("NPCManager: modelul pentru '" .. npcType .. "' (" .. template.Name .. ") nu are Humanoid/HumanoidRootPart -- folosesc rig-ul de rezerva, dar ii grefez accesoriile vizuale (ex: conul de trafic).")

		-- Clonam DOAR accesoriile de pe template (originalul din
		-- ServerStorage ramane neatins, refolosibil la urmatorul spawn).
		local salvagedAccessories = {}
		for _, descendant in ipairs(template:GetDescendants()) do
			if descendant:IsA("Accessory") then
				table.insert(salvagedAccessories, descendant:Clone())
			end
		end

		-- Rig clasic R6, construit din Parts (vezi createBlockyCharacter) --
		-- nu mai depinde de niciun model din Toolbox, deci nu poate fi
		-- niciodata "incomplet". Culoarea hainelor difera per tip de NPC.
		npc = createBlockyCharacter(npcType)
		npc.Name = npcData.DisplayName
		npc.Parent = workspace

		-- Humanoid:AddAccessory suda automat accesoriul in locul corect
		-- (cap/fata/spate etc., dupa AccessoryType), fara sa calculam noi
		-- vreun offset manual.
		for _, accessory in ipairs(salvagedAccessories) do
			local ok = pcall(function()
				npc.Humanoid:AddAccessory(accessory)
			end)

			if not ok then
				accessory:Destroy()
			end
		end
	end

	local humanoid = npc:WaitForChild("Humanoid")
	local rootPart = npc:WaitForChild("HumanoidRootPart")

	-- BUG gasit: modelele custom din Toolbox (Bobux Man, Mr. Robot, Gemeral
	-- etc.) nu aveau NICIODATA coliziunea dezactivata -- NPC-ul se misca doar
	-- prin Humanoid:MoveTo (nu fizica reala), deci fiecare piesa a fiecarui
	-- NPC clonat tot cerea calcule de coliziune/masa degeaba (cu solul, cu
	-- alti NPC/jucatori) -- aplicat la TOATE tipurile, nu doar la rig-ul de
	-- rezerva.
	for _, descendant in ipairs(npc:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.Massless = true
		end
	end

	local bonuses = getStandBonuses(player)
	local cosmeticBonuses = CosmeticManager.GetBonuses(player)
	local petBonuses = PetManager.GetBonuses(player)
	local rebirthBonuses = getRebirthBonuses(player)

	-- Viteza reala a NPC-ului -- toate sursele de Speed (stand, cosmetice,
	-- peturi, rebirth), nu doar stand-ul, la fel ca la getSpawnDelay mai sus
	-- (inainte doar stand-ul conta aici, desi upgrade-urile/peturile de Speed
	-- promiteau ca NPC-urile vin mai repede).
	local speedPassBonus = player:GetAttribute("HasSpeedPass") and Economy.SpeedPass.Speed or 0

	local totalSpeedBonus = bonuses.Speed
		+ (cosmeticBonuses.NpcSpeed or 0)
		+ (petBonuses.NpcSpeed or 0)
		+ rebirthBonuses.Speed
		+ speedPassBonus
	totalSpeedBonus = math.clamp(totalSpeedBonus, 0, Economy.Caps.Speed)

	local speedMultiplier = 1 + (totalSpeedBonus / 100)

	-- Porneste din portal, nu langa stand -- jucatorul trebuie sa vada NPC-ul
	-- venind de-acolo, oricat de departe ar fi standul lui.
	local closestPortalPosition = getClosestPortalPosition(npcSpotPosition)
	rootPart.CFrame = CFrame.new(closestPortalPosition + Vector3.new(0, 3, 0))

	-- IMPORTANT pentru corectitudine intre cei 6 jucatori: WalkSpeed NU e fix
	-- -- se calculeaza din distanta reala pana la stand, ca fiecare jucator sa
	-- astepte acelasi timp de BAZA (BASE_TRAVEL_TIME), indiferent cat de
	-- aproape/departe e standul lui de un portal. Bonusul de Speed% reduce
	-- acel timp (upgrade-urile inca conteaza), dar POZITIA pe harta nu mai da
	-- avantaj/dezavantaj gratuit.
	local BASE_TRAVEL_TIME = 6

	local legOne = math.abs(npcSpotPosition.Z - closestPortalPosition.Z)
	local legTwo = math.abs(npcSpotPosition.X - streetCenterX)
	local totalTravelDistance = math.max(legOne + legTwo, 1)

	local travelTime = BASE_TRAVEL_TIME / speedMultiplier
	humanoid.WalkSpeed = totalTravelDistance / travelTime

	-- Mersul dureaza acum travelTime secunde -- nu mai asteptam SEPARAT
	-- intregul getSpawnDelay() inainte de asta, altfel timpul total per ciclu
	-- (asteptare + mers) ar depasi ce era calibrat inainte (doar spawnDelay,
	-- fara mers vizibil). Scadem mersul din asteptare, ca timpul total sa
	-- ramana acelasi ca inainte -- doar impartit acum in "asteptare" +
	-- "mers vizibil", nu doar asteptare goala.
	local remainingWait = math.max(0, (pendingDelay or 0) - travelTime)
	if remainingWait > 0 then
		task.wait(remainingWait)
	end

	moveNPCTo(npc, npcSpotPosition)

	if not player.Parent then
		-- Jucatorul a plecat cat timp NPC-ul se deplasa -- curatam si iesim,
		-- ca sa nu ramana un NPC orfan in Workspace pentru totdeauna.
		npc:Destroy()
		activeTrades[player] = nil
		return
	end

	local vipLuck = player:GetAttribute("IsVIP") and Economy.VIP.Luck or 0
	local starterPackLuck = player:GetAttribute("HasStarterPack") and Economy.StarterPack.LuckBonus or 0
	local mediumPackLuck = player:GetAttribute("HasMediumPack") and Economy.MediumPack.LuckBonus or 0
	local elitePackLuck = player:GetAttribute("HasElitePack") and Economy.ElitePack.LuckBonus or 0
	local rebirthLuck = getRebirthBonuses(player).Luck
	local titleLuck = Economy.TokenShop.GetTitleLuckBonus(player)

	local totalLuck = bonuses.Luck + cosmeticBonuses.NpcLuck + petBonuses.NpcLuck + vipLuck + starterPackLuck + mediumPackLuck + elitePackLuck + rebirthLuck + titleLuck
	totalLuck = math.clamp(totalLuck, 0, Economy.Caps.Luck)

	-- Cat timp jucatorul nu a terminat tutorialul (primele oferte, imediat
	-- dupa join), fortam Common -- are doar cei 1000$ de start, nu vrem ca
	-- prima oferta sa fie ceva scump pe care nu si-l poate cumpara.
	local forceRarity = player:GetAttribute("TutorialCompleted") == false and "Common" or nil
	local offer = TradeManager.CreateOffer(npcType, totalLuck, forceRarity)

	if offer then
		-- Trimisa MEREU catre client, indiferent unde e jucatorul -- vizibilitatea
		-- pe ecran e deja gestionata client-side, in TradeGui.rbxmx
		-- (isPlayerInOwnZone, re-evaluata la fiecare 0.3s cat timp exista o
		-- oferta curenta) -- acolo traieste deja regula "doar pe podeaua
		-- standului tau", nu aici. Un al doilea filtru aici, pe server, era
		-- pur redundant si a introdus un bug (oferta nu mai ajungea deloc la
		-- client cand jucatorul nu era pe podea la momentul crearii ei).
		activeTrades[player] = {
			NPC = npc,
			Offer = offer,
		}

		showTradeEvent:FireClient(player, offer)

		-- Auto Buy Pass: accepta automat oferta, la scurt timp dupa ce
		-- apare (nu instant -- ca sa simta ca "jocul a dat click pentru tine",
		-- nu un multiplicator suplimentar de bani). Verificam din nou, dupa
		-- delay, ca trade-ul curent sa fie INCA acelasi (jucatorul putea sa
		-- dea click manual mai repede, sa dea skip, sau sa plece) -- altfel
		-- am accepta accidental o oferta noua, aparuta intre timp.
		--
		-- Filtrele pe raritate (AutoBuyFilter<Rarity>, implicit toate true)
		-- decid daca oferta se ACCEPTA sau se SKIP-eaza automat -- fara sa
		-- dam skip explicit cand o raritate e dezactivata, oferta ar ramane
		-- blocata pe ecran la nesfarsit (nimic n-ar mai avansa ciclul).
		--
		-- AutoBuyPassEnabled e comutatorul MASTER (implicit true) -- daca e
		-- oprit, ne intoarcem complet la manual (nici accept, nici skip
		-- automat) -- diferit de un filtru de raritate dezactivat, care tot
		-- avanseaza ciclul singur (skip).
		-- Verificarea de OWNERSHIP ramane in afara (ieftina, rar se schimba) --
		-- doar ca sa nu programam un task.delay degeaba pentru jucatorii fara
		-- Auto Buy Pass deloc. Filtrul de raritate SI comutatorul master
		-- (AutoBuyPassEnabled) se citesc din nou, PROASPAT, in interiorul
		-- closure-ului, la momentul acceptarii -- nu o data, inainte de delay.
		-- BUG anterior: erau citite o singura data AICI, inainte de delay; daca
		-- jucatorul oprea filtrul (sau tot Auto Buy) chiar in fereastra de
		-- Economy.AutoBuyPass.AcceptDelay (0.75s), codul cumpara oricum,
		-- folosind valoarea veche -- inconsistent cu verificarea de bani, care
		-- era deja corect citita live.
		if player:GetAttribute("HasAutoBuyPass") then
			task.delay(Economy.AutoBuyPass.AcceptDelay, function()
				local currentTrade = activeTrades[player]
				if not (player.Parent and currentTrade and currentTrade.Offer == offer) then
					return
				end

				-- Daca s-a oprit tot Auto Buy Pass in acest interval, ne
				-- intoarcem complet la manual (nici accept, nici skip automat)
				-- -- lasam oferta asa cum e, exact ca la comutatorul master
				-- oprit de la inceput.
				if not (player:GetAttribute("HasAutoBuyPass") and player:GetAttribute("AutoBuyPassEnabled") ~= false) then
					return
				end

				local rarityFilterAttribute = "AutoBuyFilter" .. tostring(offer.Rarity)
				local rarityEnabled = player:GetAttribute(rarityFilterAttribute) ~= false

				-- Verificam banii INAINTE sa incercam cumpararea -- altfel
				-- handleBuy ar arata doar "Not enough money" si ar lasa
				-- oferta blocata pe ecran (jucatorul nu mai e acolo sa dea
				-- Skip manual, cu Auto Buy activat). Fara bani suficienti,
				-- trecem direct la urmatorul NPC, ca ciclul sa nu se opreasca.
				local hasEnoughMoney = false
				local leaderstats = player:FindFirstChild("leaderstats")
				local money = leaderstats and leaderstats:FindFirstChild("Money")

				if money then
					hasEnoughMoney = money.Value >= (tonumber(offer.BuyPrice) or 0)
				end

				if rarityEnabled and hasEnoughMoney then
					handleBuy(player, {ItemId = offer.ItemId})
				else
					handleSkip(player)
				end
			end)
		end
	else
		-- CreateOffer nu a putut genera nicio oferta (ex: categorie goala) --
		-- eliberam slotul si reincercam mai tarziu, in loc sa lasam ciclul de
		-- trade al jucatorului blocat definitiv (fara NPC, fara reincercare).
		npc:Destroy()
		activeTrades[player] = nil

		task.delay(5, function()
			if player.Parent then
				spawnNPCForPlayer(player, getSpawnDelay(player))
			end
		end)
	end
end
local function handleOpenPetCrate(player)
	local pet = PetManager.OpenCrate(player)

	if not pet then
		warn("Pet crate failed for " .. player.Name)
		return
	end

	petOpenedEvent:FireClient(player, pet)

	showNotificationEvent:FireClient(
		player,
		"🐾 You received " .. pet.DisplayName .. " (" .. pet.Rarity .. ")"
	)
end

local buyInProgress = {}

-- getMaxInventory face un yield (UserOwnsGamePassAsync) inainte sa taxeze --
-- fara guard-ul asta, doua BuyItem trase foarte rapid pot ambele trece de
-- verificarile de mai jos in acel interval si taxa jucatorul de doua ori
-- pentru un singur item.
local function doHandleBuy(player, clientOffer)
	local trade = activeTrades[player]
	if not trade then return end

	local offer = trade.Offer
	if not offer then return end

	if not clientOffer or clientOffer.ItemId ~= offer.ItemId then
		warn("Invalid offer from " .. player.Name)
		return
	end

	local inventory = player:FindFirstChild("Inventory")
	if not inventory then return end

	local maxInventory = getMaxInventory(player)

	if #inventory:GetChildren() >= maxInventory then
		-- Auto-Sell Pass: nu blocheaza cumpararea -- e o plasa de siguranta
		-- ("nu mai raman blocat"), declansata DOAR cand inventarul e plin
		-- (nu la fiecare cumparare). Vinde cel mai vechi item, dar DOAR daca
		-- (a) filtrul pe CATEGORIA lui e activat (AutoSellFilter<Categorie>,
		-- implicit toate true) SI (b) piata pentru acea categorie e chiar pe
		-- plus (>= +1%) -- cerut explicit: nu vindem automat pe pierdere doar
		-- ca sa facem loc. Daca niciun item nu indeplineste conditiile
		-- (toate categoriile din inventar sunt pe minus sau dezactivate),
		-- ramanem blocati normal ("Inventory Full"), fara sa fortam o vanzare
		-- proasta.
		local autoSold = false

		if player:GetAttribute("HasAutoSellPass") then
			local bestItem = nil
			local bestTime = math.huge

			for _, child in ipairs(inventory:GetChildren()) do
				local categoryValue = child:FindFirstChild("Category")
				local category = categoryValue and categoryValue.Value

				local categoryEnabled = category and player:GetAttribute("AutoSellFilter" .. category) ~= false
				local categoryPercent = category and MarketManager.GetCategoryPercent(category) or 0

				if categoryEnabled and categoryPercent >= 1 then
					local purchaseTime = child:FindFirstChild("PurchaseTime")
					local timeValue = purchaseTime and purchaseTime.Value or 0

					if timeValue < bestTime then
						bestTime = timeValue
						bestItem = child
					end
				end
			end

			if bestItem then
				local bestName = bestItem:FindFirstChild("ItemName")
				local bestNameText = bestName and bestName.Value or "item"

				if SellManager.SellItem(player, bestItem) then
					autoSold = true
					showNotificationEvent:FireClient(player, "🔄 Auto-Sold " .. bestNameText .. " to make room")
				end
			end
		end

		if not autoSold then
			showNotificationEvent:FireClient(player, "🎒 Inventory Full! Press + to upgrade.")
			SFXServer.Play(player, "InventoryFull")
			-- BUG gasit: TradeGui.rbxmx ascunde oferta OPTIMIST, imediat la
			-- click pe Buy, inainte sa stie daca serverul a acceptat (vezi
			-- buyButton.Activated in TradeGui.rbxmx). Daca refuzam aici fara
			-- sa facem nimic, activeTrades ramane ocupat pentru totdeauna
			-- (guard-ul din spawnNPCForPlayer), deci niciun NPC nou nu mai
			-- apare. Tratam refuzul ca un skip automat -- NPC-ul pleaca,
			-- vine urmatorul, exact ca la Skip manual.
			removeNPC(player)
			spawnNPCForPlayer(player, getSpawnDelay(player) + 2)
			return
		end
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local money = leaderstats:FindFirstChild("Money")
	if not money then return end

	local buyPrice = tonumber(offer.BuyPrice) or 0

	if money.Value < buyPrice then
		showNotificationEvent:FireClient(player, "❌ Not enough money")
		-- Acelasi bug/fix ca mai sus -- tratam ca skip automat, ca NPC-ul sa
		-- dispara si sa vina urmatorul, in loc sa ramana blocat definitiv.
		removeNPC(player)
		spawnNPCForPlayer(player, getSpawnDelay(player) + 2)
		return
	end

	money.Value -= buyPrice

	InventoryManager.AddItem(player, offer)
	StandDisplayManager.UpdateStand(player)
	sendInventory(player)

	showNotificationEvent:FireClient(player, "✅ Bought " .. tostring(offer.ItemName) .. " for $" .. tostring(buyPrice))
	SFXServer.Play(player, "Buy")

	removeNPC(player)

	spawnNPCForPlayer(player, getSpawnDelay(player))
end

handleBuy = function(player, clientOffer)
	if buyInProgress[player] then
		return
	end

	buyInProgress[player] = true

	local ok, err = pcall(doHandleBuy, player, clientOffer)
	if not ok then
		warn("NPCManager: handleBuy error for " .. player.Name .. ": " .. tostring(err))
	end

	buyInProgress[player] = nil
end

handleSkip = function(player)
	removeNPC(player)

	-- Skip ramane putin mai lent decat buy, ca penalizare naturala.
	spawnNPCForPlayer(player, getSpawnDelay(player) + 2)
end

-- Cerut explicit: jucatorul trebuie sa vada efectiv profitul la vanzare (nu
-- doar un mesaj generic "Sold item") -- inainte, profitul era doar printat
-- in consola serverului, niciodata trimis la client.
local function formatSellNotification(itemName, sellPrice, profit)
	local profitText = profit >= 0 and ("+$" .. profit) or ("-$" .. math.abs(profit))
	return "💰 Sold " .. itemName .. " for $" .. sellPrice .. " (" .. profitText .. ")"
end

local function handleSellFirstItem(player)
	local inventory = player:FindFirstChild("Inventory")
	if not inventory then return end

	local firstItem = inventory:FindFirstChild("1")

	if not firstItem then
		showNotificationEvent:FireClient(player, "🎒 Inventory is empty")
		return
	end

	local success, sellPrice, profit, itemName = SellManager.SellItem(player, firstItem)

	if success then
		showNotificationEvent:FireClient(player, formatSellNotification(itemName, sellPrice, profit))
		sendInventory(player)
		StandDisplayManager.UpdateStand(player)
	end
end

local function handleSellSelectedItem(player, itemId)
	local inventory = player:FindFirstChild("Inventory")
	if not inventory then return end

	local item = inventory:FindFirstChild(tostring(itemId))

	if not item then
		showNotificationEvent:FireClient(player, "❌ Item not found")
		return
	end

	local success, sellPrice, profit, itemName = SellManager.SellItem(player, item)

	if success then
		showNotificationEvent:FireClient(player, formatSellNotification(itemName, sellPrice, profit))
		sendInventory(player)
		StandDisplayManager.UpdateStand(player)
	end
end

local function onPlayerAdded(player)
	local data = DataManager.LoadData(player)

	task.wait(1)
	DataManager.ApplyData(player, data)

	marketUpdateEvent:FireClient(player, MarketManager.GetClientData())

	task.wait(7)
	spawnNPCForPlayer(player)
end

local function onPlayerRemoving(player)
	removeNPC(player)
	buyInProgress[player] = nil
	DataManager.SaveData(player)
end

-- Standurile nu se mai asigneaza automat (StandManager: jucatorul trebuie sa
-- dea Claim manual) -- deci spawnNPCForPlayer de la join (dupa 7s) de multe
-- ori nu gaseste niciun stand inca si nu face nimic, iar apoi NIMIC nu-l mai
-- declanseaza vreodata pentru jucatorul ala. Ascultam direct atributul
-- "Occupied" de pe fiecare stand -- cand devine true (Claim reusit), pornim
-- primul NPC pe loc, din portal.
local function watchStandForClaim(stand)
	stand:GetAttributeChangedSignal("Occupied"):Connect(function()
		if not stand:GetAttribute("Occupied") then
			return
		end

		local ownerUserId = stand:GetAttribute("OwnerUserId")
		local player = Players:GetPlayerByUserId(ownerUserId)

		if player and not activeTrades[player] then
			spawnNPCForPlayer(player)
		end
	end)
end

do
	local standsFolder = workspace:WaitForChild("GeneratedStands")

	for _, stand in ipairs(standsFolder:GetChildren()) do
		watchStandForClaim(stand)
	end

	standsFolder.ChildAdded:Connect(watchStandForClaim)
end

buyItemEvent.OnServerEvent:Connect(handleBuy)
skipTradeEvent.OnServerEvent:Connect(handleSkip)
sellFirstItemEvent.OnServerEvent:Connect(handleSellFirstItem)
sellSelectedItemEvent.OnServerEvent:Connect(handleSellSelectedItem)
requestInventoryEvent.OnServerEvent:Connect(sendInventory)
openPetCrateEvent.OnServerEvent:Connect(handleOpenPetCrate)

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
