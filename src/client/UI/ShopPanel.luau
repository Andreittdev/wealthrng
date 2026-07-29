-- Sidebar-triggered "Shop" panel: Robux gamepass purchases (VIP, Auto
-- Roll). Built as a catalog list of rows so adding more purchasable things
-- later is just another row, not a restructure. Not to be confused with
-- AssetShopPanel.luau, the physical proximity-triggered Assets/Invest
-- trading panel. The plaza's yellow "VIP" floor marker (MapBuilder's
-- buildVIPMarker) shows its own separate quick-glance popup
-- (VIPProximityPanel.luau) instead of opening this panel.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local AutoRollConfig = require(ReplicatedStorage.Modules.AutoRollConfig)
local Theme = require(script.Parent.Theme)

local ShopPanel = {}

function ShopPanel.Create(screenGui: ScreenGui)
	-- Anchored near the top (not dead-center) so it doesn't collide with
	-- RollPanel's bottom-anchored reveal window/button on shorter viewports.
	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 360, 0, 320), UDim2.new(0.5, -180, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	local titleLabel = Theme.Label(panel, UDim2.new(1, -120, 0, 32), "Store", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	local closeButton = Theme.Button(panel, UDim2.new(0, 90, 0, 32), UDim2.new(1, -100, 0, 10), "Close")
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	local vipRow = Instance.new("Frame")
	vipRow.Size = UDim2.new(1, -32, 0, 120)
	vipRow.Position = UDim2.new(0, 16, 0, 56)
	vipRow.BackgroundColor3 = Theme.Colors.Surface
	vipRow.BackgroundTransparency = 0
	vipRow.BorderSizePixel = 0
	vipRow.Parent = panel
	Theme.Round(vipRow, UDim.new(0, 8))
	Theme.Stroke(vipRow, Theme.Colors.Accent, 1)

	local vipNameLabel = Theme.Label(vipRow, UDim2.new(1, -20, 0, 28), "VIP", true)
	vipNameLabel.Position = UDim2.new(0, 10, 0, 8)

	local vipPerksLabel = Theme.Label(vipRow, UDim2.new(1, -20, 0, 46), "+Luck on every roll, shorter cooldown, +25% cash on sell")
	vipPerksLabel.Position = UDim2.new(0, 10, 0, 38)
	vipPerksLabel.TextWrapped = true
	vipPerksLabel.TextColor3 = Theme.Colors.TextSecondary

	local buyVIPButton = Theme.Button(vipRow, UDim2.new(1, -20, 0, 32), UDim2.new(0, 10, 1, -40), "Buy", true)

	local isVIP = false
	local function refreshVIPButton()
		if isVIP then
			buyVIPButton.Text = "Owned"
			buyVIPButton.Active = false
			buyVIPButton.AutoButtonColor = false
			buyVIPButton.BackgroundColor3 = Theme.Colors.Success
			buyVIPButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			buyVIPButton.Text = "Buy"
			buyVIPButton.Active = true
			buyVIPButton.AutoButtonColor = true
			buyVIPButton.BackgroundColor3 = Theme.Colors.Accent
			buyVIPButton.TextColor3 = Color3.fromRGB(20, 20, 20)
		end
	end
	refreshVIPButton()

	buyVIPButton.Activated:Connect(function()
		if isVIP then
			return
		end
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, VIPConfig.GamepassId)
	end)

	-- ===== Auto Roll row =====
	local autoRollRow = Instance.new("Frame")
	autoRollRow.Size = UDim2.new(1, -32, 0, 120)
	autoRollRow.Position = UDim2.new(0, 16, 0, 184)
	autoRollRow.BackgroundColor3 = Theme.Colors.Surface
	autoRollRow.BackgroundTransparency = 0
	autoRollRow.BorderSizePixel = 0
	autoRollRow.Parent = panel
	Theme.Round(autoRollRow, UDim.new(0, 8))
	Theme.Stroke(autoRollRow, Theme.Colors.Accent, 1)

	local autoRollNameLabel = Theme.Label(autoRollRow, UDim2.new(1, -20, 0, 28), "Auto Roll", true)
	autoRollNameLabel.Position = UDim2.new(0, 10, 0, 8)

	local autoRollPerksLabel = Theme.Label(autoRollRow, UDim2.new(1, -20, 0, 46), "Automatically rolls for you at your normal cooldown")
	autoRollPerksLabel.Position = UDim2.new(0, 10, 0, 38)
	autoRollPerksLabel.TextWrapped = true
	autoRollPerksLabel.TextColor3 = Theme.Colors.TextSecondary

	-- Purchase-only here (Buy/Owned, same as VIP's row) -- the actual
	-- On/Off toggle lives on RollPanel's AUTO ROLL button next to ROLL,
	-- not here.
	local autoRollButton = Theme.Button(autoRollRow, UDim2.new(1, -20, 0, 32), UDim2.new(0, 10, 1, -40), "Buy", true)

	local ownsAutoRoll = false
	local function refreshAutoRollButton()
		if ownsAutoRoll then
			autoRollButton.Text = "Owned"
			autoRollButton.Active = false
			autoRollButton.AutoButtonColor = false
			autoRollButton.BackgroundColor3 = Theme.Colors.Success
			autoRollButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		else
			autoRollButton.Text = "Buy"
			autoRollButton.Active = true
			autoRollButton.AutoButtonColor = true
			autoRollButton.BackgroundColor3 = Theme.Colors.Accent
			autoRollButton.TextColor3 = Color3.fromRGB(20, 20, 20)
		end
	end
	refreshAutoRollButton()

	autoRollButton.Activated:Connect(function()
		if ownsAutoRoll then
			return
		end
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, AutoRollConfig.GamepassId)
	end)

	local handle = {}
	handle.Frame = panel

	function handle.Toggle()
		panel.Visible = not panel.Visible
	end

	function handle.Update(stats: { IsVIP: boolean, OwnsAutoRoll: boolean })
		isVIP = stats.IsVIP
		refreshVIPButton()
		ownsAutoRoll = stats.OwnsAutoRoll
		refreshAutoRollButton()
	end

	return handle
end

return ShopPanel
