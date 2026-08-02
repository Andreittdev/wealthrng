-- Top-left grid of small square icon-style toggle buttons (2 columns), not
-- a column of wide text buttons. Plain icon + bold white/black-outlined
-- caption, no card/background chrome at all -- matches the reference
-- screenshot (and the same look already used for RollPanel's ROLL/UPGRADE
-- buttons). Each button just calls .Toggle() on the matching panel handle
-- passed in from MainUI -- Sidebar itself owns no panel state.
--
-- Also owns the vertical placement of CashHud and LuckSpeedHUD: all three
-- used to be independently anchored (grid from the top, LuckSpeedHUD from
-- the bottom) with nothing coordinating their combined height against the
-- actual screen height, so on a short landscape phone they'd collide in
-- the middle even though each individually "shrank" via its own
-- Theme.AutoScale. They're now laid out sequentially inside ONE container
-- (grid -> CashHud -> LuckSpeedHUD) under a single shared AutoScale, so
-- they're guaranteed not to overlap each other at any scale -- only
-- CashHud/LuckSpeedHUD's own internal AutoScale calls were removed, not
-- their layout logic.

local Theme = require(script.Parent.Theme)

local Sidebar = {}

local BUTTONS = {
	{ Key = "Shop", Text = "Store", Image = "rbxassetid://125269752712900" },
	{ Key = "NetWorth", Text = "Net Worth", Image = "rbxassetid://110412138332805" },
	{ Key = "Inventory", Text = "Inventory", Image = "rbxassetid://105522953472595" },
	{ Key = "Trade", Text = "Trade", Image = "rbxassetid://140723733393985" },
	{ Key = "Settings", Text = "Settings", Image = "rbxassetid://79545550325552" },
	{ Key = "Profile", Text = "Profile", Image = "rbxassetid://139017666357301" },
}

-- Caption overlaps the icon's lower portion (same treatment as
-- RollPanel's ROLL/UPGRADE), not a separate label sitting fully below it.
-- START_Y used to be 150 -- way more top margin than needed once CashHud
-- moved into this same container (it's no longer clearing separate
-- top-of-screen HUDs). 60px comfortably clears Roblox's own top bar with
-- room to spare, without eating into the short vertical room a landscape
-- phone screen has.
local ICON_SIZE = 96
local START_X = 16
local START_Y = 20
local GAP_X = 2
local GAP_Y = 4
local COLUMNS = 2
local REFERENCE_WIDTH = 900

-- Vertical gap between the icon grid / CashHud / LuckSpeedHUD stack pieces.
local STACK_GAP = 14

local LABEL_COLOR = Color3.fromRGB(255, 255, 255)

export type PanelHandles = {
	Inventory: { Toggle: () -> () },
	NetWorth: { Toggle: () -> () },
	Shop: { Toggle: () -> () },
	Trade: { Toggle: () -> () },
	Settings: { Toggle: () -> () },
	Profile: { Toggle: () -> () },
}

function Sidebar.Create(screenGui: ScreenGui, handles: PanelHandles, cashHudFrame: Frame, luckSpeedHudFrame: Frame)
	local rows = math.ceil(#BUTTONS / COLUMNS)
	local gridWidth = COLUMNS * ICON_SIZE + (COLUMNS - 1) * GAP_X
	local gridHeight = rows * ICON_SIZE + (rows - 1) * GAP_Y

	local cashHudHeight = cashHudFrame.Size.Y.Offset
	local luckSpeedHudHeight = luckSpeedHudFrame.Size.Y.Offset

	local containerWidth = math.max(gridWidth, cashHudFrame.Size.X.Offset, luckSpeedHudFrame.Size.X.Offset)
	local containerHeight = gridHeight + STACK_GAP + cashHudHeight + STACK_GAP + luckSpeedHudHeight

	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, containerWidth, 0, containerHeight)
	container.Position = UDim2.new(0, START_X, 0, START_Y)
	container.BackgroundTransparency = 1
	container.Parent = screenGui
	Theme.AutoScale(screenGui, container, REFERENCE_WIDTH)

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
		button.Parent = container

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(1, 0, 1, 0)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = buttonData.Image or ""
		icon.ZIndex = 1
		icon.Parent = button

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

		local panelHandle = handles[buttonData.Key]
		if panelHandle then
			button.Activated:Connect(function()
				panelHandle.Toggle()
			end)
		end
	end

	cashHudFrame.Parent = container
	cashHudFrame.AnchorPoint = Vector2.new(0, 0)
	cashHudFrame.Position = UDim2.new(0, 0, 0, gridHeight + STACK_GAP)

	luckSpeedHudFrame.Parent = container
	luckSpeedHudFrame.AnchorPoint = Vector2.new(0, 0)
	luckSpeedHudFrame.Position = UDim2.new(0, 0, 0, gridHeight + STACK_GAP + cashHudHeight + STACK_GAP)

	local handle = {}
	handle.Frame = container
	return handle
end

return Sidebar
