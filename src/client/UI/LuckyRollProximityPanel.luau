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
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpecialRollConfig = require(ReplicatedStorage.Modules.SpecialRollConfig)
local Theme = require(script.Parent.Theme)

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

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 180, 0, 224)
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -234)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 8
	panel.Parent = screenGui
	Theme.Round(panel)
	Theme.Stroke(panel, LUCKY_COLOR, 1)
	Theme.Shadow(panel)

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
		billboard.Size = UDim2.new(0, 80, 0, 76)
		billboard.StudsOffset = Vector3.new(0, 5, 0)
		billboard.AlwaysOnTop = true
		billboard.Adornee = marker
		billboard.Parent = marker

		local billboardDiceIcon = Instance.new("ImageLabel")
		billboardDiceIcon.Size = UDim2.new(0, 36, 0, 36)
		billboardDiceIcon.AnchorPoint = Vector2.new(0.5, 0)
		billboardDiceIcon.Position = UDim2.new(0.5, 0, 0, 0)
		billboardDiceIcon.BackgroundTransparency = 1
		billboardDiceIcon.ScaleType = Enum.ScaleType.Fit
		billboardDiceIcon.Image = DICE_IMAGE
		billboardDiceIcon.Parent = billboard

		local oddsBillboardLabel = Instance.new("TextLabel")
		oddsBillboardLabel.Size = UDim2.new(1, 0, 0, 14)
		oddsBillboardLabel.Position = UDim2.new(0, 0, 0, 36)
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
		timerBillboardLabel.Position = UDim2.new(0, 0, 0, 50)
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
		stateBillboardLabel.Position = UDim2.new(0, 0, 0, 64)
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

		RunService.Heartbeat:Connect(function()
			local character = Players.LocalPlayer.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			if not rootPart then
				panel.Visible = false
				return
			end
			panel.Visible = (rootPart.Position - marker.Position).Magnitude <= PROXIMITY_RADIUS_STUDS
		end)
	end)

	local handle = {}
	handle.Frame = panel
	return handle
end

return LuckyRollProximityPanel
