-- Small popup that appears automatically -- no interact/keypress, no
-- Roblox "Press E" prompt UI -- while standing near the plaza's yellow VIP
-- floor marker (MapBuilder's buildVIPMarker), showing VIP's perks in
-- detail plus a Buy/Owned button. Driven by a plain distance check against
-- the marker part's position (a ProximityPrompt would always draw its own
-- default "Press E" UI just from being in range, which isn't wanted here).
-- Perk numbers are pulled from VIPConfig/RollConfig directly so this can't
-- drift out of sync with what VIP actually does.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local RollConfig = require(ReplicatedStorage.Modules.RollConfig)
local Theme = require(script.Parent.Theme)

local VIPProximityPanel = {}

local PROXIMITY_RADIUS_STUDS = 10

function VIPProximityPanel.Create(screenGui: ScreenGui)
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 320, 0, 200)
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -230)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 8
	panel.Parent = screenGui
	Theme.Round(panel)
	Theme.Stroke(panel, Color3.fromRGB(255, 215, 140), 1)
	Theme.Shadow(panel)

	local titleLabel = Theme.Label(panel, UDim2.new(1, -20, 0, 30), "VIP Perks", true)
	titleLabel.Position = UDim2.new(0, 10, 0, 10)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center

	local perksLabel = Theme.Label(panel, UDim2.new(1, -24, 0, 110), "")
	perksLabel.Position = UDim2.new(0, 12, 0, 44)
	perksLabel.TextWrapped = true
	perksLabel.TextYAlignment = Enum.TextYAlignment.Top
	perksLabel.TextXAlignment = Enum.TextXAlignment.Left
	perksLabel.TextColor3 = Theme.Colors.TextSecondary
	perksLabel.Text = string.format(
		"- Up to %gx better odds on rare rolls (Luxury tier)\n- %.2fs roll cooldown (down from %.2fs)\n- +%d%% cash when selling items",
		VIPConfig.LuckWeightMultiplier.Luxury or 1,
		VIPConfig.RollCooldownSeconds,
		RollConfig.BaseCooldownSeconds,
		VIPConfig.SellBonusPercent
	)

	local actionButton = Theme.Button(panel, UDim2.new(1, -24, 0, 36), UDim2.new(0, 12, 1, -46), "Buy VIP", true)
	actionButton.Activated:Connect(function()
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, VIPConfig.GamepassId)
	end)

	local isVIP = false
	local function refreshButton()
		if isVIP then
			actionButton.Text = "Owned"
			actionButton.Active = false
			actionButton.AutoButtonColor = false
			actionButton.BackgroundColor3 = Theme.Colors.Success
		else
			actionButton.Text = "Buy VIP"
			actionButton.Active = true
			actionButton.AutoButtonColor = true
			actionButton.BackgroundColor3 = Theme.Colors.Accent
		end
	end
	refreshButton()

	local handle = {}
	handle.Frame = panel

	function handle.SetVIP(value: boolean)
		isVIP = value
		refreshButton()
	end

	-- Waits in the background since Workspace.Map is built by a server
	-- Script that may not have run yet the instant this client script
	-- starts -- AND retries WaitForChild("Map") itself, not just its
	-- child: MapBuilder destroys + rebuilds Workspace.Map from scratch on
	-- every server start (see its own header comment), so if a stale Map
	-- from a previous save happened to already exist at t=0, the first
	-- WaitForChild("Map") could latch onto that soon-to-be-destroyed
	-- instance instead of the fresh one -- which then never gets this
	-- marker and hangs forever. Re-resolving Map from scratch on a
	-- failed/timed-out child lookup self-heals that race.
	task.spawn(function()
		local marker: BasePart? = nil
		while not marker do
			local mapFolder = Workspace:WaitForChild("Map")
			marker = mapFolder:WaitForChild("VIPMarker_Disk", 5) :: BasePart?
		end

		RunService.Heartbeat:Connect(function()
			local character = Players.LocalPlayer.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not rootPart then
				panel.Visible = false
				return
			end
			panel.Visible = (rootPart.Position - marker.Position).Magnitude <= PROXIMITY_RADIUS_STUDS
		end)
	end)

	return handle
end

return VIPProximityPanel
