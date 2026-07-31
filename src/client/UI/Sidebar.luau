-- Top-left grid of small square icon-style toggle buttons (2 columns), not
-- a column of wide text buttons. Plain icon + bold white/black-outlined
-- caption, no card/background chrome at all -- matches the reference
-- screenshot (and the same look already used for RollPanel's ROLL/UPGRADE
-- buttons). Each button just calls .Toggle() on the matching panel handle
-- passed in from MainUI -- Sidebar itself owns no panel state.
--
-- The whole grid sits in one container Frame with a Theme.AutoScale UIScale
-- (see Theme.luau) so it shrinks as one unit on narrow phone screens
-- instead of staying a fixed 76px per button regardless of screen size.

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
local ICON_SIZE = 96
local START_X = 16
local START_Y = 150
local GAP_X = 2
local GAP_Y = 4
local COLUMNS = 2
local REFERENCE_WIDTH = 900

local LABEL_COLOR = Color3.fromRGB(255, 255, 255)

export type PanelHandles = {
	Inventory: { Toggle: () -> () },
	NetWorth: { Toggle: () -> () },
	Shop: { Toggle: () -> () },
	Trade: { Toggle: () -> () },
	Settings: { Toggle: () -> () },
	Profile: { Toggle: () -> () },
}

function Sidebar.Create(screenGui: ScreenGui, handles: PanelHandles, cashHudFrame: Frame?)
	local rows = math.ceil(#BUTTONS / COLUMNS)
	local containerWidth = COLUMNS * ICON_SIZE + (COLUMNS - 1) * GAP_X
	local containerHeight = rows * ICON_SIZE + (rows - 1) * GAP_Y

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

		-- Cash HUD moved here from its old fixed top-right corner spot --
		-- reparented into this same AutoScale container so it scales as one
		-- unit with the rest of the grid on narrow screens, positioned
		-- directly under whichever button is "Profile" (found by Key, not a
		-- hardcoded index, so this still lands correctly if BUTTONS is ever
		-- reordered).
		if cashHudFrame and buttonData.Key == "Profile" then
			cashHudFrame.Parent = container
			cashHudFrame.AnchorPoint = Vector2.new(0.5, 0)
			cashHudFrame.Position = UDim2.new(0, x + ICON_SIZE / 2, 0, y + ICON_SIZE + GAP_Y)
		end
	end
end

return Sidebar
