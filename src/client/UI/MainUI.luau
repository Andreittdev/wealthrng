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
local AutoRollFreePanel = require(script.Parent.AutoRollFreePanel)
local AssetShopPanel = require(script.Parent.AssetShopPanel)
local PotionShopPanel = require(script.Parent.PotionShopPanel)
local ShopPanel = require(script.Parent.ShopPanel)
local VIPProximityPanel = require(script.Parent.VIPProximityPanel)
local GroupRewardsProximityPanel = require(script.Parent.GroupRewardsProximityPanel)
local DailyRewardsProximityPanel = require(script.Parent.DailyRewardsProximityPanel)
local LuckyRollProximityPanel = require(script.Parent.LuckyRollProximityPanel)
local CodesProximityPanel = require(script.Parent.CodesProximityPanel)
local StadiumOfferPanel = require(script.Parent.StadiumOfferPanel)
local EndlessModeClaimPanel = require(script.Parent.EndlessModeClaimPanel)
local EndlessModeWaveHUD = require(script.Parent.EndlessModeWaveHUD)
local EndlessModeBuildingPanel = require(script.Parent.EndlessModeBuildingPanel)
local EndlessModeCashHud = require(script.Parent.EndlessModeCashHud)
local EndlessModeRangeIndicator = require(script.Parent.EndlessModeRangeIndicator)
local EndlessModeLoadoutHotbar = require(script.Parent.EndlessModeLoadoutHotbar)
local RobuxManDialogChoices = require(script.Parent.RobuxManDialogChoices)
local NetWorthPanel = require(script.Parent.NetWorthPanel)
local SettingsPanel = require(script.Parent.SettingsPanel)
local ProfilePanel = require(script.Parent.ProfilePanel)
local TradePanel = require(script.Parent.TradePanel)
local CatalogPanel = require(script.Parent.CatalogPanel)
local UpgradesPanel = require(script.Parent.UpgradesPanel)
local OnboardingTutorial = require(script.Parent.OnboardingTutorial)
local LuckEventBanner = require(script.Parent.LuckEventBanner)
local Sidebar = require(script.Parent.Sidebar)

local MainUI = {}

function MainUI.Init()
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local inventoryUpdated = remotesFolder:WaitForChild("InventoryUpdated")
	local statsUpdated = remotesFolder:WaitForChild("StatsUpdated")
	local potionUpdated = remotesFolder:WaitForChild("PotionUpdated")
	local upgradesUpdated = remotesFolder:WaitForChild("UpgradesUpdated")
	local claimedIndexRewardsUpdated = remotesFolder:WaitForChild("ClaimedIndexRewardsUpdated")
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
	local luckEventBannerHandle = LuckEventBanner.Create(screenGui, remotesFolder)
	BoardRankLabels.Init(remotesFolder)
	local autoRollFreeHandle = AutoRollFreePanel.Create(screenGui, remotesFolder)
	local rollHandle = RollPanel.Create(screenGui, remotesFolder, autoRollFreeHandle.Show)
	local assetShopHandle = AssetShopPanel.Create(screenGui, remotesFolder)
	local potionShopHandle = PotionShopPanel.Create(screenGui, remotesFolder)
	local shopHandle = ShopPanel.Create(screenGui, remotesFolder)
	local vipProximityHandle = VIPProximityPanel.Create(screenGui)
	local groupRewardsProximityHandle = GroupRewardsProximityPanel.Create(screenGui, remotesFolder)
	local dailyRewardsProximityHandle = DailyRewardsProximityPanel.Create(screenGui, remotesFolder)
	local luckyRollProximityHandle = LuckyRollProximityPanel.Create(screenGui, remotesFolder)
	local codesProximityHandle = CodesProximityPanel.Create(screenGui, remotesFolder)
	local stadiumOfferHandle = StadiumOfferPanel.Create(screenGui, remotesFolder)
	local endlessModeClaimHandle = EndlessModeClaimPanel.Create(screenGui, remotesFolder)
	local endlessModeWaveHudHandle = EndlessModeWaveHUD.Create(screenGui)
	local endlessModeBuildingHandle = EndlessModeBuildingPanel.Create(screenGui, remotesFolder)
	local endlessModeCashHudHandle = EndlessModeCashHud.Create(screenGui)
	local endlessModeLoadoutHotbarHandle = EndlessModeLoadoutHotbar.Create(screenGui, remotesFolder)
	EndlessModeRangeIndicator.Init(remotesFolder)
	RobuxManDialogChoices.Create(screenGui, remotesFolder)
	local netWorthHandle = NetWorthPanel.Create(screenGui, remotesFolder)
	local settingsHandle = SettingsPanel.Create(screenGui, remotesFolder)
	local profileHandle = ProfilePanel.Create(screenGui)
	local tradeHandle = TradePanel.Create(screenGui, remotesFolder)
	local catalogHandle = CatalogPanel.Create(screenGui, remotesFolder)
	local upgradesHandle = UpgradesPanel.Create(screenGui, remotesFolder)

	rollHandle.UpgradeButton.Activated:Connect(upgradesHandle.Toggle)

	local sidebarHandle = Sidebar.Create(screenGui, {
		Inventory = inventoryHandle,
		NetWorth = netWorthHandle,
		Shop = shopHandle,
		Settings = settingsHandle,
		Profile = profileHandle,
		Trade = tradeHandle,
	}, cashHudHandle.Frame, luckSpeedHudHandle.Frame, endlessModeCashHudHandle.Frame)

	-- Endless Mode's sidebar only shows Inventory/Store -- everything else
	-- (Net Worth, Trade, Settings, Profile) is hidden while there, and the
	-- top-right CashHud pill (plain Cash number + Friend Boost row/invite
	-- button, both in the same Frame) hides entirely too, per explicit
	-- request. PortalTeleport (PortalManager.luau) is the signal: it fires
	-- with the destination label right as the portal fade covers the
	-- screen, so toggling visibility here happens hidden behind that fade
	-- instead of popping visibly.
	local ENDLESS_MODE_HIDDEN_SIDEBAR_KEYS = { "NetWorth", "Trade", "Settings", "Profile" }
	local portalTeleport = remotesFolder:WaitForChild("PortalTeleport")
	portalTeleport.OnClientEvent:Connect(function(destinationLabel: string)
		local inEndlessMode = destinationLabel == "Endless Mode"
		for _, key in ENDLESS_MODE_HIDDEN_SIDEBAR_KEYS do
			local button = sidebarHandle.Buttons[key]
			if button then
				button.Visible = not inEndlessMode
			end
		end
		cashHudHandle.Frame.Visible = not inEndlessMode
		endlessModeWaveHudHandle.Frame.Visible = inEndlessMode
		endlessModeCashHudHandle.Frame.Visible = inEndlessMode
		endlessModeLoadoutHotbarHandle.Frame.Visible = inEndlessMode
		luckEventBannerHandle.SetSuppressed(inEndlessMode)
		inventoryHandle.SetEstatesOnly(inEndlessMode)
		-- Per explicit request: entering Endless Mode auto-pops the (now
		-- Estates-only, per the line above) Inventory panel open so the
		-- player immediately sees a big pickable list instead of having to
		-- know to open it themselves -- Open() is idempotent, so this is
		-- silent/harmless if they'd already had it open. Doesn't force it
		-- shut again on the way OUT, so closing it mid-session doesn't get
		-- fought if they reopen it manually.
		if inEndlessMode then
			inventoryHandle.Open()
		end
	end)

	local endlessModeWaveUpdated = remotesFolder:WaitForChild("EndlessModeWaveUpdated")
	endlessModeWaveUpdated.OnClientEvent:Connect(endlessModeWaveHudHandle.SetWave)

	local endlessModeCashUpdated = remotesFolder:WaitForChild("EndlessModeCashUpdated")
	endlessModeCashUpdated.OnClientEvent:Connect(endlessModeCashHudHandle.Update)

	-- Built last -- needs the real ROLL/Inventory/Upgrade buttons (and the
	-- Upgrades panel's own internals) to already exist so it can point its
	-- various steps' highlights at them.
	OnboardingTutorial.Create(
		screenGui,
		remotesFolder,
		rollHandle.RollButton,
		sidebarHandle.InventoryButton,
		rollHandle.UpgradeButton,
		upgradesHandle,
		inventoryHandle
	)

	local modalFrames = {
		autoRollFreeHandle.Frame,
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
		codesProximityHandle.Frame,
		stadiumOfferHandle.Frame,
		endlessModeClaimHandle.Frame,
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
		sidebarHandle.BottomFrame.Visible = hudVisible
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
	claimedIndexRewardsUpdated.OnClientEvent:Connect(function(claimed: { Roll: { [string]: boolean }, Estate: { [string]: boolean } })
		luckSpeedHudHandle.SetClaimedRollTiers(claimed.Roll or {})
		profileHandle.SetClaimedRollTiers(claimed.Roll or {})
		profileHandle.SetClaimedEstateTiers(claimed.Estate or {})
	end)

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
