-- Shared "is this character standing in Endless Mode" check -- a plain
-- world-position test (HumanoidRootPart.Z past ZThreshold), not tied to how
-- they got there (portal, a future TeleportService hop, admin teleport,
-- whatever). Used by any manager that needs to behave differently there
-- (EndlessModeWaveManager.luau, PetManager.luau) -- pulled out to a shared
-- module specifically so the threshold can't drift out of sync between them.

local EndlessModeConfig = {}

-- Comfortably past the hub map's own footprint (its furthest markers sit
-- well under 200 studs from the origin) and well short of Endless Mode's own
-- origin (Z=3000, see MapBuilder.buildEndlessModeArea) -- no ambiguous
-- middle ground between the two areas for a player to be sitting in.
EndlessModeConfig.ZThreshold = 1500

-- Must match MapBuilder.buildEndlessModeArea's own ENDLESS_MODE_ORIGIN/
-- ENDLESS_MODE_GROUND_SIZE -- used to clamp Estate placement (PetManager.luau)
-- to somewhere actually on the ground instead of trusting a client-supplied
-- position outright.
EndlessModeConfig.GroundOrigin = Vector3.new(0, 0, 3000)
EndlessModeConfig.GroundHalfSize = 100

function EndlessModeConfig.IsCharacterInEndlessMode(character: Model?): boolean
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp ~= nil and hrp.Position.Z > EndlessModeConfig.ZThreshold
end

-- Clamps an arbitrary (client-supplied) world position down onto the actual
-- ground plane/footprint -- X/Z clamped to the ground's square bounds, Y
-- forced flat to GroundOrigin.Y regardless of what was passed in.
function EndlessModeConfig.ClampToGround(position: Vector3): Vector3
	local origin = EndlessModeConfig.GroundOrigin
	local half = EndlessModeConfig.GroundHalfSize
	return Vector3.new(math.clamp(position.X, origin.X - half, origin.X + half), origin.Y, math.clamp(position.Z, origin.Z - half, origin.Z + half))
end

return EndlessModeConfig
