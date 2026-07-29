-- Roll + Upgrade icon buttons (always visible, bottom-center) + a big
-- centered reveal overlay that only appears while spinning and briefly
-- after settling -- not a persistent small corner box. (Buy VIP moved to
-- the sidebar's Shop panel, ShopPanel.luau.)
--
-- Animation flow: every RollResult (from a manual click OR the Auto Roll
-- gamepass rolling on its own timer server-side, see AUTO ROLL button
-- below) is pushed onto `resultQueue`, drained one at a time by
-- processQueue -- never handled by overwriting a single shared variable,
-- which under Auto Roll's fast cooldown let one result silently clobber
-- another before it was ever shown. The queue's front item gets the full
-- drumroll-then-settle-then-hold treatment (playReveal) as long as it's
-- the only one waiting; anything still queued up behind it plays a short
-- "quick" reveal instead (no drumroll, brief hold) so a burst of Auto
-- Rolls catches back up to real time instead of the display permanently
-- lagging. The Roll button stays disabled for as long as the queue has
-- anything left to show.
--
-- Both the button cluster and the reveal overlay get their own
-- Theme.AutoScale UIScale (see Theme.luau) so they shrink toward their own
-- pinned anchor (bottom-center / screen-center) on narrow phone screens,
-- instead of staying full desktop size regardless of screen width.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local AutoRollConfig = require(ReplicatedStorage.Modules.AutoRollConfig)
local RollOdds = require(ReplicatedStorage.Modules.RollOdds)
local Theme = require(script.Parent.Theme)

local SPIN_MIN_DURATION = 0.9
local SPIN_INTERVAL = 0.06
local RESULT_DISPLAY_SECONDS = 1.8
-- Backlog items (see processQueue) skip the drumroll and hold for this
-- instead of RESULT_DISPLAY_SECONDS -- still long enough to actually read,
-- short enough that a burst of Auto Rolls catches back up quickly.
local QUICK_DISPLAY_SECONDS = 0.6

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
local ROLL_ICON_SIZE = 154
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

function RollPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local rollRequested = remotes:WaitForChild("RollRequested")
	local rollResult = remotes:WaitForChild("RollResult")
	local setAutoRoll = remotes:WaitForChild("SetAutoRoll")
	local autoRollUpdated = remotes:WaitForChild("AutoRollUpdated")

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

	local upgradeOffsetX = ROLL_ICON_SIZE / 2 + ICON_GAP + UPGRADE_ICON_SIZE / 2

	local rollButton, rollIcon = createIconButton(
		hudContainer,
		ROLL_ICON_SIZE,
		UDim2.new(0.5, 0, 0, 0),
		HUD_BASELINE_Y,
		"rbxassetid://92855815758385",
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
		HUD_BASELINE_Y - 24,
		"rbxassetid://119321429785408",
		"UPGRADE",
		LABEL_COLOR
	)
	local upgradeLabel = upgradeButton:FindFirstChildOfClass("TextLabel")
	if upgradeLabel then
		upgradeLabel.Position = UDim2.new(0.5, 0, 1, -4)
	end

	-- ===== Auto Roll pill, to the LEFT of ROLL, same raised baseline as
	-- UPGRADE. Not owned -> prompts the gamepass purchase. Owned -> toggles
	-- the server-side auto-roll loop (AutoRollManager/RollManager.TryRoll).
	local autoRollOffsetX = -(ROLL_ICON_SIZE / 2 + ICON_GAP + AUTO_ROLL_BUTTON_WIDTH / 2)

	local autoRollButton = Instance.new("TextButton")
	autoRollButton.Size = UDim2.new(0, AUTO_ROLL_BUTTON_WIDTH, 0, AUTO_ROLL_BUTTON_HEIGHT)
	autoRollButton.AnchorPoint = Vector2.new(0.5, 1)
	autoRollButton.Position = UDim2.new(0.5, autoRollOffsetX, 0, HUD_BASELINE_Y - 24)
	autoRollButton.BackgroundColor3 = Theme.Colors.Surface
	autoRollButton.BorderSizePixel = 0
	autoRollButton.AutoButtonColor = false
	autoRollButton.Text = "AUTO ROLL"
	autoRollButton.Font = Theme.Fonts.Header
	autoRollButton.TextScaled = true
	autoRollButton.TextColor3 = LABEL_COLOR
	autoRollButton.TextStrokeTransparency = 0
	autoRollButton.TextStrokeColor3 = Color3.new(0, 0, 0)
	autoRollButton.Parent = hudContainer
	Theme.Round(autoRollButton, UDim.new(0, 10))
	Theme.Stroke(autoRollButton, Color3.fromRGB(255, 215, 140), 1)

	local autoRollTextPadding = Instance.new("UIPadding")
	autoRollTextPadding.PaddingLeft = UDim.new(0.08, 0)
	autoRollTextPadding.PaddingRight = UDim.new(0.08, 0)
	autoRollTextPadding.PaddingTop = UDim.new(0.15, 0)
	autoRollTextPadding.PaddingBottom = UDim.new(0.15, 0)
	autoRollTextPadding.Parent = autoRollButton

	local ownsAutoRoll = false
	local autoRollEnabled = false

	local function refreshAutoRollButton()
		if not ownsAutoRoll then
			autoRollButton.Text = "AUTO ROLL"
			autoRollButton.BackgroundColor3 = Theme.Colors.Surface
		elseif autoRollEnabled then
			autoRollButton.Text = "AUTO ROLL: ON"
			autoRollButton.BackgroundColor3 = Theme.Colors.Success
		else
			autoRollButton.Text = "AUTO ROLL: OFF"
			autoRollButton.BackgroundColor3 = Theme.Colors.Surface
		end
	end
	refreshAutoRollButton()

	autoRollButton.Activated:Connect(function()
		if not ownsAutoRoll then
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, AutoRollConfig.GamepassId)
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
	end)

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
	revealIcon.Size = UDim2.new(0, 150, 0, 150)
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

	-- Every RollResult (manual click OR Auto Roll) lands here first instead
	-- of a single shared variable -- Auto Roll's cooldown (0.75s VIP/1.5s
	-- base) is faster than one full spin+hold cycle (~2.7s), so multiple
	-- results routinely arrive before the previous one finishes showing.
	-- A single `pendingResult` variable (the old design) just got
	-- overwritten by whichever arrived last, silently discarding every
	-- roll in between -- items/cash were still granted correctly server-
	-- side, but the player would see no feedback for most of their rolls.
	-- The queue guarantees every result eventually gets shown.
	local resultQueue: { any } = {}
	local isSpinning = false

	local function setRollEnabled(enabled: boolean)
		rollButton.Active = enabled
		rollIcon.ImageTransparency = enabled and 0 or 0.6
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

	-- Shows one already-known item (unlike the old design, the item is
	-- always known before this runs -- it only gets called once RollResult
	-- has actually arrived, whether from a manual click or Auto Roll).
	-- `quick` skips the random-cycling drumroll and shortens the hold --
	-- used for backlog items so a queue built up during a burst of Auto
	-- Rolls catches back up to real time instead of falling permanently
	-- behind.
	local function playReveal(item, quick: boolean)
		revealAnchor.Visible = true

		if not quick then
			local startTime = os.clock()
			while os.clock() - startTime < SPIN_MIN_DURATION do
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

		task.wait(quick and QUICK_DISPLAY_SECONDS or RESULT_DISPLAY_SECONDS)
		revealAnchor.Visible = false
	end

	-- Drains resultQueue one item at a time. Only the LAST item still
	-- queued at the moment each one starts gets the full drumroll+hold --
	-- everything ahead of it in a backlog plays "quick" instead, so a
	-- burst of Auto Rolls catches up instead of the display lagging
	-- further and further behind real time.
	local function processQueue()
		isSpinning = true
		setRollEnabled(false)

		while #resultQueue > 0 do
			local item = table.remove(resultQueue, 1)
			local quick = #resultQueue > 0
			playReveal(item, quick)
		end

		isSpinning = false
		setRollEnabled(true)
	end

	rollButton.Activated:Connect(function()
		if isSpinning then
			return
		end
		setRollEnabled(false)
		rollRequested:FireServer()
	end)

	rollResult.OnClientEvent:Connect(function(item)
		table.insert(resultQueue, item)
		if not isSpinning then
			task.spawn(processQueue)
		end
	end)

	local handle = {}

	-- MainUI wires this to upgradesHandle.Toggle() -- RollPanel doesn't
	-- require UpgradesPanel itself, keeping the same "MainUI wires
	-- cross-panel interactions" pattern as the modalFrames coordinator.
	handle.UpgradeButton = upgradeButton

	function handle.SetOwnsAutoRoll(owns: boolean)
		ownsAutoRoll = owns
		refreshAutoRollButton()
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
