-- Orchestrator: creates the one ScreenGui, wires remotes to every panel,
-- and builds the left Sidebar last (so it can toggle the others). RollResult
-- is consumed directly inside RollPanel (not routed through here) since
-- it's purely a display concern of the reveal window. AssetShopPanel
-- manages its own remotes internally (Buy/Sell Asset/Investment +
-- AssetUpdated/InvestmentUpdated) since it's the only panel that *acts* on
-- them -- NetWorthPanel listens to the same remotes too, but read-only.
--
-- Also owns a small "any modal open -> hide RollPanel's HUD" coordinator:
-- on short viewports there's no position that keeps a full-size modal from
-- reaching into RollPanel's bottom-anchored reveal window/button, so
-- instead of chasing the overlap with positioning, the Roll HUD just steps
-- aside while a modal (shop, net worth, settings, profile) is open.
--
-- Named MainUI (not init/Init) so it's an unambiguous plain ModuleScript --
-- same reasoning as Main.server.luau/Main.client.luau avoiding Rojo's
-- init-file convention.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryPanel = require(script.Parent.InventoryPanel)
local CashHud = require(script.Parent.CashHud)
local RollPanel = require(script.Parent.RollPanel)
local AssetShopPanel = require(script.Parent.AssetShopPanel)
local PotionShopPanel = require(script.Parent.PotionShopPanel)
local ShopPanel = require(script.Parent.ShopPanel)
local NetWorthPanel = require(script.Parent.NetWorthPanel)
local SettingsPanel = require(script.Parent.SettingsPanel)
local ProfilePanel = require(script.Parent.ProfilePanel)
local TradePanel = require(script.Parent.TradePanel)
local CatalogPanel = require(script.Parent.CatalogPanel)
local Sidebar = require(script.Parent.Sidebar)

local MainUI = {}

function MainUI.Init()
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local inventoryUpdated = remotesFolder:WaitForChild("InventoryUpdated")
	local statsUpdated = remotesFolder:WaitForChild("StatsUpdated")
	local potionUpdated = remotesFolder:WaitForChild("PotionUpdated")

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "WealthRNG_UI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 10
	screenGui.Parent = playerGui

	local inventoryHandle = InventoryPanel.Create(screenGui, remotesFolder)
	local cashHudHandle = CashHud.Create(screenGui)
	local rollHandle = RollPanel.Create(screenGui, remotesFolder)
	local assetShopHandle = AssetShopPanel.Create(screenGui, remotesFolder)
	local potionShopHandle = PotionShopPanel.Create(screenGui, remotesFolder)
	local shopHandle = ShopPanel.Create(screenGui)
	local netWorthHandle = NetWorthPanel.Create(screenGui, remotesFolder)
	local settingsHandle = SettingsPanel.Create(screenGui)
	local profileHandle = ProfilePanel.Create(screenGui)
	local tradeHandle = TradePanel.Create(screenGui, remotesFolder)
	local catalogHandle = CatalogPanel.Create(screenGui)

	Sidebar.Create(screenGui, {
		Inventory = inventoryHandle,
		NetWorth = netWorthHandle,
		Shop = shopHandle,
		Settings = settingsHandle,
		Profile = profileHandle,
		Trade = tradeHandle,
	})

	local modalFrames = {
		assetShopHandle.Frame,
		potionShopHandle.Frame,
		shopHandle.Frame,
		netWorthHandle.Frame,
		settingsHandle.Frame,
		profileHandle.Frame,
		tradeHandle.Frame,
		tradeHandle.TradeWindowFrame,
		catalogHandle.Frame,
	}

	local function updateRollHud()
		local anyModalOpen = false
		for _, frame in modalFrames do
			if frame.Visible then
				anyModalOpen = true
				break
			end
		end
		rollHandle.SetHudVisible(not anyModalOpen)
	end

	for _, frame in modalFrames do
		frame:GetPropertyChangedSignal("Visible"):Connect(updateRollHud)
	end

	statsUpdated.OnClientEvent:Connect(function(stats)
		profileHandle.Update(stats)
		rollHandle.SetVIP(stats.IsVIP)
		cashHudHandle.Update(stats.Cash)
	end)

	inventoryUpdated.OnClientEvent:Connect(inventoryHandle.Render)
	potionUpdated.OnClientEvent:Connect(profileHandle.UpdatePotions)
end

return MainUI
