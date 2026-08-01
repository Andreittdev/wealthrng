-- Auto Sell Duplicates: a collapsible section (triangle on the left,
-- points up collapsed / down expanded) that reveals one on/off toggle per
-- rarity when opened. All off by default for a new player -- this has to
-- be opted into, never silently eat a fresh player's rolls.
--
-- Below that, a Sound & Effects section (Music/SFX/VFX) -- plain on-off
-- prefs, default on. Nothing in the game reads these yet (no
-- sounds/particles exist), this just persists the toggle so it's ready
-- the moment one does.
--
-- Everything lives in a ScrollingFrame with a UIListLayout, not fixed Y
-- offsets on a fixed-height panel -- a fixed-height layout either wastes
-- space when Auto Sell Duplicates is collapsed or gets cropped by a short
-- viewport when it's expanded (UIListLayout skips invisible children, so
-- collapsing it automatically pulls Sound & Effects up; anything that
-- still doesn't fit just scrolls instead of disappearing off-screen).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local Theme = require(script.Parent.Theme)

local SettingsPanel = {}

local ROW_HEIGHT = 40
local PREFERENCE_KEYS = { "Music", "SFX", "VFX" }
-- Off by default (players visible) -- unlike Music/SFX/VFX, which default
-- on. Kept as its own row/key instead of folded into PREFERENCE_KEYS since
-- that list assumes "missing == on" everywhere it's read.
local HIDE_OTHER_PLAYERS_KEY = "HideOtherPlayers"

function SettingsPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local setAutoSellDuplicate = remotes:WaitForChild("SetAutoSellDuplicate")
	local autoSellDuplicatesUpdated = remotes:WaitForChild("AutoSellDuplicatesUpdated")
	local setPreference = remotes:WaitForChild("SetPreference")
	local preferencesUpdated = remotes:WaitForChild("PreferencesUpdated")

	local currentState: { [string]: boolean } = {}
	local currentPreferences: { [string]: boolean } = {}
	local isExpanded = false

	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 340, 0, 300), UDim2.new(0.5, -170, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	local titleLabel = Theme.Label(panel, UDim2.new(1, -120, 0, 32), "Settings", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	local closeButton = Theme.Button(panel, UDim2.new(0, 90, 0, 32), UDim2.new(1, -100, 0, 10), "Close")
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	local content = Instance.new("ScrollingFrame")
	content.Size = UDim2.new(1, -32, 1, -66)
	content.Position = UDim2.new(0, 16, 0, 56)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 6
	content.ScrollBarImageColor3 = Theme.Colors.Accent
	content.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = content

	-- ===== Auto Sell Duplicates header (click to expand/collapse) =====
	local autoSellHeader = Instance.new("Frame")
	autoSellHeader.LayoutOrder = 1
	autoSellHeader.Size = UDim2.new(1, 0, 0, 32)
	autoSellHeader.BackgroundColor3 = Color3.fromRGB(16, 16, 18)
	autoSellHeader.BorderSizePixel = 0
	autoSellHeader.Parent = content
	Theme.Round(autoSellHeader, UDim.new(0, 8))
	Theme.Stroke(autoSellHeader, Color3.fromRGB(90, 90, 98), 1)

	-- Triangle glyph -- overrides Theme.Fonts.Header (LuckiestGuy has no
	-- geometric-shape glyphs) with a plain font just for this one icon.
	local arrowLabel = Instance.new("TextLabel")
	arrowLabel.Size = UDim2.new(0, 28, 0, 28)
	arrowLabel.AnchorPoint = Vector2.new(0, 0.5)
	arrowLabel.Position = UDim2.new(0, 10, 0.5, 0)
	arrowLabel.BackgroundTransparency = 1
	arrowLabel.Font = Enum.Font.GothamBold
	arrowLabel.TextScaled = true
	arrowLabel.Text = "\u{25B2}"
	arrowLabel.TextColor3 = Theme.Colors.Accent
	arrowLabel.Parent = autoSellHeader

	local autoSellLabel = Theme.Label(autoSellHeader, UDim2.new(1, -52, 1, 0), "Auto Sell Duplicates", true)
	autoSellLabel.Position = UDim2.new(0, 48, 0, 0)

	local headerButton = Instance.new("TextButton")
	headerButton.Size = UDim2.new(1, 0, 1, 0)
	headerButton.BackgroundTransparency = 1
	headerButton.Text = ""
	headerButton.ZIndex = 2
	headerButton.Parent = autoSellHeader

	-- ===== Per-rarity toggle rows, hidden until expanded =====
	local rarityRows = Instance.new("Frame")
	rarityRows.LayoutOrder = 2
	rarityRows.Size = UDim2.new(1, 0, 0, ROW_HEIGHT * #RarityConfig.Order)
	rarityRows.BackgroundTransparency = 1
	rarityRows.Visible = false
	rarityRows.Parent = content

	local rarityToggleButtons: { [string]: TextButton } = {}

	local function styleToggle(button: TextButton, isOn: boolean)
		button.BackgroundColor3 = isOn and Theme.Colors.Success or Color3.fromRGB(40, 40, 44)
		button.Text = isOn and "ON" or "OFF"
		button.TextColor3 = isOn and Color3.fromRGB(255, 255, 255) or Theme.Colors.TextSecondary
	end

	for index, rarity in RarityConfig.Order do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT - 4)
		row.Position = UDim2.new(0, 0, 0, (index - 1) * ROW_HEIGHT)
		row.BackgroundTransparency = 1
		row.Parent = rarityRows

		local nameLabel = Theme.Label(row, UDim2.new(1, -96, 1, 0), rarity, true)
		nameLabel.TextColor3 = RarityConfig.GetColor(rarity)

		local toggleButton = Theme.Button(row, UDim2.new(0, 80, 0, 30), UDim2.new(1, -80, 0, 3), "OFF")
		styleToggle(toggleButton, false)
		rarityToggleButtons[rarity] = toggleButton

		toggleButton.Activated:Connect(function()
			local newState = not currentState[rarity]
			currentState[rarity] = newState
			styleToggle(toggleButton, newState)
			setAutoSellDuplicate:FireServer(rarity, newState)
		end)
	end

	-- ===== Sound & Effects =====
	local soundSectionLabel = Theme.Label(content, UDim2.new(1, 0, 0, 22), "Sound & Effects", true)
	soundSectionLabel.LayoutOrder = 3

	local preferenceToggleButtons: { [string]: TextButton } = {}

	local function stylePreferenceToggle(button: TextButton, isOn: boolean)
		button.BackgroundColor3 = isOn and Theme.Colors.Success or Color3.fromRGB(40, 40, 44)
		button.Text = isOn and "ON" or "OFF"
		button.TextColor3 = isOn and Color3.fromRGB(255, 255, 255) or Theme.Colors.TextSecondary
	end

	for index, key in PREFERENCE_KEYS do
		local row = Instance.new("Frame")
		row.LayoutOrder = 3 + index
		row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT - 4)
		row.BackgroundTransparency = 1
		row.Parent = content

		local nameLabel = Theme.Label(row, UDim2.new(1, -96, 1, 0), key, true)

		local toggleButton = Theme.Button(row, UDim2.new(0, 80, 0, 30), UDim2.new(1, -80, 0, 3), "ON")
		stylePreferenceToggle(toggleButton, true)
		preferenceToggleButtons[key] = toggleButton

		toggleButton.Activated:Connect(function()
			local newState = not currentPreferences[key]
			currentPreferences[key] = newState
			stylePreferenceToggle(toggleButton, newState)
			setPreference:FireServer(key, newState)
		end)
	end

	-- ===== Performance =====
	local performanceSectionLabel = Theme.Label(content, UDim2.new(1, 0, 0, 22), "Performance", true)
	performanceSectionLabel.LayoutOrder = 4 + #PREFERENCE_KEYS

	local hideOtherPlayersRow = Instance.new("Frame")
	hideOtherPlayersRow.LayoutOrder = 5 + #PREFERENCE_KEYS
	hideOtherPlayersRow.Size = UDim2.new(1, 0, 0, ROW_HEIGHT - 4)
	hideOtherPlayersRow.BackgroundTransparency = 1
	hideOtherPlayersRow.Parent = content

	local hideOtherPlayersLabel = Theme.Label(hideOtherPlayersRow, UDim2.new(1, -96, 1, 0), "Hide Other Players", true)

	local hideOtherPlayersButton = Theme.Button(hideOtherPlayersRow, UDim2.new(0, 80, 0, 30), UDim2.new(1, -80, 0, 3), "OFF")
	stylePreferenceToggle(hideOtherPlayersButton, false)
	preferenceToggleButtons[HIDE_OTHER_PLAYERS_KEY] = hideOtherPlayersButton

	hideOtherPlayersButton.Activated:Connect(function()
		local newState = not currentPreferences[HIDE_OTHER_PLAYERS_KEY]
		currentPreferences[HIDE_OTHER_PLAYERS_KEY] = newState
		stylePreferenceToggle(hideOtherPlayersButton, newState)
		setPreference:FireServer(HIDE_OTHER_PLAYERS_KEY, newState)
	end)

	preferencesUpdated.OnClientEvent:Connect(function(map: { [string]: boolean })
		for _, key in PREFERENCE_KEYS do
			local isOn = map[key] ~= false
			currentPreferences[key] = isOn
			local button = preferenceToggleButtons[key]
			if button then
				stylePreferenceToggle(button, isOn)
			end
		end

		local hideOn = map[HIDE_OTHER_PLAYERS_KEY] == true
		currentPreferences[HIDE_OTHER_PLAYERS_KEY] = hideOn
		stylePreferenceToggle(hideOtherPlayersButton, hideOn)
	end)

	local function setExpanded(expanded: boolean)
		isExpanded = expanded
		rarityRows.Visible = expanded
		arrowLabel.Text = expanded and "\u{25BC}" or "\u{25B2}"
	end

	headerButton.Activated:Connect(function()
		setExpanded(not isExpanded)
	end)

	autoSellDuplicatesUpdated.OnClientEvent:Connect(function(map: { [string]: boolean })
		for _, rarity in RarityConfig.Order do
			local isOn = map[rarity] == true
			currentState[rarity] = isOn
			local button = rarityToggleButtons[rarity]
			if button then
				styleToggle(button, isOn)
			end
		end
	end)

	local handle = {}
	handle.Frame = panel

	function handle.Toggle()
		panel.Visible = not panel.Visible
	end

	return handle
end

return SettingsPanel
