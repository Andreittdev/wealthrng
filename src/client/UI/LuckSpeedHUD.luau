-- Always-visible bottom-left icon+value pair showing your current
-- effective Luck multiplier (clover) and Roll cooldown in seconds (the
-- same dice image as RollPanel's ROLL button) -- icon on top, bold
-- white/black-outline value text below it, no background chrome, matching
-- the reference screenshot and the same icon+overlaid-label convention
-- already used for RollPanel's ROLL/UPGRADE/AUTO ROLL and Sidebar's
-- buttons.
--
-- Recomputed entirely client-side from data the client already receives
-- (StatsUpdated/UpgradesUpdated/PotionUpdated) using the exact same shared
-- config functions RollManager.pickRarity/TryRoll use server-side
-- (VIPConfig + PotionConfig + UpgradeConfig, all stacking multiplicatively)
-- -- no new remote needed, and the displayed numbers can't drift from what
-- a roll actually does.
--
-- Luck is per-rarity in this game (see RarityConfig's header), so there's
-- no single "true" Luck number -- this shows the multiplier for Luxury,
-- the top "chase" tier, as the one most worth watching climb.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local RollConfig = require(ReplicatedStorage.Modules.RollConfig)
local PotionConfig = require(ReplicatedStorage.Modules.PotionConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local Theme = require(script.Parent.Theme)

local LuckSpeedHUD = {}

local DISPLAY_RARITY = "Luxury"
local ICON_SIZE = 64
local VALUE_HEIGHT = 26
local BADGE_WIDTH = 90
local BADGE_GAP = 12

-- Same dice image RollPanel.luau's ROLL button uses -- reused here so the
-- speed badge visually reads as "the same dice" rather than a different icon.
local DICE_IMAGE = "rbxassetid://92855815758385"
local CLOVER_ICON_TEXT = "\u{1F340}"

local function createImageBadge(parent: Instance, position: UDim2, imageId: string): TextLabel
	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, BADGE_WIDTH, 0, ICON_SIZE + VALUE_HEIGHT)
	container.Position = position
	container.BackgroundTransparency = 1
	container.Parent = parent

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = imageId
	icon.Parent = container

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(1, 0, 0, VALUE_HEIGHT)
	valueLabel.Position = UDim2.new(0, 0, 0, ICON_SIZE)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Theme.Fonts.Header
	valueLabel.TextScaled = true
	valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	valueLabel.TextStrokeTransparency = 0
	valueLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	valueLabel.Parent = container

	return valueLabel
end

local function createTextIconBadge(parent: Instance, position: UDim2, iconText: string): TextLabel
	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, BADGE_WIDTH, 0, ICON_SIZE + VALUE_HEIGHT)
	container.Position = position
	container.BackgroundTransparency = 1
	container.Parent = parent

	local icon = Instance.new("TextLabel")
	icon.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.new(0.5, 0, 0, 0)
	icon.BackgroundTransparency = 1
	icon.Text = iconText
	icon.TextScaled = true
	icon.Parent = container

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(1, 0, 0, VALUE_HEIGHT)
	valueLabel.Position = UDim2.new(0, 0, 0, ICON_SIZE)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Theme.Fonts.Header
	valueLabel.TextScaled = true
	valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	valueLabel.TextStrokeTransparency = 0
	valueLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	valueLabel.Parent = container

	return valueLabel
end

function LuckSpeedHUD.Create(screenGui: ScreenGui)
	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, BADGE_WIDTH * 2 + BADGE_GAP, 0, ICON_SIZE + VALUE_HEIGHT)
	container.AnchorPoint = Vector2.new(0, 1)
	container.Position = UDim2.new(0, 16, 1, -16)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	local luckValueLabel = createTextIconBadge(container, UDim2.new(0, 0, 0, 0), CLOVER_ICON_TEXT)
	local speedValueLabel = createImageBadge(container, UDim2.new(0, BADGE_WIDTH + BADGE_GAP, 0, 0), DICE_IMAGE)

	local isVIP = false
	local upgrades: { [string]: number } = {}
	local activePotions: { [string]: number } = {}

	local function refresh()
		local now = os.time()
		local potionSession = { ActivePotions = activePotions }

		local luck = 1
		if isVIP then
			luck *= VIPConfig.LuckWeightMultiplier[DISPLAY_RARITY]
		end
		luck *= PotionConfig.GetLuckMultiplier(potionSession, DISPLAY_RARITY, now)
		luck *= UpgradeConfig.GetLuckMultiplier(upgrades.Luck or 0, DISPLAY_RARITY)
		luckValueLabel.Text = string.format("x%.2f", luck)

		local cooldown = isVIP and VIPConfig.RollCooldownSeconds or RollConfig.BaseCooldownSeconds
		cooldown *= PotionConfig.GetCooldownMultiplier(potionSession, now)
		cooldown *= UpgradeConfig.GetCooldownMultiplier(upgrades.RollSpeed or 0)
		-- Capital S, not lowercase -- LuckiestGuy's lowercase "s" reads as a
		-- "5" at this size/boldness.
		speedValueLabel.Text = string.format("%.2fS", cooldown)
	end

	refresh()

	-- Active Potions expire on their own clock -- tick once a second so
	-- both badges drop back to baseline the moment a buff runs out,
	-- instead of only updating whenever the next server push happens to
	-- land.
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)

	local handle = {}
	handle.Frame = container

	function handle.SetVIP(value: boolean)
		isVIP = value
		refresh()
	end

	function handle.SetUpgrades(newUpgrades: { [string]: number })
		upgrades = newUpgrades
		refresh()
	end

	function handle.SetActivePotions(potions: { [string]: number })
		activePotions = potions
		refresh()
	end

	return handle
end

return LuckSpeedHUD
