-- Popup shown automatically while standing near the Meshy Stadium 3D model
-- (MapBuilder.luau's StadiumOfferMarker) -- same proximity-only pattern as
-- VIPProximityPanel.luau, no ProximityPrompt. Sells Sol Stadium
-- (AssetDatabase's Top3Estate) from a shared GLOBAL stock pool
-- (StadiumOfferManager.luau) -- the one Estate that can be owned more than
-- once. Both purchase paths are wired: Cash (capped at
-- StadiumOfferConfig.MaxCashPurchases, limited by the shared stock pool)
-- and Robux (StadiumOfferConfig.RobuxProductId, unlimited, handled by
-- CashPackManager.luau's ProcessReceipt).
--
-- Deliberately more "premium gacha shop" styled than a plain Theme.Panel --
-- solid dark gradient backing (not just floating text over the game
-- world), a rotating gold shimmer border around the item card, gradient
-- gold text, and a pill badge for the EXCLUSIVE tag -- this is the one
-- popup in the game meant to look like a special/rare purchase, not a
-- routine menu.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local StadiumOfferConfig = require(ReplicatedStorage.Modules.StadiumOfferConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)
local ProximityWatcher = require(script.Parent.ProximityWatcher)

local StadiumOfferPanel = {}

local PROXIMITY_RADIUS_STUDS = 10
local PANEL_WIDTH = 360
local PANEL_HEIGHT = 480
local GOLD = Color3.fromRGB(255, 205, 90)
local GOLD_DIM = Color3.fromRGB(180, 140, 60)
local PURPLE = Color3.fromRGB(200, 120, 255)

local function gradientText(label: TextLabel, colorA: Color3, colorB: Color3)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colorA),
		ColorSequenceKeypoint.new(1, colorB),
	})
	gradient.Rotation = 90
	gradient.Parent = label
	return gradient
end

local function pillBadge(parent: Instance, size: UDim2, position: UDim2, text: string, bgColor: Color3, textColor: Color3): (Frame, TextLabel)
	local pill = Instance.new("Frame")
	pill.Size = size
	pill.Position = position
	pill.BackgroundColor3 = bgColor
	pill.BorderSizePixel = 0
	pill.Parent = parent
	Theme.Round(pill, UDim.new(1, 0))
	Theme.Stroke(pill, Color3.new(0, 0, 0), 1.5)

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Theme.Fonts.Header
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = textColor
	label.TextStrokeTransparency = 0.5
	label.Parent = pill

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.15, 0)
	padding.PaddingBottom = UDim.new(0.15, 0)
	padding.Parent = label

	return pill, label
end

function StadiumOfferPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local requestStadiumOfferState = remotes:WaitForChild("RequestStadiumOfferState")
	local stadiumOfferStateUpdated = remotes:WaitForChild("StadiumOfferStateUpdated")
	local buyStadiumOffer = remotes:WaitForChild("BuyStadiumOffer")
	local statsUpdated = remotes:WaitForChild("StatsUpdated")

	local asset = AssetDatabase.GetAsset(StadiumOfferConfig.AssetId)
	local cashPrice = StadiumOfferConfig.GetCashPrice()

	-- ===== Outer panel: solid dark gradient backing, not transparent =====
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, PANEL_HEIGHT)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = Color3.fromRGB(22, 16, 28)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 8
	panel.Parent = screenGui
	Theme.Round(panel, UDim.new(0, 22))
	local panelStroke = Theme.Stroke(panel, GOLD, 2.5)
	panelStroke.Transparency = 0.1
	Theme.AutoScale(screenGui, panel, PANEL_WIDTH, 0.5)

	local panelGradient = Instance.new("UIGradient")
	panelGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 26, 46)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 12, 20)),
	})
	panelGradient.Rotation = 90
	panelGradient.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.new(0, 34, 0, 34)
	closeButton.Position = UDim2.new(1, -18, 0, -14)
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.BackgroundColor3 = Theme.Colors.Danger
	closeButton.BorderSizePixel = 0
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.Font = Theme.Fonts.Header
	closeButton.TextScaled = true
	closeButton.ZIndex = 10
	closeButton.Parent = panel
	Theme.Round(closeButton, UDim.new(1, 0))
	Theme.Stroke(closeButton, Color3.fromRGB(255, 255, 255), 1.5)

	local manuallyClosed = false
	closeButton.Activated:Connect(function()
		manuallyClosed = true
		panel.Visible = false
	end)

	-- ===== Header: EXCLUSIVE pill + gold gradient title =====
	pillBadge(panel, UDim2.new(0, 190, 0, 26), UDim2.new(0.5, -95, 0, 16), "\u{2726} FIRST EXCLUSIVE \u{2726}", PURPLE, Color3.new(1, 1, 1))

	-- Was the item name (redundant with the name already shown on the card
	-- below) -- now shows the live stock count instead, updated in
	-- refresh() alongside the bottom stock pill/bar.
	local topStockLabel = Theme.Label(panel, UDim2.new(1, -30, 0, 40), "", true)
	topStockLabel.Position = UDim2.new(0, 15, 0, 50)
	topStockLabel.TextXAlignment = Enum.TextXAlignment.Center
	topStockLabel.TextStrokeTransparency = 0
	topStockLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	gradientText(topStockLabel, GOLD, GOLD_DIM)

	-- ===== Item card: image + a single rotating gold shimmer border
	-- directly on the card itself -- no separate glow/ring frames stacked
	-- behind it (that looked like 3 close concentric rectangles/"everything
	-- overlapping" on a real device).
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, 276, 0, 276)
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 104)
	card.BackgroundColor3 = Color3.fromRGB(30, 22, 36)
	card.BorderSizePixel = 0
	card.ZIndex = 3
	card.Parent = panel
	Theme.Round(card, UDim.new(0, 18))

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Thickness = 3
	cardStroke.Color = GOLD
	cardStroke.Parent = card
	local cardStrokeGradient = Instance.new("UIGradient")
	cardStrokeGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, GOLD),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 240)),
		ColorSequenceKeypoint.new(1, GOLD),
	})
	cardStrokeGradient.Parent = cardStroke
	task.spawn(function()
		while card.Parent do
			cardStrokeGradient.Rotation = (cardStrokeGradient.Rotation + 3) % 360
			task.wait(0.05)
		end
	end)

	if asset and asset.Image and asset.Image ~= "" and asset.Image ~= "rbxassetid://0" then
		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(1, -24, 1, -60)
		icon.Position = UDim2.new(0, 12, 0, 12)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = asset.Image
		icon.ZIndex = 4
		icon.Parent = card
	end

	local cardNameLabel = Theme.Label(card, UDim2.new(1, -20, 0, 34), string.upper(asset and asset.Name or "Sol Stadium"), true)
	cardNameLabel.Position = UDim2.new(0, 10, 1, -42)
	cardNameLabel.TextXAlignment = Enum.TextXAlignment.Center
	cardNameLabel.ZIndex = 4
	gradientText(cardNameLabel, GOLD, GOLD_DIM)

	-- ===== 2 buttons: Robux (left, UI-only for now) / Cash (right, wired) =====
	local buttonsRow = Instance.new("Frame")
	buttonsRow.Size = UDim2.new(1, -30, 0, 56)
	buttonsRow.Position = UDim2.new(0, 15, 0, 396)
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.Parent = panel

	local robuxButton = Instance.new("TextButton")
	robuxButton.Size = UDim2.new(0.5, -6, 1, 0)
	robuxButton.BackgroundColor3 = Color3.fromRGB(60, 170, 90)
	robuxButton.BorderSizePixel = 0
	robuxButton.Font = Theme.Fonts.Header
	robuxButton.TextScaled = true
	robuxButton.Text = "R$ ..."
	robuxButton.TextColor3 = Color3.fromRGB(20, 20, 20)
	robuxButton.Parent = buttonsRow
	Theme.Round(robuxButton, UDim.new(0, 12))
	Theme.Stroke(robuxButton, Color3.fromRGB(190, 240, 200), 1.5)
	local robuxTextSize = Instance.new("UITextSizeConstraint")
	robuxTextSize.MaxTextSize = 26
	robuxTextSize.Parent = robuxButton

	-- Real price fetched async (GetProductInfo, the standard Roblox way to
	-- show an accurate Developer Product price without hardcoding it here
	-- and risking it drifting from whatever's actually configured on the
	-- product) -- button just shows "R$ ..." until it resolves.
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(StadiumOfferConfig.RobuxProductId, Enum.InfoType.Product)
		end)
		if ok and info and info.PriceInRobux then
			robuxButton.Text = string.format("%d R$", info.PriceInRobux)
		else
			robuxButton.Text = "Buy R$"
		end
	end)

	robuxButton.Activated:Connect(function()
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, StadiumOfferConfig.RobuxProductId)
	end)

	local cashButton = Instance.new("TextButton")
	cashButton.Size = UDim2.new(0.5, -6, 1, 0)
	cashButton.Position = UDim2.new(0.5, 6, 0, 0)
	cashButton.BackgroundColor3 = GOLD
	cashButton.BorderSizePixel = 0
	cashButton.Font = Theme.Fonts.Header
	cashButton.TextScaled = true
	cashButton.Text = NumberFormat.FormatCash(cashPrice)
	cashButton.TextColor3 = Color3.fromRGB(30, 20, 10)
	cashButton.Parent = buttonsRow
	Theme.Round(cashButton, UDim.new(0, 12))
	local cashButtonStroke = Theme.Stroke(cashButton, Color3.fromRGB(255, 235, 180), 2)
	cashButtonStroke.Transparency = 0
	local cashTextSize = Instance.new("UITextSizeConstraint")
	cashTextSize.MaxTextSize = 26
	cashTextSize.Parent = cashButton

	local remainingStock = StadiumOfferConfig.TotalStock
	local ownedCount = 0
	local playerCash = 0
	local AFFORDABLE_COLOR = Color3.fromRGB(70, 200, 100)
	local UNAFFORDABLE_COLOR = Color3.fromRGB(220, 70, 70)
	local DISABLED_COLOR = Color3.fromRGB(48, 42, 54)

	cashButton.MouseEnter:Connect(function()
		if cashButton.Active then
			TweenService:Create(cashButton, TweenInfo.new(0.15), { BackgroundColor3 = Theme.Lighten(cashButton.BackgroundColor3, 0.08) }):Play()
		end
	end)
	cashButton.MouseLeave:Connect(function()
		if cashButton.Active then
			local affordable = playerCash >= cashPrice
			TweenService:Create(cashButton, TweenInfo.new(0.15), { BackgroundColor3 = affordable and AFFORDABLE_COLOR or UNAFFORDABLE_COLOR }):Play()
		end
	end)

	local function refresh()
		topStockLabel.Text = string.format("STOCK %d/%d", remainingStock, StadiumOfferConfig.TotalStock)

		local soldOut = remainingStock <= 0
		local atCashCap = ownedCount >= StadiumOfferConfig.MaxCashPurchases
		cashButton.Active = not soldOut and not atCashCap
		cashButton.AutoButtonColor = false

		-- Background itself is the red/green affordability signal now (a
		-- thin border alone against a big gold fill read as "still just
		-- yellow" at a glance) -- gold is reserved for the disabled/gray
		-- states below, not the normal price-shown state anymore.
		if cashButton.Active then
			cashButton.BackgroundColor3 = playerCash >= cashPrice and AFFORDABLE_COLOR or UNAFFORDABLE_COLOR
		else
			cashButton.BackgroundColor3 = DISABLED_COLOR
		end

		-- Text always stays black -- the background itself (above) is the
		-- affordability signal now, not the text or border.
		cashButton.TextColor3 = Color3.fromRGB(20, 15, 10)
		cashButtonStroke.Color = Color3.fromRGB(255, 235, 180)
		if soldOut then
			cashButton.Text = "SOLD OUT"
		elseif atCashCap then
			cashButton.Text = string.format("OWNED %d/%d", ownedCount, StadiumOfferConfig.MaxCashPurchases)
		else
			cashButton.Text = NumberFormat.FormatCash(cashPrice)
		end
	end
	refresh()

	cashButton.Activated:Connect(function()
		if not cashButton.Active then
			return
		end
		buyStadiumOffer:FireServer()
	end)

	stadiumOfferStateUpdated.OnClientEvent:Connect(function(state: { RemainingStock: number, TotalStock: number, OwnedCount: number, MaxCashPurchases: number })
		remainingStock = state.RemainingStock
		ownedCount = state.OwnedCount
		refresh()
	end)

	statsUpdated.OnClientEvent:Connect(function(stats: { Cash: number })
		playerCash = stats.Cash
		refresh()
	end)

	task.spawn(function()
		local marker: BasePart? = nil
		while not marker do
			local mapFolder = Workspace:WaitForChild("Map")
			marker = mapFolder:WaitForChild("StadiumOfferMarker", 5) :: BasePart?
		end

		ProximityWatcher.Register(marker, PROXIMITY_RADIUS_STUDS, function(inRange)
			if inRange and not manuallyClosed then
				if not panel.Visible then
					requestStadiumOfferState:FireServer()
				end
				panel.Visible = true
			elseif not inRange then
				manuallyClosed = false
				panel.Visible = false
			end
		end)
	end)

	local handle = {}
	handle.Frame = panel
	return handle
end

return StadiumOfferPanel
