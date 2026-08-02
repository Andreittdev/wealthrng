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

-- Single decorative display font for everything (no separate header/body
-- weight the way Gotham had Bold/Regular) -- one field for each since every
-- Theme.Label/Theme.Button call site already asks for one or the other.
Theme.Fonts = {
	Header = Enum.Font.LuckiestGuy,
	Body = Enum.Font.LuckiestGuy,
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

local function applyPanelChrome(frame: Frame): Frame
	frame.BackgroundColor3 = Theme.Colors.Panel
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	Theme.Round(frame)
	Theme.Stroke(frame, Color3.fromRGB(255, 215, 140), 1)

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(42, 42, 54)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 16, 24)),
	})
	gradient.Rotation = 90
	gradient.Parent = frame

	return Theme.Shadow(frame)
end

-- Fixed pixel size -- only used for RollPanel's small reveal window, which
-- runs its own Size-tweening bounce animation (see RollPanel.luau's
-- playSettleBounce) that would fight with any responsive/scale-based
-- sizing here. Every other panel should use Theme.ResponsivePanel instead.
function Theme.Panel(parent: Instance, size: UDim2, position: UDim2): Frame
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.Parent = parent
	applyPanelChrome(frame)
	return frame
end

-- Same look as Theme.Panel, but shrinks to fit narrow/short (phone)
-- screens instead of overflowing them: `maxSize`'s X.Offset becomes an
-- upper bound (via UISizeConstraint), not a fixed width -- the panel is
-- 94% of screen width up to that bound.
--
-- Height USED to stay fixed at maxSize.Y.Offset on the (wrong) assumption
-- that these dialogs were short enough vertically that only width could
-- overflow. On a short landscape phone screen a flat 400-600px-tall panel
-- overflows the whole viewport top and bottom (that's the "Store looks
-- buggy on phone" report -- an oversized fixed-height panel, not a grid
-- bug). Height is now `100% of the screen minus a symmetric margin` (every
-- call site passes the same `position.Y.Offset` as its top gap, e.g. 60,
-- so mirroring it as the bottom gap too keeps the panel vertically
-- centered-ish and guarantees it fits), capped at maxSize.Y.Offset so
-- desktop/tablet sizing is unchanged from before.
-- `position`'s X component is ignored -- the panel is always centered via
-- AnchorPoint instead of the caller working out "-width/2" by hand, which
-- only produced correct centering for a fixed width. Pass position's Y
-- component exactly like Theme.Panel's.
function Theme.ResponsivePanel(parent: Instance, maxSize: UDim2, position: UDim2): Frame
	local verticalMargin = position.Y.Offset

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0.94, 0, 1, -verticalMargin * 2)
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, position.Y.Scale, position.Y.Offset)
	frame.Parent = parent

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(maxSize.X.Offset, maxSize.Y.Offset)
	sizeConstraint.Parent = frame

	local shadow = applyPanelChrome(frame)

	-- Shadow is a sibling Frame (see Theme.Shadow), not a child, so it
	-- doesn't inherit `frame`'s UISizeConstraint automatically -- give it
	-- a matching cap or it'd render wider than the panel it's shadowing on
	-- large screens.
	local shadowConstraint = Instance.new("UISizeConstraint")
	shadowConstraint.MaxSize = Vector2.new(maxSize.X.Offset, maxSize.Y.Offset)
	shadowConstraint.Parent = shadow

	return frame
end

-- Shrinks a fixed-size HUD cluster (Sidebar's button grid, RollPanel's
-- reveal window + button) to fit narrow phone screens, via UIScale rather
-- than resizing every child individually -- `container` should be an
-- otherwise-plain (BackgroundTransparency = 1) Frame sized to exactly wrap
-- its children at their normal/desktop size, anchored wherever the cluster
-- should stay pinned (e.g. bottom-center for the Roll HUD) so scaling
-- shrinks it toward that anchor instead of toward the screen's corner.
-- `referenceWidth` is the screen width at/above which Scale stays 1 (no
-- change from the existing desktop look); below it, Scale shrinks down to
-- `minScale` (default 0.6, chosen so Sidebar's 76px buttons don't shrink
-- past ~46px -- still comfortably tappable).
--
-- Also factors in HEIGHT against a fixed reference (not just width) --
-- landscape phones are wide but short, so a width-only scale left
-- fixed-pixel HUD clusters (Sidebar, LuckSpeedHUD, etc.) nearly full-size
-- on those screens even though there wasn't nearly enough VERTICAL room,
-- which is exactly what caused them to visually collide with each other.
-- The smaller of the two ratios wins, so a short-but-wide screen shrinks
-- enough to actually clear itself, not just a narrow-but-tall one.
local AUTOSCALE_REFERENCE_HEIGHT = 700

function Theme.AutoScale(screenGui: ScreenGui, container: GuiObject, referenceWidth: number, minScale: number?): UIScale
	local uiScale = Instance.new("UIScale")
	uiScale.Parent = container

	local function update()
		local size = screenGui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local widthScale = size.X / referenceWidth
		local heightScale = size.Y / AUTOSCALE_REFERENCE_HEIGHT
		uiScale.Scale = math.clamp(math.min(widthScale, heightScale), minScale or 0.6, 1)
	end

	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()

	return uiScale
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
