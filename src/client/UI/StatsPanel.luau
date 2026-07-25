-- Top-left panel: Title (+ VIP pill), Cash, Net Worth. Pure presentation --
-- StatsManager.luau already sends exactly the {Cash, NetWorth, Title, IsVIP}
-- shape this consumes, no server changes needed.

local Theme = require(script.Parent.Theme)

local StatsPanel = {}

export type StatsPayload = { Cash: number, NetWorth: number, Title: string, IsVIP: boolean }

function StatsPanel.Create(screenGui: ScreenGui)
	local panel = Theme.Panel(screenGui, UDim2.new(0, 240, 0, 120), UDim2.new(0, 16, 0, 16))

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = panel

	local titleRow = Instance.new("Frame")
	titleRow.Size = UDim2.new(1, 0, 0, 28)
	titleRow.BackgroundTransparency = 1
	titleRow.Parent = panel

	local titleLabel = Theme.Label(titleRow, UDim2.new(1, -60, 1, 0), "Beginner", true)

	local vipPill = Instance.new("TextLabel")
	vipPill.Size = UDim2.new(0, 50, 0, 22)
	vipPill.AnchorPoint = Vector2.new(1, 0.5)
	vipPill.Position = UDim2.new(1, 0, 0.5, 0)
	vipPill.BackgroundColor3 = Theme.Colors.Accent
	vipPill.TextColor3 = Color3.fromRGB(20, 20, 20)
	vipPill.Font = Theme.Fonts.Header
	vipPill.TextScaled = true
	vipPill.Text = "VIP"
	vipPill.Visible = false
	vipPill.Parent = titleRow
	Theme.Round(vipPill, UDim.new(0, 6))

	local cashLabel = Theme.Label(panel, UDim2.new(1, 0, 0, 26), "Cash: $0")
	local netWorthLabel = Theme.Label(panel, UDim2.new(1, 0, 0, 26), "Net Worth: $0")

	local handle = {}

	function handle.Update(stats: StatsPayload)
		titleLabel.Text = stats.Title
		vipPill.Visible = stats.IsVIP
		cashLabel.Text = string.format("Cash: $%d", stats.Cash)
		netWorthLabel.Text = string.format("Net Worth: $%d", stats.NetWorth)
	end

	return handle
end

return StatsPanel
