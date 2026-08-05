-- Reusable one-time tutorial callout -- a rounded icon tile (with a
-- pointing hand + red "!" badge, same look every hint uses) plus a speech
-- bubble with a title + description, shown ONCE ever per hint id
-- (session.SeenTutorialHints, TutorialHintManager.luau) then never again.
-- Dismisses on tap anywhere on it. Meant to be reused for future hints
-- beyond the first one (Upgrades) -- callers just pick a unique id.

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)

local TutorialHint = {}

local ACCENT_COLOR = Color3.fromRGB(120, 200, 255)

export type HintConfig = {
	Title: string,
	Description: string,
	Image: string?,
}

function TutorialHint.Create(screenGui: ScreenGui, remotes: Folder)
	local tutorialHintsUpdated = remotes:WaitForChild("TutorialHintsUpdated")
	local markTutorialHintSeen = remotes:WaitForChild("MarkTutorialHintSeen")

	local seenHints: { [string]: boolean } = {}
	tutorialHintsUpdated.OnClientEvent:Connect(function(map: { [string]: boolean })
		seenHints = map or {}
	end)

	local handle = {}

	-- Builds and shows `config`'s callout centered on screen, unconditionally.
	local function display(config: HintConfig)
		local overlay = Instance.new("Frame")
		overlay.Size = UDim2.new(1, 0, 1, 0)
		overlay.BackgroundTransparency = 1
		overlay.ZIndex = 50
		overlay.Parent = screenGui

		local dismissButton = Instance.new("TextButton")
		dismissButton.Size = UDim2.new(1, 0, 1, 0)
		dismissButton.BackgroundTransparency = 1
		dismissButton.Text = ""
		dismissButton.ZIndex = 50
		dismissButton.Parent = overlay

		local root = Instance.new("Frame")
		root.Size = UDim2.new(0, 340, 0, 190)
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.new(0.5, 0, 0.38, 0)
		root.BackgroundTransparency = 1
		root.ZIndex = 51
		root.Parent = overlay
		Theme.AutoScale(screenGui, root, 340, 0.6)

		-- ===== Icon tile =====
		local tile = Instance.new("Frame")
		tile.Size = UDim2.new(0, 110, 0, 110)
		tile.Position = UDim2.new(0, 0, 0, 40)
		tile.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
		tile.ZIndex = 52
		tile.Parent = root
		Theme.Round(tile, UDim.new(0, 20))
		Theme.Stroke(tile, Color3.fromRGB(255, 255, 255), 3)

		if config.Image and config.Image ~= "" then
			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.new(0, 78, 0, 78)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.new(0.5, 0, 0.5, 0)
			icon.BackgroundTransparency = 1
			icon.ScaleType = Enum.ScaleType.Fit
			icon.Image = config.Image
			icon.ZIndex = 53
			icon.Parent = tile
		end

		-- Pointing hand, hovering above the tile, bobbing up/down to draw
		-- the eye -- the reference image's own "click here" cue.
		local hand = Instance.new("TextLabel")
		hand.Size = UDim2.new(0, 60, 0, 60)
		hand.AnchorPoint = Vector2.new(0.5, 1)
		hand.Position = UDim2.new(0.3, 0, 0, 36)
		hand.Rotation = -18
		hand.BackgroundTransparency = 1
		hand.Text = "\u{1F446}"
		hand.TextScaled = true
		hand.ZIndex = 54
		hand.Parent = root

		task.spawn(function()
			while hand.Parent do
				local up = TweenService:Create(hand, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Position = UDim2.new(0.3, 0, 0, 26) })
				up:Play()
				up.Completed:Wait()
				if not hand.Parent then
					break
				end
				local down = TweenService:Create(hand, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Position = UDim2.new(0.3, 0, 0, 36) })
				down:Play()
				down.Completed:Wait()
			end
		end)

		-- Red "!" badge, top-right corner of the tile.
		local badge = Instance.new("Frame")
		badge.Size = UDim2.new(0, 34, 0, 34)
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.new(1, 0, 0, 0)
		badge.BackgroundColor3 = Theme.Colors.Danger
		badge.ZIndex = 55
		badge.Parent = tile
		Theme.Round(badge, UDim.new(1, 0))
		Theme.Stroke(badge, Color3.fromRGB(255, 255, 255), 2)

		local badgeLabel = Instance.new("TextLabel")
		badgeLabel.Size = UDim2.new(1, 0, 1, 0)
		badgeLabel.BackgroundTransparency = 1
		badgeLabel.Font = Theme.Fonts.Header
		badgeLabel.TextScaled = true
		badgeLabel.Text = "!"
		badgeLabel.TextColor3 = Color3.new(1, 1, 1)
		badgeLabel.ZIndex = 56
		badgeLabel.Parent = badge

		-- ===== Speech bubble, to the right of the tile =====
		local bubble = Instance.new("Frame")
		bubble.Size = UDim2.new(0, 210, 0, 110)
		bubble.Position = UDim2.new(0, 120, 0, 66)
		bubble.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
		bubble.ZIndex = 52
		bubble.Parent = root
		Theme.Round(bubble, UDim.new(0, 16))
		Theme.Stroke(bubble, Color3.fromRGB(70, 70, 78), 1.5)

		local bubblePadding = Instance.new("UIPadding")
		bubblePadding.PaddingTop = UDim.new(0, 12)
		bubblePadding.PaddingBottom = UDim.new(0, 12)
		bubblePadding.PaddingLeft = UDim.new(0, 14)
		bubblePadding.PaddingRight = UDim.new(0, 14)
		bubblePadding.Parent = bubble

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Size = UDim2.new(1, 0, 0, 30)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Theme.Fonts.Header
		titleLabel.TextScaled = true
		titleLabel.Text = string.upper(config.Title)
		titleLabel.TextColor3 = Color3.new(1, 1, 1)
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.ZIndex = 53
		titleLabel.Parent = bubble

		local descriptionLabel = Instance.new("TextLabel")
		descriptionLabel.Size = UDim2.new(1, 0, 0, 60)
		descriptionLabel.Position = UDim2.new(0, 0, 0, 34)
		descriptionLabel.BackgroundTransparency = 1
		descriptionLabel.Font = Theme.Fonts.Body
		descriptionLabel.TextScaled = true
		descriptionLabel.TextWrapped = true
		descriptionLabel.Text = config.Description
		descriptionLabel.TextColor3 = ACCENT_COLOR
		descriptionLabel.TextXAlignment = Enum.TextXAlignment.Left
		descriptionLabel.TextYAlignment = Enum.TextYAlignment.Top
		descriptionLabel.ZIndex = 53
		descriptionLabel.Parent = bubble

		local tapHintLabel = Theme.Label(root, UDim2.new(1, 0, 0, 20), "Tap anywhere to continue", false)
		tapHintLabel.Position = UDim2.new(0, 0, 1, -20)
		tapHintLabel.TextColor3 = Theme.Colors.TextSecondary
		tapHintLabel.TextXAlignment = Enum.TextXAlignment.Center
		tapHintLabel.ZIndex = 52

		dismissButton.Activated:Connect(function()
			overlay:Destroy()
		end)
	end

	-- Shows `config`'s callout centered on screen, once, the first time
	-- this exact `hintId` is ever passed in for this player -- every call
	-- after the first (this session or a future one) is a silent no-op.
	function handle.ShowOnce(hintId: string, config: HintConfig)
		if seenHints[hintId] then
			return
		end
		-- Marks it locally right away too -- prevents a 2nd ShowOnce call
		-- for the same id (e.g. opening the panel twice fast) from firing
		-- a 2nd overlapping callout before the server's ack would've
		-- updated seenHints on its own.
		seenHints[hintId] = true
		markTutorialHintSeen:FireServer(hintId)
		display(config)
	end

	-- Shows `config`'s callout every single time it's called, no "seen"
	-- gating at all -- temporary, per current request, until the hint's
	-- final one-time trigger point is decided.
	function handle.Show(config: HintConfig)
		display(config)
	end

	return handle
end

return TutorialHint
