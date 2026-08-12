-- 4-square hotbar, ENDLESS MODE ONLY (toggled by MainUI.luau off the same
-- PortalTeleport signal every other Endless-only HUD piece uses) -- per
-- explicit request: up to AssetDatabase.MaxEquippedEndlessMode (4) Estates
-- can be equipped at once while actually IN Endless Mode (the Hub's own
-- MaxEquipped stays at 2, per explicit "in lobby sa poti da equip numai la
-- 2 Estates" follow-up -- see AssetDatabase.luau/AssetManager.luau), and
-- this is how the player picks WHICH ONE of them is actually held/placeable
-- right now. Tapping a filled square fires SelectEndlessModeHeldEstate --
-- PetManager.luau owns the actual "only one Estate is ever welded in hand
-- at a time" enforcement server-side; this panel just reflects whatever it
-- reports back. Each slot also shows its placement cost underneath
-- (EndlessModeBuildingConfig.GetPlacementCost, same formula PetManager.luau
-- charges EndlessModeCash against on actual placement), per explicit
-- request, so the player knows what they're committing to before placing.
--
-- The 4 Crate-exclusive Estates (Storage Unit/Premium Restaurant/Central
-- Bank/Dream Castle) are real AssetDatabase Assets now (session.
-- OwnedAssets/EquippedAssets, see AssetDatabase.luau's own comment) -- they
-- occupy an ordinary slot here like any other Estate, no special-casing
-- needed.
--
-- Deliberately its own small file, not folded into InventoryPanel.luau --
-- that panel is the "big table" for PICKING the loadout (Equip/Unequip,
-- already Estates-only while in Endless Mode via SetEstatesOnly), this is
-- the separate always-on-screen "which one is active right now" strip once
-- it's closed again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local EstateRarityConfig = require(ReplicatedStorage.Modules.EstateRarityConfig)
local EndlessModeBuildingConfig = require(ReplicatedStorage.Modules.EndlessModeBuildingConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local EndlessModeLoadoutHotbar = {}

-- Bumped up from 64 and moved higher off the bottom edge, per explicit
-- request -- bigger/easier to read, and leaves room underneath each square
-- for its own price label.
local SLOT_SIZE = 96
local SLOT_GAP = 14
local SLOT_COUNT = 4
local PRICE_LABEL_HEIGHT = 22
local PRICE_LABEL_GAP = 4
local SLOT_CONTAINER_HEIGHT = SLOT_SIZE + PRICE_LABEL_GAP + PRICE_LABEL_HEIGHT
local EMPTY_SLOT_COLOR = Color3.fromRGB(50, 50, 56)

function EndlessModeLoadoutHotbar.Create(screenGui: ScreenGui, remotes: Folder)
	local selectEndlessModeHeldEstate = remotes:WaitForChild("SelectEndlessModeHeldEstate")
	local assetUpdated = remotes:WaitForChild("AssetUpdated")
	local endlessModeHeldEstateUpdated = remotes:WaitForChild("EndlessModeHeldEstateUpdated")

	local row = Instance.new("Frame")
	row.Size = UDim2.new(0, SLOT_COUNT * SLOT_SIZE + (SLOT_COUNT - 1) * SLOT_GAP, 0, SLOT_CONTAINER_HEIGHT)
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -40)
	row.BackgroundTransparency = 1
	row.Visible = false
	row.ZIndex = 5
	row.Parent = screenGui
	Theme.AutoScale(screenGui, row, SLOT_COUNT * SLOT_SIZE + (SLOT_COUNT - 1) * SLOT_GAP)

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, SLOT_GAP)
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Parent = row

	-- Which assetId (if any) each square currently represents -- read by the
	-- square's own click handler at click time, instead of re-connecting
	-- Activated on every render.
	local slotAssetIds: { string? } = {}
	local slotIcons: { ImageLabel } = {}
	local slotStrokes: { UIStroke } = {}
	local slotPriceLabels: { TextLabel } = {}

	for slotIndex = 1, SLOT_COUNT do
		-- One per slot -- stacks the icon square and its price label
		-- vertically, so the outer row's own horizontal UIListLayout can
		-- still just lay out 4 equal columns without knowing about the
		-- price label at all.
		local slotContainer = Instance.new("Frame")
		slotContainer.LayoutOrder = slotIndex
		slotContainer.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_CONTAINER_HEIGHT)
		slotContainer.BackgroundTransparency = 1
		slotContainer.ZIndex = 5
		slotContainer.Parent = row

		local square = Instance.new("Frame")
		square.Size = UDim2.new(0, SLOT_SIZE, 0, SLOT_SIZE)
		square.Position = UDim2.new(0, 0, 0, 0)
		square.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
		square.BackgroundTransparency = 0
		square.BorderSizePixel = 0
		square.ZIndex = 5
		square.Parent = slotContainer
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

		local priceLabel = Theme.Label(slotContainer, UDim2.new(1, 0, 0, PRICE_LABEL_HEIGHT), "")
		priceLabel.Position = UDim2.new(0, 0, 0, SLOT_SIZE + PRICE_LABEL_GAP)
		priceLabel.TextXAlignment = Enum.TextXAlignment.Center
		priceLabel.TextColor3 = Theme.Colors.Success
		priceLabel.ZIndex = 5
		slotPriceLabels[slotIndex] = priceLabel

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, 0, 1, 0)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.ZIndex = 7
		button.Parent = slotContainer
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
				local placementCost = EndlessModeBuildingConfig.GetPlacementCost(asset.Id, asset.Rarity)
				slotPriceLabels[slotIndex].Text = NumberFormat.FormatCash(placementCost)
				slotPriceLabels[slotIndex].Visible = true
			else
				slotIcons[slotIndex].Visible = false
				slotStrokes[slotIndex].Color = EMPTY_SLOT_COLOR
				slotStrokes[slotIndex].Thickness = 2
				slotPriceLabels[slotIndex].Visible = false
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
