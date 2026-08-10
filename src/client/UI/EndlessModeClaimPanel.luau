-- Small popup that appears automatically -- same proximity-only pattern as
-- VIPProximityPanel.luau/CodesProximityPanel.luau, no ProximityPrompt --
-- while standing near either of Endless Mode's 2 claimable plots
-- (MapBuilder.buildEndlessModeArea's "EndlessMode_ClaimLeft"/
-- "EndlessMode_ClaimRight" markers). One shared panel, not two separate
-- ones -- only one side can ever be in range at a time (they're ~49 studs
-- apart, well outside 2x the proximity radius), so `currentSide` just
-- tracks which marker is currently near.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Theme)
local ProximityWatcher = require(script.Parent.ProximityWatcher)

local EndlessModeClaimPanel = {}

local PROXIMITY_RADIUS_STUDS = 10
local ACCENT = Color3.fromRGB(90, 220, 140)

type ClaimInfo = { UserId: number, Name: string }?
type ClaimState = { Left: ClaimInfo, Right: ClaimInfo }

function EndlessModeClaimPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local claimEndlessModeLand = remotes:WaitForChild("ClaimEndlessModeLand")
	local requestEndlessModeClaimState = remotes:WaitForChild("RequestEndlessModeClaimState")
	local endlessModeLandClaimed = remotes:WaitForChild("EndlessModeLandClaimed")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 300, 0, 160)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 8
	panel.Parent = screenGui
	Theme.Round(panel)
	Theme.Stroke(panel, ACCENT, 1)
	local panelShadow = Theme.Shadow(panel)
	Theme.AutoScale(screenGui, panel, 300)
	Theme.AutoScale(screenGui, panelShadow, 300)

	local titleLabel = Theme.Label(panel, UDim2.new(1, -20, 0, 30), "Claim This Land", true)
	titleLabel.Position = UDim2.new(0, 10, 0, 12)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center

	local statusLabel = Theme.Label(panel, UDim2.new(1, -24, 0, 44), "")
	statusLabel.Position = UDim2.new(0, 12, 0, 48)
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center
	statusLabel.TextColor3 = Theme.Colors.TextSecondary

	local claimButton = Theme.Button(panel, UDim2.new(1, -24, 0, 40), UDim2.new(0, 12, 1, -52), "Claim", true)

	local nearSide: string? = nil -- which marker's radius we're physically inside right now, or nil
	local activeSide: string? = nil -- side the panel is actually showing for (nil while hidden)
	local claimState: ClaimState = { Left = nil, Right = nil }

	local function isMine(side: string): boolean
		local claimedBy = claimState[side]
		return claimedBy ~= nil and claimedBy.UserId == Players.LocalPlayer.UserId
	end

	local function refresh()
		if not activeSide then
			return
		end

		local claimedBy = claimState[activeSide]
		if not claimedBy then
			statusLabel.Text = "This half is unclaimed!"
			claimButton.Text = "Claim"
			claimButton.Active = true
			claimButton.AutoButtonColor = true
			claimButton.BackgroundColor3 = ACCENT
		else
			statusLabel.Text = "Claimed by " .. claimedBy.Name
			claimButton.Text = "Taken"
			claimButton.Active = false
			claimButton.AutoButtonColor = false
			claimButton.BackgroundColor3 = Theme.Colors.Danger
		end
	end

	-- Only shows while standing near an unclaimed plot or someone else's --
	-- once a plot is YOURS, there's nothing left to do there, so the panel
	-- hides entirely instead of showing a disabled "Claimed" state (per
	-- explicit request: walking back over your own land shouldn't pop it
	-- up again).
	local function applyVisibility()
		if nearSide and not isMine(nearSide) then
			activeSide = nearSide
			panel.Visible = true
			refresh()
		else
			activeSide = nil
			panel.Visible = false
		end
	end

	claimButton.Activated:Connect(function()
		if not activeSide or not claimButton.Active then
			return
		end
		claimEndlessModeLand:FireServer(activeSide)
	end)

	endlessModeLandClaimed.OnClientEvent:Connect(function(state: ClaimState)
		claimState = state
		applyVisibility()
	end)

	-- Self-healing WaitForChild retry (same reasoning as
	-- VIPProximityPanel.luau) -- re-resolves Workspace.Map itself, not just
	-- the child, in case a stale Map from a previous save existed at t=0 and
	-- got destroyed/rebuilt out from under a cached reference.
	local function registerSide(side: string, markerName: string)
		task.spawn(function()
			local marker: BasePart? = nil
			while not marker do
				local mapFolder = Workspace:WaitForChild("Map")
				marker = mapFolder:WaitForChild(markerName, 5) :: BasePart?
			end

			ProximityWatcher.Register(marker, PROXIMITY_RADIUS_STUDS, function(inRange)
				if inRange then
					nearSide = side
					requestEndlessModeClaimState:FireServer()
					applyVisibility()
				elseif nearSide == side then
					nearSide = nil
					applyVisibility()
				end
			end)
		end)
	end

	-- Right only for now, per explicit request -- the left marker stays on
	-- the map but isn't wired up to anything (EndlessModeClaimManager.luau
	-- rejects a "Left" claim attempt too, so this isn't the only guard).
	registerSide("Right", "EndlessMode_ClaimRight")

	local handle = {}
	handle.Frame = panel
	return handle
end

return EndlessModeClaimPanel
