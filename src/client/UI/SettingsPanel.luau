-- Empty placeholder -- sidebar button + panel shell exist, no settings yet.

local Theme = require(script.Parent.Theme)

local SettingsPanel = {}

function SettingsPanel.Create(screenGui: ScreenGui)
	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 320, 0, 180), UDim2.new(0.5, -160, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	local titleLabel = Theme.Label(panel, UDim2.new(1, -120, 0, 32), "Settings", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	local closeButton = Theme.Button(panel, UDim2.new(0, 90, 0, 32), UDim2.new(1, -100, 0, 10), "Close")
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	local comingSoonLabel = Theme.Label(panel, UDim2.new(1, -32, 0, 26), "Coming soon")
	comingSoonLabel.Position = UDim2.new(0, 16, 0, 60)
	comingSoonLabel.TextColor3 = Theme.Colors.TextSecondary

	local handle = {}
	handle.Frame = panel

	function handle.Toggle()
		panel.Visible = not panel.Visible
	end

	return handle
end

return SettingsPanel
