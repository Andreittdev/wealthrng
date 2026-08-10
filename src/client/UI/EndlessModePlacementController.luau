-- Shows a semi-transparent preview of the currently-held Estate (server-
-- reported via EndlessModeHeldEstateUpdated, PetManager.luau) following the
-- mouse/touch position while in Endless Mode, and fires
-- PlaceEndlessModeEstate on click/tap to plant it there. Preview uses the
-- SAME template PetManager.luau clones from (ReplicatedStorage.PetModels /
-- Workspace fallback), so it looks exactly like what actually gets placed.
-- Picking a placed Estate back up doesn't go through here at all -- that's
-- a plain ClickDetector PetManager.luau puts directly on the placed model.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)

local EndlessModePlacementController = {}

local PREVIEW_TRANSPARENCY = 0.5

-- Mirrors PetManager.luau's own findPetTemplate lookup -- can't require a
-- server module from the client, so this small bit of lookup logic is
-- necessarily duplicated (same idiom every other client-side "mirror what
-- the server would do" check in this codebase uses).
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

local function makePreview(template: Model): Model
	local preview = template:Clone()
	preview.Name = "EndlessModePlacementPreview"
	for _, descendant in preview:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Transparency = math.max(descendant.Transparency, PREVIEW_TRANSPARENCY)
		elseif descendant:IsA("ClickDetector") then
			-- Only ever present on an already-PLACED clone (PetManager.luau
			-- adds these to let the owner pick it back up) -- this is a
			-- fresh preview ghost, not clickable.
			descendant:Destroy()
		end
	end
	preview.Parent = Workspace
	return preview
end

function EndlessModePlacementController.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local endlessModeHeldEstateUpdated = remotes:WaitForChild("EndlessModeHeldEstateUpdated")
	local placeEndlessModeEstate = remotes:WaitForChild("PlaceEndlessModeEstate")

	local player = Players.LocalPlayer

	local heldAssetId: string? = nil
	local preview: Model? = nil
	local lastHitPosition: Vector3? = nil

	local function clearPreview()
		if preview then
			preview:Destroy()
			preview = nil
		end
		lastHitPosition = nil
	end

	local function rebuildPreview()
		clearPreview()
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
			preview = makePreview(template)
		end
	end

	endlessModeHeldEstateUpdated.OnClientEvent:Connect(function(assetId: string?)
		heldAssetId = assetId
		rebuildPreview()
	end)

	RunService.RenderStepped:Connect(function()
		if not preview then
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
		raycastParams.FilterDescendantsInstances = { preview, player.Character }

		local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, raycastParams)
		if result then
			lastHitPosition = result.Position
			preview:PivotTo(CFrame.new(result.Position))
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not preview or not heldAssetId or not lastHitPosition then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		placeEndlessModeEstate:FireServer(heldAssetId, lastHitPosition)
	end)
end

return EndlessModePlacementController
