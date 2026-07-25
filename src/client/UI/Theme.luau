-- Shared style constants + factory helpers so every panel looks consistent.
-- Dark/gold "wealth" palette; rarity colors still come from RarityConfig
-- (shared with the server), not duplicated here.

local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(15, 15, 20),
	Panel = Color3.fromRGB(24, 24, 32),
	-- Lighter than Panel on purpose: rows/cards use Surface so they visibly
	-- pop off the panel backdrop instead of blending into one dark mass.
	Surface = Color3.fromRGB(42, 42, 54),
	Accent = Color3.fromRGB(212, 175, 55),
	Success = Color3.fromRGB(60, 190, 100),
	Danger = Color3.fromRGB(200, 60, 60),
	TextPrimary = Color3.fromRGB(240, 240, 245),
	TextSecondary = Color3.fromRGB(170, 170, 180),
}

Theme.Fonts = {
	Header = Enum.Font.GothamBold,
	Body = Enum.Font.Gotham,
}

Theme.CornerRadius = UDim.new(0, 16)

local HOVER_DELTA = 0.08

function Theme.Round(instance: Instance, radius: UDim?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or Theme.CornerRadius
	corner.Parent = instance
	return corner
end

function Theme.Lighten(color: Color3, amount: number): Color3
	return Color3.new(
		math.clamp(color.R + amount, 0, 1),
		math.clamp(color.G + amount, 0, 1),
		math.clamp(color.B + amount, 0, 1)
	)
end

function Theme.Stroke(instance: GuiObject, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.fromRGB(255, 255, 255)
	stroke.Thickness = thickness or 1
	stroke.Transparency = 0.35
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = instance
	return stroke
end

-- Flat, offset, semi-transparent Frame behind `instance` -- reads as a soft
-- drop shadow without needing an image asset. Only used on panels (the
-- reveal window, stat card) -- deliberately not on every small button/row,
-- to keep the inventory list light.
function Theme.Shadow(instance: GuiObject, offset: number?): Frame
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.6
	shadow.BorderSizePixel = 0
	shadow.Size = instance.Size
	shadow.Position = instance.Position + UDim2.new(0, offset or 4, 0, offset or 4)
	shadow.AnchorPoint = instance.AnchorPoint
	shadow.ZIndex = instance.ZIndex - 1
	shadow.Visible = instance.Visible
	shadow.Parent = instance.Parent
	Theme.Round(shadow)

	-- Shadow is a sibling (has to be, to draw behind instance's own
	-- background), so toggling instance.Visible doesn't cascade to it for
	-- free the way a child's would -- keep them in sync explicitly.
	instance:GetPropertyChangedSignal("Visible"):Connect(function()
		shadow.Visible = instance.Visible
	end)

	return shadow
end

function Theme.Panel(parent: Instance, size: UDim2, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Theme.Round(frame)
	Theme.Stroke(frame, Color3.fromRGB(255, 215, 140), 1)

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(42, 42, 54)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 16, 24)),
	})
	gradient.Rotation = 90
	gradient.Parent = frame

	Theme.Shadow(frame)

	return frame
end

-- Hover/leave lighten by a fixed delta relative to whatever the button's
-- CURRENT color is, rather than a remembered "base" color -- callers are
-- free to change BackgroundColor3 after the fact (e.g. InventoryPanel
-- recoloring a Sell button to Danger red) without the hover tween snapping
-- back to a stale original.
function Theme.Button(parent: Instance, size: UDim2, position: UDim2, text: string, accent: boolean?): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = accent and Theme.Colors.Accent or Theme.Colors.Surface
	button.BorderSizePixel = 0
	button.TextColor3 = accent and Color3.fromRGB(20, 20, 20) or Theme.Colors.TextPrimary
	button.Font = Theme.Fonts.Header
	button.TextScaled = true
	button.Text = text
	button.Parent = parent
	Theme.Round(button)
	Theme.Stroke(button, accent and Color3.fromRGB(255, 235, 180) or Color3.fromRGB(110, 110, 122), accent and 1.5 or 1)

	if accent then
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 224, 145)),
			ColorSequenceKeypoint.new(1, Theme.Colors.Accent),
		})
		gradient.Rotation = 90
		gradient.Parent = button
	end

	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { BackgroundColor3 = Theme.Lighten(button.BackgroundColor3, HOVER_DELTA) }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { BackgroundColor3 = Theme.Lighten(button.BackgroundColor3, -HOVER_DELTA) }):Play()
	end)

	return button
end

function Theme.Label(parent: Instance, size: UDim2, text: string, isHeader: boolean?): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = size
	label.BackgroundTransparency = 1
	label.TextColor3 = isHeader and Theme.Colors.Accent or Theme.Colors.TextPrimary
	label.Font = isHeader and Theme.Fonts.Header or Theme.Fonts.Body
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent

	if isHeader then
		label.TextStrokeTransparency = 0.7
	end

	return label
end

return Theme
