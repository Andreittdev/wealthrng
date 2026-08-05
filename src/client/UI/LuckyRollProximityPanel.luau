-- Small popup that appears automatically -- same proximity-only pattern as
-- GroupRewardsProximityPanel.luau/VIPProximityPanel.luau, no ProximityPrompt/
-- "Press E" -- while standing near the grass "Lucky Roll" floor marker
-- (MapBuilder's buildFloorMarker). Deliberately minimal, per request: just
-- the dice icon (reusing the same image RollPanel's ROLL button uses, not
-- a custom 3D dice model), the odds multiplier, a countdown timer, and a
-- Claim/Locked state -- no title, no description.
--
-- Lucky Roll is 6 SpecialRollConfig tiers (Kind = "SecondsStage", Ids
-- "Lucky1".."Lucky6"), not one -- they all share ONE underlying online-time
-- counter (see RollManager.luau's per-second loop) that climbs across a
-- 90-minute cycle, each stage unlocking every 15 minutes with a bigger
-- Ultra-odds multiplier (195x -> 5000x). Claiming an early stage does NOT
-- reset the shared counter -- only claiming the final stage (Lucky6) does,
-- starting a fresh climb from Stage I. This panel only ever shows ONE
-- stage at a time: whichever is next to claim (see pickCurrentStage below)
-- -- state comes from SpecialRollStateUpdated (pushed on join, and every
-- ~5s while online so the countdown stays roughly live) and RollResult's
-- piggybacked tiers snapshot (for an immediate refresh right after a
-- claim, instead of waiting up to 5s for the next periodic push). Claiming
-- fires the same RollSpecial(tierId) request regardless of which UI
-- triggered it -- one server-side code path (RollManager.TrySpecialRoll).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpecialRollConfig = require(ReplicatedStorage.Modules.SpecialRollConfig)
local AutoClaimConfig = require(ReplicatedStorage.Modules.AutoClaimConfig)
local Theme = require(script.Parent.Theme)
local ProximityWatcher = require(script.Parent.ProximityWatcher)

local LuckyRollProximityPanel = {}

local PROXIMITY_RADIUS_STUDS = 10
local DICE_IMAGE = "rbxassetid://92855815758385"
local LUCKY_COLOR = Color3.fromRGB(180, 100, 255)

local function formatCountdown(remainingSeconds: number): string
	local wholeSeconds = math.max(0, math.floor(remainingSeconds))
	return string.format("%d:%02d", wholeSeconds // 60, wholeSeconds % 60)
end

function LuckyRollProximityPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local rollSpecial = remotes:WaitForChild("RollSpecial")
	local rollResult = remotes:WaitForChild("RollResult")
	local specialRollStateUpdated = remotes:WaitForChild("SpecialRollStateUpdated")
	local statsUpdated = remotes:WaitForChild("StatsUpdated")
	local setAutoClaim = remotes:WaitForChild("SetAutoClaim")
	local autoClaimUpdated = remotes:WaitForChild("AutoClaimUpdated")

	-- The 6 stage tier defs, sorted weakest -> strongest by Threshold --
	-- pickCurrentStage below walks this order to find whichever one is
	-- next. Static (SpecialRollConfig never changes at runtime), built once.
	local luckyStages: { SpecialRollConfig.Tier } = {}
	for _, tier in SpecialRollConfig.Milestones do
		if tier.Kind == "SecondsStage" and tier.ProgressKey == "Lucky" then
			table.insert(luckyStages, tier)
		end
	end
	table.sort(luckyStages, function(a, b)
		return a.Threshold < b.Threshold
	end)

	local stageCount = #luckyStages

	-- Per-stage live state, keyed by tier Id -- seeded with zeroed-out
	-- defaults so the panel renders sensibly (Stage I, Locked, full
	-- countdown) before the first server push ever arrives.
	local stageStates: { [string]: { Progress: number, Threshold: number, Available: boolean } } = {}
	for _, tier in luckyStages do
		stageStates[tier.Id] = { Progress = 0, Threshold = tier.Threshold, Available = false }
	end
	local lastPushAt = os.clock()

	-- Centered, not bottom-anchored with a fixed "-234" offset -- that fixed
	-- offset sat the panel right up against the top of a short landscape
	-- phone screen (same issue DailyRewardsProximityPanel had). Safe to
	-- center: this panel is already in MainUI's modalFrames list, so
	-- RollPanel's bottom HUD is hidden the whole time this is open anyway.
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 220, 0, 224)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 8
	panel.Parent = screenGui
	Theme.Round(panel)
	Theme.Stroke(panel, LUCKY_COLOR, 1)
	local panelShadow = Theme.Shadow(panel)
	-- Fixed-pixel popup -- shrinks as one unit toward its bottom-center
	-- anchor on narrow phone screens instead of running off the edges.
	-- Shadow needs its own matching call, see GroupRewardsProximityPanel's
	-- comment for why. The autoClaimBadge/priceFloatLabel below are children
	-- of `panel` (or of autoClaimBadge, itself a child of panel), so they
	-- scale along with everything else automatically.
	Theme.AutoScale(screenGui, panel, 220)
	Theme.AutoScale(screenGui, panelShadow, 220)

	-- Auto Claim gamepass badge -- sits right on the panel's own border
	-- (top-right corner), not inside the main icon/odds/timer stack.
	-- "Buy" while unowned (opens the purchase prompt); once owned it
	-- becomes a real ON/OFF toggle (green/red, see refreshAutoClaimBadge
	-- further down) -- RollManager.luau's per-second loop only auto-claims
	-- while it's ON. The price itself isn't in this text anymore -- see
	-- priceFloatLabel just below, a separate bobbing "9 R$" tag to its
	-- right, same idea as a floating price tag in a mobile-game shop icon.
	local autoClaimBadge = Instance.new("TextButton")
	autoClaimBadge.Size = UDim2.new(0, 130, 0, 34)
	autoClaimBadge.AnchorPoint = Vector2.new(0.5, 0)
	autoClaimBadge.Position = UDim2.new(0.5, -14, 0, -17)
	autoClaimBadge.BackgroundColor3 = LUCKY_COLOR
	autoClaimBadge.BorderSizePixel = 0
	autoClaimBadge.AutoButtonColor = true
	autoClaimBadge.Text = "AUTO CLAIM: BUY"
	autoClaimBadge.Font = Theme.Fonts.Header
	autoClaimBadge.TextScaled = true
	autoClaimBadge.TextWrapped = true
	autoClaimBadge.TextColor3 = Color3.fromRGB(20, 20, 20)
	autoClaimBadge.ZIndex = 9
	autoClaimBadge.Parent = panel
	Theme.Round(autoClaimBadge, UDim.new(1, 0))
	Theme.Stroke(autoClaimBadge, Color3.new(0, 0, 0), 1)
	local autoClaimBadgeTextSize = Instance.new("UITextSizeConstraint")
	autoClaimBadgeTextSize.MaxTextSize = 17
	autoClaimBadgeTextSize.Parent = autoClaimBadge

	-- Floating "9 R$" price tag to the badge's right -- gently bobs up and
	-- down forever (a gentle Sine in/out Position tween, RepeatCount=-1,
	-- Reverses=true) to draw the eye toward it, same "can't miss it"
	-- purpose a floating price tag serves in mobile-game shop icons.
	-- Hidden once the gamepass is owned (see refreshAutoClaimBadge below)
	-- -- there's nothing left to buy at that point.
	local priceFloatLabel = Instance.new("TextLabel")
	priceFloatLabel.Size = UDim2.new(0, 72, 0, 22)
	priceFloatLabel.AnchorPoint = Vector2.new(0, 0.5)
	priceFloatLabel.Position = UDim2.new(0.5, 60, 0.5, 0)
	priceFloatLabel.BackgroundTransparency = 1
	priceFloatLabel.Font = Theme.Fonts.Header
	priceFloatLabel.TextScaled = true
	priceFloatLabel.Text = "Only 9 R$"
	priceFloatLabel.TextColor3 = Color3.fromRGB(80, 220, 120)
	priceFloatLabel.TextStrokeTransparency = 0
	priceFloatLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	priceFloatLabel.ZIndex = 9
	priceFloatLabel.Parent = autoClaimBadge

	local priceFloatBasePosition = priceFloatLabel.Position
	TweenService:Create(
		priceFloatLabel,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = priceFloatBasePosition + UDim2.new(0, 0, 0, -6) }
	):Play()

	local diceIcon = Instance.new("ImageLabel")
	diceIcon.Size = UDim2.new(0, 64, 0, 64)
	diceIcon.AnchorPoint = Vector2.new(0.5, 0)
	diceIcon.Position = UDim2.new(0.5, 0, 0, 12)
	diceIcon.BackgroundTransparency = 1
	diceIcon.ScaleType = Enum.ScaleType.Fit
	diceIcon.Image = DICE_IMAGE
	diceIcon.Parent = panel

	-- Every TextScaled label/button below gets a UITextSizeConstraint
	-- capping it well under what TextScaled would otherwise fill its box
	-- with -- same pattern as AssetShopPanel's tab buttons (Theme.Label/
	-- Theme.Button don't expose a font-size knob of their own).
	local function capTextSize(target: TextLabel | TextButton, maxTextSize: number)
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = maxTextSize
		constraint.Parent = target
	end

	local oddsLabel = Theme.Label(panel, UDim2.new(1, -20, 0, 24), "", true)
	oddsLabel.Position = UDim2.new(0, 10, 0, 82)
	oddsLabel.TextXAlignment = Enum.TextXAlignment.Center
	oddsLabel.TextColor3 = LUCKY_COLOR
	capTextSize(oddsLabel, 18)

	local stageLabel = Theme.Label(panel, UDim2.new(1, -20, 0, 18), "", true)
	stageLabel.Position = UDim2.new(0, 10, 0, 106)
	stageLabel.TextXAlignment = Enum.TextXAlignment.Center
	stageLabel.TextColor3 = Theme.Colors.TextSecondary
	capTextSize(stageLabel, 14)

	local timerLabel = Theme.Label(panel, UDim2.new(1, -20, 0, 26), "", true)
	timerLabel.Position = UDim2.new(0, 10, 0, 130)
	timerLabel.TextXAlignment = Enum.TextXAlignment.Center
	timerLabel.TextColor3 = Color3.new(1, 1, 1)
	capTextSize(timerLabel, 18)

	local actionButton = Theme.Button(panel, UDim2.new(1, -24, 0, 40), UDim2.new(0, 12, 1, -50), "Locked", true)
	capTextSize(actionButton, 16)

	-- Floating over the dice pile marker itself, matching the reference
	-- screenshot's layout -- built once the marker part resolves (see the
	-- task.spawn below), always visible at a distance (not gated by
	-- proximity like `panel` is), kept live by the SAME refresh() that
	-- updates the close-up panel.
	local billboardOddsLabel: TextLabel? = nil
	local billboardStageLabel: TextLabel? = nil
	local billboardTimerLabel: TextLabel? = nil
	local billboardStateLabel: TextLabel? = nil

	-- Which stage to show: the earliest (lowest Threshold) one that's
	-- either ready to claim right now, or hasn't been reached yet. A stage
	-- that's already been claimed this cycle looks like "Progress >=
	-- Threshold but Available = false" (see RollManager.buildSpecialRollTiers)
	-- -- that combination is what tells this apart from "not reached yet"
	-- (Progress < Threshold) without needing a separate claimed flag
	-- client-side at all.
	local function pickCurrentStage()
		for _, tier in luckyStages do
			local state = stageStates[tier.Id]
			if state.Available or state.Progress < state.Threshold then
				return tier, state
			end
		end
		return luckyStages[stageCount], stageStates[luckyStages[stageCount].Id]
	end

	local function refresh()
		local tier, state = pickCurrentStage()
		local stageIndex = 1
		for i, t in luckyStages do
			if t.Id == tier.Id then
				stageIndex = i
				break
			end
		end

		local liveElapsed = os.clock() - lastPushAt
		local liveProgress = math.min(state.Progress + liveElapsed, state.Threshold)
		local isReady = state.Available or liveProgress >= state.Threshold
		local countdownText = formatCountdown(state.Threshold - liveProgress)

		local multiplier = math.floor(SpecialRollConfig.GetLuckMultiplier(tier, "Ultra") + 0.5)
		local oddsText = string.format("%dx Odds!", multiplier)
		local stageText = string.format("Stage %d / %d", stageIndex, stageCount)

		oddsLabel.Text = oddsText
		stageLabel.Text = stageText
		timerLabel.Text = countdownText

		if isReady then
			actionButton.Text = "Claim"
			actionButton.Active = true
			actionButton.AutoButtonColor = true
			actionButton.BackgroundColor3 = LUCKY_COLOR
			actionButton.TextColor3 = Color3.fromRGB(20, 20, 20)
		else
			actionButton.Text = "Locked"
			actionButton.Active = false
			actionButton.AutoButtonColor = false
			actionButton.BackgroundColor3 = Theme.Colors.Surface
			actionButton.TextColor3 = Theme.Colors.TextSecondary
		end

		if billboardOddsLabel then
			billboardOddsLabel.Text = oddsText
		end
		if billboardStageLabel then
			billboardStageLabel.Text = stageText
		end
		if billboardTimerLabel then
			billboardTimerLabel.Text = countdownText
		end
		if billboardStateLabel then
			billboardStateLabel.Text = isReady and "Claim" or "Locked"
			billboardStateLabel.TextColor3 = isReady and LUCKY_COLOR or Color3.fromRGB(200, 200, 200)
		end
	end
	refresh()

	local function applyTiers(tiers)
		local sawAny = false
		for _, entry in tiers do
			if stageStates[entry.TierId] then
				stageStates[entry.TierId] = { Progress = entry.Progress, Threshold = entry.Threshold, Available = entry.Available }
				sawAny = true
			end
		end
		if sawAny then
			lastPushAt = os.clock()
			refresh()
		end
	end

	specialRollStateUpdated.OnClientEvent:Connect(applyTiers)

	-- Piggybacked on every RollResult (see RollManager.luau) -- gives an
	-- immediate refresh right after claiming instead of waiting up to 5s
	-- for the next periodic SpecialRollStateUpdated push.
	rollResult.OnClientEvent:Connect(function(_, tiers)
		if tiers then
			applyTiers(tiers)
		end
	end)

	actionButton.Activated:Connect(function()
		local tier, state = pickCurrentStage()
		if state.Available then
			rollSpecial:FireServer(tier.Id)
		end
	end)

	-- Not owned -> "BUY" (opens the purchase prompt). Owned -> a real ON/OFF
	-- toggle (green when on, red when off) instead of a static "Owned" --
	-- RollManager.luau's per-second loop only auto-claims while both Owns()
	-- AND session.AutoClaimEnabled are true, so this button is what flips
	-- that second half.
	local ownsAutoClaim = false
	local autoClaimEnabled = false
	local function refreshAutoClaimBadge()
		-- The price tag is only relevant pre-purchase -- nothing left to
		-- buy once owned, regardless of the on/off toggle state.
		priceFloatLabel.Visible = not ownsAutoClaim
		if not ownsAutoClaim then
			autoClaimBadge.Text = "AUTO CLAIM: BUY"
			autoClaimBadge.BackgroundColor3 = LUCKY_COLOR
		elseif autoClaimEnabled then
			autoClaimBadge.Text = "AUTO CLAIM: ON"
			autoClaimBadge.BackgroundColor3 = Theme.Colors.Success
		else
			autoClaimBadge.Text = "AUTO CLAIM: OFF"
			autoClaimBadge.BackgroundColor3 = Theme.Colors.Danger
		end
	end
	refreshAutoClaimBadge()

	autoClaimBadge.Activated:Connect(function()
		if not ownsAutoClaim then
			MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, AutoClaimConfig.GamepassId)
			return
		end
		setAutoClaim:FireServer(not autoClaimEnabled)
	end)

	statsUpdated.OnClientEvent:Connect(function(stats: { OwnsAutoClaim: boolean })
		ownsAutoClaim = stats.OwnsAutoClaim
		refreshAutoClaimBadge()
	end)

	-- Echoes the actual persisted server-side state back (see
	-- AutoClaimManager.luau's SetAutoClaim handler) -- pushed on join and
	-- again after every successful toggle, so this can't drift from reality
	-- (e.g. a toggle-on request that got rejected because ownership somehow
	-- lapsed between clicks).
	autoClaimUpdated.OnClientEvent:Connect(function(enabled: boolean)
		autoClaimEnabled = enabled
		refreshAutoClaimBadge()
	end)

	-- Runs regardless of panel.Visible (unlike the perf-gated pattern used
	-- elsewhere) -- the 3D billboard needs to keep ticking even when the
	-- player is far away and just glancing at it, not only while standing
	-- in the close-up panel's proximity radius. refresh() is cheap (a
	-- handful of label text writes), so this is real work, not waste.
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)

	-- Same self-healing retry as VIPProximityPanel.luau -- re-resolves
	-- Workspace.Map itself (not just the child lookup) in case a stale Map
	-- existed at t=0 and got destroyed/rebuilt out from under a cached
	-- reference.
	task.spawn(function()
		local marker: BasePart? = nil
		while not marker do
			local mapFolder = Workspace:WaitForChild("Map")
			marker = mapFolder:WaitForChild("LuckyRollMarker_Disk", 5) :: BasePart?
		end

		-- Much smaller than the first pass (was 110x140) -- that made the
		-- text stack render as a huge multi-line block hanging most of the
		-- way down to the ground/fountain in front of the marker instead of
		-- a compact callout hovering right above the dice. Every child
		-- below is packed tightly (small icon, thin label rows, minimal
		-- gaps) to fit this smaller footprint instead of spreading out to
		-- fill it.
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "LuckyRollCallout"
		billboard.Size = UDim2.new(0, 80, 0, 40)
		billboard.StudsOffset = Vector3.new(0, 8, 0)
		billboard.AlwaysOnTop = true
		-- Bigger than the default 40 (MapBuilder.luau's floor marker
		-- labels) -- Lucky Roll's marker sits out on the open grass, same
		-- reasoning as Group/Daily Rewards' own larger radius.
		billboard.MaxDistance = 80
		billboard.Adornee = marker
		billboard.Parent = marker

		-- No dice icon here anymore -- the real "3 Dices" 3D model
		-- (MapBuilder.luau) sits at this exact spot now, so a floating 2D
		-- dice image on top of it was redundant. Text-only callout.
		local oddsBillboardLabel = Instance.new("TextLabel")
		oddsBillboardLabel.Size = UDim2.new(1, 0, 0, 14)
		oddsBillboardLabel.Position = UDim2.new(0, 0, 0, 0)
		oddsBillboardLabel.BackgroundTransparency = 1
		oddsBillboardLabel.TextColor3 = LUCKY_COLOR
		oddsBillboardLabel.TextStrokeTransparency = 0
		oddsBillboardLabel.Font = Enum.Font.LuckiestGuy
		oddsBillboardLabel.TextScaled = true
		oddsBillboardLabel.Text = ""
		oddsBillboardLabel.Parent = billboard
		capTextSize(oddsBillboardLabel, 9)

		-- No stage label here on purpose -- "Stage X/6" stays 2D-panel-only
		-- (see billboardStageLabel staying nil below), the 3D callout only
		-- shows odds/timer/claim-state.
		local timerBillboardLabel = Instance.new("TextLabel")
		timerBillboardLabel.Size = UDim2.new(1, 0, 0, 14)
		timerBillboardLabel.Position = UDim2.new(0, 0, 0, 14)
		timerBillboardLabel.BackgroundTransparency = 1
		timerBillboardLabel.TextColor3 = Color3.new(1, 1, 1)
		timerBillboardLabel.TextStrokeTransparency = 0
		timerBillboardLabel.Font = Enum.Font.LuckiestGuy
		timerBillboardLabel.TextScaled = true
		timerBillboardLabel.Text = ""
		timerBillboardLabel.Parent = billboard
		capTextSize(timerBillboardLabel, 9)

		local stateBillboardLabel = Instance.new("TextLabel")
		stateBillboardLabel.Size = UDim2.new(1, 0, 0, 12)
		stateBillboardLabel.Position = UDim2.new(0, 0, 0, 28)
		stateBillboardLabel.BackgroundTransparency = 1
		stateBillboardLabel.TextStrokeTransparency = 0
		stateBillboardLabel.Font = Enum.Font.LuckiestGuy
		stateBillboardLabel.TextScaled = true
		stateBillboardLabel.Text = ""
		stateBillboardLabel.Parent = billboard
		capTextSize(stateBillboardLabel, 8)

		billboardOddsLabel = oddsBillboardLabel
		-- billboardStageLabel stays nil -- see the "no stage label here on
		-- purpose" comment above; refresh()'s `if billboardStageLabel then`
		-- guard already skips it safely.
		billboardTimerLabel = timerBillboardLabel
		billboardStateLabel = stateBillboardLabel
		refresh()

		ProximityWatcher.Register(marker, PROXIMITY_RADIUS_STUDS, function(inRange)
			panel.Visible = inRange
		end)
	end)

	local handle = {}
	handle.Frame = panel
	return handle
end

return LuckyRollProximityPanel
