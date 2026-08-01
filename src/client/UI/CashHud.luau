-- Always-visible Cash pill, top-right corner -- distinct from the full
-- stats card inside ProfilePanel (Title/VIP/NetWorth/Income), which stays
-- opt-in. Cash specifically is the one number players expect to see at a
-- glance without opening a menu, so it's not gated behind any panel/modal
-- and never hides when a modal opens (unlike RollPanel's HUD).

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local CASH_ICON = "rbxassetid://72463281853990"
local ROW1_HEIGHT = 52
local ROW2_HEIGHT = 32

local CashHud = {}

-- One row = one Frame with a horizontal UIListLayout (VerticalAlignment =
-- Center) -- Roblox's own layout engine centers every child on the same
-- vertical line automatically, instead of each child needing its own
-- hand-tuned Y offset/AnchorPoint (which is what kept drifting out of
-- alignment every time text length/box size changed).
local function createRow(parent: Instance, height: number, positionY: number): Frame
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, height)
	row.Position = UDim2.new(0, 0, 0, positionY)
	row.BackgroundTransparency = 1
	row.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	return row
end

function CashHud.Create(screenGui: ScreenGui)
	-- No panel/stroke/shadow -- just the icon + text floating directly over
	-- the game, per request. `pill` is now purely a layout container (still
	-- named that for the rest of this function/its children's relative
	-- positioning), not a visible background shape.
	local pill = Instance.new("Frame")
	pill.Size = UDim2.new(0, 220, 0, ROW1_HEIGHT + ROW2_HEIGHT)
	pill.Position = UDim2.new(1, -166, 0, 16)
	pill.BackgroundTransparency = 1
	pill.BorderSizePixel = 0
	pill.ZIndex = 5
	pill.Parent = screenGui

	-- ===== Row 1: icon + cash =====
	local row1 = createRow(pill, ROW1_HEIGHT, 0)

	local icon = Instance.new("ImageLabel")
	icon.LayoutOrder = 1
	icon.Size = UDim2.new(0, ROW1_HEIGHT, 0, ROW1_HEIGHT)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = CASH_ICON
	icon.ZIndex = 6
	icon.Parent = row1

	local label = Instance.new("TextLabel")
	label.LayoutOrder = 2
	label.Size = UDim2.new(0, 150, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Theme.Fonts.Header
	label.TextScaled = true
	label.Text = "$0"
	label.TextColor3 = Theme.Colors.Accent
	label.TextXAlignment = Enum.TextXAlignment.Left
	-- Stronger stroke than a plain header label's default -- needed for
	-- legibility now that there's no panel background behind it, just the
	-- 3D game world.
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Parent = row1
	local labelTextSize = Instance.new("UITextSizeConstraint")
	labelTextSize.MaxTextSize = 34
	labelTextSize.Parent = label

	-- ===== Row 2: Friend Boost text + invite button =====
	local row2 = createRow(pill, ROW2_HEIGHT, ROW1_HEIGHT)
	local row2Padding = Instance.new("UIPadding")
	row2Padding.PaddingLeft = UDim.new(0, 14)
	row2Padding.Parent = row2

	local friendBoostLabel = Instance.new("TextLabel")
	friendBoostLabel.LayoutOrder = 1
	-- Fixed TextSize + AutomaticSize (X) instead of TextScaled + a guessed
	-- fixed width -- TextScaled kept the BOX at 168px regardless of how
	-- short the shrunk-to-fit text actually rendered, leaving a big empty
	-- gap between the visible text and the "+" button sitting right after
	-- that oversized box. AutomaticSize makes the box hug the real text
	-- width instead, so the button sits immediately next to it no matter
	-- how long "Friend Boost: +N%" ends up being.
	friendBoostLabel.Size = UDim2.new(0, 0, 1, 0)
	friendBoostLabel.AutomaticSize = Enum.AutomaticSize.X
	friendBoostLabel.BackgroundTransparency = 1
	friendBoostLabel.Font = Theme.Fonts.Header
	friendBoostLabel.TextSize = 20
	friendBoostLabel.TextWrapped = false
	friendBoostLabel.Text = "Friend Boost: +0%"
	friendBoostLabel.TextColor3 = Theme.Colors.Success
	friendBoostLabel.TextXAlignment = Enum.TextXAlignment.Left
	friendBoostLabel.TextStrokeTransparency = 0
	friendBoostLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	friendBoostLabel.Parent = row2

	local inviteButton = Instance.new("TextButton")
	inviteButton.LayoutOrder = 2
	inviteButton.Size = UDim2.new(0, ROW2_HEIGHT, 0, ROW2_HEIGHT)
	inviteButton.BackgroundColor3 = Theme.Colors.Success
	inviteButton.BorderSizePixel = 0
	inviteButton.AutoButtonColor = true
	inviteButton.Text = "+"
	inviteButton.Font = Theme.Fonts.Header
	inviteButton.TextScaled = true
	inviteButton.TextColor3 = Color3.fromRGB(20, 20, 20)
	inviteButton.ZIndex = 6
	inviteButton.Parent = row2
	Theme.Round(inviteButton, UDim.new(1, 0))

	-- SocialService is the real API for this (not GuiService, which doesn't
	-- have PromptGameInvite) -- CanSendGameInviteAsync is an async network
	-- call that can fail, so it's wrapped in a pcall per Roblox's own
	-- guidance instead of assuming it always succeeds.
	inviteButton.Activated:Connect(function()
		local ok, canInvite = pcall(function()
			return SocialService:CanSendGameInviteAsync(Players.LocalPlayer)
		end)
		if ok and canInvite then
			SocialService:PromptGameInvite(Players.LocalPlayer)
		end
	end)

	local handle = {}
	handle.Frame = pill

	function handle.Update(cash: number)
		label.Text = NumberFormat.FormatCash(cash)
	end

	function handle.UpdateFriendBoost(percent: number)
		friendBoostLabel.Text = string.format("Friend Boost: +%d%%", percent)
	end

	return handle
end

return CashHud
