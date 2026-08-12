-- Cash pill for Endless Mode -- a currency SEPARATE from the Hub's own Cash
-- (session.EndlessModeCash, not session.Cash), same icon as CashHud.luau's
-- regular pill. Only visible while in Endless Mode (see MainUI.luau's
-- PortalTeleport listener, same toggle idiom as EndlessModeWaveHUD.luau).
-- Position/scale are entirely owned by Sidebar.luau -- it slots this into
-- the SAME stacked spot below the icon grid (below the Inventory button,
-- per explicit request) that the regular CashHud occupies, swapping in
-- automatically since only one of the two is ever Visible at a time. The
-- Size/Position set here are just a default before Sidebar reparents it
-- (same idiom CashHud.luau's own pill uses). No earning source wired up
-- yet, per explicit "momentan fa o asa" request -- just the display,
-- updated live off EndlessModeCashUpdated whenever the server pushes a new
-- amount.

local NumberFormat = require(game:GetService("ReplicatedStorage").Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local CASH_ICON = "rbxassetid://72463281853990"
local ICON_SIZE = 40

local EndlessModeCashHud = {}

function EndlessModeCashHud.Create(screenGui: ScreenGui)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(0, 150, 0, ICON_SIZE)
	row.Position = UDim2.new(0, 16, 0, 16)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Visible = false
	row.ZIndex = 5
	row.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = row

	local icon = Instance.new("ImageLabel")
	icon.LayoutOrder = 1
	icon.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = CASH_ICON
	icon.ZIndex = 6
	icon.Parent = row

	local label = Instance.new("TextLabel")
	label.LayoutOrder = 2
	label.Size = UDim2.new(0, 100, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Theme.Fonts.Header
	label.TextScaled = true
	label.Text = "$0"
	label.TextColor3 = Theme.Colors.Success
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = row
	local labelTextSize = Instance.new("UITextSizeConstraint")
	labelTextSize.MaxTextSize = 30
	labelTextSize.Parent = label

	local handle = {}
	handle.Frame = row

	function handle.Update(amount: number)
		label.Text = NumberFormat.FormatCash(amount)
	end

	return handle
end

return EndlessModeCashHud
