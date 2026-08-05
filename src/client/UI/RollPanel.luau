-- Roll + Upgrade icon buttons (always visible, bottom-center) + a big
-- centered reveal overlay that only appears while spinning and briefly
-- after settling -- not a persistent small corner box. (Buy VIP moved to
-- the sidebar's Shop panel, ShopPanel.luau.)
--
-- Animation flow: every RollResult (from a manual click OR Auto Roll's
-- own client-side continuation loop, see AUTO ROLL button below and
-- performRoll/continueAutoRollIfNeeded) is pushed onto `resultQueue` and
-- drained by processQueue with the SAME fixed-length drumroll every time.
-- Auto Roll never requests its next roll until the current one's reveal
-- has fully finished (continueAutoRollIfNeeded), so there is only ever
-- one roll in flight -- "Auto Roll is a normal roll, just automatic, same
-- cooldown, same everything," not a background process racing ahead of
-- what's on screen. The Roll button stays disabled for as long as the
-- queue has anything left to show.
--
-- Both the button cluster and the reveal overlay get their own
-- Theme.AutoScale UIScale (see Theme.luau) so they shrink toward their own
-- pinned anchor (bottom-center / screen-center) on narrow phone screens,
-- instead of staying full desktop size regardless of screen width.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local FastRollConfig = require(ReplicatedStorage.Modules.FastRollConfig)
local RollOdds = require(ReplicatedStorage.Modules.RollOdds)
local SpecialRollConfig = require(ReplicatedStorage.Modules.SpecialRollConfig)
local Theme = require(script.Parent.Theme)

-- Defaults (no Fast Roll gamepass) -- owning Fast Roll swaps both of these
-- for FastRollConfig's shorter values, see getSpinDuration/
-- getResultDisplaySeconds below. RARE_RESULT_DISPLAY_SECONDS is
-- deliberately untouched by Fast Roll either way (see FastRollConfig's header).
local DEFAULT_SPIN_DURATION = 0.9
local SPIN_INTERVAL = 0.06
local DEFAULT_RESULT_DISPLAY_SECONDS = 1.8
-- Legendary/Ultra/Luxury results linger longer than a normal 1.8s reveal,
-- escalating with rarity -- Ultra/Luxury especially are the "post it in
-- chat" pulls, worth actually savoring. Auto Roll naturally pauses for
-- this too (it only requests the next roll once playReveal finishes),
-- which is exactly the showcase moment intended here. Rarities not listed
-- here fall through to RESULT_DISPLAY_SECONDS (see playReveal).
local RARE_RESULT_DISPLAY_SECONDS: { [string]: number } = {
	Legendary = 3,
	Ultra = 10,
	Luxury = 10,
}
-- Which rarities get playRareHold's continuous pulsing glow (Legendary just
-- gets the longer plain hold above, no extra animation) -- Luxury alone
-- additionally gets a rotating rainbow shimmer on top of the pulse, the
-- single biggest visual escalation in the game, reserved for its one
-- rarest tier.
local RARE_HOLD_ANIMATION_RARITIES = { Ultra = true, Luxury = true }
local REVEAL_ICON_SIZE = UDim2.new(0, 150, 0, 150)
local NORMAL_DICE_IMAGE = "rbxassetid://92855815758385"

-- Plain icon + text, no background/circle chrome -- and the text sits ON
-- TOP of the icon's lower portion (overlapping it), not below it as a
-- separate label, matching the reference screenshot. Both icons sit on
-- the same bottom baseline (not the same center) -- ROLL is bigger, so
-- center-aligning it with UPGRADE would push ROLL's bottom edge lower
-- than UPGRADE's, which doesn't match the reference's row of icons that
-- all sit on one line. ROLL is anchored to the true horizontal center of
-- the container (Scale 0.5, not a fixed pixel offset) so it lands on
-- actual screen-center regardless of the container's total width;
-- UPGRADE sits a fixed offset to its right.
local ROLL_ICON_SIZE = 165
local UPGRADE_ICON_SIZE = 88
local ICON_GAP = -14
-- Auto Roll is a text pill (no bespoke icon asset), not an icon+label like
-- ROLL/UPGRADE -- mirrors UPGRADE's side offset/gap formula but to the
-- LEFT of ROLL instead of the right.
local AUTO_ROLL_BUTTON_WIDTH = 118
local AUTO_ROLL_BUTTON_HEIGHT = 40
local HUD_CONTAINER_SIZE = UDim2.new(0, 400, 0, ROLL_ICON_SIZE + 20)
local HUD_BASELINE_Y = ROLL_ICON_SIZE + 10
local HUD_REFERENCE_WIDTH = 900

-- White + black outline for both labels, matching the reference exactly
-- (not colored per-button).
local LABEL_COLOR = Color3.fromRGB(255, 255, 255)

local REVEAL_SIZE = UDim2.new(0, 380, 0, 280)
local REVEAL_REFERENCE_WIDTH = 900

-- StarterGui.EffectsGui.RareItemEffect.{Ultra,Luxury}Emitter -- Emitter2D
-- Configuration objects (see their own attributes for color/texture/etc.).
-- Fired with :Emit(amount) on settle for these two tiers only -- the
-- whole point of Ultra/Luxury is that they're rare, so only the rarest
-- pulls get a particle burst, not every roll.
local RARE_EFFECT_PATH = { "EffectsGui", "RareItemEffect" }
local RARE_EFFECT_EMITTER_NAMES = { Ultra = "UltraEmitter", Luxury = "LuxuryEmitter" }
local RARE_EFFECT_BURST_AMOUNT = 60
-- Bigger than REVEAL_SIZE and centered on the same spot -- gives the
-- burst room to spread past the reveal box's edges instead of clipping
-- exactly at it.
local RARE_EFFECT_HOST_SIZE = UDim2.new(0, 700, 0, 500)

local function formatOdds(item): string
	local oneInN = RollOdds.GetOneInN(item.Id)
	if not oneInN then
		return item.Rarity
	end
	return string.format("%s  \u{2022}  1 in %d", item.Rarity, math.floor(oneInN + 0.5))
end

-- `xPosition` is this icon's horizontal position within its parent (full
-- UDim2.X control, so ROLL can use Scale=0.5 for true centering while
-- UPGRADE uses a fixed pixel offset from it). `baselineY` is the shared
-- bottom-edge Y both icons sit on. Returns the button (click target, same
-- size as the icon) and the icon ImageLabel separately, so callers can
-- dim it for a disabled state.
local function createIconButton(parent: Instance, size: number, xPosition: UDim2, baselineY: number, iconId: string, labelText: string, labelColor: Color3): (TextButton, ImageLabel)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, size, 0, size)
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(xPosition.X.Scale, xPosition.X.Offset, 0, baselineY)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.Parent = parent

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(1, 0, 1, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = iconId
	icon.ZIndex = 1
	icon.Parent = button

	-- Bottom-anchored with a fixed pixel margin (not a Scale fraction of
	-- `size`) so ROLL's and UPGRADE's labels land at the exact same
	-- absolute height -- both buttons share one baseline, but a
	-- Scale-based label position would still put the smaller UPGRADE's
	-- text lower than ROLL's, since it's a smaller % of a smaller button.
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 14, 0, 22)
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -14)
	label.BackgroundTransparency = 1
	label.Font = Theme.Fonts.Header
	label.TextScaled = true
	label.Text = labelText
	label.TextColor3 = labelColor
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.ZIndex = 2
	label.Parent = button

	return button, icon
end

local RollPanel = {}

function RollPanel.Create(screenGui: ScreenGui, remotes: Folder, onAutoRollButtonWithoutOwnership: () -> ())
	local rollRequested = remotes:WaitForChild("RollRequested")
	local rollResult = remotes:WaitForChild("RollResult")
	local setAutoRoll = remotes:WaitForChild("SetAutoRoll")
	local autoRollUpdated = remotes:WaitForChild("AutoRollUpdated")
	local rollSpecial = remotes:WaitForChild("RollSpecial")
	local specialRollStateUpdated = remotes:WaitForChild("SpecialRollStateUpdated")

	-- NotRollable items (e.g. GroupRewardChest, exclusive to the Group
	-- Rewards claim) never come out of an actual roll -- excluded here too
	-- so the cosmetic random-cycling "drumroll" never flashes an item that
	-- can't actually be the result, and RollOdds.GetOneInN never gets
	-- asked for an odds figure that isn't well-defined for it.
	local allItems = {}
	for _, item in ItemDatabase.GetAllItems() do
		if not item.NotRollable then
			table.insert(allItems, item)
		end
	end

	-- Emitter2D requires a real GuiObject ancestor to know where/how to
	-- render (Config:FindFirstAncestorWhichIsA("GuiObject")) -- whatever
	-- "RareItemEffect" actually is in Studio (Model/Folder/Configuration
	-- aren't GuiObjects), it can't satisfy that on its own. This Frame
	-- guarantees valid ancestry unconditionally, and doubles as control
	-- over where on screen the burst appears (centered on the reveal spot).
	local rareEffectHost = Instance.new("Frame")
	rareEffectHost.Size = RARE_EFFECT_HOST_SIZE
	rareEffectHost.AnchorPoint = Vector2.new(0.5, 0.5)
	rareEffectHost.Position = UDim2.new(0.5, 0, 0.42, 0)
	rareEffectHost.BackgroundTransparency = 1
	rareEffectHost.Parent = screenGui

	-- Resolved once, lazily, off the main thread -- StarterGui clones into
	-- PlayerGui asynchronously, and a missing/misnamed effect should never
	-- block or error out the roll button itself.
	local rareEffectEmitters: { [string]: Configuration } = {}
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local container = playerGui
		for _, name in RARE_EFFECT_PATH do
			local ok, child = pcall(function()
				return container:WaitForChild(name, 10)
			end)
			container = ok and child or nil
			if not container then
				warn(string.format("[RollPanel] Rare item effect not found: PlayerGui.%s missing", table.concat(RARE_EFFECT_PATH, ".")))
				return
			end
		end

		for rarity, emitterName in RARE_EFFECT_EMITTER_NAMES do
			local emitter = container:FindFirstChild(emitterName)
			if emitter then
				rareEffectEmitters[rarity] = emitter
				-- Reparent into our known-good Frame -- fixes ValidAncestry
				-- regardless of what RareItemEffect's actual class is.
				emitter.Parent = rareEffectHost
				-- Force the tag on ourselves instead of trusting it was
				-- saved correctly in Studio -- the Emit/Clear/SetSeeds
				-- children visible in the Explorer were created by the
				-- Studio PLUGIN's own preview (which doesn't run during
				-- Play/live gameplay), not necessarily by an actual
				-- CollectionService tag the runtime loader would see.
				CollectionService:AddTag(emitter, "Emitter2D")
			else
				warn(string.format("[RollPanel] Rare item effect missing emitter '%s' for %s", emitterName, rarity))
			end
		end
	end)

	local function playRareEffect(rarity: string)
		local emitter = rareEffectEmitters[rarity]
		local emit = emitter and emitter:FindFirstChild("Emit")
		if emit then
			emit:Fire(RARE_EFFECT_BURST_AMOUNT)
		end
	end

	-- ===== Roll + Upgrade icon buttons, bottom-center =====
	local hudContainer = Instance.new("Frame")
	hudContainer.Size = HUD_CONTAINER_SIZE
	hudContainer.AnchorPoint = Vector2.new(0.5, 1)
	hudContainer.Position = UDim2.new(0.5, 0, 1, -4)
	hudContainer.BackgroundTransparency = 1
	hudContainer.Parent = screenGui
	Theme.AutoScale(screenGui, hudContainer, HUD_REFERENCE_WIDTH)

	-- Declared up here (not down by the reveal overlay where it's mainly
	-- used) so the Hide Rolls button below can reach into it too. Every
	-- RollResult (manual click OR Auto Roll) lands here first -- see
	-- processQueue further down for how it's drained.
	local resultQueue: { any } = {}
	local isSpinning = false

	-- Forward-declared: assigned its real body much further down (once
	-- ownsAutoRoll/autoRollEnabled/readyTierId all exist), but
	-- autoRollUpdated's listener below needs to be able to call it the
	-- moment Auto Roll gets toggled on, to kick off the very first roll of
	-- the chain -- everything after that first one is self-perpetuating
	-- (processQueue/the Hide Rolls branch call it again once each roll
	-- finishes), this is only for starting it from a standing stop.
	local continueAutoRollIfNeeded: () -> ()

	local upgradeOffsetX = ROLL_ICON_SIZE / 2 + ICON_GAP + UPGRADE_ICON_SIZE / 2

	local rollButton, rollIcon = createIconButton(
		hudContainer,
		ROLL_ICON_SIZE,
		UDim2.new(0.5, 0, 0, 0),
		HUD_BASELINE_Y,
		NORMAL_DICE_IMAGE,
		"ROLL",
		LABEL_COLOR
	)
	local rollLabel = rollButton:FindFirstChildOfClass("TextLabel")
	if rollLabel then
		rollLabel.Size = UDim2.new(1, 14, 0, 28)
	end

	-- Raised a bit above the shared baseline -- sitting exactly level with
	-- ROLL made the (visually lighter) arrow icon read as smaller/lower
	-- than the dice.
	local upgradeButton = createIconButton(
		hudContainer,
		UPGRADE_ICON_SIZE,
		UDim2.new(0.5, upgradeOffsetX, 0, 0),
		HUD_BASELINE_Y - 34,
		"rbxassetid://119321429785408",
		"UPGRADE",
		LABEL_COLOR
	)
	local upgradeLabel = upgradeButton:FindFirstChildOfClass("TextLabel")
	if upgradeLabel then
		upgradeLabel.Position = UDim2.new(0.5, 0, 1, -4)
	end

	-- ===== Auto Roll icon, to the LEFT of ROLL, same raised baseline and
	-- icon+overlapping-label treatment as UPGRADE (via createIconButton) --
	-- no more background pill. Not owned -> prompts the gamepass purchase.
	-- Owned -> toggles server-side ownership state (AutoRollManager); the
	-- actual rolling loop lives entirely on THIS client (see
	-- continueAutoRollIfNeeded).
	local AUTO_ROLL_ICON_SIZE = UPGRADE_ICON_SIZE
	local autoRollOffsetX = -(ROLL_ICON_SIZE / 2 + ICON_GAP + AUTO_ROLL_ICON_SIZE / 2)

	local autoRollButton, autoRollIcon = createIconButton(
		hudContainer,
		AUTO_ROLL_ICON_SIZE,
		UDim2.new(0.5, autoRollOffsetX, 0, 0),
		HUD_BASELINE_Y - 34,
		"rbxassetid://115324216729484",
		"AUTO ROLL",
		LABEL_COLOR
	)
	local autoRollLabel = autoRollButton:FindFirstChildOfClass("TextLabel")
	if autoRollLabel then
		autoRollLabel.Position = UDim2.new(0.5, 0, 1, -4)
	end

	-- ===== Hide Rolls pill, stacked right below AUTO ROLL -- only shown
	-- while Auto Roll is actually ON (a manual roller never needs it).
	-- Toggling it on stops DRAWING the drumroll/reveal popup for normal
	-- rolls -- items/cash are still granted normally server-side, and
	-- playReveal still waits the exact same total duration it always
	-- would, just with nothing on screen (see playReveal's `show` param)
	-- -- Hide Rolls is the same timer/mechanism as a visible roll, not a
	-- separate faster path, so a long Auto Roll grind still paces exactly
	-- like it would with the popup showing, just silent. Special Roll
	-- claims (Golden/Diamond/Ruby/Emerald) are NOT hidden by this -- see
	-- processQueue's IsSpecial check -- they're rare enough to always be
	-- worth seeing. Turning Auto Roll back off resets it, so a manual
	-- roll always shows its reveal again.
	local hideRollsButton = Instance.new("TextButton")
	hideRollsButton.Size = UDim2.new(0, AUTO_ROLL_BUTTON_WIDTH, 0, AUTO_ROLL_BUTTON_HEIGHT)
	hideRollsButton.AnchorPoint = Vector2.new(0.5, 0)
	hideRollsButton.Position = UDim2.new(0.5, autoRollOffsetX, 0, HUD_BASELINE_Y - 34 + 6)
	hideRollsButton.BackgroundColor3 = Theme.Colors.Surface
	hideRollsButton.BorderSizePixel = 0
	hideRollsButton.AutoButtonColor = false
	hideRollsButton.Text = "HIDE ROLLS"
	hideRollsButton.Font = Theme.Fonts.Header
	hideRollsButton.TextScaled = true
	hideRollsButton.TextColor3 = LABEL_COLOR
	hideRollsButton.TextStrokeTransparency = 0
	hideRollsButton.TextStrokeColor3 = Color3.new(0, 0, 0)
	hideRollsButton.Visible = false
	hideRollsButton.Parent = hudContainer
	Theme.Round(hideRollsButton, UDim.new(0, 10))
	Theme.Stroke(hideRollsButton, Color3.fromRGB(255, 215, 140), 1)

	local hideRollsTextPadding = Instance.new("UIPadding")
	hideRollsTextPadding.PaddingLeft = UDim.new(0.08, 0)
	hideRollsTextPadding.PaddingRight = UDim.new(0.08, 0)
	hideRollsTextPadding.PaddingTop = UDim.new(0.15, 0)
	hideRollsTextPadding.PaddingBottom = UDim.new(0.15, 0)
	hideRollsTextPadding.Parent = hideRollsButton

	local hideRolls = false

	local function refreshHideRollsButton()
		if hideRolls then
			hideRollsButton.Text = "ROLLS HIDDEN"
			hideRollsButton.BackgroundColor3 = Theme.Colors.Success
		else
			hideRollsButton.Text = "HIDE ROLLS"
			hideRollsButton.BackgroundColor3 = Theme.Colors.Surface
		end
	end
	refreshHideRollsButton()

	hideRollsButton.Activated:Connect(function()
		hideRolls = not hideRolls
		refreshHideRollsButton()
		-- Flush anything already queued so toggling mid-grind doesn't
		-- leave one last popup hanging around, or (turning it back off)
		-- silently skip whatever the queue was still holding.
		if hideRolls then
			table.clear(resultQueue)
		end
	end)

	local ownsAutoRoll = false
	local autoRollEnabled = false
	local ownsFastRoll = false

	local function getSpinDuration(): number
		return ownsFastRoll and FastRollConfig.SpinSeconds or DEFAULT_SPIN_DURATION
	end

	local function getResultDisplaySeconds(): number
		return ownsFastRoll and FastRollConfig.ResultDisplaySeconds or DEFAULT_RESULT_DISPLAY_SECONDS
	end

	-- Label always just reads "AUTO ROLL" -- on/off is shown purely via
	-- the icon's tint (green when enabled), not by changing the text.
	local function refreshAutoRollButton()
		if ownsAutoRoll and autoRollEnabled then
			autoRollIcon.ImageColor3 = Theme.Colors.Success
		else
			autoRollIcon.ImageColor3 = Color3.new(1, 1, 1)
		end

		hideRollsButton.Visible = ownsAutoRoll and autoRollEnabled
		if not hideRollsButton.Visible and hideRolls then
			hideRolls = false
			refreshHideRollsButton()
		end
	end
	refreshAutoRollButton()

	autoRollButton.Activated:Connect(function()
		if not ownsAutoRoll then
			-- "Get Auto Roll Free" popup (AutoRollFreePanel.luau) instead of
			-- jumping straight to the Robux prompt -- that's now just one of
			-- its 2 options.
			onAutoRollButtonWithoutOwnership()
			return
		end
		setAutoRoll:FireServer(not autoRollEnabled)
	end)

	-- Server echoes the actual state back (e.g. a toggle-on gets rejected
	-- if ownership somehow lapsed) -- the button always reflects that, not
	-- what was clicked.
	autoRollUpdated.OnClientEvent:Connect(function(enabled: boolean)
		autoRollEnabled = enabled
		refreshAutoRollButton()
		-- Kicks off the very first roll of the chain the instant Auto Roll
		-- turns on from a standing stop (nothing else would trigger it --
		-- there's no roll in flight yet for processQueue to continue from).
		if not isSpinning then
			continueAutoRollIfNeeded()
		end
	end)

	-- ===== Special Roll badges, floating on top of the ROLL dice itself
	-- (overlapping its top edge) -- one small icon+countdown badge per tier
	-- (Golden/Diamond/Ruby/Emerald), all visible and counting down
	-- simultaneously, no background box around the icon (just the item
	-- image + a small colored number pill under it, matching the
	-- reference exactly) -- NOT one badge that sequences through tiers one
	-- at a time. Built once from HUD_MILESTONES (fixed order/count), then
	-- just updated in place as SpecialRollStateUpdated arrives. Parented to
	-- hudContainer (same as rollButton) so it inherits the same AutoScale
	-- and hides automatically whenever handle.SetHudVisible(false) hides
	-- the whole HUD; a higher ZIndex than rollButton's (both are
	-- hudContainer's direct children, so ZIndex order between them is
	-- compared directly under Roblox's default Sibling ZIndexBehavior)
	-- makes the row render on top of the dice instead of underneath it.
	--
	-- Lucky Roll's 6 SecondsStage tiers deliberately excluded here -- they
	-- have their own dedicated 3D zone + proximity panel
	-- (LuckyRollProximityPanel.luau) to claim from, so they don't also
	-- show up on the dice HUD or factor into refreshReadyTier's
	-- dice-image-swap below. Filtered by Kind (not a specific Id list) so
	-- this stays correct regardless of how many Lucky stages exist.
	local HUD_MILESTONES = {}
	for _, tier in SpecialRollConfig.Milestones do
		if tier.Kind ~= "SecondsStage" then
			table.insert(HUD_MILESTONES, tier)
		end
	end

	local SPECIAL_BADGE_ICON_SIZE = 34
	local SPECIAL_BADGE_GAP = 1
	local SPECIAL_BADGE_COUNT_HEIGHT = 13
	local SPECIAL_BADGES_ZINDEX = 5

	local specialBadgesContainer = Instance.new("Frame")
	specialBadgesContainer.Size = UDim2.new(
		0,
		#HUD_MILESTONES * SPECIAL_BADGE_ICON_SIZE + (#HUD_MILESTONES - 1) * SPECIAL_BADGE_GAP,
		0,
		SPECIAL_BADGE_ICON_SIZE
	)
	specialBadgesContainer.AnchorPoint = Vector2.new(0.5, 0)
	-- Small enough now (26px icons) to sit fully within the dice's own top
	-- face instead of overhanging its edge -- HUD_BASELINE_Y - ROLL_ICON_SIZE
	-- is the dice's top edge within hudContainer, offset down a bit further
	-- so the row reads as "on" the die.
	specialBadgesContainer.Position = UDim2.new(0.5, 0, 0, HUD_BASELINE_Y - ROLL_ICON_SIZE + 10)
	specialBadgesContainer.BackgroundTransparency = 1
	specialBadgesContainer.ZIndex = SPECIAL_BADGES_ZINDEX
	specialBadgesContainer.Parent = hudContainer

	local specialBadgesLayout = Instance.new("UIListLayout")
	specialBadgesLayout.FillDirection = Enum.FillDirection.Horizontal
	specialBadgesLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	specialBadgesLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	specialBadgesLayout.Padding = UDim.new(0, SPECIAL_BADGE_GAP)
	specialBadgesLayout.Parent = specialBadgesContainer

	type SpecialBadge = {
		Icon: ImageLabel,
		CountLabel: TextLabel,
		ClickTarget: TextButton,
		WasAvailable: boolean,
	}

	local specialBadges: { [string]: SpecialBadge } = {}

	-- Brief pop/scale tween, played once when a tier flips from locked to
	-- available -- same idea as playSettleBounce, just enough motion to
	-- draw the eye without it being a whole animation.
	local function playSpecialBadgePop(target: GuiObject)
		local baseSize = UDim2.new(0, SPECIAL_BADGE_ICON_SIZE, 0, SPECIAL_BADGE_ICON_SIZE)
		target.Size = UDim2.new(0, SPECIAL_BADGE_ICON_SIZE * 1.2, 0, SPECIAL_BADGE_ICON_SIZE * 1.2)
		TweenService:Create(target, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = baseSize }):Play()
	end

	for badgeOrder, tier in HUD_MILESTONES do
		-- No visible background/border -- just an invisible click target
		-- the same size as the icon, so the badge stays clickable without
		-- drawing a box around it.
		local clickTarget = Instance.new("TextButton")
		clickTarget.Size = UDim2.new(0, SPECIAL_BADGE_ICON_SIZE, 0, SPECIAL_BADGE_ICON_SIZE)
		clickTarget.LayoutOrder = badgeOrder
		clickTarget.BackgroundTransparency = 1
		clickTarget.AutoButtonColor = false
		clickTarget.Text = ""
		clickTarget.ZIndex = SPECIAL_BADGES_ZINDEX
		clickTarget.Parent = specialBadgesContainer

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(1, 0, 1, 0)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = tier.Image ~= "rbxassetid://0" and tier.Image or ""
		icon.ImageTransparency = 0.3
		icon.ZIndex = SPECIAL_BADGES_ZINDEX
		icon.Parent = clickTarget

		-- Plain text, no background pill -- white fill + black outline,
		-- same look as every other number/label in this HUD.
		local countLabel = Instance.new("TextLabel")
		countLabel.Size = UDim2.new(0, SPECIAL_BADGE_ICON_SIZE + 4, 0, SPECIAL_BADGE_COUNT_HEIGHT)
		countLabel.AnchorPoint = Vector2.new(0.5, 1)
		countLabel.Position = UDim2.new(0.5, 0, 1, 2)
		countLabel.BackgroundTransparency = 1
		countLabel.Font = Theme.Fonts.Header
		countLabel.TextScaled = true
		countLabel.Text = tostring(tier.Threshold)
		countLabel.TextColor3 = Color3.new(1, 1, 1)
		countLabel.TextStrokeTransparency = 0
		countLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		countLabel.ZIndex = SPECIAL_BADGES_ZINDEX + 1
		countLabel.Parent = clickTarget

		specialBadges[tier.Id] = {
			Icon = icon,
			CountLabel = countLabel,
			ClickTarget = clickTarget,
			WasAvailable = false,
		}

		clickTarget.Activated:Connect(function()
			-- Same reasoning as rollButton.Activated below -- while Auto
			-- Roll is on, its own chain already claims ready tiers on its
			-- own (performRoll checks readyTierId first); a manual tap on
			-- a badge in between would fire an EXTRA RollSpecial request
			-- on top of that, which is what made things look like several
			-- rolls landing at once.
			if autoRollEnabled then
				return
			end
			local badge = specialBadges[tier.Id]
			if badge and badge.WasAvailable then
				rollSpecial:FireServer(tier.Id)
			end
		end)
	end

	-- Every tier that still reaches this badge row is "Rolls"-kind (Lucky
	-- Roll's "SecondsStage" tiers are filtered out of HUD_MILESTONES
	-- entirely, see above), so this is always a plain roll count now -- no
	-- more MM:SS branch needed here.
	local function formatRemaining(remaining: number): string
		return tostring(remaining)
	end

	local function refreshSpecialBadge(tierId: string, state)
		local badge = specialBadges[tierId]
		if not badge then
			return
		end

		local hasImage = state.Image and state.Image ~= "" and state.Image ~= "rbxassetid://0"
		badge.Icon.Image = hasImage and state.Image or ""

		if state.Available then
			badge.CountLabel.Text = "GO!"
			badge.CountLabel.TextColor3 = state.Color
			badge.Icon.ImageTransparency = 0
			if not badge.WasAvailable then
				playSpecialBadgePop(badge.ClickTarget)
			end
		else
			local remaining = math.max(state.Threshold - state.Progress, 0)
			badge.CountLabel.Text = formatRemaining(remaining)
			badge.CountLabel.TextColor3 = Color3.new(1, 1, 1)
			badge.Icon.ImageTransparency = 0.35
		end
		badge.WasAvailable = state.Available
	end

	-- The big dice itself doubles as the claim button for whichever
	-- Special Roll tier is ready -- swaps to that tier's image/color glow
	-- until claimed, then reverts to the normal dice. If more than one
	-- tier is ready at once (they progress independently and
	-- simultaneously), the LAST entry in HUD_MILESTONES (highest tier, e.g.
	-- Emerald over Golden) wins the dice's display; the small badges above
	-- it still show every tier's own state regardless of which one
	-- currently owns the dice. Lucky is excluded from HUD_MILESTONES
	-- entirely (see its own claim flow), so it can never win this either.
	local tierStates: { [string]: any } = {}
	local readyTierId: string? = nil

	-- Only the dice image itself swaps to the ready tier's icon -- no ring/
	-- glow, and the label always stays "ROLL" (not the tier's name).
	local function refreshReadyTier()
		local best = nil
		for _, tier in HUD_MILESTONES do
			local state = tierStates[tier.Id]
			if state and state.Available then
				best = state
			end
		end

		readyTierId = best and best.TierId or nil

		if best then
			local hasImage = best.Image and best.Image ~= "" and best.Image ~= "rbxassetid://0"
			rollIcon.Image = hasImage and best.Image or NORMAL_DICE_IMAGE
		else
			rollIcon.Image = NORMAL_DICE_IMAGE
		end
	end

	specialRollStateUpdated.OnClientEvent:Connect(function(tiers)
		for _, state in tiers do
			tierStates[state.TierId] = state
			refreshSpecialBadge(state.TierId, state)
		end
		refreshReadyTier()
	end)

	-- Fires exactly the request a manual click would -- claims the ready
	-- Special Roll tier if there is one, otherwise a normal roll. Auto
	-- Roll below reuses this so it can never behave differently from a
	-- human pressing the dice.
	local function performRoll()
		if readyTierId then
			rollSpecial:FireServer(readyTierId)
		else
			rollRequested:FireServer()
		end
	end

	-- Auto Roll is driven entirely from the CLIENT, one roll at a time --
	-- there is deliberately no server-side timer requesting rolls on its
	-- own anymore. This function is called only once the previous roll's
	-- reveal has fully finished (see processQueue) or, while Hide Rolls is
	-- on, once the previous result has been applied with no animation to
	-- wait for -- so a new roll is never requested while one is still
	-- being shown, exactly mirroring a player spamming the ROLL button as
	-- fast as it re-enables. The server's own cooldown check (RollManager.
	-- TryRoll) still guards every request regardless of who sent it.
	--
	-- Watchdog: if the request this call fires (normal or a Special Roll
	-- claim) gets silently rejected server-side -- e.g. a Special Roll
	-- tier that looked ready client-side but no longer is by the time the
	-- request lands -- no RollResult ever comes back, and nothing would
	-- ever call this again, permanently stalling Auto Roll (which looked
	-- like Special Roll progress had simply stopped advancing, since
	-- normal rolls stopped landing too). `generation` lets a stale
	-- watchdog recognize a real reply already moved things forward and
	-- skip retrying; otherwise it just tries again.
	local autoRollGeneration = 0

	-- A ready Special Roll tier (dice swapped to its image) held for this
	-- long before Auto Roll actually claims it -- otherwise a tier could
	-- become ready and get auto-claimed within the same instant, so the
	-- player would never actually get to see the dice change before it
	-- was gone again.
	local SPECIAL_ROLL_AUTO_DELAY_SECONDS = 1.5

	-- True from the moment a request is fired until its response has been
	-- handled. While Hide Rolls is on there's no animation (isSpinning
	-- never turns true) to naturally stop a second chain from starting --
	-- e.g. autoRollUpdated firing more than once (a fast double-click on
	-- AUTO ROLL) could each independently call continueAutoRollIfNeeded,
	-- and with nothing gating them, TWO+ request/response chains would run
	-- in parallel, each triggering its own next roll -- which looked
	-- exactly like "10 rolls in a second" even though each individual
	-- chain was still cooldown-paced correctly. This flag makes it
	-- impossible for more than one chain to be active at a time,
	-- regardless of how many times continueAutoRollIfNeeded gets called.
	local autoRollRequestPending = false

	continueAutoRollIfNeeded = function()
		if not (ownsAutoRoll and autoRollEnabled) then
			return
		end
		if autoRollRequestPending then
			return
		end
		autoRollRequestPending = true

		autoRollGeneration += 1
		local thisGeneration = autoRollGeneration

		local function fire()
			if thisGeneration ~= autoRollGeneration or not (ownsAutoRoll and autoRollEnabled) then
				autoRollRequestPending = false
				return
			end

			performRoll()

			task.delay(2, function()
				if thisGeneration == autoRollGeneration and ownsAutoRoll and autoRollEnabled and not isSpinning then
					autoRollRequestPending = false
					continueAutoRollIfNeeded()
				end
			end)
		end

		if readyTierId then
			task.delay(SPECIAL_ROLL_AUTO_DELAY_SECONDS, fire)
		else
			fire()
		end
	end

	-- ===== Reveal overlay, centered on screen -- hidden except during/right
	-- after a spin =====
	local revealAnchor = Instance.new("Frame")
	revealAnchor.Size = REVEAL_SIZE
	revealAnchor.AnchorPoint = Vector2.new(0.5, 0.5)
	revealAnchor.Position = UDim2.new(0.5, 0, 0.42, 0)
	revealAnchor.BackgroundTransparency = 1
	revealAnchor.Visible = false
	revealAnchor.Parent = screenGui
	Theme.AutoScale(screenGui, revealAnchor, REVEAL_REFERENCE_WIDTH)

	-- Background stays flat black for every item -- only the border
	-- (revealStroke below) cycles to the rarity color, not the fill.
	local revealFrame = Theme.Panel(revealAnchor, REVEAL_SIZE, UDim2.new(0, 0, 0, 0))
	revealFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	revealFrame.BackgroundTransparency = 0

	-- Theme.Panel's default dark gradient would muddy the solid black
	-- background -- drop it, keep the stroke/shadow framing.
	local revealGradient = revealFrame:FindFirstChildOfClass("UIGradient")
	if revealGradient then
		revealGradient:Destroy()
	end
	local revealStroke = revealFrame:FindFirstChildOfClass("UIStroke")
	if revealStroke then
		revealStroke.Thickness = 6
	end

	local revealIcon = Instance.new("ImageLabel")
	revealIcon.Size = REVEAL_ICON_SIZE
	revealIcon.AnchorPoint = Vector2.new(0.5, 0)
	revealIcon.Position = UDim2.new(0.5, 0, 0, 20)
	revealIcon.BackgroundTransparency = 1
	revealIcon.ScaleType = Enum.ScaleType.Fit
	revealIcon.Image = ""
	revealIcon.Parent = revealFrame

	local revealLabel = Theme.Label(revealFrame, UDim2.new(1, -32, 0, 40), "", true)
	revealLabel.Position = UDim2.new(0, 16, 0, 180)
	revealLabel.TextXAlignment = Enum.TextXAlignment.Center
	revealLabel.TextYAlignment = Enum.TextYAlignment.Center
	revealLabel.TextWrapped = true

	-- Rarity + "1 in N" base odds.
	local oddsLabel = Theme.Label(revealFrame, UDim2.new(1, -32, 0, 30), "")
	oddsLabel.Position = UDim2.new(0, 16, 0, 222)
	oddsLabel.TextXAlignment = Enum.TextXAlignment.Center
	oddsLabel.TextYAlignment = Enum.TextYAlignment.Center
	oddsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	oddsLabel.TextStrokeTransparency = 0.5
	oddsLabel.TextWrapped = true

	-- Also disables every Special Roll badge while a reveal is animating --
	-- claiming one mid-animation used to queue its result straight behind
	-- whatever was still playing, showing the new item before the current
	-- reveal had actually finished. Now a badge simply can't be tapped
	-- until the dice itself is free again, same as ROLL.
	local function setRollEnabled(enabled: boolean)
		rollButton.Active = enabled
		rollIcon.ImageTransparency = enabled and 0 or 0.6
		for _, badge in specialBadges do
			badge.ClickTarget.Active = enabled
		end
	end

	local function playSettleBounce()
		revealFrame.Size = UDim2.new(0, REVEAL_SIZE.X.Offset * 1.1, 0, REVEAL_SIZE.Y.Offset * 1.1)
		local tween = TweenService:Create(
			revealFrame,
			TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = REVEAL_SIZE }
		)
		tween:Play()

		-- Bright flash on the border that fades back to the normal subtle
		-- stroke over a second -- a little glow highlight on the result.
		if revealStroke then
			revealStroke.Transparency = 0
			TweenService:Create(revealStroke, TweenInfo.new(1, Enum.EasingStyle.Quad), { Transparency = 0.35 }):Play()
		end
	end

	-- Ultra/Luxury's extended hold (see RARE_RESULT_DISPLAY_SECONDS) gets a
	-- continuous pulsing glow instead of just sitting there static after
	-- playSettleBounce's one-shot flash fades -- Luxury additionally gets a
	-- rotating rainbow shimmer on the border on top of that pulse. Tweens
	-- are explicit RepeatCount=-1 loops, so they're Cancel()ed and every
	-- property reset to its resting state before this returns --
	-- revealStroke/revealIcon are reused by every future reveal, a dangling
	-- infinite tween left running would bleed into a later Common's reveal.
	local function playRareHold(rarity: string, durationSeconds: number)
		local activeTweens: { Tween } = {}
		local shimmerGradient: UIGradient? = nil

		-- Setup + the wait both run inside the pcall -- if anything errors
		-- partway through (a nil index, a bad TweenInfo, etc.), the RepeatCount
		-- = -1 tweens created before the error would otherwise keep looping on
		-- revealStroke/revealIcon forever in the background (both are reused
		-- by every future reveal), silently corrupting every reveal after this
		-- one. The cleanup below always runs regardless, success or error.
		local ok = pcall(function()
			if revealStroke then
				revealStroke.Thickness = 10
				local pulseTween = TweenService:Create(
					revealStroke,
					TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Transparency = 0.05 }
				)
				pulseTween:Play()
				table.insert(activeTweens, pulseTween)
			end

			local iconPulseTween = TweenService:Create(
				revealIcon,
				TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Size = UDim2.new(0, REVEAL_ICON_SIZE.X.Offset * 1.12, 0, REVEAL_ICON_SIZE.Y.Offset * 1.12) }
			)
			iconPulseTween:Play()
			table.insert(activeTweens, iconPulseTween)

			if rarity == "Luxury" and revealStroke then
				shimmerGradient = Instance.new("UIGradient")
				shimmerGradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 170)),
					ColorSequenceKeypoint.new(0.33, Color3.fromRGB(255, 230, 80)),
					ColorSequenceKeypoint.new(0.66, Color3.fromRGB(80, 200, 255)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 170)),
				})
				shimmerGradient.Parent = revealStroke
				local shimmerTween = TweenService:Create(
					shimmerGradient,
					TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, false),
					{ Rotation = 360 }
				)
				shimmerTween:Play()
				table.insert(activeTweens, shimmerTween)
			end

			task.wait(durationSeconds)
		end)

		if not ok then
			warn("[RollPanel] playRareHold errored mid-animation, cleaning up early")
		end

		for _, tween in activeTweens do
			tween:Cancel()
		end
		if shimmerGradient then
			shimmerGradient:Destroy()
		end
		if revealStroke then
			revealStroke.Thickness = 6
			revealStroke.Transparency = 0.35
		end
		revealIcon.Size = REVEAL_ICON_SIZE
	end

	-- Shows one already-known item (unlike the old design, the item is
	-- always known before this runs -- it only gets called once RollResult
	-- has actually arrived, whether from a manual click or Auto Roll).
	-- Always the same fixed-length drumroll+settle+hold, exactly like a
	-- single manual roll -- there is no "catch up" logic anymore because
	-- there is nothing to catch up on: Auto Roll only ever requests the
	-- next roll after this one has fully finished (see
	-- continueAutoRollIfNeeded), so at most one result is ever in flight.
	-- `show = false` (Hide Rolls, see the button above, for non-Special
	-- rolls) skips every visible mutation but still waits the EXACT same
	-- total duration -- Hide Rolls uses the identical timer/mechanism as a
	-- normal roll, just with nothing drawn, instead of a separate
	-- untimed/instant path (which was only bounded by network round-trip +
	-- cooldown and could fire far faster than a real roll ever paces).
	local function playReveal(item, show: boolean)
		-- Rare showcase holds are untouched by Fast Roll even though the
		-- normal display time is (see FastRollConfig's header) -- fall
		-- through to the (possibly shortened) default only when this
		-- rarity has no dedicated hold time of its own.
		local resultDisplaySeconds = RARE_RESULT_DISPLAY_SECONDS[item.Rarity] or getResultDisplaySeconds()
		local spinDuration = getSpinDuration()

		if not show then
			task.wait(spinDuration + resultDisplaySeconds)
			return
		end

		revealAnchor.Visible = true

		local startTime = os.clock()
		while os.clock() - startTime < spinDuration do
			local randomItem = allItems[math.random(1, #allItems)]
			local randomColor = RarityConfig.GetColor(randomItem.Rarity)
			revealLabel.Text = randomItem.Name
			oddsLabel.Text = formatOdds(randomItem)
			oddsLabel.TextColor3 = randomColor
			revealIcon.Image = randomItem.Image
			if revealStroke then
				revealStroke.Color = randomColor
			end
			task.wait(SPIN_INTERVAL)
		end

		local finalColor = RarityConfig.GetColor(item.Rarity)
		revealLabel.Text = item.Name
		oddsLabel.Text = formatOdds(item)
		oddsLabel.TextColor3 = finalColor
		revealIcon.Image = item.Image
		if revealStroke then
			revealStroke.Color = finalColor
		end
		playSettleBounce()
		playRareEffect(item.Rarity)

		if RARE_HOLD_ANIMATION_RARITIES[item.Rarity] then
			playRareHold(item.Rarity, resultDisplaySeconds)
		else
			task.wait(resultDisplaySeconds)
		end
		revealAnchor.Visible = false
	end

	-- FIFO, one at a time -- in practice never holds more than a single
	-- entry, since Auto Roll only requests the next roll once this loop
	-- has finished (see continueAutoRollIfNeeded), so nothing new arrives
	-- while something is already queued. Kept as a queue (not a single
	-- variable) only as a safety net for the rare edge case of a
	-- request landing right as Auto Roll gets toggled off/on.
	local function processQueue()
		isSpinning = true
		setRollEnabled(false)

		while #resultQueue > 0 do
			local entry = table.remove(resultQueue, 1)
			-- Special Roll claims always show, even with Hide Rolls on --
			-- everything else respects it.
			playReveal(entry.Item, not hideRolls or entry.IsSpecial == true)
			-- Applied only now that THIS roll's reveal has actually
			-- finished playing -- not when the server originally sent it
			-- -- so the progress badges advance by exactly 1 per roll the
			-- player actually sees.
			if entry.Tiers then
				for _, state in entry.Tiers do
					tierStates[state.TierId] = state
					refreshSpecialBadge(state.TierId, state)
				end
				refreshReadyTier()
			end
		end

		isSpinning = false
		setRollEnabled(true)
		autoRollRequestPending = false
		continueAutoRollIfNeeded()
	end

	rollButton.Activated:Connect(function()
		if isSpinning then
			return
		end
		-- While Auto Roll is on, the chain (continueAutoRollIfNeeded)
		-- already requests every roll on its own -- a manual tap on the
		-- dice in between two auto rolls used to ALSO fire performRoll(),
		-- injecting an extra request on top of the automatic one. That's
		-- exactly what made it look like several rolls were happening at
		-- once: one from the auto chain, one from the click. Auto Roll
		-- being on means the dice isn't a manual trigger anymore.
		if autoRollEnabled then
			return
		end
		setRollEnabled(false)
		performRoll()
	end)

	-- Every result goes through the SAME queue/isSpinning pipeline
	-- regardless of Hide Rolls -- see playReveal's `show` parameter for
	-- where hiding actually happens (same timer, nothing drawn), instead
	-- of a separate untimed path that let Auto Roll fire far faster than
	-- a real roll's pacing while hidden.
	rollResult.OnClientEvent:Connect(function(item, tiers, isSpecial: boolean?)
		table.insert(resultQueue, { Item = item, Tiers = tiers, IsSpecial = isSpecial })
		if not isSpinning then
			task.spawn(processQueue)
		end
	end)

	local handle = {}

	-- MainUI wires this to upgradesHandle.Toggle() -- RollPanel doesn't
	-- require UpgradesPanel itself, keeping the same "MainUI wires
	-- cross-panel interactions" pattern as the modalFrames coordinator.
	handle.UpgradeButton = upgradeButton
	-- Exposed so OnboardingTutorial.luau can point its Step 1 arrow/glow at
	-- the actual dice button instead of guessing its screen position.
	handle.RollButton = rollButton

	function handle.SetOwnsAutoRoll(owns: boolean)
		ownsAutoRoll = owns
		refreshAutoRollButton()
	end

	function handle.SetOwnsFastRoll(owns: boolean)
		ownsFastRoll = owns
	end

	-- Hidden while any modal panel (shop, net worth, etc.) is open -- on
	-- short viewports, RollPanel's bottom-anchored button has nowhere to go
	-- that a centered/top modal can't reach, so MainUI hides these instead
	-- of chasing an ever-shrinking gap with positioning alone.
	function handle.SetHudVisible(visible: boolean)
		hudContainer.Visible = visible
		if not visible then
			revealAnchor.Visible = false
		end
	end

	return handle
end

return RollPanel
