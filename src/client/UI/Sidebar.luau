-- Top-left grid of small square icon-style toggle buttons (2 columns), not
-- a column of wide text buttons -- matches the reference's square icon
-- layout. Each button just calls .Toggle() on the matching panel handle
-- passed in from MainUI -- Sidebar itself owns no panel state.

local Theme = require(script.Parent.Theme)

local Sidebar = {}

local BUTTONS = {
	{ Key = "Inventory", Text = "Inventory" },
	{ Key = "NetWorth", Text = "Net Worth" },
	{ Key = "Shop", Text = "Store" },
	{ Key = "Settings", Text = "Settings" },
	{ Key = "Profile", Text = "Profile" },
}

local BUTTON_SIZE = 76
local START_X = 16
local START_Y = 16
local GAP = 8
local COLUMNS = 2

export type PanelHandles = {
	Inventory: { Toggle: () -> () },
	NetWorth: { Toggle: () -> () },
	Shop: { Toggle: () -> () },
	Settings: { Toggle: () -> () },
	Profile: { Toggle: () -> () },
}

function Sidebar.Create(screenGui: ScreenGui, handles: PanelHandles)
	for index, buttonData in BUTTONS do
		local row = math.floor((index - 1) / COLUMNS)
		local col = (index - 1) % COLUMNS
		local x = START_X + col * (BUTTON_SIZE + GAP)
		local y = START_Y + row * (BUTTON_SIZE + GAP)

		local button = Theme.Button(screenGui, UDim2.new(0, BUTTON_SIZE, 0, BUTTON_SIZE), UDim2.new(0, x, 0, y), buttonData.Text)
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
