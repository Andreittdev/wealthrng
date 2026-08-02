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
local LuckSpeedHUD = require(script.Parent.LuckSpeedHUD)
local BoardRankLabels = require(script.Parent.BoardRankLabels)
local RollPanel = require(script.Parent.RollPanel)
local AssetShopPanel = require(script.Parent.AssetShopPanel)
local PotionShopPanel = require(script.Parent.PotionShopPanel)
local ShopPanel = require(script.Parent.ShopPanel)
local VIPProximityPanel = require(script.Parent.VIPProximityPanel)
local GroupRewardsProximityPanel = require(script.Parent.GroupRewardsProximityPanel)
local DailyRewardsProximityPanel = require(script.Parent.DailyRewardsProximityPanel)
local LuckyRollProximityPanel = require(script.Parent.LuckyRollProximityPanel)
local NetWorthPanel = require(script.Parent.NetWorthPanel)
local SettingsPanel = require(script.Parent.SettingsPanel)
local ProfilePanel = require(script.Parent.ProfilePanel)
local TradePanel = require(script.Parent.TradePanel)
local CatalogPanel = require(script.Parent.CatalogPanel)
local UpgradesPanel = require(script.Parent.UpgradesPanel)
local Sidebar = require(script.Parent.Sidebar)

local MainUI = {}

function MainUI.Init()
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local inventoryUpdated = remotesFolder:WaitForChild("InventoryUpdated")
	local statsUpdated = remotesFolder:WaitForChild("StatsUpdated")
	local potionUpdated = remotesFolder:WaitForChild("PotionUpdated")
	local upgradesUpdated = remotesFolder:WaitForChild("UpgradesUpdated")
	local clientReady = remotesFolder:WaitForChild("ClientReady")

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
	local luckSpeedHudHandle = LuckSpeedHUD.Create(screenGui)
	BoardRankLabels.Init(remotesFolder)
	local rollHandle = RollPanel.Create(screenGui, remotesFolder)
	local assetShopHandle = AssetShopPanel.Create(screenGui, remotesFolder)
	local potionShopHandle = PotionShopPanel.Create(screenGui, remotesFolder)
	local shopHandle = ShopPanel.Create(screenGui)
	local vipProximityHandle = VIPProximityPanel.Create(screenGui)
	local groupRewardsProximityHandle = GroupRewardsProximityPanel.Create(screenGui, remotesFolder)
	local dailyRewardsProximityHandle = DailyRewardsProximityPanel.Create(screenGui, remotesFolder)
	local luckyRollProximityHandle = LuckyRollProximityPanel.Create(screenGui, remotesFolder)
	local netWorthHandle = NetWorthPanel.Create(screenGui, remotesFolder)
	local settingsHandle = SettingsPanel.Create(screenGui, remotesFolder)
	local profileHandle = ProfilePanel.Create(screenGui)
	local tradeHandle = TradePanel.Create(screenGui, remotesFolder)
	local catalogHandle = CatalogPanel.Create(screenGui, remotesFolder)
	local upgradesHandle = UpgradesPanel.Create(screenGui, remotesFolder)

	-- RollPanel's circular UPGRADE button next to ROLL is the only way to
	-- open UpgradesPanel now -- the sidebar no longer has its own entry.
	rollHandle.UpgradeButton.Activated:Connect(upgradesHandle.Toggle)

	local sidebarHandle = Sidebar.Create(screenGui, {
		Inventory = inventoryHandle,
		NetWorth = netWorthHandle,
		Shop = shopHandle,
		Settings = settingsHandle,
		Profile = profileHandle,
		Trade = tradeHandle,
	}, cashHudHandle.Frame, luckSpeedHudHandle.Frame)

	local modalFrames = {
		inventoryHandle.Frame,
		assetShopHandle.Frame,
		potionShopHandle.Frame,
		shopHandle.Frame,
		netWorthHandle.Frame,
		settingsHandle.Frame,
		profileHandle.Frame,
		tradeHandle.Frame,
		tradeHandle.TradeWindowFrame,
		catalogHandle.Frame,
		upgradesHandle.Frame,
		vipProximityHandle.Frame,
		groupRewardsProximityHandle.Frame,
		dailyRewardsProximityHandle.Frame,
		luckyRollProximityHandle.Frame,
	}

	-- inBattleZone is a 3rd independent source of "should the always-on HUD
	-- be hidden right now" alongside "any modal is open" -- both need to be
	-- folded into the SAME decision instead of separately/directly setting
	-- rollHandle's visibility, or one could stomp the other (e.g. a modal
	-- happens to still be open while walking into the LARP Battles circle).
	local inBattleZone = false

	local function updateRollHud()
		local anyModalOpen = false
		for _, frame in modalFrames do
			if frame.Visible then
				anyModalOpen = true
				break
			end
		end
		-- Sidebar used to only react to inBattleZone, ignoring anyModalOpen
		-- entirely -- on a narrow/short mobile screen, an open modal (Shop,
		-- Inventory, any proximity panel, etc.) can genuinely overlap
		-- Sidebar's top-left icon grid, and since Sidebar is built AFTER
		-- every modal with no explicit ZIndex, it painted on top of the
		-- modal's left edge instead of the other way around. Same
		-- visibility formula as the Roll HUD now.
		local hudVisible = not anyModalOpen and not inBattleZone
		rollHandle.SetHudVisible(hudVisible)
		sidebarHandle.Frame.Visible = hudVisible
	end

	for _, frame in modalFrames do
		frame:GetPropertyChangedSignal("Visible"):Connect(updateRollHud)
	end

	statsUpdated.OnClientEvent:Connect(function(stats)
		profileHandle.Update(stats)
		rollHandle.SetOwnsAutoRoll(stats.OwnsAutoRoll)
		rollHandle.SetOwnsFastRoll(stats.OwnsFastRoll)
		cashHudHandle.Update(stats.Cash)
		cashHudHandle.UpdateFriendBoost(stats.FriendBonusPercent)
		vipProximityHandle.SetVIP(stats.IsVIP)
		shopHandle.Update(stats)
		luckSpeedHudHandle.SetVIP(stats.IsVIP)
	end)

	inventoryUpdated.OnClientEvent:Connect(inventoryHandle.Render)
	potionUpdated.OnClientEvent:Connect(function(potions)
		profileHandle.UpdatePotions(potions)
		luckSpeedHudHandle.SetActivePotions(potions)
	end)
	upgradesUpdated.OnClientEvent:Connect(luckSpeedHudHandle.SetUpgrades)

	-- Every panel above is built and every OnClientEvent listener above is
	-- connected -- safe now to tell the server it can send the "here's your
	-- saved data" initial pushes (Inventory/Assets/Investments/etc.)
	-- without risking firing before anything was listening.
	clientReady:FireServer()

	local handle = {}

	-- Lets an unrelated, self-contained feature (BattlePanel's LARP Battles
	-- zone) temporarily hide the always-on Sidebar cluster (grid + CashHud +
	-- LuckSpeedHUD) and RollPanel's HUD while the player stands in its
	-- circle, on both PC and phone -- there's no good on-screen spot for a
	-- 3rd HUD layer to coexist with those, so it steps aside instead.
	function handle.SetBattleZoneActive(active: boolean)
		inBattleZone = active
		updateRollHud()
	end

	return handle
end

return MainUI
