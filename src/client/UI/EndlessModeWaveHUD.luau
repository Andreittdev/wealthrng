-- Top-center "WAVE N" readout -- only visible while in Endless Mode (see
-- MainUI.luau's PortalTeleport listener), updated live off the
-- EndlessModeWaveUpdated remote (EndlessModeWaveManager.luau, server, ticks
-- it ~once/second while the player is physically there).

local Theme = require(script.Parent.Theme)

local EndlessModeWaveHUD = {}

function EndlessModeWaveHUD.Create(screenGui: ScreenGui)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 220, 0, 44)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 12)
	label.BackgroundTransparency = 1
	label.Font = Theme.Fonts.Header
	label.Text = "WAVE 1"
	label.TextColor3 = Color3.fromRGB(255, 90, 90)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextScaled = true
	label.Visible = false
	label.ZIndex = 5
	label.Parent = screenGui
	Theme.AutoScale(screenGui, label, 220)

	local handle = {}
	handle.Frame = label

	function handle.SetWave(wave: number)
		label.Text = string.format("WAVE %d", wave)
	end

	return handle
end

return EndlessModeWaveHUD
