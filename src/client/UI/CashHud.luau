-- Always-visible Cash pill, top-right corner -- distinct from the full
-- stats card inside ProfilePanel (Title/VIP/NetWorth/Income), which stays
-- opt-in. Cash specifically is the one number players expect to see at a
-- glance without opening a menu, so it's not gated behind any panel/modal
-- and never hides when a modal opens (unlike RollPanel's HUD).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local CASH_ICON = "rbxassetid://72463281853990"

local CashHud = {}

function CashHud.Create(screenGui: ScreenGui)
	-- No panel/stroke/shadow -- just the icon + text floating directly over
	-- the game, per request. `pill` is now purely a layout container (still
	-- named that for the rest of this function/its children's relative
	-- positioning), not a visible background shape.
	local pill = Instance.new("Frame")
	pill.Size = UDim2.new(0, 150, 0, 44)
	pill.Position = UDim2.new(1, -166, 0, 16)
	pill.BackgroundTransparency = 1
	pill.BorderSizePixel = 0
	pill.ZIndex = 5
	pill.Parent = screenGui

	-- Real icon instead of the old "\u{1F4B5}" emoji prefix -- deliberately
	-- bigger than the pill itself (overflows top/bottom/left a bit) for a
	-- punchier "big icon" look, same idea as other currency HUD pills --
	-- ZIndex above the pill so it draws over the rounded corner instead of
	-- getting clipped by it.
	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.new(0, 60, 0, 60)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, -8, 0.5, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = CASH_ICON
	icon.ZIndex = 6
	icon.Parent = pill

	local label = Theme.Label(pill, UDim2.new(1, -62, 1, 0), "$0", true)
	label.Position = UDim2.new(0, 54, 0, 0)
	label.TextXAlignment = Enum.TextXAlignment.Center
	-- Stronger stroke than Theme.Label's default header stroke (0.7
	-- transparency) -- needed for legibility now that there's no panel
	-- background behind it, just the 3D game world.
	label.TextStrokeTransparency = 0

	local handle = {}
	handle.Frame = pill

	function handle.Update(cash: number)
		label.Text = NumberFormat.FormatCash(cash)
	end

	return handle
end

return CashHud
