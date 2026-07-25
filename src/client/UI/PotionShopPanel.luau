-- Physical Potions shop, triggered by walking up to the "POTIONS" kiosk
-- MapBuilder builds (ProximityPrompt named "PotionShopPrompt" on its Counter
-- part). Temporary Cash-bought boosts -- separate stand from the Assets/
-- Invest kiosk since these are consumable buffs, not net-worth items.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PotionDatabase = require(ReplicatedStorage.Modules.PotionDatabase)
local Theme = require(script.Parent.Theme)

local PotionShopPanel = {}

local function describePotion(potion): string
	if potion.LuckWeightMultiplier then
		return "Boosts luck on every roll"
	elseif potion.CooldownMultiplier then
		return string.format("%d%% shorter roll cooldown", math.floor((1 - potion.CooldownMultiplier) * 100))
	elseif potion.CashBonusPercent then
		return string.format("+%d%% cash from selling & income", potion.CashBonusPercent)
	end
	return ""
end

local function formatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function PotionShopPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local buyPotion = remotes:WaitForChild("BuyPotion")
	local potionUpdated = remotes:WaitForChild("PotionUpdated")

	local activePotions: { [string]: number } = {}

	-- Anchored near the top (not dead-center) so it doesn't collide with
	-- RollPanel's bottom-anchored reveal window/button on shorter viewports.
	local panel = Theme.Panel(screenGui, UDim2.new(0, 380, 0, 360), UDim2.new(0.5, -190, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	local titleLabel = Theme.Label(panel, UDim2.new(1, -120, 0, 32), "Potions", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	local closeButton = Theme.Button(panel, UDim2.new(0, 90, 0, 32), UDim2.new(1, -100, 0, 10), "Close")
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	local content = Instance.new("ScrollingFrame")
	content.Size = UDim2.new(1, -32, 1, -64)
	content.Position = UDim2.new(0, 16, 0, 56)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 6
	content.ScrollBarImageColor3 = Theme.Colors.Accent
	content.Parent = panel

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.Padding = UDim.new(0, 8)
	contentLayout.Parent = content

	-- Rebuilt only once (the catalog is static) -- rows are kept around and
	-- their time labels updated in place every second, rather than
	-- destroying/recreating rows on every PotionUpdated push.
	local timeLabels: { [string]: TextLabel } = {}

	local function updateTimers()
		local now = os.time()
		for id, timeLabel in timeLabels do
			local expiresAt = activePotions[id]
			if expiresAt and expiresAt > now then
				timeLabel.Text = "Active: " .. formatDuration(expiresAt - now)
				timeLabel.TextColor3 = Theme.Colors.Accent
			else
				timeLabel.Text = "Not active"
				timeLabel.TextColor3 = Theme.Colors.TextSecondary
			end
		end
	end

	local function render()
		for id, potion in PotionDatabase.GetAllPotions() do
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 78)
			row.BackgroundColor3 = Theme.Colors.Surface
			row.BackgroundTransparency = 0
			row.BorderSizePixel = 0
			row.Parent = content
			Theme.Round(row, UDim.new(0, 8))

			local nameLabel = Theme.Label(row, UDim2.new(0.6, 0, 0, 24), string.format("%s ($%d)", potion.Name, potion.Price))
			nameLabel.Position = UDim2.new(0, 10, 0, 6)

			local descLabel = Theme.Label(row, UDim2.new(0.6, 0, 0, 20), describePotion(potion))
			descLabel.Position = UDim2.new(0, 10, 0, 30)
			descLabel.TextColor3 = Theme.Colors.Success

			local timeLabel = Theme.Label(row, UDim2.new(0.6, 0, 0, 18), "Not active")
			timeLabel.Position = UDim2.new(0, 10, 0, 52)
			timeLabel.TextColor3 = Theme.Colors.TextSecondary
			timeLabels[id] = timeLabel

			local buyButton = Theme.Button(row, UDim2.new(0.32, 0, 0.6, 0), UDim2.new(1, -10, 0.5, 0), "Buy", true)
			buyButton.AnchorPoint = Vector2.new(1, 0.5)
			buyButton.Activated:Connect(function()
				buyPotion:FireServer(id)
			end)
		end
	end

	render()

	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Visible then
				updateTimers()
			end
		end
	end)

	potionUpdated.OnClientEvent:Connect(function(potions: { [string]: number })
		activePotions = potions
		updateTimers()
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player ~= Players.LocalPlayer or prompt.Name ~= "PotionShopPrompt" then
			return
		end

		panel.Visible = true
		updateTimers()
	end)

	local handle = {}
	handle.Frame = panel
	return handle
end

return PotionShopPanel
