-- Top-left grid of small square icon-style toggle buttons (2 columns), not
-- a column of wide text buttons -- matches the reference's square icon
-- layout. Each button just calls .Toggle() on the matching panel handle
-- passed in from MainUI -- Sidebar itself owns no panel state.
--
-- The whole grid sits in one container Frame with a Theme.AutoScale UIScale
-- (see Theme.luau) so it shrinks as one unit on narrow phone screens
-- instead of staying a fixed 76px per button regardless of screen size.

local Theme = require(script.Parent.Theme)

local Sidebar = {}

local BUTTONS = {
	{ Key = "Inventory", Text = "Inventory" },
	{ Key = "NetWorth", Text = "Net Worth" },
	{ Key = "Shop", Text = "Store" },
	{ Key = "Trade", Text = "Trade" },
	{ Key = "Settings", Text = "Settings" },
	{ Key = "Profile", Text = "Profile" },
}

local BUTTON_SIZE = 76
local START_X = 16
local START_Y = 16
local GAP = 8
local COLUMNS = 2
local REFERENCE_WIDTH = 900

export type PanelHandles = {
	Inventory: { Toggle: () -> () },
	NetWorth: { Toggle: () -> () },
	Shop: { Toggle: () -> () },
	Trade: { Toggle: () -> () },
	Settings: { Toggle: () -> () },
	Profile: { Toggle: () -> () },
}

function Sidebar.Create(screenGui: ScreenGui, handles: PanelHandles)
	local rows = math.ceil(#BUTTONS / COLUMNS)
	local containerWidth = COLUMNS * BUTTON_SIZE + (COLUMNS - 1) * GAP
	local containerHeight = rows * BUTTON_SIZE + (rows - 1) * GAP

	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, containerWidth, 0, containerHeight)
	container.Position = UDim2.new(0, START_X, 0, START_Y)
	container.BackgroundTransparency = 1
	container.Parent = screenGui
	Theme.AutoScale(screenGui, container, REFERENCE_WIDTH)

	for index, buttonData in BUTTONS do
		local row = math.floor((index - 1) / COLUMNS)
		local col = (index - 1) % COLUMNS
		local x = col * (BUTTON_SIZE + GAP)
		local y = row * (BUTTON_SIZE + GAP)

		local button = Theme.Button(container, UDim2.new(0, BUTTON_SIZE, 0, BUTTON_SIZE), UDim2.new(0, x, 0, y), buttonData.Text)
		button.TextWrapped = true

		local panelHandle = handles[buttonData.Key]
		if panelHandle then
			button.Activated:Connect(function()
				panelHandle.Toggle()
			end)
		end
	end
end

return Sidebar
