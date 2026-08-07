-- Player-to-player trading -- Assets and rolled Items, NOT Investments
-- (see TradeManager.luau's header for why). The sidebar "Trade" button
-- opens a player picker (no physical proximity needed); picking someone
-- sends a request that shows as a small popup (Accept/Decline) on their
-- screen. Once accepted, a two-column offer window opens: your offer
-- starts completely EMPTY except for a "+" tile -- tapping it opens a
-- browse modal (Roll Items / Estates tabs) over your full inventory,
-- tapping an item there asks Confirm/Cancel before it actually joins your
-- offer (so a misclick can't put something valuable up for trade by
-- accident). Once something's in your offer, tapping its card again
-- removes it instantly (no confirmation needed to undo). Server is the
-- source of truth for both sides' offers -- this panel just renders
-- whatever the last TradeStateUpdated push said and fires UpdateTradeOffer
-- on every local change, it never assumes an optimistic local state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
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
	local inventoryUpdated = remotes:WaitForChild("InventoryUpdated")
	local statsUpdated = remotes:WaitForChild("StatsUpdated")

	local localPlayer = Players.LocalPlayer
	local myOwnedAssets: { [string]: boolean } = {}
	local myInventory: { { Uid: number, ItemId: string } } = {}
	local myNetWorth = 0
	local currentState = nil
	local pendingRequestFrom: Player? = nil
	-- Forward-declared -- sendOffer/confirm/decline (defined below, before
	-- this gets assigned a real function) need to call it directly in
	-- TESTING_FORCE_VISIBLE mode, since there's no real server session to
	-- echo a TradeStateUpdated back and trigger it that way.
	local refresh: (() -> ())? = nil

	-- TESTING ONLY -- see the bottom of this function for where the fake
	-- session is actually created. Declared up here so sendOffer/confirm/
	-- decline (defined before that point) can already check it.
	local TESTING_FORCE_VISIBLE = false

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
	requestPopup.AnchorPoint = Vector2.new(0.5, 0)
	requestPopup.Position = UDim2.new(0.5, 0, 0, 16)
	requestPopup.BackgroundColor3 = Theme.Colors.Panel
	requestPopup.BackgroundTransparency = 0
	requestPopup.BorderSizePixel = 0
	requestPopup.ZIndex = 20
	requestPopup.Visible = false
	requestPopup.Parent = screenGui
	Theme.Round(requestPopup)
	Theme.Stroke(requestPopup, Color3.fromRGB(255, 215, 140), 1)
	local requestPopupShadow = Theme.Shadow(requestPopup)
	Theme.AutoScale(screenGui, requestPopup, 300)
	Theme.AutoScale(screenGui, requestPopupShadow, 300)

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
	local panel = Theme.ResponsivePanel(screenGui, UDim2.new(0, 560, 0, 420), UDim2.new(0.5, -280, 0, 60))
	panel.Visible = false
	panel.ZIndex = 10

	local titleLabel = Theme.Label(panel, UDim2.new(1, -20, 0, 32), "Trade", true)
	titleLabel.Position = UDim2.new(0, 16, 0, 10)

	-- Everything below the title lives inside a scrolling column instead of
	-- being fixed-pixel-positioned directly on `panel`. Theme.ResponsivePanel
	-- shrinks `panel` via Scale on short/narrow phone screens WITHOUT
	-- applying a UIScale to its children (unlike Theme.AutoScale, used below
	-- for the detached popups) -- on a short enough screen `panel`'s real
	-- height can end up smaller than this content needs even at its normal
	-- (non-shrunk) size, so proportional positioning alone can't fit it. The
	-- fix is the same one already used for this exact class of bug elsewhere
	-- in this codebase (ProfilePanel/ShopPanel): let the content scroll
	-- instead of trying to cram/overlap into whatever height is left.
	local content = Instance.new("ScrollingFrame")
	content.Size = UDim2.new(1, -32, 1, -54)
	content.Position = UDim2.new(0, 16, 0, 48)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollBarThickness = 6
	content.ScrollBarImageColor3 = Theme.Colors.Accent
	content.Parent = panel

	local contentLayout = Instance.new("UIListLayout")
	contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
	contentLayout.Padding = UDim.new(0, 10)
	contentLayout.Parent = content

	local columnLabelsRow = Instance.new("Frame")
	columnLabelsRow.Size = UDim2.new(1, 0, 0, 20)
	columnLabelsRow.BackgroundTransparency = 1
	columnLabelsRow.LayoutOrder = 1
	columnLabelsRow.Parent = content

	local myColumnLabel = Theme.Label(columnLabelsRow, UDim2.new(0.5, -4, 1, 0), "Your Offer")
	myColumnLabel.Position = UDim2.new(0, 0, 0, 0)
	myColumnLabel.TextColor3 = Theme.Colors.Accent

	local theirColumnLabel = Theme.Label(columnLabelsRow, UDim2.new(0.5, -4, 1, 0), "")
	theirColumnLabel.Position = UDim2.new(0.5, 4, 0, 0)
	theirColumnLabel.TextColor3 = Theme.Colors.Accent

	-- Grid of square-ish cards (image on top, name below), not a list of
	-- full-width rows -- fits more items visibly at once now that each one
	-- needs room for a real image instead of just a line of text.
	local CARD_SIZE = UDim2.new(0, 92, 0, 108)
	local LIST_HEIGHT = 220

	local listsRow = Instance.new("Frame")
	listsRow.Size = UDim2.new(1, 0, 0, LIST_HEIGHT)
	listsRow.BackgroundTransparency = 1
	listsRow.LayoutOrder = 2
	listsRow.Parent = content

	local function createList(x: UDim2)
		local list = Instance.new("ScrollingFrame")
		list.Size = UDim2.new(0.5, -4, 1, 0)
		list.Position = x
		list.BackgroundColor3 = Theme.Colors.Surface
		list.BackgroundTransparency = 0
		list.BorderSizePixel = 0
		list.CanvasSize = UDim2.new(0, 0, 0, 0)
		list.AutomaticCanvasSize = Enum.AutomaticSize.Y
		list.ScrollBarThickness = 6
		list.ScrollBarImageColor3 = Theme.Colors.Accent
		list.Parent = listsRow
		Theme.Round(list, UDim.new(0, 8))

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 6)
		padding.PaddingLeft = UDim.new(0, 6)
		padding.PaddingRight = UDim.new(0, 6)
		padding.Parent = list

		local layout = Instance.new("UIGridLayout")
		layout.CellSize = CARD_SIZE
		layout.CellPadding = UDim2.new(0, 6, 0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = list

		return list
	end

	local myList = createList(UDim2.new(0, 0, 0, 0))
	local theirList = createList(UDim2.new(0.5, 4, 0, 0))

	-- Persistent checkmark over Your Offer -- shown the moment you press
	-- Confirm, and stays up (not a fading animation) for as long as the
	-- server still considers you confirmed, i.e. until you press Decline
	-- or you/the other side changes the offer (which un-confirms both
	-- sides server-side).
	local myConfirmedBadge = Instance.new("Frame")
	myConfirmedBadge.Size = myList.Size
	myConfirmedBadge.Position = myList.Position
	myConfirmedBadge.BackgroundColor3 = Color3.new(0, 0, 0)
	myConfirmedBadge.BackgroundTransparency = 0.45
	myConfirmedBadge.BorderSizePixel = 0
	myConfirmedBadge.Visible = false
	myConfirmedBadge.ZIndex = 12
	myConfirmedBadge.Parent = listsRow
	Theme.Round(myConfirmedBadge, UDim.new(0, 8))

	local myConfirmedCheckmark = Instance.new("TextLabel")
	myConfirmedCheckmark.Size = UDim2.new(0, 90, 0, 90)
	myConfirmedCheckmark.AnchorPoint = Vector2.new(0.5, 0.5)
	myConfirmedCheckmark.Position = UDim2.new(0.5, 0, 0.5, 0)
	myConfirmedCheckmark.BackgroundTransparency = 1
	myConfirmedCheckmark.Font = Theme.Fonts.Header
	myConfirmedCheckmark.Text = "\u{2714}"
	myConfirmedCheckmark.TextScaled = true
	myConfirmedCheckmark.TextColor3 = Theme.Colors.Success
	myConfirmedCheckmark.TextStrokeTransparency = 0
	myConfirmedCheckmark.ZIndex = 13
	myConfirmedCheckmark.Parent = myConfirmedBadge

	-- Same badge, mirrored over Their Offer -- shows up the moment the
	-- OTHER player confirms, driven by currentState.TheirConfirmed.
	local theirConfirmedBadge = Instance.new("Frame")
	theirConfirmedBadge.Size = theirList.Size
	theirConfirmedBadge.Position = theirList.Position
	theirConfirmedBadge.BackgroundColor3 = Color3.new(0, 0, 0)
	theirConfirmedBadge.BackgroundTransparency = 0.45
	theirConfirmedBadge.BorderSizePixel = 0
	theirConfirmedBadge.Visible = false
	theirConfirmedBadge.ZIndex = 12
	theirConfirmedBadge.Parent = listsRow
	Theme.Round(theirConfirmedBadge, UDim.new(0, 8))

	local theirConfirmedCheckmark = Instance.new("TextLabel")
	theirConfirmedCheckmark.Size = UDim2.new(0, 90, 0, 90)
	theirConfirmedCheckmark.AnchorPoint = Vector2.new(0.5, 0.5)
	theirConfirmedCheckmark.Position = UDim2.new(0.5, 0, 0.5, 0)
	theirConfirmedCheckmark.BackgroundTransparency = 1
	theirConfirmedCheckmark.Font = Theme.Fonts.Header
	theirConfirmedCheckmark.Text = "\u{2714}"
	theirConfirmedCheckmark.TextScaled = true
	theirConfirmedCheckmark.TextColor3 = Theme.Colors.Success
	theirConfirmedCheckmark.TextStrokeTransparency = 0
	theirConfirmedCheckmark.ZIndex = 13
	theirConfirmedCheckmark.Parent = theirConfirmedBadge

	local cashRow = Instance.new("Frame")
	cashRow.Size = UDim2.new(1, 0, 0, 32)
	cashRow.BackgroundTransparency = 1
	cashRow.LayoutOrder = 3
	cashRow.Parent = content

	-- One cash box under EACH column, matching styling (same size/shape,
	-- Surface background, no green floating text) -- yours (left) is
	-- editable, theirs (right) is a read-only display of the same shape,
	-- not a differently-styled label.
	local myCashBox = Instance.new("TextBox")
	myCashBox.Size = UDim2.new(0.5, -4, 1, 0)
	myCashBox.Position = UDim2.new(0, 0, 0, 0)
	myCashBox.BackgroundColor3 = Theme.Colors.Surface
	myCashBox.BorderSizePixel = 0
	myCashBox.Text = "0"
	myCashBox.PlaceholderText = "Cash to offer"
	myCashBox.TextColor3 = Theme.Colors.TextPrimary
	myCashBox.Font = Theme.Fonts.Body
	myCashBox.TextScaled = true
	myCashBox.ClearTextOnFocus = false
	myCashBox.Parent = cashRow
	Theme.Round(myCashBox, UDim.new(0, 8))

	local theirCashBox = Instance.new("Frame")
	theirCashBox.Size = UDim2.new(0.5, -4, 1, 0)
	theirCashBox.Position = UDim2.new(0.5, 4, 0, 0)
	theirCashBox.BackgroundColor3 = Theme.Colors.Surface
	theirCashBox.BorderSizePixel = 0
	theirCashBox.Parent = cashRow
	Theme.Round(theirCashBox, UDim.new(0, 8))

	local theirCashLabel = Instance.new("TextLabel")
	theirCashLabel.Size = UDim2.new(1, -12, 1, 0)
	theirCashLabel.Position = UDim2.new(0, 6, 0, 0)
	theirCashLabel.BackgroundTransparency = 1
	theirCashLabel.Font = Theme.Fonts.Body
	theirCashLabel.TextScaled = true
	theirCashLabel.Text = "0"
	theirCashLabel.TextColor3 = Theme.Colors.TextPrimary
	theirCashLabel.Parent = theirCashBox

	local buttonsRow = Instance.new("Frame")
	buttonsRow.Size = UDim2.new(1, 0, 0, 40)
	buttonsRow.BackgroundTransparency = 1
	buttonsRow.LayoutOrder = 4
	buttonsRow.Parent = content

	local confirmButton = Theme.Button(buttonsRow, UDim2.new(0.5, -4, 1, 0), UDim2.new(0, 0, 0, 0), "Confirm", true)
	local declineButton = Theme.Button(buttonsRow, UDim2.new(0.5, -4, 1, 0), UDim2.new(0.5, 4, 0, 0), "Decline")
	declineButton.BackgroundColor3 = Theme.Colors.Danger
	declineButton.Activated:Connect(function()
		cancelTrade:FireServer()
		-- TESTING ONLY -- a real Decline ends the whole trade (server
		-- fires TradeStateUpdated{Active=false}), but there's no real
		-- session to do that here -- just drop the local confirmation
		-- instead, so the badge can be tested going away too.
		if TESTING_FORCE_VISIBLE and currentState then
			currentState.MyConfirmed = false
			if refresh then
				refresh()
			end
		end
	end)

	local function sendOffer(assetIds: { string }, itemUids: { number }, cash: number)
		updateTradeOffer:FireServer({ AssetIds = assetIds, ItemUids = itemUids, Cash = cash })
		-- TESTING ONLY -- there's no real server session behind the fake
		-- trade, so it would never echo back a TradeStateUpdated on its
		-- own; mutate the local fake state directly so the UI actually
		-- reacts to adding/removing things while testing solo.
		if TESTING_FORCE_VISIBLE and currentState then
			currentState.MyOffer = { AssetIds = assetIds, ItemUids = itemUids, Cash = cash }
			-- Changing the offer un-confirms BOTH sides, not just the one
			-- who changed it -- matches TradeManager.luau's real behavior.
			currentState.MyConfirmed = false
			currentState.TheirConfirmed = false
			if refresh then
				refresh()
			end
		end
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
		sendOffer(ids, currentState.MyOffer.ItemUids, currentState.MyOffer.Cash)
	end

	local function toggleItemInOffer(uid: number)
		if not currentState then
			return
		end
		local uids = table.clone(currentState.MyOffer.ItemUids)
		local index = table.find(uids, uid)
		if index then
			table.remove(uids, index)
		else
			table.insert(uids, uid)
		end
		sendOffer(currentState.MyOffer.AssetIds, uids, currentState.MyOffer.Cash)
	end

	-- ===== "Add to offer?" confirm popup -- tapping an item in the browse
	-- modal asks first instead of adding it instantly, so a misclick can't
	-- put something valuable up for trade by accident. Removing an
	-- already-offered item (tap its card in Your Offer) stays instant --
	-- undoing a mistake shouldn't need its own confirmation. =====
	local addConfirmPopup = Instance.new("Frame")
	addConfirmPopup.Size = UDim2.new(0, 260, 0, 150)
	addConfirmPopup.AnchorPoint = Vector2.new(0.5, 0.5)
	addConfirmPopup.Position = UDim2.new(0.5, 0, 0.5, 0)
	addConfirmPopup.BackgroundColor3 = Theme.Colors.Panel
	addConfirmPopup.BorderSizePixel = 0
	addConfirmPopup.ZIndex = 30
	addConfirmPopup.Visible = false
	addConfirmPopup.Parent = screenGui
	Theme.Round(addConfirmPopup)
	Theme.Stroke(addConfirmPopup, Theme.Colors.Accent, 2)
	Theme.AutoScale(screenGui, addConfirmPopup, 260)

	local addConfirmIcon = Instance.new("ImageLabel")
	addConfirmIcon.Size = UDim2.new(0, 56, 0, 56)
	addConfirmIcon.AnchorPoint = Vector2.new(0.5, 0)
	addConfirmIcon.Position = UDim2.new(0.5, 0, 0, 14)
	addConfirmIcon.BackgroundTransparency = 1
	addConfirmIcon.ScaleType = Enum.ScaleType.Fit
	addConfirmIcon.ZIndex = 31
	addConfirmIcon.Parent = addConfirmPopup

	local addConfirmLabel = Theme.Label(addConfirmPopup, UDim2.new(1, -16, 0, 24), "", true)
	addConfirmLabel.Position = UDim2.new(0, 8, 0, 76)
	addConfirmLabel.TextXAlignment = Enum.TextXAlignment.Center
	addConfirmLabel.TextWrapped = true
	addConfirmLabel.ZIndex = 31

	local addConfirmYesButton = Theme.Button(addConfirmPopup, UDim2.new(0.46, 0, 0, 34), UDim2.new(0, 10, 1, -44), "Confirm", true)
	addConfirmYesButton.ZIndex = 31
	local addConfirmNoButton = Theme.Button(addConfirmPopup, UDim2.new(0.46, 0, 0, 34), UDim2.new(1, -10, 1, -44), "Cancel")
	addConfirmNoButton.AnchorPoint = Vector2.new(1, 0)
	addConfirmNoButton.BackgroundColor3 = Theme.Colors.Danger
	addConfirmNoButton.ZIndex = 31

	local pendingAddAction: (() -> ())? = nil

	local function requestAddConfirmation(imageId: string, name: string, action: () -> ())
		addConfirmIcon.Image = imageId
		addConfirmLabel.Text = "Add " .. name .. "?"
		pendingAddAction = action
		addConfirmPopup.Visible = true
	end

	addConfirmYesButton.Activated:Connect(function()
		if pendingAddAction then
			pendingAddAction()
		end
		pendingAddAction = nil
		addConfirmPopup.Visible = false
	end)
	addConfirmNoButton.Activated:Connect(function()
		pendingAddAction = nil
		addConfirmPopup.Visible = false
	end)

	myCashBox.FocusLost:Connect(function()
		if not currentState then
			return
		end
		local amount = math.floor(math.max(tonumber(myCashBox.Text) or 0, 0))
		sendOffer(currentState.MyOffer.AssetIds, currentState.MyOffer.ItemUids, amount)
	end)

	-- Toggle button, not one-way -- pressing it again while already
	-- confirmed (its own label swaps to "Cancel") un-confirms just this
	-- player, same idea as the server's toggle (TradeManager.luau).
	confirmButton.Activated:Connect(function()
		if currentState then
			confirmTradeOffer:FireServer()
			-- TESTING ONLY -- see sendOffer's comment above, same reasoning.
			if TESTING_FORCE_VISIBLE then
				currentState.MyConfirmed = not currentState.MyConfirmed
				if refresh then
					refresh()
				end
			end
		end
	end)

	local function clearList(list: ScrollingFrame)
		for _, child in list:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
	end

	-- Vertical card: big image on top, small name below it -- no price/
	-- value text at all, per explicit request.
	local CARD_IMAGE_SIZE = 72

	local function createCard(list: ScrollingFrame, imageId: string, name: string, highlighted: boolean): Frame
		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, 0, 1, 0)
		card.BackgroundColor3 = highlighted and Theme.Colors.Accent or Theme.Colors.Panel
		card.BackgroundTransparency = 0
		card.BorderSizePixel = 0
		card.Parent = list
		Theme.Round(card, UDim.new(0, 8))

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(0, CARD_IMAGE_SIZE, 0, CARD_IMAGE_SIZE)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 6)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = imageId
		icon.Parent = card
		Theme.Round(icon, UDim.new(0, 6))

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -6, 0, 26)
		nameLabel.Position = UDim2.new(0, 3, 0, CARD_IMAGE_SIZE + 8)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Theme.Fonts.Body
		nameLabel.TextScaled = true
		nameLabel.TextWrapped = true
		nameLabel.Text = name
		nameLabel.TextColor3 = highlighted and Color3.fromRGB(20, 20, 20) or Theme.Colors.TextPrimary
		local nameSizeConstraint = Instance.new("UITextSizeConstraint")
		nameSizeConstraint.MaxTextSize = 13
		nameSizeConstraint.Parent = nameLabel
		nameLabel.Parent = card

		return card
	end

	-- Same card shell as createCard, just a "+" instead of an image/name --
	-- always the LAST tile in Your Offer (see the huge LayoutOrder below),
	-- so newly-added items appear before it and it keeps sliding down/
	-- right as the offer grows, instead of items having to squeeze in
	-- after a fixed leading "+". Tapping it opens the browse modal below.
	local function createAddTile(list: ScrollingFrame): Frame
		local tile = Instance.new("Frame")
		tile.Size = UDim2.new(1, 0, 1, 0)
		tile.BackgroundColor3 = Theme.Colors.Surface
		tile.BorderSizePixel = 0
		tile.LayoutOrder = 9999
		tile.Parent = list
		Theme.Round(tile, UDim.new(0, 8))
		Theme.Stroke(tile, Theme.Colors.Accent, 2)

		local plusLabel = Instance.new("TextLabel")
		plusLabel.Size = UDim2.new(1, 0, 1, 0)
		plusLabel.BackgroundTransparency = 1
		plusLabel.Font = Theme.Fonts.Header
		plusLabel.TextScaled = true
		plusLabel.Text = "+"
		plusLabel.TextColor3 = Theme.Colors.Accent
		plusLabel.Parent = tile

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(1, 0, 1, 0)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.Parent = tile

		return tile, button
	end

	-- ===== Browse modal (the "+" tile opens this) -- Roll Items / Estates
	-- tabs over your FULL inventory, minus whatever's already in the
	-- offer. Tapping a card here asks the Confirm/Cancel popup above
	-- before actually adding it. =====
	local addItemModal = Instance.new("Frame")
	addItemModal.Size = UDim2.new(0, 340, 0, 400)
	addItemModal.AnchorPoint = Vector2.new(0.5, 0.5)
	addItemModal.Position = UDim2.new(0.5, 0, 0.5, 0)
	addItemModal.BackgroundColor3 = Theme.Colors.Panel
	addItemModal.BorderSizePixel = 0
	addItemModal.ZIndex = 25
	addItemModal.Visible = false
	addItemModal.Parent = screenGui
	Theme.Round(addItemModal)
	Theme.Stroke(addItemModal, Theme.Colors.Accent, 2)
	Theme.AutoScale(screenGui, addItemModal, 340)

	local addItemTitle = Theme.Label(addItemModal, UDim2.new(1, -84, 0, 28), "Add to Offer", true)
	addItemTitle.Position = UDim2.new(0, 10, 0, 8)
	addItemTitle.ZIndex = 26

	local addItemCloseButton = Theme.Button(addItemModal, UDim2.new(0, 70, 0, 28), UDim2.new(1, -78, 0, 8), "Close")
	addItemCloseButton.ZIndex = 26
	addItemCloseButton.Activated:Connect(function()
		addItemModal.Visible = false
	end)

	local itemsTabButton = Theme.Button(addItemModal, UDim2.new(0.5, -16, 0, 30), UDim2.new(0, 8, 0, 42), "Roll Items")
	itemsTabButton.ZIndex = 26
	local estatesTabButton = Theme.Button(addItemModal, UDim2.new(0.5, -16, 0, 30), UDim2.new(0.5, 4, 0, 42), "Estates")
	estatesTabButton.ZIndex = 26

	local addItemGrid = Instance.new("ScrollingFrame")
	addItemGrid.Size = UDim2.new(1, -16, 1, -128)
	addItemGrid.Position = UDim2.new(0, 8, 0, 80)
	addItemGrid.BackgroundColor3 = Theme.Colors.Surface
	addItemGrid.BorderSizePixel = 0
	addItemGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
	addItemGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	addItemGrid.ScrollBarThickness = 6
	addItemGrid.ScrollBarImageColor3 = Theme.Colors.Accent
	addItemGrid.ZIndex = 26
	addItemGrid.Parent = addItemModal
	Theme.Round(addItemGrid, UDim.new(0, 8))

	local addItemPadding = Instance.new("UIPadding")
	addItemPadding.PaddingTop = UDim.new(0, 6)
	addItemPadding.PaddingLeft = UDim.new(0, 6)
	addItemPadding.PaddingRight = UDim.new(0, 6)
	addItemPadding.Parent = addItemGrid

	local addItemGridLayout = Instance.new("UIGridLayout")
	addItemGridLayout.CellSize = CARD_SIZE
	addItemGridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
	addItemGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	addItemGridLayout.Parent = addItemGrid

	local addItemCategory = "Items"

	local function renderAddItemGrid()
		clearList(addItemGrid)
		if not currentState then
			return
		end

		itemsTabButton.BackgroundColor3 = addItemCategory == "Items" and Theme.Colors.Accent or Theme.Colors.Surface
		estatesTabButton.BackgroundColor3 = addItemCategory == "Assets" and Theme.Colors.Accent or Theme.Colors.Surface

		if addItemCategory == "Items" then
			-- Most valuable (rarest) first -- Value already tracks rarity
			-- directly in this economy (Legendary/Ultra/Luxury get a big
			-- multiplier on top), so sorting by it doubles as "most
			-- exclusive first" without needing a separate rarity lookup.
			local sortedEntries = {}
			for _, entry in myInventory do
				if table.find(currentState.MyOffer.ItemUids, entry.Uid) == nil then
					table.insert(sortedEntries, entry)
				end
			end
			table.sort(sortedEntries, function(a, b)
				local itemA = ItemDatabase.GetItem(a.ItemId)
				local itemB = ItemDatabase.GetItem(b.ItemId)
				return (itemA and itemA.Value or 0) > (itemB and itemB.Value or 0)
			end)

			for _, entry in sortedEntries do
				local item = ItemDatabase.GetItem(entry.ItemId)
				if item then
					local card = createCard(addItemGrid, item.Image, item.Name, false)
					card.ZIndex = 26
					local button = Instance.new("TextButton")
					button.Size = UDim2.new(1, 0, 1, 0)
					button.BackgroundTransparency = 1
					button.Text = ""
					button.ZIndex = 26
					button.Parent = card
					button.Activated:Connect(function()
						requestAddConfirmation(item.Image, item.Name, function()
							toggleItemInOffer(entry.Uid)
							renderAddItemGrid()
						end)
					end)
				end
			end
		else
			-- Most expensive Estate first, same reasoning as Items above.
			local sortedAssetIds = {}
			for id, owned in myOwnedAssets do
				if owned and table.find(currentState.MyOffer.AssetIds, id) == nil then
					table.insert(sortedAssetIds, id)
				end
			end
			table.sort(sortedAssetIds, function(a, b)
				local assetA = AssetDatabase.GetAsset(a)
				local assetB = AssetDatabase.GetAsset(b)
				return (assetA and assetA.Price or 0) > (assetB and assetB.Price or 0)
			end)

			for _, id in sortedAssetIds do
				local asset = AssetDatabase.GetAsset(id)
				if asset then
					local card = createCard(addItemGrid, asset.Image, asset.Name, false)
					card.ZIndex = 26
					local button = Instance.new("TextButton")
					button.Size = UDim2.new(1, 0, 1, 0)
					button.BackgroundTransparency = 1
					button.Text = ""
					button.ZIndex = 26
					button.Parent = card
					button.Activated:Connect(function()
						requestAddConfirmation(asset.Image, asset.Name, function()
							toggleAssetInOffer(id)
							renderAddItemGrid()
						end)
					end)
				end
			end
		end
	end

	itemsTabButton.Activated:Connect(function()
		addItemCategory = "Items"
		renderAddItemGrid()
	end)
	estatesTabButton.Activated:Connect(function()
		addItemCategory = "Assets"
		renderAddItemGrid()
	end)

	local function openAddItemModal()
		addItemCategory = "Items"
		renderAddItemGrid()
		addItemModal.Visible = true
	end

	local function renderMyList()
		clearList(myList)
		if not currentState then
			return
		end

		local _, addTileButton = createAddTile(myList)
		addTileButton.Activated:Connect(openAddItemModal)

		for _, assetId in currentState.MyOffer.AssetIds do
			local asset = AssetDatabase.GetAsset(assetId)
			if asset then
				local card = createCard(myList, asset.Image, asset.Name, true)
				local button = Instance.new("TextButton")
				button.Size = UDim2.new(1, 0, 1, 0)
				button.BackgroundTransparency = 1
				button.Text = ""
				button.Parent = card
				button.Activated:Connect(function()
					toggleAssetInOffer(assetId)
				end)
			end
		end

		for _, uid in currentState.MyOffer.ItemUids do
			local itemId: string? = nil
			for _, entry in myInventory do
				if entry.Uid == uid then
					itemId = entry.ItemId
					break
				end
			end
			local item = itemId and ItemDatabase.GetItem(itemId)
			if item then
				local card = createCard(myList, item.Image, item.Name, true)
				local button = Instance.new("TextButton")
				button.Size = UDim2.new(1, 0, 1, 0)
				button.BackgroundTransparency = 1
				button.Text = ""
				button.Parent = card
				button.Activated:Connect(function()
					toggleItemInOffer(uid)
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
				createCard(theirList, asset.Image, asset.Name, false)
			end
		end

		for _, itemId in currentState.TheirOffer.ItemIds do
			local item = ItemDatabase.GetItem(itemId)
			if item then
				createCard(theirList, item.Image, item.Name, false)
			end
		end
	end

	refresh = function()
		if not currentState then
			panel.Visible = false
			return
		end

		panel.Visible = true
		theirColumnLabel.Text = currentState.Partner.DisplayName .. "'s Offer"
		theirCashLabel.Text = NumberFormat.FormatCash(currentState.TheirOffer.Cash)

		if not myCashBox:IsFocused() then
			myCashBox.Text = tostring(currentState.MyOffer.Cash)
		end

		renderMyList()
		renderTheirList()
		if addItemModal.Visible then
			renderAddItemGrid()
		end

		myConfirmedBadge.Visible = currentState.MyConfirmed
		theirConfirmedBadge.Visible = currentState.TheirConfirmed

		-- Same button, same spot -- swaps to "Cancel" (red) once you're
		-- confirmed, so pressing it again is obviously "undo" rather than
		-- looking like a disabled/no-op "Confirm".
		confirmButton.Text = currentState.MyConfirmed and "Cancel" or "Confirm"
		confirmButton.BackgroundColor3 = currentState.MyConfirmed and Theme.Colors.Danger or Theme.Colors.Accent
	end

	tradeStateUpdated.OnClientEvent:Connect(function(state)
		if state.Active then
			pickerPanel.Visible = false
			currentState = state
			refresh()
		else
			currentState = nil
			panel.Visible = false
			addItemModal.Visible = false
		end
	end)

	assetUpdated.OnClientEvent:Connect(function(payload: { Owned: { [string]: boolean }, Equipped: { string } })
		myOwnedAssets = payload.Owned
		if currentState then
			renderMyList()
			if addItemModal.Visible then
				renderAddItemGrid()
			end
		end
	end)

	inventoryUpdated.OnClientEvent:Connect(function(inventory: { { Uid: number, ItemId: string } })
		myInventory = inventory
		if currentState then
			renderMyList()
			if addItemModal.Visible then
				renderAddItemGrid()
			end
		end
	end)

	-- TESTING ONLY -- forces the trade window open with a fake
	-- (self-as-partner) state, using your REAL owned Assets/Items, so the
	-- new empty-offer + "+" tile + browse-modal flow can be checked
	-- without needing a 2nd player to actually trade with. Flip back to
	-- false when done (see the declaration up top too).
	if TESTING_FORCE_VISIBLE then
		currentState = {
			Active = true,
			Partner = localPlayer,
			MyOffer = { AssetIds = {}, ItemUids = {}, Cash = 0 },
			TheirOffer = { AssetIds = {}, ItemIds = {}, Cash = 0 },
			MyConfirmed = false,
			TheirConfirmed = false,
		}
		pickerPanel.Visible = false
		refresh()
	end

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
