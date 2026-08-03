-- Physical Potions shop, triggered by walking up to the "POTIONS" kiosk
-- MapBuilder builds (ProximityPrompt named "PotionShopPrompt" on its Counter
-- part). Temporary Cash-bought boosts -- separate stand from the Assets/
-- Invest kiosk since these are consumable buffs, not net-worth items.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PotionDatabase = require(ReplicatedStorage.Modules.PotionDatabase)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
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

-- Rejected purchases (e.g. not enough cash) never echo anything back, so a
-- click can't wait for server confirmation before re-enabling -- a short
-- time-based cooldown instead, just enough to absorb an accidental
-- double-click without blocking a genuine second attempt a moment later.
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

function PotionShopPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local buyPotion = remotes:WaitForChild("BuyPotion")
	local potionUpdated = remotes:WaitForChild("PotionUpdated")

	local activePotions: { [string]: number } = {}

	-- Anchored near the top (not dead-center) so it doesn't collide with
	-- RollPanel's bottom-anchored reveal window/button on shorter viewports.
	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 380, 0, 360), UDim2.new(0.5, -190, 0, 60))
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

	-- Left-hand icon strip (potion.Image) -- text columns below all shift
	-- right by ICON_COLUMN_WIDTH to make room instead of overlapping it.
	-- "rbxassetid://0" (not yet given a real image) just skips the icon
	-- like every other placeholder-image spot in this codebase.
	local ICON_SIZE = 56
	local ICON_COLUMN_WIDTH = 66

	local function render()
		for id, potion in PotionDatabase.GetAllPotions() do
			local row = Instance.new("Frame")
			-- Taller than before (78 -> 96) -- makes room for the 2 R$
			-- instant-buy button stacked under Buy (see below).
			row.Size = UDim2.new(1, 0, 0, 96)
			row.BackgroundColor3 = Theme.Colors.Surface
			row.BackgroundTransparency = 0
			row.BorderSizePixel = 0
			row.Parent = content
			Theme.Round(row, UDim.new(0, 8))

			local hasImage = potion.Image ~= "" and potion.Image ~= "rbxassetid://0"
			local textLeft = 10
			if hasImage then
				local icon = Instance.new("ImageLabel")
				icon.Size = UDim2.new(0, ICON_SIZE, 0, ICON_SIZE)
				icon.AnchorPoint = Vector2.new(0, 0.5)
				icon.Position = UDim2.new(0, 10, 0.5, 0)
				icon.BackgroundTransparency = 1
				icon.ScaleType = Enum.ScaleType.Fit
				icon.Image = potion.Image
				icon.Parent = row
				textLeft = ICON_COLUMN_WIDTH
			end

			local nameLabel = Theme.Label(row, UDim2.new(0.6, -textLeft + 10, 0, 24), potion.Name)
			nameLabel.Position = UDim2.new(0, textLeft, 0, 6)

			local descLabel = Theme.Label(row, UDim2.new(0.6, -textLeft + 10, 0, 20), describePotion(potion))
			descLabel.Position = UDim2.new(0, textLeft, 0, 30)
			descLabel.TextColor3 = Theme.Colors.Success

			local timeLabel = Theme.Label(row, UDim2.new(0.6, -textLeft + 10, 0, 18), "Not active")
			timeLabel.Position = UDim2.new(0, textLeft, 0, 52)
			timeLabel.TextColor3 = Theme.Colors.TextSecondary
			timeLabels[id] = timeLabel

			-- Price sits centered directly above the Buy/instant-buy button
			-- stack (same width + right edge as those buttons), not inline
			-- with the name.
			local priceLabel = Theme.Label(row, UDim2.new(0, 100, 0, 18), NumberFormat.FormatCash(potion.Price), true)
			priceLabel.AnchorPoint = Vector2.new(1, 0)
			priceLabel.Position = UDim2.new(1, -10, 0, 4)
			priceLabel.TextXAlignment = Enum.TextXAlignment.Center
			priceLabel.TextColor3 = Theme.Colors.Accent

			-- Buy (Cash) on top, a smaller "2 R$" instant-buy button
			-- underneath -- same idea as a Robux "skip the grind" shortcut
			-- sitting right next to the normal price everywhere else in the
			-- shop. Both stacked bottom-right, capped text size so neither
			-- label dominates the row.
			local buyButton = Theme.Button(row, UDim2.new(0, 100, 0, 32), UDim2.new(1, -10, 1, -40), "Buy", true)
			buyButton.AnchorPoint = Vector2.new(1, 1)
			local buyButtonTextSize = Instance.new("UITextSizeConstraint")
			buyButtonTextSize.MaxTextSize = 22
			buyButtonTextSize.Parent = buyButton
			buyButton.Activated:Connect(debounce(function()
				buyPotion:FireServer(id)
			end))

			local instantBuyButton = Theme.Button(row, UDim2.new(0, 100, 0, 26), UDim2.new(1, -10, 1, -8), "2 R$", false)
			instantBuyButton.AnchorPoint = Vector2.new(1, 1)
			instantBuyButton.BackgroundColor3 = Theme.Colors.Success
			local instantBuyButtonTextSize = Instance.new("UITextSizeConstraint")
			instantBuyButtonTextSize.MaxTextSize = 18
			instantBuyButtonTextSize.Parent = instantBuyButton
			instantBuyButton.Activated:Connect(debounce(function()
				if potion.InstantProductId ~= 0 then
					MarketplaceService:PromptProductPurchase(Players.LocalPlayer, potion.InstantProductId)
				end
			end))
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
