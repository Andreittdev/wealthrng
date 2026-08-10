-- While an Estate is held (equipped + in Endless Mode + not yet placed --
-- visible attached to the player's hand, see PetManager.luau), clicking/
-- tapping anywhere raycasts from the camera through the mouse/touch point
-- and fires PlaceEndlessModeEstate at whatever it hits, planting it there.
-- No separate ground-following ghost preview -- the hand-held model itself
-- (server-side, replicated) is the only visual, per explicit request.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local EndlessModePlacementController = {}

function EndlessModePlacementController.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local endlessModeHeldEstateUpdated = remotes:WaitForChild("EndlessModeHeldEstateUpdated")
	local placeEndlessModeEstate = remotes:WaitForChild("PlaceEndlessModeEstate")

	local player = Players.LocalPlayer

	local heldAssetId: string? = nil

	endlessModeHeldEstateUpdated.OnClientEvent:Connect(function(assetId: string?)
		heldAssetId = assetId
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or not heldAssetId then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
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
		raycastParams.FilterDescendantsInstances = { player.Character }

		local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, raycastParams)
		if result then
			placeEndlessModeEstate:FireServer(heldAssetId, result.Position)
		end
	end)
end

return EndlessModePlacementController
