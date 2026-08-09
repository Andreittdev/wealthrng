-- Small popup that appears automatically -- same proximity-only pattern as
-- VIPProximityPanel.luau/CodesProximityPanel.luau, no ProximityPrompt -- while
-- standing very close to (or walking through) the plaza's "Endless Mode"
-- portal sign (MapBuilder's buildPortal, marker part "Portal_Board"). Purely
-- a placeholder message -- the portal has no actual teleport/warp behavior
-- yet.

local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local ProximityWatcher = require(script.Parent.ProximityWatcher)

local PortalProximityPanel = {}

-- Small on purpose, per explicit request -- only pops up right at/through
-- the sign, not from across the plaza.
local PROXIMITY_RADIUS_STUDS = 6
local PORTAL_COLOR = Color3.fromRGB(150, 90, 220)

function PortalProximityPanel.Create(screenGui: ScreenGui)
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 300, 0, 140)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 8
	panel.Parent = screenGui
	Theme.Round(panel)
	Theme.Stroke(panel, PORTAL_COLOR, 1)
	local panelShadow = Theme.Shadow(panel)
	Theme.AutoScale(screenGui, panel, 300)
	Theme.AutoScale(screenGui, panelShadow, 300)

	local titleLabel = Theme.Label(panel, UDim2.new(1, -20, 0, 34), "Endless Mode", true)
	titleLabel.Position = UDim2.new(0, 10, 0, 16)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.TextColor3 = PORTAL_COLOR

	local messageLabel = Theme.Label(panel, UDim2.new(1, -24, 0, 60), "Coming soon...", true)
	messageLabel.Position = UDim2.new(0, 12, 0, 60)
	messageLabel.TextXAlignment = Enum.TextXAlignment.Center
	messageLabel.TextColor3 = Theme.Colors.TextSecondary

	-- Same self-healing retry as VIPProximityPanel.luau/CodesProximityPanel.luau
	-- -- re-resolves Workspace.Map itself (not just the child lookup) in case a
	-- stale Map existed at t=0 and got destroyed/rebuilt out from under a
	-- cached reference.
	task.spawn(function()
		local marker: BasePart? = nil
		while not marker do
			local mapFolder = Workspace:WaitForChild("Map")
			marker = mapFolder:WaitForChild("Portal_Board", 5) :: BasePart?
		end

		ProximityWatcher.Register(marker, PROXIMITY_RADIUS_STUDS, function(inRange)
			panel.Visible = inRange
		end)
	end)

	local handle = {}
	handle.Frame = panel
	return handle
end

return PortalProximityPanel
