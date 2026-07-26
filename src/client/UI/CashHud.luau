-- Always-visible Cash pill, top-right corner -- distinct from the full
-- stats card inside ProfilePanel (Title/VIP/NetWorth/Income), which stays
-- opt-in. Cash specifically is the one number players expect to see at a
-- glance without opening a menu, so it's not gated behind any panel/modal
-- and never hides when a modal opens (unlike RollPanel's HUD).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local CashHud = {}

function CashHud.Create(screenGui: ScreenGui)
	local pill = Instance.new("Frame")
	pill.Size = UDim2.new(0, 150, 0, 44)
	pill.Position = UDim2.new(1, -166, 0, 16)
	pill.BackgroundColor3 = Theme.Colors.Panel
	pill.BackgroundTransparency = 0
	pill.BorderSizePixel = 0
	pill.ZIndex = 5
	pill.Parent = screenGui
	Theme.Round(pill, UDim.new(0, 12))
	Theme.Stroke(pill, Color3.fromRGB(255, 215, 140), 1)
	Theme.Shadow(pill)

	local label = Theme.Label(pill, UDim2.new(1, -16, 1, 0), "\u{1F4B5} $0", true)
	label.Position = UDim2.new(0, 8, 0, 0)
	label.TextXAlignment = Enum.TextXAlignment.Center

	local handle = {}
	handle.Frame = pill

	function handle.Update(cash: number)
		label.Text = "\u{1F4B5} " .. NumberFormat.FormatCash(cash)
	end

	return handle
end

return CashHud
