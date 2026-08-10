-- The 2 big "claim your half" plots split by the street through the middle
-- of Endless Mode (MapBuilder.buildEndlessModeArea) -- first player to hit
-- Claim on a side gets it: the floor "Claim" marker (disk + beam + label)
-- hides, and a circular badge showing the claiming player's avatar face
-- floats above the plot instead.
--
-- In-memory only for now, no DataStore -- same "shared global server state,
-- not per-player persisted data" shape as StadiumOfferManager's stock count
-- or BattleManager's queue. Releases automatically when the claiming player
-- leaves the server (Players.PlayerRemoving), same idiom used everywhere
-- else in this codebase for that -- marker reappears, badge is removed.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local RemotesBootstrap = require(ServerScriptService.RemotesBootstrap)

local claimEndlessModeLand = RemotesBootstrap:WaitForChild("ClaimEndlessModeLand")
local requestEndlessModeClaimState = RemotesBootstrap:WaitForChild("RequestEndlessModeClaimState")
local endlessModeLandClaimed = RemotesBootstrap:WaitForChild("EndlessModeLandClaimed")

local EndlessModeClaimManager = {}

-- Right only for now, per explicit request -- the left plot's marker still
-- exists on the map (MapBuilder.buildEndlessModeArea), just not claimable
-- yet. tryClaim's `table.find(SIDES, side)` guard rejects a "Left" attempt
-- the same way it'd reject any other invalid side.
local SIDES = { "Right" }
local BADGE_SIZE = 55
local BADGE_STUDS_UP = 22
local BADGE_STROKE_COLOR = Color3.fromRGB(90, 220, 140)
-- Covers the WHOLE right half of Endless Mode's ground, per explicit
-- request -- reads as "this entire side is now yours/buildable" the way
-- claimed lots do in tycoon/farming games, not just a small patch near the
-- marker. Sits a hair above the grass (same z-fighting fix MapBuilder's
-- road uses) and above THAT is where the marker/badge already float, so
-- nothing here needs to move them.
--
-- These must match MapBuilder.buildEndlessModeArea's own constants:
-- ROAD_HALF_WIDTH = ENDLESS_MODE_ROAD_WIDTH/2 (20/2), GROUND_HALF_SIZE =
-- ENDLESS_MODE_GROUND_SIZE/2 (200/2). Only correct for a plot on the +X
-- ("Right") side, same "Right only for now" scope as SIDES above.
local ROAD_HALF_WIDTH = 10
local GROUND_HALF_SIZE = 100
local PATCH_WIDTH = GROUND_HALF_SIZE - ROAD_HALF_WIDTH
local PATCH_DEPTH = GROUND_HALF_SIZE * 0.65
local PATCH_HEIGHT = 1
local PATCH_CLEARANCE = 0.15
-- Same "Bloxy" checkerboard-of-square-tiles trick as MapBuilder's grass/
-- plaza/Endless Mode ground, per explicit request, instead of one flat slab.
local PATCH_TILE_SIZE = 15
local PATCH_COLOR_A = Color3.fromRGB(125, 85, 50)
local PATCH_COLOR_B = Color3.fromRGB(100, 68, 40)
-- Base HP display + a plain 3D door prototype marking the entrance (right at
-- the road edge, facing the street) -- per explicit request. Real HP now
-- (see DamageBase below), chipped away by EndlessModeMobManager.luau's mobs
-- reaching the door.
local BASE_MAX_HP = 200
local DOOR_WIDTH = 4
local DOOR_HEIGHT = 7
local DOOR_THICKNESS = 0.4
local DOOR_COLOR = Color3.fromRGB(90, 60, 40)
local DOOR_FRAME_COLOR = Color3.fromRGB(60, 40, 25)
local HP_LABEL_SIZE = UDim2.new(0, 140, 0, 32)
local HP_STUDS_UP = 3

local claimedBy: { [string]: Player } = {}
local badges: { [string]: BillboardGui } = {}
local patches: { [string]: Folder } = {}
local bases: { [string]: Folder } = {}
local baseHP: { [string]: number } = {}
local hpLabels: { [string]: TextLabel } = {}

local function buildState()
	local state = {}
	for _, side in SIDES do
		local player = claimedBy[side]
		state[side] = player and { UserId = player.UserId, Name = player.DisplayName } or nil
	end
	return state
end

local function findMarker(side: string): BasePart?
	local mapFolder = Workspace:FindFirstChild("Map")
	return mapFolder and (mapFolder:FindFirstChild("EndlessMode_Claim" .. side) :: BasePart?) or nil
end

-- Toggles the floor marker itself (disk + beam + its "Claim" label) between
-- visible/hidden -- MapBuilder's buildFloorMarker built all 3 as separate
-- siblings under mapFolder (beam) or as the "Label" BillboardGui child of
-- the disk, not one single Model, so each needs its own toggle.
local function setMarkerClaimed(side: string, claimed: boolean)
	local marker = findMarker(side)
	if not marker then
		return
	end

	marker.Transparency = claimed and 1 or 0

	local label = marker:FindFirstChild("Label")
	if label and label:IsA("BillboardGui") then
		label.Enabled = not claimed
	end

	local mapFolder = marker.Parent
	local beam = mapFolder and mapFolder:FindFirstChild("EndlessMode_Claim" .. side .. "_Beam")
	if beam and beam:IsA("BasePart") then
		beam.Transparency = claimed and 1 or 0.55
	end
end

local function clearBadge(side: string)
	local badge = badges[side]
	if badge then
		badge:Destroy()
		badges[side] = nil
	end
end

local function spawnBadge(side: string, player: Player)
	clearBadge(side)

	local marker = findMarker(side)
	if not marker then
		warn("[EndlessModeClaimManager] Missing EndlessMode_Claim" .. side .. " marker -- can't show badge")
		return
	end

	local ok, thumbnail = pcall(function()
		return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
	end)
	if not ok then
		warn("[EndlessModeClaimManager] Couldn't fetch avatar thumbnail for " .. player.Name .. ": " .. tostring(thumbnail))
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EndlessMode_ClaimBadge" .. side
	billboard.Size = UDim2.new(0, BADGE_SIZE, 0, BADGE_SIZE)
	billboard.StudsOffset = Vector3.new(0, BADGE_STUDS_UP, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = marker
	billboard.Parent = marker

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(1, 0, 1, 0)
	icon.BackgroundTransparency = 1
	icon.Image = thumbnail :: string
	icon.Parent = billboard

	local iconCorner = Instance.new("UICorner")
	iconCorner.CornerRadius = UDim.new(1, 0)
	iconCorner.Parent = icon

	local iconStroke = Instance.new("UIStroke")
	iconStroke.Thickness = 3
	iconStroke.Color = BADGE_STROKE_COLOR
	iconStroke.Parent = icon

	badges[side] = billboard
end

local function clearPatch(side: string)
	local patch = patches[side]
	if patch then
		patch:Destroy()
		patches[side] = nil
	end
end

local function spawnPatch(side: string)
	clearPatch(side)

	local marker = findMarker(side)
	if not marker then
		return
	end

	local patchCenterX = ROAD_HALF_WIDTH + PATCH_WIDTH / 2
	local patchCenterZ = marker.Position.Z
	local patchTopY = marker.Position.Y + PATCH_CLEARANCE

	local patchFolder = Instance.new("Folder")
	patchFolder.Name = "EndlessMode_ClaimPatch" .. side
	patchFolder.Parent = marker.Parent

	local tileCountX = math.max(1, math.floor(PATCH_WIDTH / PATCH_TILE_SIZE))
	local tileCountZ = math.max(1, math.floor(PATCH_DEPTH / PATCH_TILE_SIZE))
	local halfSpanX = (tileCountX * PATCH_TILE_SIZE) / 2
	local halfSpanZ = (tileCountZ * PATCH_TILE_SIZE) / 2

	for row = 0, tileCountZ - 1 do
		for col = 0, tileCountX - 1 do
			local x = patchCenterX - halfSpanX + PATCH_TILE_SIZE * col + PATCH_TILE_SIZE / 2
			local z = patchCenterZ - halfSpanZ + PATCH_TILE_SIZE * row + PATCH_TILE_SIZE / 2
			local isEven = (row + col) % 2 == 0

			local tile = Instance.new("Part")
			tile.Name = "PatchTile"
			tile.Size = Vector3.new(PATCH_TILE_SIZE, PATCH_HEIGHT, PATCH_TILE_SIZE)
			tile.CFrame = CFrame.new(x, patchTopY - PATCH_HEIGHT / 2, z)
			tile.Anchored = true
			tile.CanCollide = false
			tile.Color = isEven and PATCH_COLOR_A or PATCH_COLOR_B
			tile.Material = Enum.Material.Ground
			tile.TopSurface = Enum.SurfaceType.Smooth
			tile.BottomSurface = Enum.SurfaceType.Smooth
			tile.Parent = patchFolder
		end
	end

	patches[side] = patchFolder
end

local function clearBase(side: string)
	local base = bases[side]
	if base then
		base:Destroy()
		bases[side] = nil
	end
	hpLabels[side] = nil
	baseHP[side] = nil
end

-- Door sits at the BACK of the plot (far edge, away from the road), not the
-- front -- per explicit request, mobs (EndlessModeMobManager.luau) now spawn
-- near the street and march the full depth of the base to reach it, instead
-- of the door guarding the entrance. HP label floats just above it.
local DOOR_BACK_BUFFER = 8

local function spawnBase(side: string, marker: BasePart)
	clearBase(side)

	local doorX = ROAD_HALF_WIDTH + PATCH_WIDTH - DOOR_BACK_BUFFER
	local doorZ = marker.Position.Z
	local doorCenterY = marker.Position.Y + DOOR_HEIGHT / 2

	local baseFolder = Instance.new("Folder")
	baseFolder.Name = "EndlessMode_ClaimBase" .. side
	baseFolder.Parent = marker.Parent

	local frame = Instance.new("Part")
	frame.Name = "DoorFrame"
	frame.Size = Vector3.new(DOOR_THICKNESS * 2, DOOR_HEIGHT + 0.6, DOOR_WIDTH + 0.8)
	frame.CFrame = CFrame.new(doorX, doorCenterY + 0.3, doorZ)
	frame.Anchored = true
	frame.CanCollide = false
	frame.Color = DOOR_FRAME_COLOR
	frame.Material = Enum.Material.Wood
	frame.TopSurface = Enum.SurfaceType.Smooth
	frame.BottomSurface = Enum.SurfaceType.Smooth
	frame.Parent = baseFolder

	-- Prototype only -- CanCollide false (not blocking movement) and not
	-- hinged/openable yet, just marking where the entrance is.
	local door = Instance.new("Part")
	door.Name = "Door"
	door.Size = Vector3.new(DOOR_THICKNESS, DOOR_HEIGHT, DOOR_WIDTH)
	door.CFrame = CFrame.new(doorX, doorCenterY, doorZ)
	door.Anchored = true
	door.CanCollide = false
	door.Color = DOOR_COLOR
	door.Material = Enum.Material.WoodPlanks
	door.TopSurface = Enum.SurfaceType.Smooth
	door.BottomSurface = Enum.SurfaceType.Smooth
	door.Parent = baseFolder

	local hpAnchor = Instance.new("Part")
	hpAnchor.Name = "HPAnchor"
	hpAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
	hpAnchor.Transparency = 1
	hpAnchor.CFrame = CFrame.new(doorX, doorCenterY + DOOR_HEIGHT / 2 + HP_STUDS_UP, doorZ)
	hpAnchor.Anchored = true
	hpAnchor.CanCollide = false
	hpAnchor.Parent = baseFolder

	local hpBillboard = Instance.new("BillboardGui")
	hpBillboard.Name = "HPDisplay"
	hpBillboard.Size = HP_LABEL_SIZE
	hpBillboard.AlwaysOnTop = true
	hpBillboard.Adornee = hpAnchor
	hpBillboard.Parent = hpAnchor

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Size = UDim2.new(1, 0, 1, 0)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Font = Enum.Font.LuckiestGuy
	hpLabel.Text = string.format("%d/%d HP", BASE_MAX_HP, BASE_MAX_HP)
	hpLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
	hpLabel.TextStrokeTransparency = 0
	hpLabel.TextStrokeColor3 = Color3.fromRGB(10, 10, 10)
	hpLabel.TextScaled = true
	hpLabel.Parent = hpBillboard

	bases[side] = baseFolder
	hpLabels[side] = hpLabel
	baseHP[side] = BASE_MAX_HP
end

-- Called by EndlessModeMobManager.luau when a mob reaches the door. Clamped
-- at 0 (not negative) -- what actually happens once it HITS 0 (base lost,
-- respawns, etc.) isn't decided yet, so for now it just sits at 0/MAX,
-- displayed in place, no mobs stop spawning.
function EndlessModeClaimManager.DamageBase(side: string, amount: number)
	local hp = baseHP[side]
	local label = hpLabels[side]
	if not hp or not label then
		return
	end

	hp = math.max(0, hp - amount)
	baseHP[side] = hp
	label.Text = string.format("%d/%d HP", hp, BASE_MAX_HP)
end

-- Lets other managers (EndlessModeMobManager.luau) check whether a side is
-- actively claimed (and by whom) without duplicating the claimedBy table.
function EndlessModeClaimManager.GetOwner(side: string): Player?
	return claimedBy[side]
end

local function tryClaim(player: Player, side: string)
	if not table.find(SIDES, side) then
		return
	end

	local currentOwner = claimedBy[side]
	if currentOwner and currentOwner.Parent then
		-- Still connected -- already taken, reject.
		return
	end

	local marker = findMarker(side)
	if not marker then
		return
	end

	claimedBy[side] = player
	setMarkerClaimed(side, true)
	spawnPatch(side)
	spawnBadge(side, player)
	spawnBase(side, marker)
	endlessModeLandClaimed:FireAllClients(buildState())
end

claimEndlessModeLand.OnServerEvent:Connect(function(player: Player, side: string)
	if typeof(side) ~= "string" then
		return
	end
	tryClaim(player, side)
end)

requestEndlessModeClaimState.OnServerEvent:Connect(function(player: Player)
	endlessModeLandClaimed:FireClient(player, buildState())
end)

Players.PlayerRemoving:Connect(function(player: Player)
	local changed = false
	for _, side in SIDES do
		if claimedBy[side] == player then
			claimedBy[side] = nil
			clearBadge(side)
			clearPatch(side)
			clearBase(side)
			setMarkerClaimed(side, false)
			changed = true
		end
	end
	if changed then
		endlessModeLandClaimed:FireAllClients(buildState())
	end
end)

return EndlessModeClaimManager
