-- Sidebar-triggered "Shop" panel: currently just the VIP gamepass purchase
-- (moved here from RollPanel, which used to have a permanent Buy VIP
-- button next to Roll). Built as a catalog list (one row today) so adding
-- more purchasable things later is just another row, not a restructure.
-- Not to be confused with AssetShopPanel.luau, the physical proximity-
-- triggered Assets/Invest trading panel.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local Theme = require(script.Parent.Theme)

local ShopPanel = {}

function ShopPanel.Create(screenGui: ScreenGui)
	-- Anchored near the top (not dead-center) so it doesn't collide with
	-- RollPanel's bottom-anchored reveal window/button on shorter viewports.
	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 360, 0, 220), UDim2.new(0.5, -180, 0, 60))
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

	local buyVIPButton = Theme.Button(vipRow, UDim2.new(1, -20, 0, 32), UDim2.new(0, 10, 1, -40), "Buy VIP", true)
	buyVIPButton.Activated:Connect(function()
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, VIPConfig.GamepassId)
	end)

	local handle = {}
	handle.Frame = panel

	function handle.Toggle()
		panel.Visible = not panel.Visible
	end

	return handle
end

return ShopPanel
