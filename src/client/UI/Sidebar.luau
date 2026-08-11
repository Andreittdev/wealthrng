-- Top-left grid of small square icon-style toggle buttons (2 columns), not
-- a column of wide text buttons. Plain icon + bold white/black-outlined
-- caption, no card/background chrome at all -- matches the reference
-- screenshot (and the same look already used for RollPanel's ROLL/UPGRADE
-- buttons). Each button just calls .Toggle() on the matching panel handle
-- passed in from MainUI -- Sidebar itself owns no panel state.
--
-- Also owns CashHud/LuckSpeedHUD's placement -- CashHud is stacked
-- directly below the icon grid (same top-anchored container, one
-- AutoScale, per explicit request), while LuckSpeedHUD stays its own
-- independent bottom-left cluster. (Theme.AutoScale's height-awareness
-- still shrinks each cluster on a short screen, but doesn't guarantee zero
-- overlap between the two separately-anchored ones the way a single
-- shared stack would.)

local Players = game:GetService("Players")

local Theme = require(script.Parent.Theme)

local Sidebar = {}

local BUTTONS = {
	{ Key = "Shop", Text = "Store", Image = "rbxassetid://125269752712900" },
	{ Key = "NetWorth", Text = "Net Worth", Image = "rbxassetid://110412138332805" },
	{ Key = "Inventory", Text = "Inventory", Image = "rbxassetid://105522953472595" },
	{ Key = "Trade", Text = "Trade", Image = "rbxassetid://140723733393985" },
	{ Key = "Settings", Text = "Settings", Image = "rbxassetid://79545550325552" },
	{ Key = "Profile", Text = "Profile", Image = "" },
}

-- Caption overlaps the icon's lower portion (same treatment as
-- RollPanel's ROLL/UPGRADE), not a separate label sitting fully below it.
-- START_Y history: 150 (original) -> 20 (chasing a mobile landscape
-- complaint, overshot -- collided with Roblox's own top bar on PC) -> 70
-- -> 100 -> 180 (chasing PC "still too high" feedback). That last climb
-- reintroduced the ORIGINAL problem this whole saga started from: START_Y
-- is a FIXED pixel offset that Theme.AutoScale never shrinks (only the
-- container's SIZE), so on a short landscape phone, a 180px top margin
-- alone eats most of the available height, pushing the icon+cash cluster
-- down into (or past) the independent Luck/Speed cluster at the bottom.
-- PREFERRED_START_Y is now just the DESKTOP target -- updateTopPosition
-- below shrinks it back down toward MIN_START_Y on short screens instead,
-- computed from the actual current scale/screen height every resize, so
-- it can never overlap the bottom cluster no matter how short the screen is.
local ICON_SIZE = 96
local START_X = 16
local PREFERRED_START_Y = 120
local MIN_START_Y = 60
local GAP_X = 2
local GAP_Y = 4
local COLUMNS = 2
local REFERENCE_WIDTH = 900
-- Mirrors Theme.AutoScale's own internal AUTOSCALE_REFERENCE_HEIGHT --
-- Sidebar can't just call Theme.AutoScale for its own top/bottom clusters
-- anymore (see updateLayout below for why), so it needs its own copy of
-- the same height reference to keep scaling consistent with every other
-- panel.
local HEIGHT_REFERENCE = 700
-- The two clusters now scale INDEPENDENTLY (see updateLayout) -- explicit
-- request that the icon grid/CashHud read comfortably large even on a
-- cramped phone screen, while the Luck/Roll Speed badges stay small and
-- compact rather than matching. TOP_MIN_SCALE is the floor for the
-- former; BOTTOM_MIN_SCALE (deliberately lower) is the floor for the
-- latter -- LuckSpeedHUD is computed and shrunk FIRST, then the icon
-- cluster gets whatever room that leaves, so a bigger icon floor can
-- never force LuckSpeedHUD to grow to match it.
local TOP_MIN_SCALE = 0.5
local BOTTOM_MIN_SCALE = 0.35
-- Extra shrink applied to JUST CashHud (on top of iconUIScale) once the
-- top cluster is already in its mobile-shrinking regime (topScale < 1) --
-- explicit request that Cash read a bit smaller specifically on phone,
-- without touching the icon buttons themselves or anything on PC (where
-- topScale sits at 1 and this never applies).
local CASH_MOBILE_SCALE = 0.8
-- Extra breathing room beyond the bare-minimum fit, so the two clusters
-- end up with a real visible gap instead of an exact mathematical
-- touch (which any small rendering slop -- text stroke overflow, corner
-- radius, etc. -- turns back into a visible overlap).
local SAFETY_GAP = 10

-- Vertical gap between CashHud and LuckSpeedHUD in the bottom-left
-- cluster, and between that cluster and the bottom of the screen.
local STACK_GAP = 14
local BOTTOM_MARGIN = 15

local LABEL_COLOR = Color3.fromRGB(255, 255, 255)

export type PanelHandles = {
	Inventory: { Toggle: () -> () },
	NetWorth: { Toggle: () -> () },
	Shop: { Toggle: () -> () },
	Trade: { Toggle: () -> () },
	Settings: { Toggle: () -> () },
	Profile: { Toggle: () -> () },
}

function Sidebar.Create(screenGui: ScreenGui, handles: PanelHandles, cashHudFrame: Frame, luckSpeedHudFrame: Frame, endlessModeCashHudFrame: Frame?)
	local rows = math.ceil(#BUTTONS / COLUMNS)
	local gridWidth = COLUMNS * ICON_SIZE + (COLUMNS - 1) * GAP_X
	local gridHeight = rows * ICON_SIZE + (rows - 1) * GAP_Y

	local cashHudHeight = cashHudFrame.Size.Y.Offset
	local topWidth = math.max(gridWidth, cashHudFrame.Size.X.Offset)
	local topHeight = gridHeight + STACK_GAP + cashHudHeight
	local bottomHeight = luckSpeedHudFrame.Size.Y.Offset

	-- iconContainer is now purely a vertical UIListLayout stack of exactly 2
	-- children (gridFrame, then cashHudFrame) instead of both being manually
	-- Position-ed by hand-computed pixel offsets that had to be kept in sync
	-- with gridHeight/STACK_GAP/cashHudHeight by eye. A UIListLayout can't
	-- render its 2nd child anywhere but directly after (below) the 1st, no
	-- matter what scale/clamp math runs elsewhere -- removes an entire class
	-- of "the numbers looked right but something still overlapped on one
	-- specific device" bugs the constant-tuning approach kept running into.
	local iconContainer = Instance.new("Frame")
	iconContainer.Size = UDim2.new(0, topWidth, 0, topHeight)
	iconContainer.Position = UDim2.new(0, START_X, 0, PREFERRED_START_Y)
	iconContainer.BackgroundTransparency = 1
	iconContainer.Parent = screenGui
	-- NOT Theme.AutoScale -- that clamps its own Scale to a flat 0.6 floor
	-- with no awareness of the independent bottom cluster (LuckSpeedHUD),
	-- which is exactly how the two ended up overlapping on a short
	-- landscape phone: the icon+cash cluster refused to shrink past 0.6,
	-- and the top-position clamp below had nowhere left to push it except
	-- straight into LuckSpeedHUD. updateLayout (below) computes this
	-- UIScale's value itself, jointly with the bottom cluster's, so it can
	-- shrink BELOW 0.6 on a screen too short to fit both otherwise.
	local iconUIScale = Instance.new("UIScale")
	iconUIScale.Parent = iconContainer

	local stackLayout = Instance.new("UIListLayout")
	stackLayout.FillDirection = Enum.FillDirection.Vertical
	stackLayout.SortOrder = Enum.SortOrder.LayoutOrder
	stackLayout.Padding = UDim.new(0, STACK_GAP)
	stackLayout.Parent = iconContainer

	local gridFrame = Instance.new("Frame")
	gridFrame.LayoutOrder = 1
	gridFrame.Size = UDim2.new(0, gridWidth, 0, gridHeight)
	gridFrame.BackgroundTransparency = 1
	gridFrame.Parent = iconContainer

	-- Exposed on `handle` below (only Inventory needed so far) so
	-- OnboardingTutorial.luau can point its Step 2 arrow/glow at the real
	-- button instead of guessing its screen position.
	local buttonsByKey: { [string]: TextButton } = {}

	for index, buttonData in BUTTONS do
		local row = math.floor((index - 1) / COLUMNS)
		local col = (index - 1) % COLUMNS
		local x = col * (ICON_SIZE + GAP_X)
		local y = row * (ICON_SIZE + GAP_Y)

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
		button.Position = UDim2.new(0, x, 0, y)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.AutoButtonColor = false
		button.Parent = gridFrame

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(1, 0, 1, 0)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = buttonData.Image or ""
		icon.ZIndex = 1
		icon.Parent = button

		-- Profile's icon is the player's own avatar headshot instead of a
		-- static image -- fetched async (GetUserThumbnailAsync yields) so it
		-- doesn't block building the rest of the grid, then rounded into a
		-- circle to actually read as an avatar, not a square photo.
		if buttonData.Key == "Profile" then
			-- Crop instead of Fit -- Roblox's headshot thumbnail has empty
			-- margin baked in around the face, so Fit (same as the other
			-- icons use) left the actual face reading smaller than every
			-- other button's icon despite the same bounding box. Crop fills
			-- the full square/circle instead.
			icon.ScaleType = Enum.ScaleType.Crop
			-- Full ICON_SIZE, unchanged -- the face reads at the exact same
			-- scale as every other button's art, not shrunk down.
			icon.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
			Theme.Round(icon, UDim.new(1, 0))

			-- A separate clipping wrapper, shorter than the full button and
			-- pinned to the top, is what actually hides the overflow -- the
			-- full-size circle above still renders at full scale inside it,
			-- only the bottom sliver (where the "PROFILE" caption sits) gets
			-- cut away instead of the whole image being shrunk to fit.
			local iconMask = Instance.new("Frame")
			iconMask.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE - 20)
			iconMask.Position = UDim2.new(0, 0, 0, 0)
			iconMask.BackgroundTransparency = 1
			iconMask.ClipsDescendants = true
			iconMask.ZIndex = icon.ZIndex
			iconMask.Parent = button
			icon.Parent = iconMask

			task.spawn(function()
				local ok, content = pcall(function()
					return Players:GetUserThumbnailAsync(
						Players.LocalPlayer.UserId,
						Enum.ThumbnailType.HeadShot,
						Enum.ThumbnailSize.Size100x100
					)
				end)
				if ok and content then
					icon.Image = content
				end
			end)
		end

		local caption = Instance.new("TextLabel")
		caption.Size = UDim2.new(1, 10, 0, 18)
		caption.AnchorPoint = Vector2.new(0.5, 1)
		caption.Position = UDim2.new(0.5, 0, 1, -4)
		caption.BackgroundTransparency = 1
		caption.Font = Theme.Fonts.Header
		caption.TextScaled = true
		caption.Text = buttonData.Text
		caption.TextColor3 = LABEL_COLOR
		caption.TextStrokeTransparency = 0
		caption.TextStrokeColor3 = Color3.new(0, 0, 0)
		caption.ZIndex = 2
		caption.Parent = button

		buttonsByKey[buttonData.Key] = button

		local panelHandle = handles[buttonData.Key]
		if panelHandle then
			button.Activated:Connect(function()
				panelHandle.Toggle()
			end)
		end
	end

	-- CashHud stacks directly below the icon grid via the UIListLayout above
	-- -- no manual Position needed, the layout places it.
	cashHudFrame.LayoutOrder = 2
	cashHudFrame.AnchorPoint = Vector2.new(0, 0)
	cashHudFrame.Position = UDim2.new(0, 0, 0, 0)
	cashHudFrame.Parent = iconContainer
	-- Extra scale layered on top of iconUIScale, see CASH_MOBILE_SCALE.
	local cashUIScale = Instance.new("UIScale")
	cashUIScale.Parent = cashHudFrame

	-- EndlessModeCashHud shares this EXACT stacked slot (same LayoutOrder) --
	-- per explicit "under Inventory" request, it swaps in right where CashHud
	-- normally sits, below the icon grid, instead of getting its own
	-- independent position. UIListLayout skips Invisible children
	-- automatically, and MainUI.luau already keeps the two mutually
	-- exclusive (CashHud hides the instant Endless Mode's HUD shows), so
	-- there's never a moment both actually occupy the slot at once.
	local endlessCashUIScale: UIScale? = nil
	if endlessModeCashHudFrame then
		endlessModeCashHudFrame.LayoutOrder = 2
		endlessModeCashHudFrame.AnchorPoint = Vector2.new(0, 0)
		endlessModeCashHudFrame.Position = UDim2.new(0, 0, 0, 0)
		endlessModeCashHudFrame.Parent = iconContainer
		endlessCashUIScale = Instance.new("UIScale")
		endlessCashUIScale.Parent = endlessModeCashHudFrame
	end

	-- LuckSpeedHUD stays its own independent bottom-left cluster.
	local bottomContainer = Instance.new("Frame")
	bottomContainer.Size = luckSpeedHudFrame.Size
	bottomContainer.AnchorPoint = Vector2.new(0, 1)
	bottomContainer.Position = UDim2.new(0, START_X, 1, -BOTTOM_MARGIN)
	bottomContainer.BackgroundTransparency = 1
	bottomContainer.Parent = screenGui
	-- Same reasoning as iconUIScale above -- driven by updateLayout, not
	-- Theme.AutoScale, so both clusters always shrink together.
	local bottomUIScale = Instance.new("UIScale")
	bottomUIScale.Parent = bottomContainer

	luckSpeedHudFrame.Parent = bottomContainer
	luckSpeedHudFrame.AnchorPoint = Vector2.new(0, 0)
	luckSpeedHudFrame.Position = UDim2.new(0, 0, 0, 0)

	-- LuckSpeedHUD's scale is resolved FIRST, independently (plain width/
	-- height scale, its own smaller floor) -- it's small to begin with, so
	-- it never needs the icon cluster's bigger floor. The icon+CashHud
	-- cluster's scale/Y offset are resolved SECOND, against whatever room
	-- LuckSpeedHUD's now-known real footprint leaves, via the same
	-- fitScale approach as before -- so on a screen too short to fit both
	-- at their preferred floors, they still can never be forced to
	-- overlap (see the original bug: a single shared scale pinned at its
	-- floor collided with LuckSpeedHUD below it).
	local function updateLayout()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end

		local widthScale = size.X / REFERENCE_WIDTH
		local heightScale = size.Y / HEIGHT_REFERENCE
		local baseScale = math.min(widthScale, heightScale)

		local bottomScale = math.clamp(baseScale, BOTTOM_MIN_SCALE, 1)
		bottomUIScale.Scale = bottomScale

		local availableHeight = size.Y - MIN_START_Y - STACK_GAP - SAFETY_GAP - BOTTOM_MARGIN - bottomHeight * bottomScale
		local fitScale = topHeight > 0 and (availableHeight / topHeight) or 1
		local topScale = math.clamp(math.min(widthScale, heightScale, fitScale), TOP_MIN_SCALE, 1)
		iconUIScale.Scale = topScale
		cashUIScale.Scale = topScale < 1 and CASH_MOBILE_SCALE or 1
		if endlessCashUIScale then
			endlessCashUIScale.Scale = cashUIScale.Scale
		end

		local bottomClusterTop = size.Y - BOTTOM_MARGIN - bottomHeight * bottomScale
		local maxStartY = bottomClusterTop - topHeight * topScale - STACK_GAP - SAFETY_GAP
		local startY = math.clamp(math.min(PREFERRED_START_Y, maxStartY), MIN_START_Y, PREFERRED_START_Y)
		iconContainer.Position = UDim2.new(0, START_X, 0, startY)
	end

	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateLayout)
	updateLayout()

	-- Two independent clusters now (see header comment) -- callers that
	-- need to hide/show "the sidebar" (e.g. MainUI.luau while a modal or
	-- the LARP Battles zone is active) toggle both.
	local handle = {}
	handle.Frame = iconContainer
	handle.BottomFrame = bottomContainer
	handle.InventoryButton = buttonsByKey.Inventory
	-- Exposed so MainUI.luau can hide individual icons (e.g. everything but
	-- Inventory/Shop while inside Endless Mode) without Sidebar needing to
	-- know why.
	handle.Buttons = buttonsByKey
	return handle
end

return Sidebar
