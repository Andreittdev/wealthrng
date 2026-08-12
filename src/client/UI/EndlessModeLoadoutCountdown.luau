-- Small countdown banner, ENDLESS MODE ONLY, showing the live
-- EndlessModeLoadoutCountdownUpdated payload (EndlessModeMobManager.luau
-- owns the actual timing) -- "Picking" phase reads as a nudge to actually
-- go pick a loadout (EndlessModeLoadoutHotbar.luau/InventoryPanel.luau) and
-- only shows while the Inventory panel itself is open (SetInventoryOpen,
-- driven by MainUI.luau watching inventoryHandle.Frame's own Visible); the
-- countdown keeps running server-side the whole time regardless, this just
-- isn't shown as a floating banner while the panel's closed. "Locked" phase
-- nudges the player to actually place the Estates they just picked before
-- mobs start -- shown UNCONDITIONALLY (not gated on the panel being open),
-- since the same transition that starts it also force-closes the panel.
--
-- Purely a display -- the actual "hide the Sidebar's Inventory button /
-- force-close the panel once Picking ends" side effect lives in MainUI.luau
-- (a second, independent listener on the same remote), not here, so this
-- file doesn't need direct references to Sidebar/InventoryPanel's handles
-- for THAT part.

local Theme = require(script.Parent.Theme)

local EndlessModeLoadoutCountdown = {}

local PICKING_TEXT = "Pick 4 Estates! %ds"
local LOCKED_TEXT = "Place your estates! %ds"

function EndlessModeLoadoutCountdown.Create(screenGui: ScreenGui, remotes: Folder)
	local endlessModeLoadoutCountdownUpdated = remotes:WaitForChild("EndlessModeLoadoutCountdownUpdated")

	-- Same top-center slot EndlessModeWaveHUD.luau's own "WAVE N" label
	-- uses (Position y=12) -- per explicit request, this and the wave
	-- readout are mutually exclusive (MainUI.luau hides the wave readout
	-- for as long as this has an active payload), not a request to have
	-- them coexist stacked -- the old y=70 placement sat BEHIND
	-- InventoryPanel.luau's own panel (which starts at y=60 with a higher
	-- ZIndex), reading as if it never showed up at all.
	local label = Theme.Label(screenGui, UDim2.new(0, 320, 0, 44), "", true)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 12)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	label.BackgroundTransparency = 0.15
	label.TextColor3 = Theme.Colors.Accent
	label.Visible = false
	label.ZIndex = 6
	Theme.Round(label, UDim.new(0, 10))
	local labelStroke = Theme.Stroke(label, Color3.fromRGB(90, 90, 98), 1.5)
	labelStroke.Transparency = 0
	Theme.AutoScale(screenGui, label, 320)

	-- "Picking" only shows while the Inventory panel is open (see
	-- SetInventoryOpen below) -- but "Locked" has to show UNCONDITIONALLY:
	-- the same phase transition that starts it also force-closes the
	-- Inventory panel (MainUI.luau's own EndlessModeLoadoutCountdownUpdated
	-- listener), so gating it on isInventoryOpen too would mean it NEVER
	-- actually shows -- the one phase the player most needs the "Place your
	-- estates!" nudge for.
	local currentPhase: string? = nil
	local isInventoryOpen = false

	local function refreshVisible()
		label.Visible = currentPhase ~= nil and (currentPhase == "Locked" or isInventoryOpen)
	end

	endlessModeLoadoutCountdownUpdated.OnClientEvent:Connect(function(payload: { Phase: string, SecondsRemaining: number }?)
		currentPhase = payload and payload.Phase
		if payload then
			if payload.Phase == "Picking" then
				label.Text = string.format(PICKING_TEXT, payload.SecondsRemaining)
				label.TextColor3 = Theme.Colors.Accent
			else
				label.Text = string.format(LOCKED_TEXT, payload.SecondsRemaining)
				label.TextColor3 = Theme.Colors.Danger
			end
		end
		refreshVisible()
	end)

	local handle = {}
	handle.Frame = label

	-- MainUI.luau calls this off inventoryHandle.Frame's own
	-- GetPropertyChangedSignal("Visible") -- per explicit "textul ala...
	-- sa fie cand ai inventory ul deschis" request.
	function handle.SetInventoryOpen(open: boolean)
		isInventoryOpen = open
		refreshVisible()
	end

	return handle
end

return EndlessModeLoadoutCountdown
