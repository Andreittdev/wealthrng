-- Player-to-player trading -- Assets and Investments only (see
-- TradeManager.luau's header for why rolled items are out of scope). The
-- sidebar "Trade" button opens a player picker (no physical proximity
-- needed); picking someone sends a request that shows as a small popup
-- (Accept/Decline) on their screen. Once accepted, a two-column offer
-- window opens -- your owned Assets/Investments (tap to add/remove) + a
-- cash box on the left, their offer (read-only) on the right. Server is
-- the source of truth for both sides' offers -- this panel just renders
-- whatever the last TradeStateUpdated push said and fires UpdateTradeOffer
-- on every local change, it never assumes an optimistic local state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local InvestmentDatabase = require(ReplicatedStorage.Modules.InvestmentDatabase)
local TradeConfig = require(ReplicatedStorage.Modules.TradeConfig)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local TradePanel = {}

function TradePanel.Create(screenGui: ScreenGui, remotes: Folder)
	local requestTrade = remotes:WaitForChild("RequestTrade")
	local tradeRequestReceived = remotes:WaitForChild("TradeRequestReceived")
	local respondTradeRequest = remotes:WaitForChild("RespondTradeRequest")
	local tradeStateUpdated = remotes:WaitForChild("TradeStateUpdated")
	local updateTradeOffer = remotes:WaitForChild("UpdateTradeOffer")
	local confirmTradeOffer = remotes:WaitForChild("ConfirmTradeOffer")
	local cancelTrade = remotes:WaitForChild("CancelTrade")
	local assetUpdated = remotes:WaitForChild("AssetUpdated")
	local investmentUpdated = remotes:WaitForChild("InvestmentUpdated")
	local statsUpdated = remotes:WaitForChild("StatsUpdated")

	local localPlayer = Players.LocalPlayer
	local myOwnedAssets: { [string]: boolean } = {}
	local myInvestments: { { Uid: number, Id: string, PurchasedAt: number, Quantity: number } } = {}
	local myNetWorth = 0
	local currentState = nil
	local pendingRequestFrom: Player? = nil

	-- ===== Player picker (sidebar "Trade" button) =====
	local pickerPanel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 320, 0, 400), UDim2.new(0.5, -160, 0, 60))
	pickerPanel.Visible = false
	pickerPanel.ZIndex = 10

	local pickerTitle = Theme.Label(pickerPanel, UDim2.new(1, -120, 0, 32), "Trade", true)
	pickerTitle.Position = UDim2.new(0, 16, 0, 10)

	local pickerCloseButton = Theme.Button(pickerPanel, UDim2.new(0, 90, 0, 32), UDim2.new(1, -100, 0, 10), "Close")
	pickerCloseButton.Activated:Connect(function()
		pickerPanel.Visible = false
	end)

	local requirementLabel = Theme.Label(pickerPanel, UDim2.new(1, -32, 0, 36), "")
	requirementLabel.Position = UDim2.new(0, 16, 0, 50)
	requirementLabel.TextColor3 = Theme.Colors.TextSecondary
	requirementLabel.TextWrapped = true

	local pickerList = Instance.new("ScrollingFrame")
	pickerList.Size = UDim2.new(1, -32, 1, -160)
	pickerList.Position = UDim2.new(0, 16, 0, 92)
	pickerList.BackgroundTransparency = 1
	pickerList.BorderSizePixel = 0
	pickerList.CanvasSize = UDim2.new(0, 0, 0, 0)
	pickerList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	pickerList.ScrollBarThickness = 6
	pickerList.ScrollBarImageColor3 = Theme.Colors.Accent
	pickerList.Parent = pickerPanel

	local pickerLayout = Instance.new("UIListLayout")
	pickerLayout.Padding = UDim.new(0, 6)
	pickerLayout.Parent = pickerList

	local function renderPicker()
		local eligible = myNetWorth >= TradeConfig.MinNetWorth
		requirementLabel.Text = eligible and "Pick a player to send a trade request." or string.format("You need %s+ Net Worth to trade.", NumberFormat.FormatCash(TradeConfig.MinNetWorth))
		requirementLabel.TextColor3 = eligible and Theme.Colors.TextSecondary or Theme.Colors.Danger

		for _, child in pickerList:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		for _, player in Players:GetPlayers() do
			if player == localPlayer then
				continue
			end

			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 44)
			row.BackgroundColor3 = Theme.Colors.Surface
			row.BackgroundTransparency = 0
			row.BorderSizePixel = 0
			row.Parent = pickerList
			Theme.Round(row, UDim.new(0, 8))

			local nameLabel = Theme.Label(row, UDim2.new(0.6, 0, 1, 0), player.DisplayName)
			nameLabel.Position = UDim2.new(0, 10, 0, 0)

			local requestButton = Theme.Button(row, UDim2.new(0.36, 0, 0.7, 0), UDim2.new(1, -10, 0.5, 0), "Request", eligible)
			requestButton.AnchorPoint = Vector2.new(1, 0.5)
			if not eligible then
				requestButton.Active = false
				requestButton.AutoButtonColor = false
			end
			requestButton.Activated:Connect(function()
				if eligible then
					requestTrade:FireServer(player)
				end
			end)
		end
	end

	Players.PlayerAdded:Connect(function()
		if pickerPanel.Visible then
			renderPicker()
		end
	end)
	Players.PlayerRemoving:Connect(function()
		if pickerPanel.Visible then
			renderPicker()
		end
	end)

	statsUpdated.OnClientEvent:Connect(function(stats)
		myNetWorth = stats.NetWorth
		if pickerPanel.Visible then
			renderPicker()
		end
	end)

	-- ===== Incoming request popup =====
	local requestPopup = Instance.new("Frame")
	requestPopup.Size = UDim2.new(0, 300, 0, 110)
	requestPopup.Position = UDim2.new(0.5, -150, 0, 16)
	requestPopup.BackgroundColor3 = Theme.Colors.Panel
	requestPopup.BackgroundTransparency = 0
	requestPopup.BorderSizePixel = 0
	requestPopup.ZIndex = 20
	requestPopup.Visible = false
	requestPopup.Parent = screenGui
	Theme.Round(requestPopup)
	Theme.Stroke(requestPopup, Color3.fromRGB(255, 215, 140), 1)
	Theme.Shadow(requestPopup)

	local requestLabel = Theme.Label(requestPopup, UDim2.new(1, -20, 0, 50), "", true)
	requestLabel.Position = UDim2.new(0, 10, 0, 8)
	requestLabel.TextWrapped = true

	local acceptButton = Theme.Button(requestPopup, UDim2.new(0.46, 0, 0, 34), UDim2.new(0, 10, 1, -44), "Accept", true)
	local declineButton = Theme.Button(requestPopup, UDim2.new(0.46, 0, 0, 34), UDim2.new(1, -10, 1, -44), "Decline")
	declineButton.AnchorPoint = Vector2.new(1, 0)
	declineButton.BackgroundColor3 = Theme.Colors.Danger

	acceptButton.Activated:Connect(function()
		if pendingRequestFrom then
			respondTradeRequest:FireServer(pendingRequestFrom, true)
			requestPopup.Visible = false
			pendingRequestFrom = nil
		end
	end)
	declineButton.Activated:Connect(function()
		if pendingRequestFrom then
			respondTradeRequest:FireServer(pendingRequestFrom, false)
			requestPopup.Visible = false
			pendingRequestFrom = nil
		end
	end)

	tradeRequestReceived.OnClientEvent:Connect(function(fromPlayer: Player)
		pendingRequestFrom = fromPlayer
		requestLabel.Text = string.format("%s wants to trade", fromPlayer.DisplayName)
		requestPopup.Visible = true
	end)

	-- ===== Active trade window =====
	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 480, 0, 420), UDim2.new(0.5, -240, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	local titleLabel = Theme.Label(panel, UDim2.new(1, -120, 0, 32), "Trade", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	local cancelButton = Theme.Button(panel, UDim2.new(0, 90, 0, 32), UDim2.new(1, -100, 0, 10), "Cancel")
	cancelButton.BackgroundColor3 = Theme.Colors.Danger
	cancelButton.Activated:Connect(function()
		cancelTrade:FireServer()
	end)

	local myColumnLabel = Theme.Label(panel, UDim2.new(0.5, -24, 0, 20), "Your Offer")
	myColumnLabel.Position = UDim2.new(0, 16, 0, 50)
	myColumnLabel.TextColor3 = Theme.Colors.Accent

	local theirColumnLabel = Theme.Label(panel, UDim2.new(0.5, -24, 0, 20), "")
	theirColumnLabel.Position = UDim2.new(0.5, 8, 0, 50)
	theirColumnLabel.TextColor3 = Theme.Colors.Accent

	local function createList(x: UDim2)
		local list = Instance.new("ScrollingFrame")
		list.Size = UDim2.new(0.5, -24, 0, 220)
		list.Position = x
		list.BackgroundColor3 = Theme.Colors.Surface
		list.BackgroundTransparency = 0
		list.BorderSizePixel = 0
		list.CanvasSize = UDim2.new(0, 0, 0, 0)
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.ScrollBarThickness = 6
		list.ScrollBarImageColor3 = Theme.Colors.Accent
		list.Parent = panel
		Theme.Round(list, UDim.new(0, 8))

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 6)
		padding.PaddingLeft = UDim.new(0, 6)
		padding.PaddingRight = UDim.new(0, 6)
		padding.Parent = list

		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.Parent = list

		return list
	end

	local myList = createList(UDim2.new(0, 16, 0, 74))
	local theirList = createList(UDim2.new(0.5, 8, 0, 74))

	local myCashBox = Instance.new("TextBox")
	myCashBox.Size = UDim2.new(0.5, -24, 0, 32)
	myCashBox.Position = UDim2.new(0, 16, 0, 300)
	myCashBox.BackgroundColor3 = Theme.Colors.Surface
	myCashBox.BorderSizePixel = 0
	myCashBox.Text = "0"
	myCashBox.PlaceholderText = "Cash to offer"
	myCashBox.TextColor3 = Theme.Colors.TextPrimary
	myCashBox.Font = Theme.Fonts.Body
	myCashBox.TextScaled = true
	myCashBox.ClearTextOnFocus = false
	myCashBox.Parent = panel
	Theme.Round(myCashBox, UDim.new(0, 8))

	local theirCashLabel = Theme.Label(panel, UDim2.new(0.5, -24, 0, 32), "Cash: $0")
	theirCashLabel.Position = UDim2.new(0.5, 8, 0, 300)
	theirCashLabel.TextColor3 = Theme.Colors.Success

	local statusLabel = Theme.Label(panel, UDim2.new(1, -32, 0, 20), "")
	statusLabel.Position = UDim2.new(0, 16, 0, 340)
	statusLabel.TextColor3 = Theme.Colors.TextSecondary
	statusLabel.TextXAlignment = Enum.TextXAlignment.Center

	local confirmButton = Theme.Button(panel, UDim2.new(1, -32, 0, 40), UDim2.new(0, 16, 1, -50), "Confirm Trade", true)

	local function sendOffer(assetIds: { string }, investmentUids: { number }, cash: number)
		updateTradeOffer:FireServer({ AssetIds = assetIds, InvestmentUids = investmentUids, Cash = cash })
	end

	local function toggleAssetInOffer(assetId: string)
		if not currentState then
			return
		end
		local ids = table.clone(currentState.MyOffer.AssetIds)
		local index = table.find(ids, assetId)
		if index then
			table.remove(ids, index)
		else
			table.insert(ids, assetId)
		end
		sendOffer(ids, currentState.MyOffer.InvestmentUids, currentState.MyOffer.Cash)
	end

	local function toggleInvestmentInOffer(uid: number)
		if not currentState then
			return
		end
		local uids = table.clone(currentState.MyOffer.InvestmentUids)
		local index = table.find(uids, uid)
		if index then
			table.remove(uids, index)
		else
			table.insert(uids, uid)
		end
		sendOffer(currentState.MyOffer.AssetIds, uids, currentState.MyOffer.Cash)
	end

	myCashBox.FocusLost:Connect(function()
		if not currentState then
			return
		end
		local amount = math.floor(math.max(tonumber(myCashBox.Text) or 0, 0))
		sendOffer(currentState.MyOffer.AssetIds, currentState.MyOffer.InvestmentUids, amount)
	end)

	confirmButton.Activated:Connect(function()
		if currentState and not currentState.MyConfirmed then
			confirmTradeOffer:FireServer()
		end
	end)

	local function clearList(list: ScrollingFrame)
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end

	local function createRow(list: ScrollingFrame, text: string, highlighted: boolean): Frame
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -12, 0, 40)
		row.BackgroundColor3 = highlighted and Theme.Colors.Accent or Theme.Colors.Panel
		row.BackgroundTransparency = 0
		row.BorderSizePixel = 0
		row.Parent = list
		Theme.Round(row, UDim.new(0, 6))

		local label = Theme.Label(row, UDim2.new(1, -12, 1, 0), text)
		label.Position = UDim2.new(0, 8, 0, 0)
		label.TextColor3 = highlighted and Color3.fromRGB(20, 20, 20) or Theme.Colors.TextPrimary

		return row
	end

	local function renderMyList()
		clearList(myList)
		if not currentState then
			return
		end

		for id, owned in myOwnedAssets do
			if owned then
				local asset = AssetDatabase.GetAsset(id)
				if asset then
					local inOffer = table.find(currentState.MyOffer.AssetIds, id) ~= nil
					local row = createRow(myList, string.format("\u{1F3E0} %s (%s)", asset.Name, NumberFormat.FormatCash(asset.Price)), inOffer)
					local button = Instance.new("TextButton")
					button.Size = UDim2.new(1, 0, 1, 0)
					button.BackgroundTransparency = 1
					button.Text = ""
					button.Parent = row
					button.Activated:Connect(function()
						toggleAssetInOffer(id)
					end)
				end
			end
		end

		local now = os.time()
		for _, entry in myInvestments do
			local investment = InvestmentDatabase.GetInvestment(entry.Id)
			if investment then
				local currentValue = InvestmentDatabase.ComputeEntryValue(entry, now)
				local inOffer = table.find(currentState.MyOffer.InvestmentUids, entry.Uid) ~= nil
				local quantityText = (entry.Quantity or 1) > 1 and (" x" .. entry.Quantity) or ""
				local row = createRow(myList, string.format("\u{1F48E} %s%s (%s)", investment.Name, quantityText, NumberFormat.FormatCash(currentValue)), inOffer)
				local button = Instance.new("TextButton")
				button.Size = UDim2.new(1, 0, 1, 0)
				button.BackgroundTransparency = 1
				button.Text = ""
				button.Parent = row
				button.Activated:Connect(function()
					toggleInvestmentInOffer(entry.Uid)
				end)
			end
		end
	end

	local function renderTheirList()
		clearList(theirList)
		if not currentState then
			return
		end

		for _, assetId in currentState.TheirOffer.AssetIds do
			local asset = AssetDatabase.GetAsset(assetId)
			if asset then
				createRow(theirList, string.format("\u{1F3E0} %s (%s)", asset.Name, NumberFormat.FormatCash(asset.Price)), false)
			end
		end

		for _, summary in currentState.TheirOffer.Investments do
			local investment = InvestmentDatabase.GetInvestment(summary.Id)
			if investment then
				local quantityText = (summary.Quantity or 1) > 1 and (" x" .. summary.Quantity) or ""
				createRow(theirList, string.format("\u{1F48E} %s%s (%s)", investment.Name, quantityText, NumberFormat.FormatCash(summary.CurrentValue)), false)
			end
		end
	end

	local function refresh()
		if not currentState then
			panel.Visible = false
			return
		end

		panel.Visible = true
		theirColumnLabel.Text = currentState.Partner.DisplayName .. "'s Offer"
		theirCashLabel.Text = "Cash: " .. NumberFormat.FormatCash(currentState.TheirOffer.Cash)

		if not myCashBox:IsFocused() then
			myCashBox.Text = tostring(currentState.MyOffer.Cash)
		end

		renderMyList()
		renderTheirList()

		local myStatus = currentState.MyConfirmed and "You: Confirmed" or "You: Not confirmed"
		local theirStatus = (currentState.TheirConfirmed and "Confirmed" or "Not confirmed")
		statusLabel.Text = string.format("%s  |  %s: %s", myStatus, currentState.Partner.DisplayName, theirStatus)

		confirmButton.Text = currentState.MyConfirmed and "Waiting for confirmation..." or "Confirm Trade"
	end

	tradeStateUpdated.OnClientEvent:Connect(function(state)
		if state.Active then
			pickerPanel.Visible = false
			currentState = state
			refresh()
		else
			currentState = nil
			panel.Visible = false
		end
	end)

	assetUpdated.OnClientEvent:Connect(function(payload: { Owned: { [string]: boolean }, Equipped: { string } })
		myOwnedAssets = payload.Owned
		if currentState then
			renderMyList()
		end
	end)

	investmentUpdated.OnClientEvent:Connect(function(investments: { { Uid: number, Id: string, PurchasedAt: number, Quantity: number } })
		myInvestments = investments
		if currentState then
			renderMyList()
		end
	end)

	local handle = {}
	handle.Frame = pickerPanel
	-- Exposed separately (not the main sidebar-toggled Frame) so MainUI's
	-- "any modal open" coordinator also hides the Roll HUD while an active
	-- trade window is up, not just while the player picker is.
	handle.TradeWindowFrame = panel

	function handle.Toggle()
		pickerPanel.Visible = not pickerPanel.Visible
		if pickerPanel.Visible then
			renderPicker()
		end
	end

	return handle
end

return TradePanel
