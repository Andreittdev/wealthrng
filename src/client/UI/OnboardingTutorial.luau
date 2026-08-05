-- New-player walkthrough, shown once ever (session.CompletedOnboarding,
-- OnboardingManager.luau) right after a brand-new player joins:
--   Step 1: "Welcome to the game! Roll your first item!" -- whole screen
--           dimmed except the ROLL dice (glow + bouncing arrow pointing at
--           it). Advances the instant a RollResult arrives.
--   Step 2: "Equip your inventory!" -- still dimmed, but now BOTH the dice
--           and the Inventory sidebar icon are undimmed (glow on both, an
--           arrow only on Inventory since Step 1 already taught the dice).
--           Advances the instant EquippedItemsUpdated reports something
--           equipped (InventoryPanel.luau's own Equip button does the
--           actual work -- this just watches for the result).
--   Step 3: "Don't forget to collect Free Daily Rewards and explore the
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

local MASK_ZINDEX = 8
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

function OnboardingTutorial.Create(screenGui: ScreenGui, remotes: Folder, rollButton: GuiObject, inventoryButton: GuiObject)
	local onboardingStateUpdated = remotes:WaitForChild("OnboardingStateUpdated")
	local markOnboardingComplete = remotes:WaitForChild("MarkOnboardingComplete")
	local rollResult = remotes:WaitForChild("RollResult")
	local equippedItemsUpdated = remotes:WaitForChild("EquippedItemsUpdated")

	local root = Instance.new("Frame")
	root.Size = UDim2.new(1, 0, 1, 0)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = MASK_ZINDEX
	root.Parent = screenGui

	local maskContainer = Instance.new("Frame")
	maskContainer.Size = UDim2.new(1, 0, 1, 0)
	maskContainer.BackgroundTransparency = 1
	maskContainer.ZIndex = MASK_ZINDEX
	maskContainer.Parent = root

	local highlightContainer = Instance.new("Frame")
	highlightContainer.Size = UDim2.new(1, 0, 1, 0)
	highlightContainer.BackgroundTransparency = 1
	highlightContainer.ZIndex = MASK_ZINDEX + 1
	highlightContainer.Parent = root

	local banner = Instance.new("Frame")
	banner.Size = UDim2.new(0.6, 0, 0, 44)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 36)
	banner.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	banner.BackgroundTransparency = 0.1
	banner.BorderSizePixel = 0
	banner.ZIndex = MASK_ZINDEX + 2
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
	bannerLabel.ZIndex = MASK_ZINDEX + 2
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
							cell.ZIndex = MASK_ZINDEX
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
		glow.ZIndex = MASK_ZINDEX + 1
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
		arrow.ZIndex = MASK_ZINDEX + 1
		arrow.Parent = highlightContainer

		local bobTween = TweenService:Create(
			arrow,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.new(0, pos.X + size.X / 2, 0, pos.Y - 24) }
		)
		bobTween:Play()
		table.insert(activeGlowTweens, bobTween)
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

	local completed = true
	local step = 0

	local function endTutorial()
		step = 0
		root.Visible = false
		clearHighlights()
		for _, child in maskContainer:GetChildren() do
			child:Destroy()
		end
	end

	local function showStep3()
		step = 3
		applyStepVisuals("Don't forget to collect Free Daily Rewards and explore the game!", {})
		markOnboardingComplete:FireServer()
		task.delay(15, function()
			if step == 3 then
				endTutorial()
			end
		end)
	end

	local function showStep2()
		step = 2
		applyStepVisuals("Equip your item!", {
			{ Target = rollButton, Arrow = false },
			{ Target = inventoryButton, Arrow = true },
		})
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

	-- Only ever runs for a player who hasn't completed it before --
	-- session.CompletedOnboarding, set once via markOnboardingComplete at
	-- the end of Step 3, is what makes this a true "new players only" flow.
	onboardingStateUpdated.OnClientEvent:Connect(function(isCompleted: boolean)
		completed = isCompleted == true
		if not completed and step == 0 then
			showStep1()
		end
	end)

	rollResult.OnClientEvent:Connect(function()
		if not completed and step == 1 then
			showStep2()
		end
	end)

	equippedItemsUpdated.OnClientEvent:Connect(function(uids: { number })
		if not completed and step == 2 and #uids > 0 then
			showStep3()
		end
	end)

	return {}
end

return OnboardingTutorial
