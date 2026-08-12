-- Right-side HP/upgrade panel for whichever placed Estate in Endless Mode is
-- currently selected (PetManager.luau, server, owns selection/upgrade
-- state -- this just mirrors it). Shows the instant a building is placed or
-- clicked, hides again the instant it's deselected (clicked again, picked
-- up, or otherwise no longer valid), per explicit "only while that specific
-- Estate is just-placed/selected" request -- not a toggle the client
-- controls on its own.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local EndlessModeBuildingConfig = require(ReplicatedStorage.Modules.EndlessModeBuildingConfig)
local Theme = require(script.Parent.Theme)

local EndlessModeBuildingPanel = {}

type Selection = {
	PlacementId: string,
	AssetId: string,
	Name: string,
	HP: number,
	MaxHP: number,
	UpgradeLevel: number,
	UpgradeCost: number?,
	Role: string?,
	Damage: number?,
	Range: number?,
	Cooldown: number?,
	AllyCount: number?,
}

-- Rejected upgrade/pick-up attempts never echo anything back, so a click
-- can't wait for server confirmation before re-enabling -- same debounce
-- idiom as every other shop-style panel (PotionShopPanel.luau etc.).
local DEBOUNCE_SECONDS = 0.5

local function debounce(fn: () -> ())
	local lastFiredAt = 0
	return function()
		local now = os.clock()
		if now - lastFiredAt < DEBOUNCE_SECONDS then
			return
		end
		lastFiredAt = now
		fn()
	end
end

local PANEL_WIDTH = 240
local PANEL_HEIGHT = 220

function EndlessModeBuildingPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local endlessModeBuildingSelected = remotes:WaitForChild("EndlessModeBuildingSelected")
	local upgradeEndlessModeBuilding = remotes:WaitForChild("UpgradeEndlessModeBuilding")
	local pickUpEndlessModeBuilding = remotes:WaitForChild("PickUpEndlessModeBuilding")

	local selection: Selection? = nil

	-- Anchored to the right edge, vertically centered -- a HUD accessory
	-- tied to a selection, not a modal the player deliberately opens/closes,
	-- so it doesn't compete with the Sidebar/Inventory panels' own left/
	-- center placement.
	local panel = Theme.Panel(screenGui, UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT), UDim2.new(1, -16, 0.5, 0))
	panel.AnchorPoint = Vector2.new(1, 0.5)
	panel.Visible = false
	panel.ZIndex = 10

	local nameLabel = Theme.Label(panel, UDim2.new(1, -24, 0, 26), "", true)
	nameLabel.Position = UDim2.new(0, 12, 0, 10)

	local hpLabel = Theme.Label(panel, UDim2.new(1, -24, 0, 20), "")
	hpLabel.Position = UDim2.new(0, 12, 0, 40)
	hpLabel.TextColor3 = Theme.Colors.Success

	local levelLabel = Theme.Label(panel, UDim2.new(1, -24, 0, 20), "")
	levelLabel.Position = UDim2.new(0, 12, 0, 62)
	levelLabel.TextColor3 = Theme.Colors.TextSecondary

	-- Damage: "Damage: N | Range: N" -- Spawner: "Allies per spawn: N" --
	-- Tank has nothing extra to show here (pure soak, no offensive stat),
	-- so this just stays hidden for it.
	local statsLabel = Theme.Label(panel, UDim2.new(1, -24, 0, 20), "")
	statsLabel.Position = UDim2.new(0, 12, 0, 84)
	statsLabel.TextColor3 = Theme.Colors.TextSecondary

	-- Damage only: "Cooldown: Ns" -- own line directly under the Damage/
	-- Range line above, per explicit request.
	local cooldownLabel = Theme.Label(panel, UDim2.new(1, -24, 0, 18), "")
	cooldownLabel.Position = UDim2.new(0, 12, 0, 106)
	cooldownLabel.TextColor3 = Theme.Colors.TextSecondary

	local upgradeButton = Theme.Button(panel, UDim2.new(1, -24, 0, 40), UDim2.new(0, 12, 1, -96), "Upgrade", true)
	upgradeButton.Activated:Connect(debounce(function()
		if selection then
			upgradeEndlessModeBuilding:FireServer(selection.PlacementId)
		end
	end))

	local pickUpButton = Theme.Button(panel, UDim2.new(1, -24, 0, 36), UDim2.new(0, 12, 1, -50), "Pick Up")
	pickUpButton.Activated:Connect(debounce(function()
		if selection then
			pickUpEndlessModeBuilding:FireServer(selection.PlacementId)
		end
	end))

	local function render()
		if not selection then
			panel.Visible = false
			return
		end

		panel.Visible = true
		nameLabel.Text = selection.Name
		hpLabel.Text = string.format("HP: %d / %d", selection.HP, selection.MaxHP)
		levelLabel.Text = string.format("Upgrade Level: %d / %d", selection.UpgradeLevel, EndlessModeBuildingConfig.MaxUpgradeLevel)

		if selection.Role == "Damage" and selection.Damage and selection.Range then
			statsLabel.Text = string.format("Damage: %d | Range: %d", selection.Damage, selection.Range)
			statsLabel.Visible = true
			cooldownLabel.Text = string.format("Cooldown: %.1fs", selection.Cooldown or 0)
			cooldownLabel.Visible = selection.Cooldown ~= nil
		elseif selection.Role == "Spawner" and selection.AllyCount then
			statsLabel.Text = string.format("Allies per spawn: %d", selection.AllyCount)
			statsLabel.Visible = true
			cooldownLabel.Visible = false
		else
			statsLabel.Visible = false
			cooldownLabel.Visible = false
		end

		if selection.UpgradeCost then
			upgradeButton.Text = string.format("Upgrade (%s)", NumberFormat.FormatCash(selection.UpgradeCost))
			upgradeButton.Active = true
			upgradeButton.AutoButtonColor = true
		else
			upgradeButton.Text = "MAXED"
			upgradeButton.Active = false
			upgradeButton.AutoButtonColor = false
		end
	end

	endlessModeBuildingSelected.OnClientEvent:Connect(function(payload: Selection?)
		selection = payload
		render()
	end)

	local handle = {}
	handle.Frame = panel
	return handle
end

return EndlessModeBuildingPanel
