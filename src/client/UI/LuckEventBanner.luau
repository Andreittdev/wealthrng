-- Top-of-screen banner for the recurring server-wide "X2 Luck" event
-- (LuckEventConfig.luau/LuckEventManager.luau) -- clover icon + "X2 Luck
-- Active!", visible to everyone at once since it's the same window for
-- every player, not a per-player timer. No countdown text shown (per
-- explicit request), but it still auto-hides itself exactly when the
-- window actually ends -- EndsAt (a Unix timestamp from the server) is
-- still tracked internally purely to know when to disappear, same idea as
-- every other countdown in this codebase, just not rendered.

local RunService = game:GetService("RunService")

local Theme = require(script.Parent.Theme)

local LuckEventBanner = {}

local BANNER_SIZE = UDim2.new(0, 300, 0, 76)
local ICON_SIZE = 56
-- Same clover image LuckSpeedHUD.luau's Luck badge uses, so this banner
-- visually reads as "the same Luck" rather than a different icon.
local LUCK_ICON = "rbxassetid://76273108449466"

function LuckEventBanner.Create(screenGui: ScreenGui, remotes: Folder)
	local luckEventStateUpdated = remotes:WaitForChild("LuckEventStateUpdated")

	local banner = Instance.new("Frame")
	banner.Size = BANNER_SIZE
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 8)
	banner.BackgroundTransparency = 1
	banner.Visible = false
	banner.ZIndex = 15
	banner.Parent = screenGui
	Theme.AutoScale(screenGui, banner, BANNER_SIZE.X.Offset)

	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = LUCK_ICON
	icon.ZIndex = 16
	icon.Parent = banner

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -(ICON_SIZE + 20), 1, -12)
	titleLabel.AnchorPoint = Vector2.new(0, 0.5)
	titleLabel.Position = UDim2.new(0, ICON_SIZE + 16, 0.5, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Theme.Fonts.Header
	titleLabel.TextScaled = true
	titleLabel.Text = "X2 Luck Active!"
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextStrokeTransparency = 0
	titleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = 16
	titleLabel.Parent = banner

	local endsAt: number? = nil
	local eventActive = false
	-- Set by MainUI.luau while in Endless Mode -- suppresses the banner
	-- regardless of whether the event is actually active, per explicit
	-- request, without losing track of the real active/EndsAt state
	-- underneath (so it comes back correctly the instant it's un-suppressed,
	-- not just "on" unconditionally).
	local suppressed = false

	local function updateVisibility()
		banner.Visible = eventActive and not suppressed
	end

	luckEventStateUpdated.OnClientEvent:Connect(function(state: { Active: boolean, EndsAt: number? })
		if state.Active and state.EndsAt then
			endsAt = state.EndsAt
			eventActive = true
		else
			endsAt = nil
			eventActive = false
		end
		updateVisibility()
	end)

	-- No countdown shown -- this loop only exists to hide the banner right
	-- when the window actually ends, instead of leaving it up until the
	-- next server push (which only fires on transitions).
	RunService.Heartbeat:Connect(function()
		if not endsAt then
			return
		end
		if endsAt - os.time() <= 0 then
			endsAt = nil
			eventActive = false
			updateVisibility()
		end
	end)

	local handle = {}
	handle.Frame = banner

	function handle.SetSuppressed(value: boolean)
		suppressed = value
		updateVisibility()
	end

	return handle
end

return LuckEventBanner
