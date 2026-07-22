local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Acelasi GamePassId/Attribute ca in MainShop.client.luau (randul "VIP").
local VIP_GAMEPASS_ID = 1898198234
local OWNED_COLOR = Color3.fromRGB(100, 235, 140)

-- Standul (cercul galben) e construit de VIPPerksStand.server.luau -- il
-- asteptam, ruleaza pe alt script, poate inca nu exista in primele frame-uri.
local stall = Workspace:WaitForChild("VIPPerksStand")
local disc = stall:WaitForChild("Disc")

-- Jumatate din diametrul cercului (20 studs, vezi VIPPerksStand.server.luau)
-- + o mica marja, ca panoul sa apara chiar cand calci pe marginea cercului,
-- nu doar exact in centrul lui.
local ZONE_RADIUS = 11

-- UI 2D, pe ecran (nu in lumea 3D) -- un chenar cu perks-urile VIP, aparut
-- jos-centru cand intri in cerc, la fel ca alte panouri din joc.
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "VIPPerksZoneGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -140)
panel.Size = UDim2.new(0, 260, 0, 190)
panel.BackgroundColor3 = Color3.fromRGB(30, 24, 8)
panel.BackgroundTransparency = 0.05
panel.Parent = screenGui

Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(212, 175, 55)
stroke.Thickness = 2.5
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 36)
title.Position = UDim2.new(0, 0, 0, 8)
title.BackgroundTransparency = 1
title.Text = "VIP PERKS"
title.TextColor3 = Color3.fromRGB(255, 210, 40)
title.Font = Enum.Font.FredokaOne
title.TextScaled = true
title.Parent = panel

local perksList = Instance.new("TextLabel")
perksList.Size = UDim2.new(1, -20, 0, 86)
perksList.Position = UDim2.new(0, 10, 0, 46)
perksList.BackgroundTransparency = 1
perksList.Text = string.format(
	"x%s Money\n+%d Luck\n+%d Inventory Slots",
	tostring(Economy.VIP.MoneyMultiplier),
	Economy.VIP.Luck,
	Economy.VIP.ExtraInventorySlots
)
perksList.TextColor3 = Color3.fromRGB(255, 245, 220)
perksList.Font = Enum.Font.FredokaOne
perksList.TextScaled = true
perksList.TextWrapped = true
perksList.Parent = panel

-- Butonul Buy (devine "OWNED", fara click, daca jucatorul detine deja
-- gamepass-ul) -- acelasi GamePassId ca in randul VIP din MainShop.
local buyButton = Instance.new("TextButton")
buyButton.Name = "BuyButton"
buyButton.AnchorPoint = Vector2.new(0.5, 1)
buyButton.Position = UDim2.new(0.5, 0, 1, -12)
buyButton.Size = UDim2.new(1, -24, 0, 40)
buyButton.Font = Enum.Font.FredokaOne
buyButton.TextScaled = true
buyButton.AutoButtonColor = true
buyButton.Parent = panel

Instance.new("UICorner", buyButton).CornerRadius = UDim.new(0, 10)

local function refreshBuyButton()
	local owned = player:GetAttribute("IsVIP") == true
	if owned then
		buyButton.BackgroundColor3 = Color3.fromRGB(20, 40, 22)
		buyButton.Text = "OWNED"
		buyButton.TextColor3 = OWNED_COLOR
		buyButton.AutoButtonColor = false
		buyButton.Active = false
	else
		buyButton.BackgroundColor3 = Color3.fromRGB(255, 210, 40)
		buyButton.Text = "BUY"
		buyButton.TextColor3 = Color3.fromRGB(40, 30, 5)
		buyButton.AutoButtonColor = true
		buyButton.Active = true
	end
end

refreshBuyButton()
player:GetAttributeChangedSignal("IsVIP"):Connect(refreshBuyButton)

buyButton.MouseButton1Click:Connect(function()
	if player:GetAttribute("IsVIP") == true then
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, VIP_GAMEPASS_ID)
end)

local isInside = false

RunService.Heartbeat:Connect(function()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		isInside = false
		screenGui.Enabled = false
		return
	end

	local distance = (rootPart.Position - disc.Position) * Vector3.new(1, 0, 1)
	local nowInside = distance.Magnitude <= ZONE_RADIUS

	if nowInside ~= isInside then
		isInside = nowInside
		screenGui.Enabled = isInside
	end
end)
