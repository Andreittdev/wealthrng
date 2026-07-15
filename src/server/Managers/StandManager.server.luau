local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local templatesFolder = ServerStorage:WaitForChild("Templates")
local standTemplate = templatesFolder:WaitForChild("StandTemplate")

-- Pozitii date manual de jucator (coordonate exacte, cate 2 pe fiecare
-- "rand" -- unul dat direct, celalalt in oglinda pe partea opusa a strazii,
-- la acelasi Z). Rotatia se calculeaza automat dupa semnul lui X (stanga
-- strazii = fata spre +X, dreapta = fata spre -X).
local STAND_Y = 5

-- Strada e la X in [-16,16], trotuarele pana la X=+-24 (vezi TownMapBuilder)
-- -- 30 le tine clar pe iarba (6 studs dupa trotuar), dar aproape de strada,
-- nu departate. FARA shift de grup -- simetric fata de mijlocul strazii
-- (X=0), altfel un rand ajunge sa cada peste asfalt (exact ce s-a intamplat
-- cu shift-ul de dinainte).
local SIDE_DISTANCE = 45

local Z_START = 331.155
local Z_STEP = 90

local ROW_Z = {Z_START, Z_START + Z_STEP, Z_START + Z_STEP * 2}

local STAND_POSITIONS = {
	{x = SIDE_DISTANCE, z = ROW_Z[1]},
	{x = -SIDE_DISTANCE, z = ROW_Z[1]},
	{x = -SIDE_DISTANCE, z = ROW_Z[2]},
	{x = SIDE_DISTANCE, z = ROW_Z[2]},
	{x = -SIDE_DISTANCE, z = ROW_Z[3]},
	{x = SIDE_DISTANCE, z = ROW_Z[3]}
}

-- Aceeasi textura "bloxy" de pe strada/iarba (TownMapBuilder), dar tentata
-- albastru (nu verde ca iarba) -- aplicata pe Base-ul fiecarui stand.
local GRID_TEXTURE_ID = "rbxassetid://6372755229"
local STAND_TINT = Color3.fromRGB(90, 130, 175)

-- Platforma (Base) marita fata de template -- doar pe orizontala (X/Z), fara
-- sa atingem grosimea (Y). Aplicata PRIMA, inainte de textura/trim, ca restul
-- functiilor citesc base.Size in momentul apelului si se adapteaza singure.
local BASE_SCALE = 1.5

local function enlargeStandBase(stand)
	local base = stand:FindFirstChild("Base")
	if not base then
		return
	end

	base.Size = Vector3.new(base.Size.X * BASE_SCALE, base.Size.Y, base.Size.Z * BASE_SCALE)
end

local function applyStandTexture(stand)
	local base = stand:FindFirstChild("Base")
	if not base then
		return
	end

	local existingTexture = base:FindFirstChild("GridTexture")
	if existingTexture then
		existingTexture:Destroy()
	end

	local texture = Instance.new("Texture")
	texture.Name = "GridTexture"
	texture.Face = Enum.NormalId.Top
	texture.Texture = GRID_TEXTURE_ID
	texture.Color3 = STAND_TINT
	texture.StudsPerTileU = 2
	texture.StudsPerTileV = 2
	texture.Parent = base
end

-- Bordura aurie subtire sub baza -- acelasi accent "premium" folosit la
-- standul de Token Shop, ca standurile jucatorilor sa arate mai moderne, nu
-- doar cutia simpla din template.
local PREMIUM_GOLD = Color3.fromRGB(212, 175, 55)

local function applyPremiumTrim(stand)
	local base = stand:FindFirstChild("Base")
	if not base then
		return
	end

	local existingTrim = stand:FindFirstChild("PremiumTrim")
	if existingTrim then
		existingTrim:Destroy()
	end

	local trim = Instance.new("Part")
	trim.Name = "PremiumTrim"
	trim.Anchored = true
	trim.CanCollide = false
	trim.Material = Enum.Material.Neon
	trim.Color = PREMIUM_GOLD
	trim.Size = Vector3.new(base.Size.X + 0.6, 0.25, base.Size.Z + 0.6)
	trim.CFrame = base.CFrame * CFrame.new(0, -base.Size.Y / 2 - 0.15, 0)
	trim.Parent = stand
end

-- Pancarda gri (NameBoard) latita ca sa fie la fel de lata ca podeaua marita
-- (base.Size.X) -- altfel ramanea la latimea veche, mai ingusta decat noua
-- platforma. Doar latimea (X); inaltimea (Y) si grosimea (Z) raman neatinse.
local function widenNameBoard(stand)
	local base = stand:FindFirstChild("Base")
	if not base then
		return
	end

	local nameBoard = base:FindFirstChild("NameBoard")
	if not nameBoard then
		return
	end

	nameBoard.Size = Vector3.new(base.Size.X, nameBoard.Size.Y, nameBoard.Size.Z)
end

-- Contur maro in spatele pancardei gri cu numele jucatorului -- o placa
-- maro, putin mai mare, chiar in spatele NameBoard-ului, ca sa iasa vizibil
-- pe margini (in loc de un UIStroke, care ar contura doar textul, nu placa).
local BORDER_BROWN = Color3.fromRGB(92, 51, 23)

local function applyNameBoardBorder(stand)
	local base = stand:FindFirstChild("Base")
	if not base then
		return
	end

	local nameBoard = base:FindFirstChild("NameBoard")
	if not nameBoard then
		return
	end

	local existingBorder = base:FindFirstChild("NameBoardBorder")
	if existingBorder then
		existingBorder:Destroy()
	end

	local border = Instance.new("Part")
	border.Name = "NameBoardBorder"
	border.Anchored = true
	border.CanCollide = false
	border.Material = Enum.Material.Plastic
	border.Color = BORDER_BROWN
	border.Size = nameBoard.Size + Vector3.new(0.6, 0.6, 0)
	border.CFrame = nameBoard.CFrame * CFrame.new(0, 0, -(nameBoard.Size.Z / 2 + 0.05))
	border.Parent = base
end

local standsFolder = Instance.new("Folder")
standsFolder.Name = "GeneratedStands"
standsFolder.Parent = workspace

local stands = {}

-- Avatarul jucatorului, deasupra pancardei cu numele -- BillboardGui cu
-- headshot-ul lui, mai sus decat NameBoard.
local function setStandAvatar(stand, player)
	local base = stand:FindFirstChild("Base")
	if not base then
		return
	end

	local existingAvatar = base:FindFirstChild("AvatarBillboard")
	if existingAvatar then
		existingAvatar:Destroy()
	end

	if not player then
		return
	end

	local content = Players:GetUserThumbnailAsync(
		player.UserId,
		Enum.ThumbnailType.HeadShot,
		Enum.ThumbnailSize.Size100x100
	)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AvatarBillboard"
	billboard.Size = UDim2.new(0, 55, 0, 55)
	billboard.StudsOffset = Vector3.new(0, 14, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 100
	billboard.Adornee = base
	billboard.Parent = base

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.Parent = billboard

	Instance.new("UICorner", frame).CornerRadius = UDim.new(1, 0)

	local stroke = Instance.new("UIStroke")
	stroke.Color = PREMIUM_GOLD
	stroke.Thickness = 2
	stroke.Parent = frame

	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(1, -4, 1, -4)
	icon.Position = UDim2.new(0, 2, 0, 2)
	icon.Image = content
	icon.Parent = frame

	Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)
end

-- Cerc galben, plat, pe podea, langa standul cuiva care si l-a asignat --
-- marcheaza vizual "zona" in care clientul (UpgradeGui.rbxmx) verifica daca
-- jucatorul e suficient de aproape ca sa i se deschida automat Stand Upgrades.
local ZONE_RADIUS = 2.8
local ZONE_COLOR = Color3.fromRGB(255, 221, 0)

-- Cat de departe de centru, spre stanga, sa fie cercul (ca fractie din
-- latimea bazei, nu valoare fixa -- ramane proportional indiferent de
-- BASE_SCALE). Daca iese pe dreapta in loc de stanga (in functie de cum e
-- orientat modelul de baza), schimba semnul (-> pozitiv).
local ZONE_SIDE_FRACTION = -0.35

local function setClaimZone(stand, active)
	local base = stand:FindFirstChild("Base")
	if not base then
		return
	end

	local existingZone = base:FindFirstChild("ClaimZone")
	if existingZone then
		existingZone:Destroy()
	end

	if not active then
		return
	end

	local zone = Instance.new("Part")
	zone.Name = "ClaimZone"
	zone.Shape = Enum.PartType.Cylinder
	zone.Material = Enum.Material.Neon
	zone.Color = ZONE_COLOR
	zone.Transparency = 0.4
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CanQuery = false

	-- Size.X = grosimea discului (axa "lungimii" cilindrului); Size.Y/Z =
	-- diametrul cercului. Rotim 90 pe Z ca axa X (implicit orizontala) sa
	-- ajunga verticala -- discul iese culcat, plat pe podea, indiferent de
	-- rotatia standului (rotatia se compune relativ la base.CFrame).
	zone.Size = Vector3.new(0.2, ZONE_RADIUS * 2, ZONE_RADIUS * 2)

	local sideOffset = base.Size.X * ZONE_SIDE_FRACTION
	zone.CFrame = base.CFrame * CFrame.new(sideOffset, base.Size.Y / 2 + 0.15, 0) * CFrame.Angles(0, 0, math.rad(90))
	zone.Parent = base

	-- Text plutitor deasupra cercului, ca jucatorul sa stie la ce foloseste
	-- (altfel e doar un cerc galben fara sens). Enabled e controlat de bucla
	-- de mai jos (nu de MaxDistance) -- apare/dispare exact cand cineva
	-- calca pe toata podeaua (dreptunghiul lui base), nu dupa distanta.
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ClaimZoneLabel"
	billboard.Size = UDim2.new(0, 160, 0, 32)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.Adornee = zone
	billboard.Parent = zone

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Text = "STAND UPGRADES"
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 221, 0)
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Parent = billboard
end

-- Punct in dreptunghiul podelei (base), nu intr-un cerc de distanta --
-- converteste punctul in spatiul local al lui base si il compara cu
-- jumatatile de latime/lungime (functioneaza indiferent de rotatia bazei).
local function isPointOnBase(base, worldPoint)
	local relative = base.CFrame:PointToObjectSpace(worldPoint)
	return math.abs(relative.X) <= base.Size.X / 2 and math.abs(relative.Z) <= base.Size.Z / 2
end

-- Arata/ascunde textul "STAND UPGRADES" exact cat timp cineva (oricine, nu
-- doar proprietarul) sta pe podeaua unui stand ocupat -- verificat periodic
-- pe server (nu per-client), ca toata lumea sa vada aceeasi stare.
local LABEL_CHECK_INTERVAL = 0.25
local labelCheckTimer = 0

RunService.Heartbeat:Connect(function(dt)
	labelCheckTimer += dt
	if labelCheckTimer < LABEL_CHECK_INTERVAL then
		return
	end
	labelCheckTimer = 0

	for _, stand in ipairs(stands) do
		if stand:GetAttribute("Occupied") then
			local base = stand:FindFirstChild("Base")
			local zone = base and base:FindFirstChild("ClaimZone")
			local billboard = zone and zone:FindFirstChild("ClaimZoneLabel")

			if billboard then
				local anyoneOnPlatform = false

				for _, player in ipairs(Players:GetPlayers()) do
					local character = player.Character
					local rootPart = character and character:FindFirstChild("HumanoidRootPart")

					if rootPart and isPointOnBase(base, rootPart.Position) then
						anyoneOnPlatform = true
						break
					end
				end

				billboard.Enabled = anyoneOnPlatform
			end
		end
	end
end)

-- ProximityPrompt pe fiecare stand liber -- jucatorul isi alege singur
-- standul, nu mai e asignat automat la conectare.
local function createClaimPrompt(stand)
	local base = stand:FindFirstChild("Base")
	if not base then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClaimPrompt"
	prompt.ActionText = "Claim"
	prompt.ObjectText = "Stand"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = base
end

local function createStands()
	local positions = {}

	for _, entry in ipairs(STAND_POSITIONS) do
		-- Stanga strazii (X<0) = fata spre +X; dreapta (X>0) = fata spre -X.
		local rotY = entry.x < 0 and math.rad(-90) or math.rad(90)
		table.insert(positions, {x = entry.x, z = entry.z, rotY = rotY})
	end

	for i, pos in ipairs(positions) do
		local stand = standTemplate:Clone()
		stand.Name = "Stand_" .. i
		stand.Parent = standsFolder

		stand:SetAttribute("OwnerUserId", 0)
		stand:SetAttribute("Occupied", false)
		stand:SetAttribute("StandLevel", 1)

		-- Fara PrimaryPart explicit, PivotTo foloseste pivotul automat calculat
		-- de Roblox (bounding box), care poate sa nu fie axat drept -- de-aia
		-- standurile ieseau usor "intr-o parte" dupa rotatie, nu drepte.
		-- Fixam pivotul pe Base (partea de jos, cunoscuta), inainte de rotatie.
		local baseForPivot = stand:FindFirstChild("Base")
		if baseForPivot then
			stand.PrimaryPart = baseForPivot
		end

		stand:PivotTo(
			CFrame.new(pos.x, STAND_Y, pos.z) * CFrame.Angles(0, pos.rotY, 0)
		)

		enlargeStandBase(stand)
		applyStandTexture(stand)
		applyPremiumTrim(stand)
		widenNameBoard(stand)
		applyNameBoardBorder(stand)
		createClaimPrompt(stand)

		table.insert(stands, stand)
	end

	-- DEBUG TEMPORAR -- listeaza in Output (F9 in Studio) toate piesele din
	-- primul stand, cu dimensiuni, ca sa identificam exact "bucata gri"
	-- (fara acces la Explorer/Studio, asta e singurul mod sa aflam numele
	-- corect). Sterge blocul asta dupa ce gasim piesa.
	if stands[1] then
		print("=== DEBUG: piesele din " .. stands[1].Name .. " ===")
		for _, descendant in ipairs(stands[1]:GetDescendants()) do
			if descendant:IsA("BasePart") then
				print(string.format(
					"  %s (%s) - Size=%s Color=%s",
					descendant.Name,
					descendant.ClassName,
					tostring(descendant.Size),
					tostring(descendant.Color)
				))
			end
		end
		print("=== END DEBUG ===")
	end
end

local function setStandName(stand, text)
	local base = stand:FindFirstChild("Base")
	if not base then
		warn("Base not found in " .. stand.Name)
		return
	end

	local nameBoard = base:FindFirstChild("NameBoard")
	if not nameBoard then
		warn("NameBoard not found in Base of " .. stand.Name)
		return
	end

	local surfaceGui = nameBoard:FindFirstChild("SurfaceGui")
	if not surfaceGui then
		warn("SurfaceGui not found in NameBoard of " .. stand.Name)
		return
	end

	local textLabel = surfaceGui:FindFirstChild("TextLabel")
	if not textLabel then
		warn("TextLabel not found in SurfaceGui of " .. stand.Name)
		return
	end

	textLabel.Text = text
end

local function getClaimPrompt(stand)
	local base = stand:FindFirstChild("Base")
	return base and base:FindFirstChild("ClaimPrompt")
end

-- Elibereaza standul unui jucator (daca are unul) -- redeschide prompt-ul de
-- Claim pentru altcineva si sterge numele/avatarul.
local function releaseStand(player)
	for _, stand in ipairs(stands) do
		if stand:GetAttribute("OwnerUserId") == player.UserId then
			stand:SetAttribute("OwnerUserId", 0)
			stand:SetAttribute("Occupied", false)

			setStandName(stand, "Empty Stand")
			setStandAvatar(stand, nil)
			setClaimZone(stand, false)

			local prompt = getClaimPrompt(stand)
			if prompt then
				prompt.Enabled = true
			end

			print(player.Name .. " released " .. stand.Name)
			return
		end
	end
end

-- Jucatorul isi alege standul mergand la el si folosind ProximityPrompt-ul --
-- daca are deja alt stand, il elibereaza automat pe cel vechi (un singur
-- stand per jucator).
local function claimStand(player, stand)
	if stand:GetAttribute("Occupied") then
		return
	end

	releaseStand(player)

	stand:SetAttribute("OwnerUserId", player.UserId)
	stand:SetAttribute("Occupied", true)

	setStandName(stand, player.Name)
	setStandAvatar(stand, player)
	setClaimZone(stand, true)

	local prompt = getClaimPrompt(stand)
	if prompt then
		prompt.Enabled = false
	end

	print(player.Name .. " claimed " .. stand.Name)
end

createStands()

for _, stand in ipairs(stands) do
	local prompt = getClaimPrompt(stand)
	if prompt then
		prompt.Triggered:Connect(function(player)
			claimStand(player, stand)
		end)
	end
end

Players.PlayerRemoving:Connect(releaseStand)