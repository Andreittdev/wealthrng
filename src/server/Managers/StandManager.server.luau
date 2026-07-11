local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local templatesFolder = ServerStorage:WaitForChild("Templates")
local standTemplate = templatesFolder:WaitForChild("StandTemplate")

local STAND_COUNT = 8
local RADIUS = 55

local standsFolder = Instance.new("Folder")
standsFolder.Name = "GeneratedStands"
standsFolder.Parent = workspace

local stands = {}

local function createStands()
	for i = 1, STAND_COUNT do
		local angle = (2 * math.pi / STAND_COUNT) * (i - 1)

		local x = math.cos(angle) * RADIUS
		local z = math.sin(angle) * RADIUS

		local stand = standTemplate:Clone()
		stand.Name = "Stand_" .. i
		stand.Parent = standsFolder

		stand:SetAttribute("OwnerUserId", 0)
		stand:SetAttribute("Occupied", false)
		stand:SetAttribute("StandLevel", 1)

		stand:PivotTo(
			CFrame.new(x, 1, z) * CFrame.Angles(0, -angle, 0)
		)

		table.insert(stands, stand)
	end
end

local function getFreeStand()
	for _, stand in ipairs(stands) do
		if stand:GetAttribute("Occupied") == false then
			return stand
		end
	end

	return nil
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

local function teleportPlayerToStand(player, stand)
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

	local base = stand:FindFirstChild("Base")
	if not base then
		warn("Base not found in " .. stand.Name)
		return
	end

	local playerSpawn = base:FindFirstChild("PlayerSpawn")
	if not playerSpawn then
		warn("PlayerSpawn not found in Base of " .. stand.Name)
		return
	end

	humanoidRootPart.CFrame = playerSpawn.WorldCFrame + Vector3.new(0, 4, 0)
end

local function assignStand(player)
	local freeStand = getFreeStand()

	if not freeStand then
		warn("No free stand available for " .. player.Name)
		return
	end

	freeStand:SetAttribute("OwnerUserId", player.UserId)
	freeStand:SetAttribute("Occupied", true)

	setStandName(freeStand, player.Name)
	teleportPlayerToStand(player, freeStand)

	print(player.Name .. " was assigned to " .. freeStand.Name)
end

local function releaseStand(player)
	for _, stand in ipairs(stands) do
		if stand:GetAttribute("OwnerUserId") == player.UserId then
			stand:SetAttribute("OwnerUserId", 0)
			stand:SetAttribute("Occupied", false)

			setStandName(stand, "Empty Stand")

			print(player.Name .. " released " .. stand.Name)
			return
		end
	end
end

createStands()

Players.PlayerAdded:Connect(assignStand)
Players.PlayerRemoving:Connect(releaseStand)