-- Ground-level range circle for whichever placed Damage-role Estate is
-- currently selected (same EndlessModeBuildingSelected payload
-- EndlessModeBuildingPanel.luau's stat panel already reads) -- per explicit
-- request, so the player can actually SEE how far it reaches instead of
-- just reading a number. A flat, translucent disc (Roblox's Cylinder part
-- shape rotated to lie flat) sized to the building's real Range -- appears/
-- disappears exactly when the stat panel does, and only for Damage
-- buildings (Tank/Spawner have no range stat to show).

local Workspace = game:GetService("Workspace")

local EndlessModeRangeIndicator = {}

local RING_HEIGHT_STUDS = 0.2
local RING_COLOR = Color3.fromRGB(255, 90, 90)
local RING_TRANSPARENCY = 0.75
-- `position` is the STORED ground-level CFrame (same one the building's own
-- Model gets PivotTo'd above by half its own height) -- sitting the ring's
-- CENTER exactly there put half its thin height literally below the ground
-- tiles, reading as "buried". A small clearance floats the whole disc just
-- above the surface instead.
local RING_GROUND_CLEARANCE_STUDS = 0.5

function EndlessModeRangeIndicator.Init(remotes: Folder)
	local endlessModeBuildingSelected = remotes:WaitForChild("EndlessModeBuildingSelected")

	local ring: Part? = nil

	local function clearRing()
		if ring then
			ring:Destroy()
			ring = nil
		end
	end

	local function showRing(position: Vector3, range: number)
		clearRing()

		local part = Instance.new("Part")
		part.Name = "EndlessModeRangeIndicator"
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(RING_HEIGHT_STUDS, range * 2, range * 2)
		-- Cylinder's flat round faces point along local X by default --
		-- rotating 90 degrees around Z tips them to face up/down instead,
		-- so it lies flat on the ground like a disc rather than standing
		-- upright like a drum.
		part.CFrame = CFrame.new(position + Vector3.new(0, RING_GROUND_CLEARANCE_STUDS, 0)) * CFrame.Angles(0, 0, math.rad(90))
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.Material = Enum.Material.Neon
		part.Color = RING_COLOR
		part.Transparency = RING_TRANSPARENCY
		part.Parent = Workspace

		ring = part
	end

	endlessModeBuildingSelected.OnClientEvent:Connect(function(payload: { Role: string?, Position: Vector3?, Range: number? }?)
		if payload and payload.Role == "Damage" and payload.Position and payload.Range then
			showRing(payload.Position, payload.Range)
		else
			clearRing()
		end
	end)
end

return EndlessModeRangeIndicator
