local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

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
	billboard.StudsOffset = Vector3.new(0, 9, 0)
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

		applyStandTexture(stand)
		applyPremiumTrim(stand)
		applyNameBoardBorder(stand)
		createClaimPrompt(stand)

		table.insert(stands, stand)
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