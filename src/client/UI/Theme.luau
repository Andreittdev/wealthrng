-- Shared style constants + factory helpers so every panel looks consistent.
-- Dark/gold "wealth" palette; rarity colors still come from RarityConfig
-- (shared with the server), not duplicated here.

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(15, 15, 20),
	Panel = Color3.fromRGB(24, 24, 32),
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

Theme.CornerRadius = UDim.new(0, 12)

function Theme.Round(instance: Instance, radius: UDim?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or Theme.CornerRadius
	corner.Parent = instance
	return corner
end

function Theme.Panel(parent: Instance, size: UDim2, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Parent = parent
	Theme.Round(frame)
	return frame
end

function Theme.Button(parent: Instance, size: UDim2, position: UDim2, text: string, accent: boolean?): TextButton
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = accent and Theme.Colors.Accent or Theme.Colors.Panel
	button.BorderSizePixel = 0
	button.TextColor3 = accent and Color3.fromRGB(20, 20, 20) or Theme.Colors.TextPrimary
	button.Font = Theme.Fonts.Header
	button.TextScaled = true
	button.Text = text
	button.Parent = parent
	Theme.Round(button)

	if accent then
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 224, 145)),
			ColorSequenceKeypoint.new(1, Theme.Colors.Accent),
		})
		gradient.Rotation = 90
		gradient.Parent = button
	end

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
	return label
end

return Theme
