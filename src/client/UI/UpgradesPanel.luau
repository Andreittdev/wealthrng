-- Sidebar/RollPanel-triggered panel for the 3 permanent Cash-bought upgrade
-- tracks (Roll Speed, Luck, Potion Boost Time) -- see UpgradeConfig.luau for
-- the cost/effect curves.
--
-- "Grape cluster" navigation, per explicit user request: a root "UPGRADES"
-- node up top, connected by red arrows down to the 3 track branches (Roll
-- Speed / Luck / Potion Boost). Tapping a branch opens that track's own
-- vine -- a vertical chain of every level already owned (small, gold,
-- "done") connected by red arrows down to ONE big expanded node for the
-- next purchasable level (icon + red "!" badge + effect + buy pill). Buying
-- re-renders the whole vine, which is what makes it grow one node at a
-- time -- level 1 shown first, buy it, level 2's node appears next, and so
-- on up to 20, exactly like the user described.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local PotionDatabase = require(ReplicatedStorage.Modules.PotionDatabase)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local UpgradesPanel = {}

local DICE_IMAGE = "rbxassetid://92855815758385" -- same dice RollPanel/LuckSpeedHUD use
local LUCK_ICON = "rbxassetid://76273108449466" -- same clover LuckSpeedHUD uses
local ROOT_IMAGE = "rbxassetid://119321429785408" -- the Upgrades icon the user supplied
local POTION_BOOST_IMAGE = PotionDatabase.GetPotion("LuckPotion").Image

local DEBOUNCE_SECONDS = 0.5

local function debounce(fn: () -> ())
	local lastFiredAt = 0
	return function()
		local now = os.clock()
		if now - lastFiredAt < DEBOUNCE_SECONDS then
			return
		end
		lastFiredAt = now
		fn()
	end
end

local ROMAN_NUMERALS = {
	"0", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
	"XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX",
}
local function toRoman(level: number): string
	return ROMAN_NUMERALS[level + 1] or tostring(level)
end

local TRACK_INFO: { [string]: { Image: string?, Emoji: string?, Label: string, EffectText: (number) -> string } } = {
	RollSpeed = {
		Image = DICE_IMAGE,
		Label = "ROLL SPEED",
		EffectText = function(level: number): string
			return string.format("-%d%% COOLDOWN", math.floor((1 - UpgradeConfig.GetCooldownMultiplier(level)) * 100 + 0.5))
		end,
	},
	Luck = {
		Image = LUCK_ICON,
		Label = "LUCK BOOST",
		EffectText = function(level: number): string
			local luxuryMult = UpgradeConfig.GetLuckMultiplier(level, "Luxury")
			return string.format("+%d%% MORE LUCK!", math.floor((luxuryMult - 1) * 100 + 0.5))
		end,
	},
	PotionBoost = {
		Image = POTION_BOOST_IMAGE,
		Label = "POTION BOOST",
		EffectText = function(level: number): string
			return string.format("+%d%% DURATION", math.floor((UpgradeConfig.GetPotionDurationMultiplier(level) - 1) * 100 + 0.5))
		end,
	},
}

-- Root-view connectors are drawn as a plain axis-aligned "org chart" tree
-- (vertical stub down from the root -> horizontal spreader bar -> vertical
-- drop to each branch) instead of rotated point-to-point lines -- much
-- harder to get subtly wrong than trig, and reads just as clearly as
-- "everything connected".
local function vLine(parent: Instance, x: number, yTop: number, yBottom: number, color: Color3, thickness: number?)
	local t = thickness or 4
	local line = Instance.new("Frame")
	line.Position = UDim2.new(0, x - t / 2, 0, yTop)
	line.Size = UDim2.new(0, t, 0, yBottom - yTop)
	line.BackgroundColor3 = color
	line.BorderSizePixel = 0
	line.Parent = parent
	Theme.Round(line, UDim.new(1, 0))
end

local function hLine(parent: Instance, xLeft: number, xRight: number, y: number, color: Color3, thickness: number?)
	local t = thickness or 4
	local line = Instance.new("Frame")
	line.Position = UDim2.new(0, xLeft, 0, y - t / 2)
	line.Size = UDim2.new(0, xRight - xLeft, 0, t)
	line.BackgroundColor3 = color
	line.BorderSizePixel = 0
	line.Parent = parent
	Theme.Round(line, UDim.new(1, 0))
end

local function downArrowHead(parent: Instance, x: number, y: number, color: Color3)
	local head = Instance.new("TextLabel")
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.Position = UDim2.new(0, x, 0, y)
	head.Size = UDim2.new(0, 16, 0, 16)
	head.Rotation = 90
	head.BackgroundTransparency = 1
	head.Text = "\u{25B6}"
	head.TextColor3 = color
	head.TextScaled = true
	head.Parent = parent
end

-- Same arrow, but as a UIListLayout item (used inside the scrolling
-- per-track vine, which stacks straight down, not at arbitrary points).
local function verticalConnectorItem(parent: Instance, layoutOrder: number)
	local wrap = Instance.new("Frame")
	wrap.LayoutOrder = layoutOrder
	wrap.Size = UDim2.new(1, 0, 0, 26)
	wrap.BackgroundTransparency = 1
	wrap.Parent = parent

	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.new(0.5, 0, 0, 0)
	line.Size = UDim2.new(0, 4, 0, 16)
	line.BackgroundColor3 = Theme.Colors.Danger
	line.BorderSizePixel = 0
	line.Parent = wrap
	Theme.Round(line, UDim.new(1, 0))

	local head = Instance.new("TextLabel")
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.new(0.5, 0, 0, 14)
	head.Size = UDim2.new(0, 16, 0, 16)
	head.Rotation = 90
	head.BackgroundTransparency = 1
	head.Text = "\u{25B6}"
	head.TextColor3 = Theme.Colors.Danger
	head.TextScaled = true
	head.Parent = wrap
end

function UpgradesPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local buyUpgrade = remotes:WaitForChild("BuyUpgrade")
	local upgradesUpdated = remotes:WaitForChild("UpgradesUpdated")

	local currentLevels: { [string]: number } = {}
	local openTrackId: string? = nil -- nil = showing the root (3-branch) view
	-- Forward-declared: branch/back buttons below close over this before its
	-- real body (down in "Shared render") is assigned.
	local render: () -> ()

	local ROOT_WIDTH, ROOT_HEIGHT = 340, 620

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, ROOT_WIDTH, 0, ROOT_HEIGHT)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = Theme.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 10
	panel.Parent = screenGui
	Theme.Round(panel)
	Theme.Stroke(panel, Color3.fromRGB(255, 215, 140), 1)
	-- minScale was 0.55, which floors out at 620*0.55=341px tall -- on a
	-- short phone screen (height under 700*0.55=385px, i.e. most phones in
	-- portrait), AutoScale couldn't shrink the panel any further than that
	-- floor, so it overflowed top and bottom regardless of how short the
	-- actual screen was. Lower floor gives it real room to keep shrinking.
	Theme.AutoScale(screenGui, panel, ROOT_WIDTH, 0.28)

	local titleLabel = Theme.Label(panel, UDim2.new(1, -32, 0, 30), "UPGRADES", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 12)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.new(1, -32, 0, 48)
	closeButton.Position = UDim2.new(0, 16, 1, -54)
	closeButton.BackgroundColor3 = Theme.Colors.Danger
	closeButton.BorderSizePixel = 0
	closeButton.Font = Theme.Fonts.Header
	closeButton.TextScaled = true
	closeButton.Text = "CLOSE"
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.Parent = panel
	Theme.Round(closeButton, UDim.new(0, 14))
	Theme.Stroke(closeButton, Color3.fromRGB(255, 255, 255), 1.5)
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	local viewArea = Instance.new("Frame")
	viewArea.Size = UDim2.new(1, -32, 1, -120)
	viewArea.Position = UDim2.new(0, 16, 0, 52)
	viewArea.BackgroundTransparency = 1
	viewArea.Parent = panel

	-- ===================== ROOT VIEW: Upgrades -> 3 branches =====================
	local rootView = Instance.new("Frame")
	rootView.Size = UDim2.new(1, 0, 1, 0)
	rootView.BackgroundTransparency = 1
	rootView.Parent = viewArea

	-- viewArea is 340 - 32 = 308px wide (see its Size above), NOT the full
	-- 340px panel width -- the branch/root X's below are chosen to fit
	-- INSIDE that real 308px, not the panel's own width. The previous
	-- 55/170/285 set assumed the full 340px and pushed the rightmost
	-- branch past viewArea's actual right edge, which is what was
	-- overlapping the panel border.
	local ROOT_CENTER_X = 154

	local rootTile = Instance.new("Frame")
	rootTile.Size = UDim2.new(0, 90, 0, 90)
	rootTile.AnchorPoint = Vector2.new(0.5, 0)
	rootTile.Position = UDim2.new(0, ROOT_CENTER_X, 0, 4)
	rootTile.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	rootTile.Parent = rootView
	Theme.Round(rootTile, UDim.new(0, 18))
	Theme.Stroke(rootTile, Color3.fromRGB(255, 215, 140), 3)

	local rootIcon = Instance.new("ImageLabel")
	rootIcon.Size = UDim2.new(1, -20, 1, -20)
	rootIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	rootIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	rootIcon.BackgroundTransparency = 1
	rootIcon.ScaleType = Enum.ScaleType.Fit
	rootIcon.Image = ROOT_IMAGE
	rootIcon.Parent = rootTile

	local rootLabel = Theme.Label(rootView, UDim2.new(1, 0, 0, 16), "UPGRADES", true)
	rootLabel.Position = UDim2.new(0, 0, 0, 102)
	rootLabel.TextXAlignment = Enum.TextXAlignment.Center

	local BRANCH_X = { 58, 154, 250 }
	local branchLevelLabels: { [string]: TextLabel } = {}

	-- Stub down from the root, then one horizontal bar spanning all 3
	-- branches, then one vertical drop + arrowhead per branch -- see
	-- vLine/hLine's comment for why this is axis-aligned instead of
	-- rotated point-to-point lines. The stub starts BELOW the "UPGRADES"
	-- label (not right at the icon's bottom edge), so it never cuts through
	-- that text -- it used to span the label's exact Y range.
	local SPREADER_Y = 130
	local BRANCH_TOP_Y = 220
	vLine(rootView, ROOT_CENTER_X, 122, SPREADER_Y, Theme.Colors.Danger)
	hLine(rootView, BRANCH_X[1], BRANCH_X[#BRANCH_X], SPREADER_Y, Theme.Colors.Danger)
	for _, centerX in BRANCH_X do
		vLine(rootView, centerX, SPREADER_Y, BRANCH_TOP_Y, Theme.Colors.Danger)
		downArrowHead(rootView, centerX, BRANCH_TOP_Y, Theme.Colors.Danger)
	end

	-- Exposed on the returned handle (RollSpeed only, so far) so
	-- OnboardingTutorial.luau can point an arrow straight at the branch
	-- tile itself, not just the outer button that opens this whole panel.
	local branchButtons: { [string]: TextButton } = {}

	for i, trackId in UpgradeConfig.Order do
		local info = TRACK_INFO[trackId]
		local centerX = BRANCH_X[i]

		local branchButton = Instance.new("TextButton")
		branchButton.Size = UDim2.new(0, 84, 0, 84)
		branchButton.AnchorPoint = Vector2.new(0.5, 0)
		branchButton.Position = UDim2.new(0, centerX, 0, 220)
		branchButton.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
		branchButton.Text = ""
		branchButton.AutoButtonColor = true
		branchButton.Parent = rootView
		Theme.Round(branchButton, UDim.new(0, 16))
		Theme.Stroke(branchButton, Color3.fromRGB(255, 255, 255), 2.5)

		if info.Image then
			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.new(1, -16, 1, -16)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.new(0.5, 0, 0.5, 0)
			icon.BackgroundTransparency = 1
			icon.ScaleType = Enum.ScaleType.Fit
			icon.Image = info.Image
			icon.Parent = branchButton
		else
			local emojiLabel = Instance.new("TextLabel")
			emojiLabel.Size = UDim2.new(1, -16, 1, -16)
			emojiLabel.AnchorPoint = Vector2.new(0.5, 0.5)
			emojiLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
			emojiLabel.BackgroundTransparency = 1
			emojiLabel.Text = info.Emoji
			emojiLabel.TextScaled = true
			emojiLabel.Parent = branchButton
		end

		local branchName = Theme.Label(rootView, UDim2.new(0, 110, 0, 16), info.Label, true)
		branchName.Position = UDim2.new(0, centerX - 55, 0, 306)
		branchName.TextXAlignment = Enum.TextXAlignment.Center

		local branchLevel = Theme.Label(rootView, UDim2.new(0, 110, 0, 16), "", false)
		branchLevel.Position = UDim2.new(0, centerX - 55, 0, 324)
		branchLevel.TextXAlignment = Enum.TextXAlignment.Center
		branchLevel.TextColor3 = Theme.Colors.TextSecondary
		branchLevelLabels[trackId] = branchLevel

		branchButton.Activated:Connect(function()
			openTrackId = trackId
			render()
		end)

		branchButtons[trackId] = branchButton
	end

	-- ===================== TRACK VIEW: one track's level vine =====================
	local trackView = Instance.new("Frame")
	trackView.Size = UDim2.new(1, 0, 1, 0)
	trackView.BackgroundTransparency = 1
	trackView.Visible = false
	trackView.Parent = viewArea

	local backButton = Instance.new("TextButton")
	backButton.Size = UDim2.new(0, 74, 0, 30)
	backButton.BackgroundColor3 = Theme.Colors.Surface
	backButton.Font = Theme.Fonts.Header
	backButton.TextScaled = true
	backButton.Text = "< BACK"
	backButton.TextColor3 = Theme.Colors.TextPrimary
	backButton.Parent = trackView
	Theme.Round(backButton, UDim.new(0, 8))
	backButton.Activated:Connect(function()
		openTrackId = nil
		render()
	end)

	local trackTitle = Theme.Label(trackView, UDim2.new(1, -90, 0, 30), "", true)
	trackTitle.Position = UDim2.new(0, 82, 0, 0)
	trackTitle.TextXAlignment = Enum.TextXAlignment.Left

	local vine = Instance.new("ScrollingFrame")
	vine.Size = UDim2.new(1, 0, 1, -42)
	vine.Position = UDim2.new(0, 0, 0, 42)
	vine.BackgroundTransparency = 1
	vine.BorderSizePixel = 0
	vine.CanvasSize = UDim2.new(0, 0, 0, 0)
	vine.AutomaticCanvasSize = Enum.AutomaticSize.Y
	vine.ScrollBarThickness = 6
	vine.ScrollBarImageColor3 = Theme.Colors.Danger
	vine.Parent = trackView

	-- The scrollbar draws inside vine's own bounds, overlapping whatever's
	-- at the very right edge -- without this, full-width (1,0) cards ran
	-- straight under it and poked past the visible edge (what looked like
	-- "frames going off screen"). Padding keeps every card's real right
	-- edge clear of it.
	local vinePadding = Instance.new("UIPadding")
	vinePadding.PaddingLeft = UDim.new(0, 8)
	vinePadding.PaddingRight = UDim.new(0, 16)
	vinePadding.Parent = vine

	local vineLayout = Instance.new("UIListLayout")
	vineLayout.SortOrder = Enum.SortOrder.LayoutOrder
	vineLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	vineLayout.Parent = vine

	-- One small "already owned" node in the vine.
	local function buildCompletedNode(order: number, trackId: string, level: number)
		local info = TRACK_INFO[trackId]
		local card = Instance.new("Frame")
		card.LayoutOrder = order
		card.Size = UDim2.new(1, 0, 0, 56)
		card.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
		card.BorderSizePixel = 0
		card.Parent = vine
		Theme.Round(card, UDim.new(0, 10))
		local stroke = Theme.Stroke(card, Color3.fromRGB(255, 215, 140), 1.5)
		stroke.Transparency = 0

		local pip = Instance.new("Frame")
		pip.Size = UDim2.new(0, 40, 0, 40)
		pip.Position = UDim2.new(0, 8, 0.5, -20)
		pip.BackgroundColor3 = Theme.Colors.Accent
		pip.Parent = card
		Theme.Round(pip, UDim.new(1, 0))
		local pipLabel = Instance.new("TextLabel")
		pipLabel.Size = UDim2.new(1, 0, 1, 0)
		pipLabel.BackgroundTransparency = 1
		pipLabel.Font = Theme.Fonts.Header
		pipLabel.TextScaled = true
		pipLabel.Text = "\u{2713}"
		pipLabel.TextColor3 = Color3.fromRGB(20, 20, 20)
		pipLabel.Parent = pip

		local label = Theme.Label(card, UDim2.new(1, -60, 0, 20), string.format("%s %s", info.Label, toRoman(level)))
		label.Position = UDim2.new(0, 56, 0, 8)

		local effect = Theme.Label(card, UDim2.new(1, -60, 0, 18), info.EffectText(level))
		effect.Position = UDim2.new(0, 56, 0, 28)
		effect.TextColor3 = Theme.Colors.Success
	end

	-- Fired every time buildExpandedNode below (re)creates the buy button
	-- for a track -- OnboardingTutorial.luau uses this to keep its "buy the
	-- first Roll Speed upgrade" arrow pointed at the CURRENT button
	-- instance, since renderVine tears down and rebuilds the whole vine
	-- (including this button) on every render, not just the first time the
	-- track opens.
	local onExpandedNodeBuilt: ((string, TextButton) -> ())? = nil

	-- The ONE expanded node: the next level to buy (or the final MAXED state).
	-- `currentLevel` is what's already owned -- the card itself always
	-- describes the level ABOVE that (currentLevel + 1), i.e. what buying
	-- right now gets you, so it never repeats the roman numeral the last
	-- completed node above it already showed.
	local function buildExpandedNode(order: number, trackId: string, currentLevel: number)
		local track = UpgradeConfig.Tracks[trackId]
		local info = TRACK_INFO[trackId]
		local maxed = currentLevel >= track.MaxLevel
		local displayLevel = maxed and currentLevel or currentLevel + 1

		local card = Instance.new("Frame")
		card.LayoutOrder = order
		card.Size = UDim2.new(1, 0, 0, 128)
		card.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
		card.BorderSizePixel = 0
		card.Parent = vine
		Theme.Round(card, UDim.new(0, 16))
		Theme.Stroke(card, Color3.fromRGB(255, 255, 255), 2.5)

		local tile = Instance.new("Frame")
		tile.Size = UDim2.new(0, 90, 0, 90)
		tile.Position = UDim2.new(0, 12, 0.5, -45)
		tile.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
		tile.Parent = card
		Theme.Round(tile, UDim.new(0, 14))

		if info.Image then
			local icon = Instance.new("ImageLabel")
			icon.Size = UDim2.new(1, -14, 1, -14)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.new(0.5, 0, 0.5, 0)
			icon.BackgroundTransparency = 1
			icon.ScaleType = Enum.ScaleType.Fit
			icon.Image = info.Image
			icon.Parent = tile
		else
			local emojiLabel = Instance.new("TextLabel")
			emojiLabel.Size = UDim2.new(1, -14, 1, -14)
			emojiLabel.AnchorPoint = Vector2.new(0.5, 0.5)
			emojiLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
			emojiLabel.BackgroundTransparency = 1
			emojiLabel.Text = info.Emoji
			emojiLabel.TextScaled = true
			emojiLabel.Parent = tile
		end

		if not maxed then
			-- Inset fully INSIDE the tile's own top-right corner (not
			-- hanging half-off it) -- hanging off the corner is what put it
			-- on top of the name/effect text sitting right next to the
			-- tile.
			local badge = Instance.new("Frame")
			badge.Size = UDim2.new(0, 26, 0, 26)
			badge.AnchorPoint = Vector2.new(1, 0)
			badge.Position = UDim2.new(1, -4, 0, 4)
			badge.BackgroundColor3 = Theme.Colors.Danger
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
			badgeLabel.Parent = badge
		end

		local nameLabel = Theme.Label(card, UDim2.new(1, -118, 0, 22), string.format("%s %s", info.Label, toRoman(displayLevel)), true)
		nameLabel.Position = UDim2.new(0, 112, 0, 12)

		local effectLabel = Theme.Label(card, UDim2.new(1, -118, 0, 20), info.EffectText(displayLevel))
		effectLabel.Position = UDim2.new(0, 112, 0, 36)
		effectLabel.TextColor3 = Theme.Colors.Success

		local buyButton = Theme.Button(card, UDim2.new(1, -118, 0, 32), UDim2.new(0, 112, 0, 84), "Buy", true)
		if maxed then
			buyButton.Text = "MAXED"
			buyButton.AutoButtonColor = false
		else
			local cost = UpgradeConfig.GetCost(trackId, currentLevel)
			buyButton.Text = "Buy - " .. NumberFormat.FormatCash(cost :: number)
			buyButton.Activated:Connect(debounce(function()
				buyUpgrade:FireServer(trackId)
			end))
		end

		if onExpandedNodeBuilt then
			onExpandedNodeBuilt(trackId, buyButton)
		end
	end

	local function renderVine()
		if not openTrackId then
			return
		end
		for _, child in vine:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		local trackId = openTrackId
		local info = TRACK_INFO[trackId]
		local level = currentLevels[trackId] or 0

		trackTitle.Text = info.Label

		local order = 1
		for i = 1, level do
			buildCompletedNode(order, trackId, i)
			order += 1
			verticalConnectorItem(vine, order)
			order += 1
		end
		buildExpandedNode(order, trackId, level)
	end

	-- ===================== Shared render =====================
	render = function()
		rootView.Visible = openTrackId == nil
		trackView.Visible = openTrackId ~= nil

		for _, trackId in UpgradeConfig.Order do
			local track = UpgradeConfig.Tracks[trackId]
			local level = currentLevels[trackId] or 0
			branchLevelLabels[trackId].Text = string.format("Lv %d/%d", level, track.MaxLevel)
		end

		renderVine()
	end

	upgradesUpdated.OnClientEvent:Connect(function(map: { [string]: number })
		currentLevels = map
		render()
	end)

	render()

	local handle = {}
	handle.Frame = panel
	handle.CloseButton = closeButton
	handle.RollSpeedBranchButton = branchButtons.RollSpeed

	function handle.Toggle()
		panel.Visible = not panel.Visible
	end

	-- See onExpandedNodeBuilt above -- lets OnboardingTutorial.luau react
	-- every time a track's buy button is (re)built, not just once.
	function handle.SetExpandedNodeCallback(callback: (string, TextButton) -> ())
		onExpandedNodeBuilt = callback
	end

	return handle
end

return UpgradesPanel
