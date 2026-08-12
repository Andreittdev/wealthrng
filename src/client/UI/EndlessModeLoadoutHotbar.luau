-- 4-square hotbar, bottom-center of screen, ENDLESS MODE ONLY (toggled by
-- MainUI.luau off the same PortalTeleport signal every other Endless-only
-- HUD piece uses) -- per explicit request: up to AssetDatabase.MaxEquipped
-- (4) Estates can be equipped at once now (bumped from 2, see
-- AssetDatabase.luau), and this is how the player picks WHICH ONE of them
-- is actually held/placeable right now. Tapping a filled square fires
-- SelectEndlessModeHeldEstate -- PetManager.luau owns the actual "only one
-- Estate is ever welded in hand at a time" enforcement server-side; this
-- panel just reflects whatever it reports back.
--
-- Deliberately its own small file, not folded into InventoryPanel.luau --
-- that panel is the "big table" for PICKING the loadout (Equip/Unequip,
-- already Estates-only while in Endless Mode via SetEstatesOnly), this is
-- the separate always-on-screen "which one is active right now" strip once
-- it's closed again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local EstateRarityConfig = require(ReplicatedStorage.Modules.EstateRarityConfig)
local Theme = require(script.Parent.Theme)

local EndlessModeLoadoutHotbar = {}

local SLOT_SIZE = 64
local SLOT_GAP = 10
local SLOT_COUNT = 4
local EMPTY_SLOT_COLOR = Color3.fromRGB(50, 50, 56)

function EndlessModeLoadoutHotbar.Create(screenGui: ScreenGui, remotes: Folder)
	local selectEndlessModeHeldEstate = remotes:WaitForChild("SelectEndlessModeHeldEstate")
	local assetUpdated = remotes:WaitForChild("AssetUpdated")
	local endlessModeHeldEstateUpdated = remotes:WaitForChild("EndlessModeHeldEstateUpdated")

	local row = Instance.new("Frame")
	row.Size = UDim2.new(0, SLOT_COUNT * SLOT_SIZE + (SLOT_COUNT - 1) * SLOT_GAP, 0, SLOT_SIZE)
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -20)
	row.BackgroundTransparency = 1
	row.Visible = false
	row.ZIndex = 5
	row.Parent = screenGui
	Theme.AutoScale(screenGui, row, SLOT_COUNT * SLOT_SIZE + (SLOT_COUNT - 1) * SLOT_GAP)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, SLOT_GAP)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = row

	-- Which assetId (if any) each square currently represents -- read by the
	-- square's own click handler at click time, instead of re-connecting
	-- Activated on every render.
	local slotAssetIds: { string? } = {}
	local slotIcons: { ImageLabel } = {}
	local slotStrokes: { UIStroke } = {}

	for slotIndex = 1, SLOT_COUNT do
		local square = Instance.new("Frame")
		square.LayoutOrder = slotIndex
		square.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		square.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
		square.BackgroundTransparency = 0
		square.BorderSizePixel = 0
		square.ZIndex = 5
		square.Parent = row
		Theme.Round(square, UDim.new(0, 10))
		local stroke = Theme.Stroke(square, EMPTY_SLOT_COLOR, 2)
		stroke.Transparency = 0
		slotStrokes[slotIndex] = stroke

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(1, -12, 1, -12)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, 0, 0.5, 0)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = ""
		icon.Visible = false
		icon.ZIndex = 6
		icon.Parent = square
		slotIcons[slotIndex] = icon

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, 0, 1, 0)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.ZIndex = 7
		button.Parent = square
		button.Activated:Connect(function()
			local assetId = slotAssetIds[slotIndex]
			if assetId then
				selectEndlessModeHeldEstate:FireServer(assetId)
			end
		end)
	end

	local equippedAssetIds: { string } = {}
	local heldAssetId: string? = nil

	local function render()
		for slotIndex = 1, SLOT_COUNT do
			local assetId = equippedAssetIds[slotIndex]
			slotAssetIds[slotIndex] = assetId

			local asset = assetId and AssetDatabase.GetAsset(assetId)
			if asset then
				slotIcons[slotIndex].Image = asset.Image
				slotIcons[slotIndex].Visible = true
				local isHeld = assetId == heldAssetId
				slotStrokes[slotIndex].Color = isHeld and Theme.Colors.Accent or EstateRarityConfig.GetColor(asset.Rarity)
				slotStrokes[slotIndex].Thickness = isHeld and 3 or 2
			else
				slotIcons[slotIndex].Visible = false
				slotStrokes[slotIndex].Color = EMPTY_SLOT_COLOR
				slotStrokes[slotIndex].Thickness = 2
			end
		end
	end

	assetUpdated.OnClientEvent:Connect(function(payload: { Equipped: { string } })
		equippedAssetIds = payload.Equipped or {}
		render()
	end)

	endlessModeHeldEstateUpdated.OnClientEvent:Connect(function(assetId: string?)
		heldAssetId = assetId
		render()
	end)

	local handle = {}
	handle.Frame = row
	return handle
end

return EndlessModeLoadoutHotbar
