-- Small popup that appears automatically -- same proximity-only pattern as
-- VIPProximityPanel.luau/GroupRewardsProximityPanel.luau, no ProximityPrompt
-- -- while standing near the plaza's green "Codes" floor marker
-- (MapBuilder's buildFloorMarker). A TextBox + Redeem button; the actual
-- validation/grant happens server-side (CodesManager.luau/CodesConfig.luau)
-- -- this is input + result display only.

local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local ProximityWatcher = require(script.Parent.ProximityWatcher)

local CodesProximityPanel = {}

local PROXIMITY_RADIUS_STUDS = 10
local CODES_COLOR = Color3.fromRGB(80, 220, 160)

function CodesProximityPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local redeemCode = remotes:WaitForChild("RedeemCode")
	local codeRedeemResult = remotes:WaitForChild("CodeRedeemResult")

	-- Centered, same convention every other proximity popup uses now (see
	-- VIPProximityPanel.luau's comment for why -- a fixed bottom-anchored
	-- offset used to push these off the top of short phone screens).
	-- Bigger than the standard 320x220 proximity popup (360x300) -- felt
	-- cramped at the smaller size, especially with the on-screen keyboard
	-- competing for space on phone. Lower minScale (0.5, not the default
	-- 0.6) so it still comfortably fits a short landscape phone screen at
	-- this larger base size instead of getting stuck oversized.
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 360, 0, 300)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 8
	panel.Parent = screenGui
	Theme.Round(panel)
	Theme.Stroke(panel, CODES_COLOR, 1)
	local panelShadow = Theme.Shadow(panel)
	Theme.AutoScale(screenGui, panel, 360, 0.5)
	Theme.AutoScale(screenGui, panelShadow, 360, 0.5)

	local titleLabel = Theme.Label(panel, UDim2.new(1, -20, 0, 34), "Redeem Code", true)
	titleLabel.Position = UDim2.new(0, 10, 0, 14)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center

	local codeBox = Instance.new("TextBox")
	codeBox.Size = UDim2.new(1, -32, 0, 48)
	codeBox.Position = UDim2.new(0, 16, 0, 66)
	codeBox.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	codeBox.BorderSizePixel = 0
	codeBox.Text = ""
	codeBox.PlaceholderText = "Enter code..."
	codeBox.TextColor3 = Theme.Colors.TextPrimary
	codeBox.PlaceholderColor3 = Theme.Colors.TextSecondary
	codeBox.Font = Theme.Fonts.Body
	codeBox.TextSize = 20
	codeBox.TextXAlignment = Enum.TextXAlignment.Center
	codeBox.ClearTextOnFocus = false
	codeBox.Parent = panel
	Theme.Round(codeBox, UDim.new(0, 8))
	local codeBoxStroke = Theme.Stroke(codeBox, Color3.fromRGB(90, 90, 98), 1.5)
	codeBoxStroke.Transparency = 0

	local resultLabel = Theme.Label(panel, UDim2.new(1, -32, 0, 50), "")
	resultLabel.Position = UDim2.new(0, 16, 0, 126)
	resultLabel.TextXAlignment = Enum.TextXAlignment.Center
	resultLabel.TextWrapped = true
	resultLabel.TextColor3 = Theme.Colors.TextSecondary

	local redeemButton = Theme.Button(panel, UDim2.new(1, -32, 0, 46), UDim2.new(0, 16, 1, -62), "Redeem", true)

	local function trySubmit()
		-- Trim whitespace before sending -- mobile autocapitalize/autocomplete
		-- and pasted codes (e.g. copied from Discord) can carry a leading/
		-- trailing space or newline that would otherwise make an exact
		-- server-side match fail on an otherwise-valid code.
		local code = codeBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
		if code == "" then
			return
		end
		redeemButton.Active = false
		redeemCode:FireServer(code)
	end

	redeemButton.Activated:Connect(trySubmit)
	codeBox.FocusLost:Connect(function(enterPressed: boolean)
		if enterPressed then
			trySubmit()
		end
	end)

	codeRedeemResult.OnClientEvent:Connect(function(success: boolean, message: string)
		redeemButton.Active = true
		resultLabel.Text = message
		resultLabel.TextColor3 = success and Theme.Colors.Success or Theme.Colors.Danger
		if success then
			codeBox.Text = ""
		end
	end)

	-- Same self-healing retry as VIPProximityPanel.luau -- re-resolves
	-- Workspace.Map itself (not just the child lookup) in case a stale Map
	-- existed at t=0 and got destroyed/rebuilt out from under a cached
	-- reference.
	task.spawn(function()
		local marker: BasePart? = nil
		while not marker do
			local mapFolder = Workspace:WaitForChild("Map")
			marker = mapFolder:WaitForChild("CodesMarker_Disk", 5) :: BasePart?
		end

		ProximityWatcher.Register(marker, PROXIMITY_RADIUS_STUDS, function(inRange)
			panel.Visible = inRange
			if not inRange then
				resultLabel.Text = ""
			end
		end)
	end)

	local handle = {}
	handle.Frame = panel
	return handle
end

return CodesProximityPanel
