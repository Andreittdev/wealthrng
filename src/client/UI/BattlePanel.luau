-- LARP Battles: fully self-contained (owns its own ScreenGui + remotes),
-- same pattern as NotificationToast.luau -- Main.client.luau just calls
-- BattlePanel.Init(). A 3-card menu (Casual / Multiplayer / Rewards)
-- appears automatically while standing near the black line marker
-- (MapBuilder's buildBattleMarker) -- plain distance check against that
-- part, same pattern as VIPProximityPanel.luau, no ProximityPrompt/"Press
-- E" involved. "Casual" fights the bot instantly; "Multiplayer" queues for
-- a real 2nd player, showing "1/2 Wait for opponent..." until one joins;
-- "Rewards" is a placeholder card, not wired to anything yet.
--
-- Once BattleResult arrives (either path), this plays a long (~1 minute),
-- premium-feeling reveal:
--   1. Intro -- both players' avatar/name, then their Net Worth counting up,
--      then a "FIGHT!" flash.
--   2. One round per category -- spin through candidate items (like a slot
--      machine), land on the real item BattleManager sent, a "comparing"
--      beat, then highlight the round's winner.
--   3. Outro -- final WON/LOST/DRAW banner + score + points earned.
-- The Close button can skip out at any point (checked between every beat
-- via `reveal.Skip`), so nobody's stuck watching the full minute if they
-- don't want to.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local AssetDatabase = require(ReplicatedStorage.Modules.AssetDatabase)
local InvestmentDatabase = require(ReplicatedStorage.Modules.InvestmentDatabase)
local NumberFormat = require(ReplicatedStorage.Modules.NumberFormat)
local Theme = require(script.Parent.Theme)

local BattlePanel = {}

local PROXIMITY_RADIUS_STUDS = 10

-- ===== Timing -- tuned so intro + 3 rounds + outro lands around ~1 minute
-- total (see this file's header for the phase breakdown). =====
local INTRO_SUSPENSE_PAUSE = 1.2
local NET_WORTH_COUNT_DURATION = 3
local FIGHT_FLASH_HOLD = 1.8
local INTRO_FINAL_PAUSE = 0.8

local CATEGORY_INTRO_PAUSE = 1.6
local SPIN_DURATION = 2.2
local SPIN_INTERVAL = 0.07
local SETTLE_PAUSE = 0.4
local COMPARING_PAUSE = 1.6
local WINNER_GLOW_PAUSE = 1.6
local CATEGORY_HOLD = 2.2
local CATEGORY_TRANSITION_PAUSE = 1.6

local OUTRO_BANNER_PAUSE = 1
local OUTRO_RESULT_PAUSE = 2
local OUTRO_SCORE_PAUSE = 1
local OUTRO_FINAL_HOLD = 2.5

-- One image pool per category, in the same order BattleManager.luau sends
-- Categories -- purely decorative "shuffling through your stuff" spin
-- fodder before landing on the real item the server already decided.
local function buildImagePool(entries: { [string]: { Image: string } }): { string }
	local pool = {}
	for _, entry in entries do
		if entry.Image and entry.Image ~= "" and entry.Image ~= "rbxassetid://0" then
			table.insert(pool, entry.Image)
		end
	end
	return pool
end

local CATEGORY_POOLS = {
	buildImagePool(ItemDatabase.GetAllItems()),
	buildImagePool(AssetDatabase.GetAllAssets()),
	buildImagePool(InvestmentDatabase.GetAllInvestments()),
}

-- Sleeps `duration`, but bails out (returning false) the moment
-- reveal.Skip flips true instead of only checking at the top of the wait --
-- polls in small slices so a Close click during a multi-second pause takes
-- effect almost immediately, not just before/after it.
local function waitOrSkip(duration: number, reveal): boolean
	local remaining = duration
	local STEP = 0.1
	while remaining > 0 do
		if reveal.Skip then
			return false
		end
		task.wait(math.min(STEP, remaining))
		remaining -= STEP
	end
	return not reveal.Skip
end

function BattlePanel.Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local joinBattleQueue = remotes:WaitForChild("JoinBattleQueue")
	local leaveBattleQueue = remotes:WaitForChild("LeaveBattleQueue")
	local battleQueueUpdated = remotes:WaitForChild("BattleQueueUpdated")
	local joinCasualBattle = remotes:WaitForChild("JoinCasualBattle")
	local battleResult = remotes:WaitForChild("BattleResult")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "WealthRNG_Battle"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 15
	screenGui.Parent = playerGui

	local inQueue = false
	-- Hides the zone menu while a reveal is actively playing, even if still
	-- standing in range -- the Heartbeat distance loop otherwise fights any
	-- manual .Visible change every frame (see the loop near the bottom).
	local suppressMenu = false

	-- ===== Zone menu -- Casual / Multiplayer / Rewards =====
	-- Top-anchored, not the usual bottom "-230" band every other proximity
	-- popup uses -- that band is also where NotificationToast's stack
	-- lives (bottom-right), and this menu is wide enough (494px) that on
	-- medium-width screens (~900-1206px) the two could actually overlap.
	-- Top-center is clear of both the bottom HUD and the toast stack.
	local menuFrame = Instance.new("Frame")
	menuFrame.Size = UDim2.new(0, 494, 0, 232)
	menuFrame.AnchorPoint = Vector2.new(0.5, 0)
	menuFrame.Position = UDim2.new(0.5, 0, 0, 100)
	menuFrame.BackgroundTransparency = 1
	menuFrame.Visible = false
	menuFrame.ZIndex = 6
	menuFrame.Parent = screenGui
	Theme.AutoScale(screenGui, menuFrame, 900)

	local menuTitle = Theme.Label(menuFrame, UDim2.new(1, 0, 0, 28), "LARP BATTLES", true)
	menuTitle.TextXAlignment = Enum.TextXAlignment.Center

	-- ===== Queue status banner -- sits directly above the LARP Battles
	-- menu itself, only visible while actually queued for Multiplayer.
	local waitingLabel = Instance.new("TextLabel")
	waitingLabel.AnchorPoint = Vector2.new(0.5, 1)
	waitingLabel.Size = UDim2.new(0, 340, 0, 40)
	waitingLabel.Position = UDim2.new(0.5, 0, 0, 94)
	waitingLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
	waitingLabel.BackgroundTransparency = 0.1
	waitingLabel.Font = Theme.Fonts.Header
	waitingLabel.Text = ""
	waitingLabel.TextColor3 = Theme.Colors.Accent
	waitingLabel.TextScaled = true
	waitingLabel.TextStrokeTransparency = 0
	waitingLabel.Visible = false
	waitingLabel.ZIndex = 7
	waitingLabel.Parent = screenGui
	Theme.Round(waitingLabel, UDim.new(0, 10))
	local waitingStroke = Theme.Stroke(waitingLabel, Theme.Colors.Accent, 1.5)
	waitingStroke.Transparency = 0
	Theme.AutoScale(screenGui, waitingLabel, 900)

	-- Returns the card's TextButton and its subtitle label, so callers can
	-- wire Activated and update the subtitle text (e.g. Multiplayer's
	-- queue status) independently.
	local function createCard(xOffset: number, bgColor: Color3, title: string, subtitle: string): (TextButton, TextLabel)
		local card = Instance.new("TextButton")
		card.Size = UDim2.new(0, 150, 0, 190)
		card.Position = UDim2.new(0, xOffset, 0, 38)
		card.BackgroundColor3 = bgColor
		card.BorderSizePixel = 0
		card.AutoButtonColor = true
		card.Text = ""
		card.Parent = menuFrame
		Theme.Round(card, UDim.new(0, 14))
		local cardStroke = Theme.Stroke(card, Color3.fromRGB(15, 15, 18), 4)
		cardStroke.Transparency = 0

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Size = UDim2.new(1, -12, 0, 32)
		titleLabel.Position = UDim2.new(0, 6, 1, -74)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Theme.Fonts.Header
		titleLabel.Text = title
		titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		titleLabel.TextScaled = true
		titleLabel.TextStrokeTransparency = 0
		titleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		titleLabel.Parent = card

		local subtitleLabel = Instance.new("TextLabel")
		subtitleLabel.Size = UDim2.new(1, -12, 0, 36)
		subtitleLabel.Position = UDim2.new(0, 6, 1, -40)
		subtitleLabel.BackgroundTransparency = 1
		subtitleLabel.Font = Theme.Fonts.Header
		subtitleLabel.Text = subtitle
		subtitleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		subtitleLabel.TextScaled = true
		subtitleLabel.TextWrapped = true
		subtitleLabel.TextStrokeTransparency = 0.3
		subtitleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		subtitleLabel.Parent = card
		local subtitleSizeConstraint = Instance.new("UITextSizeConstraint")
		subtitleSizeConstraint.MaxTextSize = 18
		subtitleSizeConstraint.Parent = subtitleLabel

		return card, subtitleLabel
	end

	local casualCard = createCard(0, Color3.fromRGB(70, 170, 60), "Casual", "Find match!")
	local multiplayerCard, multiplayerSubtitle = createCard(172, Color3.fromRGB(150, 30, 30), "Multiplayer", "Find match!")
	local rewardsCard = createCard(344, Color3.fromRGB(110, 60, 190), "Rewards", "Coming soon!")
	-- Not wired to anything yet -- visual placeholder only, per request.
	rewardsCard.AutoButtonColor = false

	local function setInQueue(newInQueue: boolean, count: number?)
		inQueue = newInQueue
		if inQueue then
			local n = count or 1
			if n >= 2 then
				waitingLabel.Text = "2/2 Match Found!"
				waitingLabel.TextColor3 = Theme.Colors.Success
				waitingStroke.Color = Theme.Colors.Success
			else
				waitingLabel.Text = string.format("%d/2 Waiting for opponent...", n)
				waitingLabel.TextColor3 = Theme.Colors.Accent
				waitingStroke.Color = Theme.Colors.Accent
			end
			waitingLabel.Visible = true
		else
			waitingLabel.Visible = false
		end
	end

	battleQueueUpdated.OnClientEvent:Connect(function(state: { InQueue: boolean, Count: number })
		setInQueue(state.InQueue, state.Count)
	end)

	casualCard.Activated:Connect(function()
		if suppressMenu then
			return
		end
		joinCasualBattle:FireServer()
	end)

	multiplayerCard.Activated:Connect(function()
		if suppressMenu then
			return
		end
		if inQueue then
			leaveBattleQueue:FireServer()
		else
			joinBattleQueue:FireServer()
		end
	end)

	-- ===== Reveal popup =====
	local popup = Instance.new("Frame")
	popup.Size = UDim2.new(0, 400, 0, 540)
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.new(0.5, 0, 0.5, 0)
	popup.BackgroundColor3 = Theme.Colors.Panel
	popup.BorderSizePixel = 0
	popup.Visible = false
	popup.ZIndex = 20
	popup.Parent = screenGui
	Theme.Round(popup)
	local popupStroke = Theme.Stroke(popup, Color3.fromRGB(255, 215, 140), 1.5)
	popupStroke.Transparency = 0
	local popupShadow = Theme.Shadow(popup)
	Theme.AutoScale(screenGui, popup, 400)
	Theme.AutoScale(screenGui, popupShadow, 400)

	local titleLabel = Theme.Label(popup, UDim2.new(1, -24, 0, 26), "LARP BATTLE", true)
	titleLabel.Position = UDim2.new(0, 12, 0, 10)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- ===== Player header: avatar + name + Net Worth, both sides =====
	local function createPlayerHeader(xOffset: number): (ImageLabel, TextLabel, TextLabel)
		local frame = Instance.new("Frame")
		frame.Size = UDim2.new(0, 170, 0, 140)
		frame.Position = UDim2.new(0, xOffset, 0, 40)
		frame.BackgroundTransparency = 1
		frame.Parent = popup

		local avatar = Instance.new("ImageLabel")
		avatar.AnchorPoint = Vector2.new(0.5, 0)
		avatar.Size = UDim2.new(0, 84, 0, 84)
		avatar.Position = UDim2.new(0.5, 0, 0, 0)
		avatar.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
		avatar.ScaleType = Enum.ScaleType.Fit
		avatar.Image = ""
		avatar.Parent = frame
		Theme.Round(avatar, UDim.new(0, 10))
		local avatarStroke = Theme.Stroke(avatar, Theme.Colors.Accent, 1.5)
		avatarStroke.Transparency = 0

		local nameLabel = Theme.Label(frame, UDim2.new(1, 0, 0, 22), "")
		nameLabel.Position = UDim2.new(0, 0, 0, 88)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center

		local netWorthLabel = Theme.Label(frame, UDim2.new(1, 0, 0, 24), "$0", true)
		netWorthLabel.Position = UDim2.new(0, 0, 0, 112)
		netWorthLabel.TextXAlignment = Enum.TextXAlignment.Center
		netWorthLabel.TextColor3 = Theme.Colors.Accent

		return avatar, nameLabel, netWorthLabel
	end

	local leftAvatar, leftPlayerNameLabel, leftNetWorthLabel = createPlayerHeader(15)
	local rightAvatar, rightPlayerNameLabel, rightNetWorthLabel = createPlayerHeader(215)

	local headerVsLabel = Theme.Label(popup, UDim2.new(0, 30, 0, 30), "VS", true)
	headerVsLabel.AnchorPoint = Vector2.new(0.5, 0)
	headerVsLabel.Position = UDim2.new(0.5, 0, 0, 45)
	headerVsLabel.TextXAlignment = Enum.TextXAlignment.Center
	headerVsLabel.TextColor3 = Theme.Colors.TextSecondary

	-- ===== Category headline + round status =====
	local categoryLabel = Theme.Label(popup, UDim2.new(1, -24, 0, 24), "", true)
	categoryLabel.Position = UDim2.new(0, 12, 0, 192)
	categoryLabel.TextXAlignment = Enum.TextXAlignment.Center
	categoryLabel.TextColor3 = Theme.Colors.Accent

	local progressLabel = Theme.Label(popup, UDim2.new(1, -24, 0, 16), "")
	progressLabel.Position = UDim2.new(0, 12, 0, 218)
	progressLabel.TextXAlignment = Enum.TextXAlignment.Center
	progressLabel.TextColor3 = Theme.Colors.TextSecondary

	-- ===== Mine / Opponent item cards =====
	local function createItemSlot(xOffset: number, label: string): (ImageLabel, TextLabel, UIStroke)
		local card = Instance.new("Frame")
		card.Size = UDim2.new(0, 150, 0, 168)
		card.Position = UDim2.new(0, xOffset, 0, 240)
		card.BackgroundColor3 = Theme.Colors.Surface
		card.BorderSizePixel = 0
		card.Parent = popup
		Theme.Round(card, UDim.new(0, 10))
		local cardStroke = Theme.Stroke(card, Theme.Colors.Accent, 2)
		cardStroke.Transparency = 0

		local headerLabel = Theme.Label(card, UDim2.new(1, -8, 0, 16), label)
		headerLabel.Position = UDim2.new(0, 4, 0, 4)
		headerLabel.TextXAlignment = Enum.TextXAlignment.Center
		headerLabel.TextColor3 = Theme.Colors.TextSecondary

		local icon = Instance.new("ImageLabel")
		icon.Size = UDim2.new(0, 110, 0, 110)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 22)
		icon.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
		icon.BackgroundTransparency = 0
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = ""
		icon.Parent = card
		Theme.Round(icon, UDim.new(0, 8))

		local nameLabel = Theme.Label(card, UDim2.new(1, -10, 0, 30), "")
		nameLabel.Position = UDim2.new(0, 5, 1, -32)
		nameLabel.TextXAlignment = Enum.TextXAlignment.Center
		nameLabel.TextWrapped = true
		local nameSizeConstraint = Instance.new("UITextSizeConstraint")
		nameSizeConstraint.MaxTextSize = 16
		nameSizeConstraint.Parent = nameLabel

		return icon, nameLabel, cardStroke
	end

	local leftItemIcon, leftItemNameLabel, leftStroke = createItemSlot(20, "YOU")
	local rightItemIcon, rightItemNameLabel, rightStroke = createItemSlot(230, "OPPONENT")

	local itemsVsLabel = Theme.Label(popup, UDim2.new(0, 40, 0, 30), "VS", true)
	itemsVsLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	itemsVsLabel.Position = UDim2.new(0.5, 0, 0, 322)
	itemsVsLabel.TextXAlignment = Enum.TextXAlignment.Center
	itemsVsLabel.TextColor3 = Theme.Colors.TextSecondary

	local outcomeLabel = Theme.Label(popup, UDim2.new(1, -24, 0, 32), "", true)
	outcomeLabel.Position = UDim2.new(0, 12, 0, 420)
	outcomeLabel.TextXAlignment = Enum.TextXAlignment.Center

	local scoreLabel = Theme.Label(popup, UDim2.new(1, -24, 0, 18), "")
	scoreLabel.Position = UDim2.new(0, 12, 0, 452)
	scoreLabel.TextXAlignment = Enum.TextXAlignment.Center
	scoreLabel.TextColor3 = Theme.Colors.TextSecondary

	-- currentReveal: a fresh table {Skip=false} every time a new result
	-- comes in -- Close sets THIS run's Skip flag, so an in-flight
	-- animation coroutine unwinds promptly instead of continuing to mutate
	-- a hidden popup after the player dismisses it.
	local currentReveal = nil

	local closeButton = Theme.Button(popup, UDim2.new(0, 100, 0, 32), UDim2.new(0.5, -50, 1, -44), "Skip")
	closeButton.Activated:Connect(function()
		if currentReveal then
			currentReveal.Skip = true
		end
		popup.Visible = false
		suppressMenu = false
	end)

	local function spinSlot(icon: ImageLabel, pool: { string }, reveal)
		if #pool == 0 then
			return
		end
		local startTime = os.clock()
		while os.clock() - startTime < SPIN_DURATION do
			if reveal.Skip then
				return
			end
			icon.Image = pool[math.random(1, #pool)]
			task.wait(SPIN_INTERVAL)
		end
	end

	local function settleSlot(icon: ImageLabel, nameLabel: TextLabel, itemInfo: { Name: string, Image: string }?)
		if itemInfo then
			icon.Image = itemInfo.Image
			nameLabel.Text = itemInfo.Name
		else
			icon.Image = ""
			nameLabel.Text = "Nothing owned"
		end
	end

	local function animateNetWorthCountUp(label: TextLabel, targetValue: number)
		local steps = 20
		for i = 1, steps do
			local t = i / steps
			local eased = 1 - (1 - t) * (1 - t)
			label.Text = NumberFormat.FormatCash(math.floor(targetValue * eased))
			task.wait(NET_WORTH_COUNT_DURATION / steps)
		end
		label.Text = NumberFormat.FormatCash(targetValue)
	end

	local function playIntro(result, reveal): boolean
		leftAvatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
		if result.OpponentUserId and result.OpponentUserId > 0 then
			rightAvatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. result.OpponentUserId .. "&w=150&h=150"
		else
			rightAvatar.Image = ""
		end
		leftPlayerNameLabel.Text = player.Name
		rightPlayerNameLabel.Text = result.Opponent
		leftNetWorthLabel.Text = "$0"
		rightNetWorthLabel.Text = "$0"

		categoryLabel.TextColor3 = Theme.Colors.Accent
		categoryLabel.Text = "FINDING OPPONENT..."
		progressLabel.Text = ""
		if not waitOrSkip(INTRO_SUSPENSE_PAUSE, reveal) then
			return false
		end

		categoryLabel.Text = "NET WORTH"
		task.spawn(animateNetWorthCountUp, leftNetWorthLabel, result.MyNetWorth)
		task.spawn(animateNetWorthCountUp, rightNetWorthLabel, result.OpponentNetWorth)
		if not waitOrSkip(NET_WORTH_COUNT_DURATION + 0.2, reveal) then
			return false
		end

		categoryLabel.Text = "FIGHT!"
		categoryLabel.TextColor3 = Theme.Colors.Danger
		if not waitOrSkip(FIGHT_FLASH_HOLD, reveal) then
			return false
		end
		categoryLabel.TextColor3 = Theme.Colors.Accent

		return waitOrSkip(INTRO_FINAL_PAUSE, reveal)
	end

	local function playCategories(result, reveal): boolean
		local categoryCount = #result.Categories
		for i, category in result.Categories do
			categoryLabel.TextColor3 = Theme.Colors.Accent
			categoryLabel.Text = string.upper(category.Name)
			progressLabel.Text = string.format("ROUND %d / %d", i, categoryCount)
			leftStroke.Color = Theme.Colors.Accent
			rightStroke.Color = Theme.Colors.Accent
			leftItemIcon.Image = ""
			rightItemIcon.Image = ""
			leftItemNameLabel.Text = ""
			rightItemNameLabel.Text = ""

			if not waitOrSkip(CATEGORY_INTRO_PAUSE, reveal) then
				return false
			end

			local pool = CATEGORY_POOLS[i] or {}
			spinSlot(leftItemIcon, pool, reveal)
			if reveal.Skip then
				return false
			end
			settleSlot(leftItemIcon, leftItemNameLabel, category.MyItem)
			if not waitOrSkip(SETTLE_PAUSE, reveal) then
				return false
			end

			spinSlot(rightItemIcon, pool, reveal)
			if reveal.Skip then
				return false
			end
			settleSlot(rightItemIcon, rightItemNameLabel, category.OpponentItem)
			if not waitOrSkip(SETTLE_PAUSE, reveal) then
				return false
			end

			progressLabel.Text = "COMPARING VALUES..."
			if not waitOrSkip(COMPARING_PAUSE, reveal) then
				return false
			end

			if category.Outcome == 1 then
				leftStroke.Color = Theme.Colors.Success
				rightStroke.Color = Theme.Colors.Danger
				progressLabel.Text = "YOU WIN THIS ROUND!"
			elseif category.Outcome == 2 then
				leftStroke.Color = Theme.Colors.Danger
				rightStroke.Color = Theme.Colors.Success
				progressLabel.Text = "OPPONENT WINS THIS ROUND!"
			else
				leftStroke.Color = Theme.Colors.TextSecondary
				rightStroke.Color = Theme.Colors.TextSecondary
				progressLabel.Text = "TIED!"
			end
			if not waitOrSkip(WINNER_GLOW_PAUSE, reveal) then
				return false
			end
			if not waitOrSkip(CATEGORY_HOLD, reveal) then
				return false
			end

			if i < categoryCount and not waitOrSkip(CATEGORY_TRANSITION_PAUSE, reveal) then
				return false
			end
		end
		return true
	end

	local function playOutro(result, reveal)
		categoryLabel.Text = "RESULT"
		progressLabel.Text = ""
		if not waitOrSkip(OUTRO_BANNER_PAUSE, reveal) then
			return
		end

		if result.Won == true then
			outcomeLabel.Text = "YOU WON!"
			outcomeLabel.TextColor3 = Theme.Colors.Success
		elseif result.Won == false then
			outcomeLabel.Text = "YOU LOST"
			outcomeLabel.TextColor3 = Theme.Colors.Danger
		else
			outcomeLabel.Text = "DRAW"
			outcomeLabel.TextColor3 = Theme.Colors.TextSecondary
		end
		if not waitOrSkip(OUTRO_RESULT_PAUSE, reveal) then
			return
		end

		scoreLabel.Text = string.format("(%d - %d)", result.WinsMine, result.WinsOpponent)
		if not waitOrSkip(OUTRO_SCORE_PAUSE, reveal) then
			return
		end

		if result.Won == true then
			scoreLabel.Text = scoreLabel.Text .. "   +1 Point"
		end
		waitOrSkip(OUTRO_FINAL_HOLD, reveal)
	end

	battleResult.OnClientEvent:Connect(function(result)
		setInQueue(false)
		suppressMenu = true
		menuFrame.Visible = false
		-- Cut short any still-running reveal from a PREVIOUS result before
		-- starting this one -- without this, two results landing close
		-- together (e.g. a fast double-click on Casual firing
		-- JoinCasualBattle twice before the first reply arrives) would run
		-- two coroutines writing to the same labels/icons at once.
		if currentReveal then
			currentReveal.Skip = true
		end
		outcomeLabel.Text = ""
		scoreLabel.Text = ""
		popup.Visible = true

		local reveal = { Skip = false }
		currentReveal = reveal
		task.spawn(function()
			if playIntro(result, reveal) and playCategories(result, reveal) then
				playOutro(result, reveal)
			end
			-- Only close things out if THIS reveal is still the current one
			-- -- if a newer result has since superseded it (currentReveal
			-- was reassigned above), that newer coroutine owns the
			-- popup/menu state now, not this stale one.
			if currentReveal == reveal then
				popup.Visible = false
				suppressMenu = false
			end
		end)
	end)

	-- Self-healing WaitForChild retry (same reasoning as
	-- VIPProximityPanel.luau) -- re-resolves Workspace.Map itself, not just
	-- the child, in case a stale Map from a previous save still existed at
	-- t=0 and got destroyed/rebuilt out from under a cached reference.
	task.spawn(function()
		local marker: BasePart? = nil
		while not marker do
			local mapFolder = Workspace:WaitForChild("Map")
			marker = mapFolder:WaitForChild("BattleMarker_Line", 5) :: BasePart?
		end

		local wasInRange = false
		RunService.Heartbeat:Connect(function()
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			local inRange = rootPart ~= nil and (rootPart.Position - marker.Position).Magnitude <= PROXIMITY_RADIUS_STUDS

			if not suppressMenu then
				menuFrame.Visible = inRange
			end

			-- Walking away while queued auto-leaves -- otherwise a player
			-- could queue up, wander off, and stay invisibly reserved for a
			-- match they're no longer around to see start.
			if wasInRange and not inRange and inQueue then
				leaveBattleQueue:FireServer()
			end
			wasInRange = inRange
		end)
	end)
end

return BattlePanel
