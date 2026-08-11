-- While an Estate is held (equipped + in Endless Mode + not yet placed --
-- visible attached in front of the player, see PetManager.luau), a
-- semi-transparent ghost of the FULL-SIZE placed building follows the
-- mouse/touch position on the ground, so there's a clear preview of where
-- it'll land before committing. Clicking/tapping fires PlaceEndlessModeEstate
-- at the ghost's current spot. Picking a placed Estate back up doesn't go
-- through here at all -- that's a plain ClickDetector PetManager.luau puts
-- directly on the placed model.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)

local EndlessModePlacementController = {}

local GHOST_TRANSPARENCY = 0.5
-- Must match PetManager.luau's own ENDLESS_MODE_PET_SCALE -- the ghost
-- previews the FULL-SIZE placed result, not the small held-in-hand version.
-- Dropped from 2.5 to 1 (natural/unscaled) per explicit "very big and
-- looks damaged" feedback -- worth checking whether that was purely the
-- scale or a deeper geometry issue with this specific model.
local GHOST_SCALE = 1

-- Mirrors PetManager.luau's own findPetTemplate lookup -- can't require a
-- server module from the client, so this small bit of lookup logic is
-- necessarily duplicated (same idiom every other client-side "mirror what
-- the server would do" check in this codebase uses).
--
-- Unlike the server-side version, the Workspace fallback here is NOT
-- reliable -- ReplicatedStorage always fully replicates to every client
-- regardless of distance, but a template merely sitting loose in Workspace
-- is subject to normal content streaming, and this whole feature only
-- matters 3000+ studs away in Endless Mode. A streamed-out template still
-- exists as an empty shell (FindFirstChild succeeds, GetBoundingBox comes
-- back (0,0,0)) with no real geometry client-side, silently producing an
-- invisible ghost. Every pet model needs a copy under
-- ReplicatedStorage.PetModels for this to work -- confirmed by moving
-- "Studio Apartment" there.
local function findPetTemplate(name: string, id: string): Model?
	local petsFolder = ReplicatedStorage:FindFirstChild("PetModels")
	if petsFolder then
		local byName = petsFolder:FindFirstChild(name)
		if byName and byName:IsA("Model") then
			return byName
		end
		local byId = petsFolder:FindFirstChild(id)
		if byId and byId:IsA("Model") then
			return byId
		end
	end

	local byNameWorkspace = Workspace:FindFirstChild(name)
	if byNameWorkspace and byNameWorkspace:IsA("Model") then
		return byNameWorkspace
	end
	local byIdWorkspace = Workspace:FindFirstChild(id)
	if byIdWorkspace and byIdWorkspace:IsA("Model") then
		return byIdWorkspace
	end

	return nil
end

-- Returns the ghost AND how far its own pivot sits above its bounding box's
-- BOTTOM -- imported models frequently have an off-center pivot (same issue
-- PetManager.luau's own bounding-box-center anchor works around for the
-- real held/placed versions), so placing the ghost by its raw pivot alone
-- can bury most of it below the ground instead of standing it on top.
local function makeGhost(template: Model): (Model, number)
	local ghost = template:Clone()
	ghost.Name = "EndlessModePlacementGhost"

	-- Parented BEFORE ScaleTo/GetBoundingBox below, not after -- calling
	-- either on a clone that isn't in the DataModel yet produced wildly
	-- inconsistent results server-side (PetManager.luau hit the exact same
	-- bug: a SMALLER scale measuring BIGGER than no scale at all), which
	-- explains the "gigantic"/"looks damaged" ghost -- these APIs need the
	-- model actually parented somewhere real to compute/apply correctly.
	ghost.Parent = Workspace
	ghost:ScaleTo(GHOST_SCALE)

	for _, descendant in ghost:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Transparency = math.max(descendant.Transparency, GHOST_TRANSPARENCY)
		elseif descendant:IsA("ClickDetector") then
			-- Only ever present on an already-PLACED clone (PetManager.luau
			-- adds these to let the owner pick it back up) -- this is a
			-- fresh preview ghost, not clickable.
			descendant:Destroy()
		end
	end

	local boundingCFrame, size = ghost:GetBoundingBox()
	local pivotY = ghost:GetPivot().Position.Y
	local bottomY = boundingCFrame.Position.Y - size.Y / 2
	local groundOffset = pivotY - bottomY

	return ghost, groundOffset
end

function EndlessModePlacementController.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local endlessModeHeldEstateUpdated = remotes:WaitForChild("EndlessModeHeldEstateUpdated")
	local placeEndlessModeEstate = remotes:WaitForChild("PlaceEndlessModeEstate")

	local player = Players.LocalPlayer

	local heldAssetId: string? = nil
	local ghost: Model? = nil
	local ghostGroundOffset = 0
	local lastHitPosition: Vector3? = nil

	local function clearGhost()
		if ghost then
			ghost:Destroy()
			ghost = nil
		end
		lastHitPosition = nil
	end

	local function rebuildGhost()
		clearGhost()
		if not heldAssetId then
			return
		end

		local asset = AssetDatabase.GetAsset(heldAssetId)
		local item = not asset and ItemDatabase.GetItem(heldAssetId)
		local name = (asset and asset.Name) or (item and item.Name)
		local id = (asset and asset.Id) or (item and item.Id) or heldAssetId
		if not name then
			return
		end

		local template = findPetTemplate(name, id)
		if template then
			ghost, ghostGroundOffset = makeGhost(template)
		end
	end

	endlessModeHeldEstateUpdated.OnClientEvent:Connect(function(assetId: string?)
		heldAssetId = assetId
		rebuildGhost()
	end)

	RunService.RenderStepped:Connect(function()
		if not ghost then
			return
		end

		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end

		local mouseLocation = UserInputService:GetMouseLocation()
		local unitRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = { ghost, player.Character }

		local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, raycastParams)
		if result then
			lastHitPosition = result.Position
			ghost:PivotTo(CFrame.new(result.Position + Vector3.new(0, ghostGroundOffset, 0)))
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not ghost or not heldAssetId or not lastHitPosition then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		placeEndlessModeEstate:FireServer(heldAssetId, lastHitPosition)
	end)
end

return EndlessModePlacementController
