-- Full-screen "You Died!" modal -- shown when the player's claimed base
-- (200 HP, EndlessModeClaimManager.luau) gets destroyed by mobs, per
-- explicit request. By the time EndlessModeGameOver fires, the server has
-- ALREADY reset that player's Endless Mode progress (session.EndlessModeWave
-- /EndlessModeCash back to their starting values, every placed building
-- destroyed, everything unequipped, the claim released -- see PetManager
-- .luau's own EndlessModeClaimManager.BaseDestroyed listener) -- this is
-- purely the "here's what happened, what do you want to do now" screen.
-- "Respawn" just dismisses it (the plot is already unclaimed again, free to
-- walk up and Claim fresh); "Go Lobby" teleports straight back to the Hub
-- (RequestEndlessModeLobbyTeleport, handled in PortalManager.luau).

local Theme = require(script.Parent.Theme)

local EndlessModeGameOverPanel = {}

function EndlessModeGameOverPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local endlessModeGameOver = remotes:WaitForChild("EndlessModeGameOver")
	local requestEndlessModeLobbyTeleport = remotes:WaitForChild("RequestEndlessModeLobbyTeleport")

	-- Dims the WHOLE SCREEN and blocks clicks from passing through to
	-- whatever's underneath -- same "detached from the panel, ZIndex'd just
	-- below it" idiom InventoryPanel.luau's own backdrop uses.
	local backdrop = Instance.new("TextButton")
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Visible = false
	backdrop.ZIndex = 30
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 360, 0, 230)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 31
	panel.Parent = screenGui
	Theme.Round(panel, UDim.new(0, 14))
	local panelStroke = Theme.Stroke(panel, Color3.fromRGB(220, 40, 40), 2)
	panelStroke.Transparency = 0
	local panelShadow = Theme.Shadow(panel)
	Theme.AutoScale(screenGui, panel, 360)
	Theme.AutoScale(screenGui, panelShadow, 360)

	local titleLabel = Theme.Label(panel, UDim2.new(1, -24, 0, 50), "You Died!", true)
	titleLabel.Position = UDim2.new(0, 12, 0, 18)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.TextColor3 = Color3.fromRGB(220, 40, 40)

	local subLabel = Theme.Label(panel, UDim2.new(1, -24, 0, 44), "Your base was destroyed -- Endless progress has been reset.")
	subLabel.Position = UDim2.new(0, 12, 0, 74)
	subLabel.TextXAlignment = Enum.TextXAlignment.Center
	subLabel.TextWrapped = true
	subLabel.TextColor3 = Theme.Colors.TextSecondary

	local respawnButton = Theme.Button(panel, UDim2.new(1, -24, 0, 44), UDim2.new(0, 12, 1, -110), "Respawn", true)
	local lobbyButton = Theme.Button(panel, UDim2.new(1, -24, 0, 44), UDim2.new(0, 12, 1, -58), "Go Lobby")

	local function hide()
		panel.Visible = false
		backdrop.Visible = false
	end

	respawnButton.Activated:Connect(hide)
	backdrop.Activated:Connect(hide)
	lobbyButton.Activated:Connect(function()
		requestEndlessModeLobbyTeleport:FireServer()
		hide()
	end)

	endlessModeGameOver.OnClientEvent:Connect(function()
		panel.Visible = true
		backdrop.Visible = true
	end)

	local handle = {}
	handle.Frame = panel
	return handle
end

return EndlessModeGameOverPanel
