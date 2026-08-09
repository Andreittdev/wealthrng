-- New-player walkthrough, shown once ever (session.CompletedOnboarding,
-- OnboardingManager.luau) right after a brand-new player joins:
--   Step 1: "Welcome to the game! Roll your first item!" -- whole screen
--           dimmed except the ROLL dice (glow + bouncing arrow pointing at
--           it). Advances the instant a RollResult arrives.
--   Step 2: "Look, you opened a/an [Item Name]!" -- no dimming (nothing to
--           point at, the item was just revealed by RollPanel's own reveal
--           animation) -- just a banner, clears itself and advances on its
--           own after a few seconds, no player action needed.
--   Step 3: 2 internal phases, same idiom as Step 4:
--             "guide" -- "Equip your item!", dice + Inventory sidebar icon
--                        undimmed (arrow only on Inventory, Step 1 already
--                        taught the dice). Clears once the Inventory panel
--                        actually opens (InventoryPanel.luau's own Equip
--                        button does the real work -- this just watches).
--             "close" -- once EquippedItemsUpdated reports something
--                        equipped, arrow moves to Inventory's own Close
--                        button instead of jumping straight to Step 4
--                        while the panel still covers the screen.
--           Closing Inventory before equipping anything just re-prompts
--           "guide". Advances to Step 4 once Inventory is closed AFTER
--           equipping.
--   Step 4: 4 internal phases, all still "Step 4" externally:
--             "open"   -- "Upgrade your Roll Speed for free!", arrow on
--                         RollPanel's Upgrade button.
--             "select" -- once the Upgrades panel opens, arrow moves to the
--                         Roll Speed branch tile itself.
--             "buy"    -- once that branch is tapped, arrow moves to the
--                         actual Buy button for level 1 (Roll Speed's very
--                         first level is a permanent $0 freebie,
--                         UpgradeConfig.luau, so a brand-new player can
--                         always complete this regardless of Cash earned
--                         so far).
--             "close"  -- once UpgradesUpdated reports RollSpeed at level
--                         1+, arrow moves to the panel's own Close button.
--           Closing the panel before actually buying just re-prompts
--           "open" instead of getting stuck pointing at hidden panel
--           internals. Advances to Step 5 once the panel is closed AFTER
--           buying. If Roll Speed was already bought BEFORE Step 4 even
--           started (the Upgrade button is always clickable), Step 4 skips
--           straight to Step 5 instead of waiting for a purchase that
--           already happened.
--   Step 5: "Don't forget to collect Free Daily Rewards and explore the
--           game!" -- dimming is already gone by this point (nothing left
--           to point at), just a banner that clears itself after a few
--           seconds. Marks onboarding complete the moment this is shown.
--
-- The dimmed background is a literal geometric cutout (a grid of opaque
-- Frames covering the screen MINUS the target buttons' own rects), not a
-- ZIndex trick -- ZIndex "Sibling" behavior only orders direct siblings
-- under the same parent, so a screenGui-level overlay can't selectively
-- sit "above everything except these two specific nested buttons" just by
-- picking a ZIndex. A literal hole works regardless of how deep the target
-- lives in the tree. Every mask/glow/arrow piece has Active = false, so
-- even where it visually covers something, clicks still pass through to
-- the real UI underneath -- dimming is purely a visual cue, never a hard
-- lock.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local OnboardingTutorial = {}

-- BASE_ZINDEX (below every modal panel, e.g. InventoryPanel) is what every
-- earlier step needs -- Step 3 opens Inventory and wants IT fully visible
-- undimmed on top, with the dimming mask staying behind it. Step 4's
-- "select"/"close" phases are the opposite: they need to highlight
-- something INSIDE the already-open (higher-ZIndex) Upgrades panel, so the
-- mask/glow there has to render ABOVE it instead, via ELEVATED_ZINDEX (see
-- setElevated below). A single fixed ZIndex can't satisfy both, since
-- different panels sit at different ZIndex values.
local BASE_ZINDEX = 8
local ELEVATED_ZINDEX = 50
local MASK_TRANSPARENCY = 0.35
local HIGHLIGHT_PADDING = 10

local function getAbsRect(target: GuiObject, padding: number)
	local pos = target.AbsolutePosition
	local size = target.AbsoluteSize
	return {
		Left = pos.X - padding,
		Top = pos.Y - padding,
		Right = pos.X + size.X + padding,
		Bottom = pos.Y + size.Y + padding,
	}
end

local function pointInRect(x: number, y: number, rect): boolean
	return x >= rect.Left and x < rect.Right and y >= rect.Top and y < rect.Bottom
end

function OnboardingTutorial.Create(
	screenGui: ScreenGui,
	remotes: Folder,
	rollButton: GuiObject,
	inventoryButton: GuiObject,
	upgradeButton: GuiObject,
	upgradesHandle: { Frame: Frame, RollSpeedBranchButton: GuiObject, CloseButton: GuiObject, SetExpandedNodeCallback: (callback: (string, GuiObject) -> ()) -> () },
	inventoryHandle: { Frame: Frame, CloseButton: GuiObject }
)
	local upgradesPanelFrame = upgradesHandle.Frame
	local rollSpeedBranchButton = upgradesHandle.RollSpeedBranchButton
	local upgradesCloseButton = upgradesHandle.CloseButton
	local inventoryPanelFrame = inventoryHandle.Frame
	local inventoryCloseButton = inventoryHandle.CloseButton
	local onboardingStateUpdated = remotes:WaitForChild("OnboardingStateUpdated")
	local markOnboardingComplete = remotes:WaitForChild("MarkOnboardingComplete")
	local rollResult = remotes:WaitForChild("RollResult")
	local equippedItemsUpdated = remotes:WaitForChild("EquippedItemsUpdated")
	local upgradesUpdated = remotes:WaitForChild("UpgradesUpdated")

	-- Read by rebuildMask/addGlow/addArrow below at CREATION time -- so
	-- calling setElevated (defined further down) before the next
	-- applyStepVisuals call is enough to move every freshly-built piece to
	-- the right layer, no need to hunt down and re-parent existing ones.
	local currentZIndex = BASE_ZINDEX

	local root = Instance.new("Frame")
	root.Size = UDim2.new(1, 0, 1, 0)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = currentZIndex
	root.Parent = screenGui

	local maskContainer = Instance.new("Frame")
	maskContainer.Size = UDim2.new(1, 0, 1, 0)
	maskContainer.BackgroundTransparency = 1
	maskContainer.ZIndex = currentZIndex
	maskContainer.Parent = root

	local highlightContainer = Instance.new("Frame")
	highlightContainer.Size = UDim2.new(1, 0, 1, 0)
	highlightContainer.BackgroundTransparency = 1
	highlightContainer.ZIndex = currentZIndex + 1
	highlightContainer.Parent = root

	local banner = Instance.new("Frame")
	banner.Size = UDim2.new(0.6, 0, 0, 44)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 36)
	banner.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	banner.BackgroundTransparency = 0.1
	banner.BorderSizePixel = 0
	banner.ZIndex = currentZIndex + 2
	banner.Parent = root

	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 14)
	bannerCorner.Parent = banner

	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Color = Color3.fromRGB(255, 215, 140)
	bannerStroke.Thickness = 1.5
	bannerStroke.Parent = banner

	local bannerPadding = Instance.new("UIPadding")
	bannerPadding.PaddingLeft = UDim.new(0, 14)
	bannerPadding.PaddingRight = UDim.new(0, 14)
	bannerPadding.Parent = banner

	local bannerLabel = Instance.new("TextLabel")
	bannerLabel.Size = UDim2.new(1, 0, 1, 0)
	bannerLabel.BackgroundTransparency = 1
	bannerLabel.Font = Enum.Font.LuckiestGuy
	bannerLabel.TextScaled = true
	bannerLabel.TextWrapped = true
	bannerLabel.TextColor3 = Color3.new(1, 1, 1)
	bannerLabel.TextStrokeTransparency = 0
	bannerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	bannerLabel.Text = ""
	bannerLabel.ZIndex = currentZIndex + 2
	bannerLabel.Parent = banner

	local bannerTextSize = Instance.new("UITextSizeConstraint")
	bannerTextSize.MaxTextSize = 22
	bannerTextSize.Parent = bannerLabel

	-- ===== Mask: a grid of opaque cells covering the screen minus every
	-- current target's rect (see getAbsRect/pointInRect above). =====
	local currentTargets: { GuiObject } = {}

	local function rebuildMask()
		for _, child in maskContainer:GetChildren() do
			child:Destroy()
		end

		local screenSize = screenGui.AbsoluteSize
		if screenSize.X <= 0 or screenSize.Y <= 0 or #currentTargets == 0 then
			return
		end

		local rects = {}
		for _, target in currentTargets do
			table.insert(rects, getAbsRect(target, HIGHLIGHT_PADDING))
		end

		local xs = { 0, screenSize.X }
		local ys = { 0, screenSize.Y }
		for _, r in rects do
			table.insert(xs, math.clamp(r.Left, 0, screenSize.X))
			table.insert(xs, math.clamp(r.Right, 0, screenSize.X))
			table.insert(ys, math.clamp(r.Top, 0, screenSize.Y))
			table.insert(ys, math.clamp(r.Bottom, 0, screenSize.Y))
		end
		table.sort(xs)
		table.sort(ys)

		for i = 1, #xs - 1 do
			local x0, x1 = xs[i], xs[i + 1]
			if x1 > x0 then
				for j = 1, #ys - 1 do
					local y0, y1 = ys[j], ys[j + 1]
					if y1 > y0 then
						local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
						local inHole = false
						for _, r in rects do
							if pointInRect(cx, cy, r) then
								inHole = true
								break
							end
						end
						if not inHole then
							local cell = Instance.new("Frame")
							cell.Position = UDim2.new(0, x0, 0, y0)
							cell.Size = UDim2.new(0, x1 - x0, 0, y1 - y0)
							cell.BackgroundColor3 = Color3.new(0, 0, 0)
							cell.BackgroundTransparency = MASK_TRANSPARENCY
							cell.BorderSizePixel = 0
							cell.Active = false
							cell.ZIndex = currentZIndex
							cell.Parent = maskContainer
						end
					end
				end
			end
		end
	end

	-- ===== Highlights: a pulsing glow ring per target, plus one bouncing
	-- arrow pointing at whichever target is newly introduced this step. =====
	local activeGlowTweens: { Tween } = {}

	local function clearHighlights()
		for _, tween in activeGlowTweens do
			tween:Cancel()
		end
		table.clear(activeGlowTweens)
		for _, child in highlightContainer:GetChildren() do
			child:Destroy()
		end
	end

	local function addGlow(target: GuiObject)
		local pos = target.AbsolutePosition
		local size = target.AbsoluteSize
		local pad = HIGHLIGHT_PADDING

		local glow = Instance.new("Frame")
		glow.Position = UDim2.new(0, pos.X - pad, 0, pos.Y - pad)
		glow.Size = UDim2.new(0, size.X + pad * 2, 0, size.Y + pad * 2)
		glow.BackgroundTransparency = 1
		glow.Active = false
		glow.ZIndex = currentZIndex + 1
		glow.Parent = highlightContainer

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 18)
		corner.Parent = glow

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 235, 150)
		stroke.Thickness = 4
		stroke.Transparency = 0.1
		stroke.Parent = glow

		local pulse = TweenService:Create(
			stroke,
			TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.75, Thickness = 2 }
		)
		pulse:Play()
		table.insert(activeGlowTweens, pulse)
	end

	local function addArrow(target: GuiObject)
		local pos = target.AbsolutePosition
		local size = target.AbsoluteSize

		local arrow = Instance.new("TextLabel")
		arrow.AnchorPoint = Vector2.new(0.5, 1)
		arrow.Size = UDim2.new(0, 50, 0, 50)
		arrow.Position = UDim2.new(0, pos.X + size.X / 2, 0, pos.Y - 12)
		arrow.BackgroundTransparency = 1
		arrow.Text = "\u{1F447}"
		arrow.TextScaled = true
		arrow.Active = false
		arrow.ZIndex = currentZIndex + 1
		arrow.Parent = highlightContainer

		local bobTween = TweenService:Create(
			arrow,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.new(0, pos.X + size.X / 2, 0, pos.Y - 24) }
		)
		bobTween:Play()
		table.insert(activeGlowTweens, bobTween)
	end

	-- Moves the WHOLE tutorial overlay (mask + highlights + banner) between
	-- BASE_ZINDEX (default -- stays behind modal panels like Inventory, so
	-- THEY render fully visible/undimmed on top when opened mid-step) and
	-- ELEVATED_ZINDEX (needed when a step has to highlight something INSIDE
	-- an already-open modal, e.g. Step 4's Roll Speed branch tile/Close
	-- button inside the Upgrades panel). Only root/banner/bannerLabel need
	-- updating directly here -- they're built once and never recreated;
	-- maskContainer/highlightContainer's CHILDREN (cells/glow/arrow) are
	-- rebuilt by every applyStepVisuals call and just read currentZIndex
	-- fresh each time.
	local function setElevated(elevated: boolean)
		currentZIndex = elevated and ELEVATED_ZINDEX or BASE_ZINDEX
		root.ZIndex = currentZIndex
		maskContainer.ZIndex = currentZIndex
		highlightContainer.ZIndex = currentZIndex + 1
		banner.ZIndex = currentZIndex + 2
		bannerLabel.ZIndex = currentZIndex + 2
	end

	-- `entries`: { { Target = GuiObject, Arrow = boolean? } }
	local function applyStepVisuals(text: string, entries: { { Target: GuiObject, Arrow: boolean? } })
		bannerLabel.Text = text
		clearHighlights()

		currentTargets = {}
		for _, entry in entries do
			table.insert(currentTargets, entry.Target)
			addGlow(entry.Target)
			if entry.Arrow then
				addArrow(entry.Target)
			end
		end
		rebuildMask()
	end

	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if root.Visible then
			rebuildMask()
			-- Re-running applyStepVisuals's glow/arrow positioning on resize
			-- would need the current step's entries kept around -- simplest
			-- correct fix is just re-deriving positions for whatever's
			-- already built, but since a resize is rare mid-tutorial (this
			-- is a short 2-action flow), a full mask rebuild is enough to
			-- keep the important part (the cutout) correct; glow/arrow
			-- drift slightly stale until the next step change, which is
			-- cosmetic only.
		end
	end)

	local ITEM_REVEAL_HOLD_SECONDS = 4

	local completed = true
	local step = 0
	-- Kept current EVEN OUTSIDE step 4 -- the Upgrade button is always
	-- clickable, so a curious player can buy Roll Speed's free level 0->1
	-- during an earlier step, before Step 4's own upgradesUpdated listener
	-- is even watching for it. Without tracking this independently, Step 4
	-- would still make them hunt for a "free" buy button that's already
	-- gone (level 1 is bought, the next one costs real Cash), soft-locking
	-- the whole tutorial forever. showStep4 checks this the instant it
	-- starts and skips straight to Step 5 if it's already satisfied.
	local currentRollSpeedLevel = 0
	-- Same reasoning, for Step 3 -- the Inventory sidebar icon is always
	-- clickable too, so a player could equip something during Step 1/2
	-- (e.g. exploring while Step 2's item-reveal banner is still up).
	-- Without this, Step 3 would ask them to equip something that's
	-- already equipped, with no obvious reason left to click Equip again.
	local hasEquippedItem = false

	local function endTutorial()
		step = 0
		root.Visible = false
		clearHighlights()
		for _, child in maskContainer:GetChildren() do
			child:Destroy()
		end
	end

	local function showStep5()
		step = 5
		setElevated(false)
		applyStepVisuals("Don't forget to collect Free Daily Rewards and explore the game!", {})
		markOnboardingComplete:FireServer()
		task.delay(15, function()
			if step == 5 then
				endTutorial()
			end
		end)
	end

	-- Step 4 has 4 internal phases (still all `step == 4` externally, so
	-- the equip/upgrade listeners further down don't need to know about
	-- them) -- "open" (point at RollPanel's Upgrade button), "select"
	-- (point at the Roll Speed branch tile once the panel's actually open),
	-- "buy" (point at the actual Buy button once that branch is tapped),
	-- "close" (point at the panel's own Close button once RollSpeed is
	-- actually bought). Tracked separately from `step` since the panel's
	-- Visible-changed signal needs to know which phase to react to.
	local upgradePhase = "open"

	local function showStep4Close()
		upgradePhase = "close"
		setElevated(true)
		applyStepVisuals("Nice! Now close this to continue.", {
			{ Target = upgradesCloseButton, Arrow = true },
		})
	end

	-- `buyButton` is passed in fresh every time (see SetExpandedNodeCallback
	-- below) -- UpgradesPanel.luau tears down and rebuilds the whole vine
	-- (including this exact button instance) on every render, so this can't
	-- just be captured once.
	local function showStep4Buy(buyButton: GuiObject)
		upgradePhase = "buy"
		setElevated(true)
		applyStepVisuals("Buy your first upgrade!", {
			{ Target = buyButton, Arrow = true },
		})
	end

	local function showStep4Select()
		upgradePhase = "select"
		setElevated(true)
		applyStepVisuals("Tap Roll Speed!", {
			{ Target = rollSpeedBranchButton, Arrow = true },
		})
	end

	local function showStep4()
		step = 4
		-- Already bought (curiosity-clicked the Upgrade button during an
		-- earlier step) -- nothing left to guide them through, and waiting
		-- around for a "free" purchase that already happened would
		-- soft-lock the tutorial forever. Skip straight to Step 5.
		if currentRollSpeedLevel >= 1 then
			showStep5()
			return
		end
		-- Panel's already open (curiosity-clicked Upgrade during an earlier
		-- step, then left it open) -- the Visible-changed signal that
		-- normally drives "open" -> "select" won't fire since Visible isn't
		-- actually changing, which would otherwise strand the highlight on
		-- the Upgrade button behind/under the already-open panel. Jump
		-- straight to "select", same as if they'd just opened it.
		if upgradesPanelFrame.Visible then
			showStep4Select()
			return
		end
		upgradePhase = "open"
		setElevated(false)
		applyStepVisuals("Upgrade your Roll Speed for free!", {
			{ Target = upgradeButton, Arrow = true },
		})
	end

	-- Step 3 also has 2 internal phases, same idiom as Step 4 -- "guide"
	-- (point at the dice + Inventory icon, or nothing once Inventory's
	-- open but nothing's equipped yet) and "close" (once something's
	-- actually equipped, point at Inventory's own Close button instead of
	-- jumping straight to Step 4 while the panel's still covering the
	-- screen).
	local equipPhase = "guide"

	local function showStep3CloseInventory()
		equipPhase = "close"
		setElevated(true)
		applyStepVisuals("Nice! Now close this to continue.", {
			{ Target = inventoryCloseButton, Arrow = true },
		})
	end

	local function showStep3()
		step = 3
		-- Already equipped (curiosity-clicked Inventory during an earlier
		-- step) -- nothing left to guide them through here, skip straight
		-- to Step 4 instead of asking them to re-equip something that's
		-- already on.
		if hasEquippedItem then
			showStep4()
			return
		end
		-- Same "already open" case as showStep4() above -- Inventory's
		-- opened during an earlier step and left open, so the
		-- Visible-changed signal that clears the dice/Inventory-icon glow
		-- won't fire on its own. Clear it immediately instead of leaving it
		-- pointing at icons the open panel is now covering.
		if inventoryPanelFrame.Visible then
			equipPhase = "guide"
			setElevated(false)
			applyStepVisuals("Equip your item!", {})
			return
		end
		equipPhase = "guide"
		setElevated(false)
		applyStepVisuals("Equip your item!", {
			{ Target = rollButton, Arrow = false },
			{ Target = inventoryButton, Arrow = true },
		})
	end

	-- "a" vs "an" off the item's own first letter -- good enough for every
	-- real ItemDatabase name (no silent-H edge cases like "an hour" to
	-- worry about here).
	local function articleFor(name: string): string
		local firstChar = string.upper(string.sub(name, 1, 1))
		if firstChar == "A" or firstChar == "E" or firstChar == "I" or firstChar == "O" or firstChar == "U" then
			return "an"
		end
		return "a"
	end

	local function showStep2(item: { Name: string })
		step = 2
		applyStepVisuals(string.format("Look, you opened %s %s!", articleFor(item.Name), item.Name), {})
		task.delay(ITEM_REVEAL_HOLD_SECONDS, function()
			if step == 2 then
				showStep3()
			end
		end)
	end

	local function showStep1()
		step = 1
		root.Visible = true
		-- This is the very first thing OnboardingTutorial does, called
		-- straight out of MainUI.Init() building every panel in one go --
		-- AbsolutePosition/AbsoluteSize on a JUST-created/positioned
		-- GuiObject only reflect reality after Roblox's layout engine has
		-- actually run a step, not the instant Position/Size are set. Reading
		-- rollButton's rect before that gave stale (0,0)-ish coordinates,
		-- which is why the mask hole/glow/arrow were all in the wrong place
		-- the first time this ran. One Heartbeat is enough to guarantee a
		-- real layout pass happened.
		RunService.Heartbeat:Wait()
		applyStepVisuals("Welcome to the game! Roll your first item!", {
			{ Target = rollButton, Arrow = true },
		})
	end

	-- TESTING ONLY -- forces the tutorial to always play from Step 1 on
	-- join, regardless of session.CompletedOnboarding, so the new 5-step
	-- flow can be replayed on demand without needing a fresh account every
	-- time. Set back to false once done testing.
	local TESTING_FORCE_VISIBLE = false

	-- Only ever runs for a player who hasn't completed it before --
	-- session.CompletedOnboarding, set once via markOnboardingComplete at
	-- the end of Step 5, is what makes this a true "new players only" flow.
	onboardingStateUpdated.OnClientEvent:Connect(function(isCompleted: boolean)
		if TESTING_FORCE_VISIBLE then
			completed = false
		else
			completed = isCompleted == true
		end
		if not completed and step == 0 then
			showStep1()
		end
	end)

	rollResult.OnClientEvent:Connect(function(item: { Name: string })
		if not completed and step == 1 then
			showStep2(item)
		end
	end)

	-- hasEquippedItem tracked unconditionally (see its own comment above).
	-- When it happens during step 3, moves Step 3 into its "close" phase
	-- (point at Inventory's own Close button) instead of jumping straight
	-- to Step 4, which would try to highlight the Upgrade button while
	-- Inventory is still covering the whole screen.
	equippedItemsUpdated.OnClientEvent:Connect(function(uids: { number })
		hasEquippedItem = #uids > 0
		if not completed and step == 3 and equipPhase ~= "close" and hasEquippedItem then
			-- If Inventory's already closed by the time this reply lands
			-- (player equipped then closed the panel before the server
			-- round-trip finished), there's nothing left to point the
			-- "close this" prompt at -- it's already closed, so just
			-- advance straight to Step 4 instead of stranding a highlight
			-- over a closed panel.
			if inventoryPanelFrame.Visible then
				showStep3CloseInventory()
			else
				showStep4()
			end
		end
	end)

	inventoryPanelFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if completed or step ~= 3 then
			return
		end
		if inventoryPanelFrame.Visible then
			-- Clears Step 3's glow/arrow (dice + Inventory icon) the instant
			-- the Inventory panel actually opens -- both targets have done
			-- their job (guided the player TO the panel), and the icon
			-- they were pointing at is now sitting behind/beside the open
			-- panel, which reads as a stale leftover instead of useful
			-- guidance. Only applies in "guide" phase -- "close" phase has
			-- its own highlight (the Close button) that shouldn't be wiped.
			if equipPhase == "guide" then
				applyStepVisuals("Equip your item!", {})
			end
		else
			-- Closed while in "close" phase (equipped + closed, done) --
			-- advance to Step 4. Closed EARLY, still "guide" phase (no
			-- equip yet) -- just re-prompt Step 3 from the top.
			if equipPhase == "close" then
				showStep4()
			elseif equipPhase == "guide" then
				showStep3()
			end
		end
	end)

	-- Tracked unconditionally (not just "while step == 4") -- see
	-- currentRollSpeedLevel's own comment above for why. When it DOES
	-- happen during step 4, moves Step 4 into its "close" phase (point at
	-- the panel's Close button); doesn't advance `step` itself yet, that
	-- only happens once the panel is actually closed, below.
	upgradesUpdated.OnClientEvent:Connect(function(levels: { [string]: number })
		currentRollSpeedLevel = levels.RollSpeed or 0
		if not completed and step == 4 and upgradePhase ~= "close" and currentRollSpeedLevel >= 1 then
			-- Same early-close race as the equip listener above -- if the
			-- panel's already closed by the time this reply lands (bought,
			-- then closed before the round-trip finished), skip the
			-- now-pointless "close this" prompt and go straight to Step 5.
			if upgradesPanelFrame.Visible then
				showStep4Close()
			else
				showStep5()
			end
		end
	end)

	-- "select" -> "buy" the instant a buy button actually exists for the
	-- Roll Speed track -- fires every time UpgradesPanel.luau (re)builds
	-- one (entering the track view, or any later re-render), so the arrow
	-- always tracks the CURRENT live instance instead of a possibly-
	-- destroyed stale one.
	upgradesHandle.SetExpandedNodeCallback(function(trackId: string, buyButton: GuiObject)
		if completed or step ~= 4 then
			return
		end
		if trackId == "RollSpeed" then
			if upgradePhase == "select" or upgradePhase == "buy" then
				showStep4Buy(buyButton)
			end
		elseif upgradePhase == "select" or upgradePhase == "buy" then
			-- Wandered into a DIFFERENT track's vine (Luck/Potion Boost)
			-- instead of Roll Speed -- the stale glow/arrow would otherwise
			-- keep pointing at Roll Speed's now-hidden branch tile/buy
			-- button. Drop the highlight and just repeat the banner text
			-- instead of leaving it pointing at nothing.
			upgradePhase = "select"
			applyStepVisuals("Tap Roll Speed!", {})
		end
	end)

	-- Drives Step 4's "open" -> "select" -> "buy" -> "close" -> Step 5
	-- progression. Opening the panel while still in "open" phase means they
	-- just clicked the Upgrade button -- move on to pointing at the Roll
	-- Speed branch. Closing it while in "close" phase means they actually
	-- bought the free level and are done -- advance to Step 5. Closing it
	-- EARLY (still "open"/"select"/"buy", no purchase yet) just re-prompts
	-- Step 4 from the top instead of getting stuck pointing at now-invisible
	-- panel internals.
	upgradesPanelFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if completed or step ~= 4 then
			return
		end
		if upgradesPanelFrame.Visible then
			if upgradePhase == "open" then
				showStep4Select()
			end
		else
			if upgradePhase == "close" then
				showStep5()
			elseif upgradePhase == "select" or upgradePhase == "buy" then
				showStep4()
			end
		end
	end)

	return {}
end

return OnboardingTutorial
