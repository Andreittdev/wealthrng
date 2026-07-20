local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local showTradeEvent = remotes:WaitForChild("ShowTrade")
local completeTutorialEvent = remotes:WaitForChild("CompleteTutorial")

-- Primul lucru pe care il vede un jucator NOU e jocul gol, fara nicio
-- explicatie (nu exista deloc tutorial pana acum) -- jucatorul trebuie sa
-- ghiceasca singur ce e un NPC, un Stand, cum cumperi/vinzi. Acest script
-- ghideaza primii pasi (gaseste NPC -> cumpara -> vinde), o singura data,
-- doar pentru jucatori chiar noi (TutorialCompleted=false vine din
-- DataManager -- jucatorii vechi il primesc implicit TRUE la incarcare,
-- vezi DataManager.LoadData, ca sa nu li se arate din senin).

local function computeIsMobile()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.X < 700 or viewport.Y < 500
end

local FONT_DISPLAY = Enum.Font.FredokaOne
local FONT_BODY = Enum.Font.FredokaOne

-- Tema "premium" -- auriu pe fundal grafit inchis (in loc de accent-ul plat
-- cyan de la prima varianta), gradient pe fundaluri/butoane + insigna
-- rotunda pentru emoji + tranzitii (scale/fade/slide) la aparitie, ca sa
-- semene cu un onboarding lucrat, nu doar un chenar simplu cu text.
local GOLD = Color3.fromRGB(255, 199, 79)
local GOLD_DEEP = Color3.fromRGB(214, 146, 30)
local BG_TOP = Color3.fromRGB(32, 27, 20)
local BG_BOTTOM = Color3.fromRGB(15, 13, 10)
local TEXT_LIGHT = Color3.fromRGB(248, 243, 233)
local TEXT_DIM = Color3.fromRGB(200, 191, 174)

-- MOD DE TEST -- arata tutorialul la FIECARE intrare, indiferent daca
-- TutorialCompleted e true (jucator vechi/deja testat), ca sa poata fi
-- testat repetat fara sa stergem manual DataStore-ul de fiecare data.
-- PUNE INAPOI PE false inainte de lansarea reala -- altfel tutorialul
-- apare la fiecare join, si pentru jucatorii vechi.
local FORCE_SHOW_FOR_TESTING = false

local function markCompleted()
	player:SetAttribute("TutorialCompleted", true)
	completeTutorialEvent:FireServer()
end

-- Asteapta explicit flag-ul (nil = inca nu s-au incarcat datele din
-- DataStore) -- daca am citi o singura data la pornire, am prinde mereu nil
-- si am crede gresit ca oricine e jucator nou.
local function waitForTutorialFlag()
	while player:GetAttribute("TutorialCompleted") == nil do
		task.wait(0.1)
	end
	return player:GetAttribute("TutorialCompleted") == true
end

local function addGradient(instance, topColor, bottomColor)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(topColor, bottomColor)
	gradient.Rotation = 90
	gradient.Parent = instance
	return gradient
end

task.spawn(function()
	local alreadyCompleted = waitForTutorialFlag()
	if alreadyCompleted and not FORCE_SHOW_FOR_TESTING then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TutorialDisplay"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 50
	screenGui.Parent = playerGui

	-- Fundal semi-transparent DOAR in spatele popup-urilor de bun venit/final
	-- (nu si in spatele banner-ului de progres, ca sa nu blocheze jocul in
	-- timp ce jucatorul e ghidat sa umble prin harta).
	local dimmer = Instance.new("Frame")
	dimmer.Name = "Dimmer"
	dimmer.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	dimmer.BackgroundTransparency = 1
	dimmer.Size = UDim2.new(1, 0, 1, 0)
	dimmer.Visible = false
	dimmer.ZIndex = 50
	dimmer.Parent = screenGui

	local function createModal(emoji, message, buttonText)
		local modal = Instance.new("Frame")
		modal.Name = "Modal"
		modal.AnchorPoint = Vector2.new(0.5, 0.5)
		modal.Position = UDim2.new(0.5, 0, 0.5, 0)
		modal.Size = computeIsMobile() and UDim2.new(0.85, 0, 0, 280) or UDim2.new(0, 460, 0, 260)
		modal.BackgroundColor3 = BG_TOP
		modal.ZIndex = 51
		modal.Parent = screenGui

		addGradient(modal, BG_TOP, BG_BOTTOM)
		Instance.new("UICorner", modal).CornerRadius = UDim.new(0, 20)

		local innerStroke = Instance.new("UIStroke")
		innerStroke.Color = GOLD
		innerStroke.Thickness = 2
		innerStroke.Transparency = 0.15
		innerStroke.Parent = modal

		-- A doua conturare, mai groasa si mai transparenta -- simuleaza un
		-- glow subtil in jurul cardului, fara sa avem acces la un blur real.
		local glowStroke = Instance.new("UIStroke")
		glowStroke.Color = GOLD
		glowStroke.Thickness = 5
		glowStroke.Transparency = 0.75
		glowStroke.Parent = modal

		local scale = Instance.new("UIScale")
		scale.Scale = 0.8
		scale.Parent = modal

		-- Insigna rotunda cu emoji, jumatate iesita peste marginea de sus a
		-- cardului -- tipar comun in UI-uri "premium" de onboarding.
		local badge = Instance.new("Frame")
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.Position = UDim2.new(0.5, 0, 0, 0)
		badge.Size = UDim2.new(0, 76, 0, 76)
		badge.BackgroundColor3 = GOLD
		badge.ZIndex = 53
		badge.Parent = modal

		addGradient(badge, GOLD, GOLD_DEEP)
		Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)

		local badgeStroke = Instance.new("UIStroke")
		badgeStroke.Color = BG_TOP
		badgeStroke.Thickness = 3
		badgeStroke.Parent = badge

		local emojiLabel = Instance.new("TextLabel")
		emojiLabel.BackgroundTransparency = 1
		emojiLabel.Size = UDim2.new(1, 0, 1, 0)
		emojiLabel.Text = emoji
		emojiLabel.Font = FONT_DISPLAY
		emojiLabel.TextScaled = true
		emojiLabel.TextColor3 = Color3.fromRGB(30, 22, 10)
		emojiLabel.ZIndex = 54
		emojiLabel.Parent = badge

		local messageLabel = Instance.new("TextLabel")
		messageLabel.BackgroundTransparency = 1
		messageLabel.Size = UDim2.new(1, -56, 0, 100)
		messageLabel.Position = UDim2.new(0, 28, 0, 56)
		messageLabel.Text = message
		messageLabel.Font = FONT_BODY
		messageLabel.TextScaled = true
		messageLabel.TextWrapped = true
		messageLabel.TextColor3 = TEXT_LIGHT
		messageLabel.ZIndex = 52
		messageLabel.Parent = modal

		local button = Instance.new("TextButton")
		button.Size = UDim2.new(0, 200, 0, 48)
		button.Position = UDim2.new(0.5, 0, 1, -66)
		button.AnchorPoint = Vector2.new(0.5, 0)
		button.BackgroundColor3 = GOLD
		button.Text = buttonText
		button.Font = FONT_DISPLAY
		button.TextScaled = true
		button.TextColor3 = Color3.fromRGB(30, 22, 10)
		button.AutoButtonColor = false
		button.ZIndex = 52
		button.Parent = modal

		addGradient(button, GOLD, GOLD_DEEP)
		Instance.new("UICorner", button).CornerRadius = UDim.new(0, 12)

		local buttonStroke = Instance.new("UIStroke")
		buttonStroke.Color = Color3.fromRGB(255, 235, 190)
		buttonStroke.Transparency = 0.5
		buttonStroke.Thickness = 1
		buttonStroke.Parent = button

		-- Feedback tactil simplu -- se comprima usor la apasare, revine la
		-- eliberare, in loc de AutoButtonColor (prea plat pentru tema asta).
		button.MouseButton1Down:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.08), {Size = UDim2.new(0, 192, 0, 45)}):Play()
		end)
		button.MouseButton1Up:Connect(function()
			TweenService:Create(button, TweenInfo.new(0.08), {Size = UDim2.new(0, 200, 0, 48)}):Play()
		end)

		TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()

		return modal, button
	end

	local function showModalAndWait(emoji, message, buttonText)
		TweenService:Create(dimmer, TweenInfo.new(0.2), {BackgroundTransparency = 0.45}):Play()
		dimmer.Visible = true
		local modal, button = createModal(emoji, message, buttonText)

		local done = false
		button.Activated:Connect(function()
			done = true
		end)

		while not done do
			task.wait(0.1)
		end

		TweenService:Create(dimmer, TweenInfo.new(0.15), {BackgroundTransparency = 1}):Play()
		dimmer.Visible = false
		modal:Destroy()
	end

	-- Banner de progres, sus pe ecran -- nu blocheaza restul jocului, doar
	-- indica pasul curent + un link mic de "Skip" pentru cine nu il vrea.
	-- Centrat pe mijlocul ecranului -- la fel pe PC si pe mobil -- dupa 3
	-- incercari de pozitionare sus (mereu acoperit de topbar-ul Roblox sau
	-- de alte elemente de HUD), varianta sigura e centrul ecranului, unde
	-- nu exista nimic altceva peste care sa se suprapuna.
	local banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	-- Mai sus pe PC (unde ecranul e lat, spatiul de sus e liber), neschimbat
	-- pe mobil (unde spatiul de sus e mai ingust si risca sa acopere HUD-ul).
	banner.Position = computeIsMobile() and UDim2.new(0.5, 0, 0.35, 0) or UDim2.new(0.5, 0, 0.16, 0)
	banner.Size = computeIsMobile() and UDim2.new(0.9, 0, 0, 64) or UDim2.new(0, 540, 0, 64)
	banner.BackgroundColor3 = BG_TOP
	banner.Visible = false
	banner.ZIndex = 40
	banner.Parent = screenGui

	local bannerScale = Instance.new("UIScale")
	bannerScale.Scale = 1
	bannerScale.Parent = banner

	addGradient(banner, BG_TOP, BG_BOTTOM)
	Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 16)

	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Color = GOLD
	bannerStroke.Thickness = 2
	bannerStroke.Transparency = 0.2
	bannerStroke.Parent = banner

	local stepBadge = Instance.new("Frame")
	stepBadge.AnchorPoint = Vector2.new(0, 0.5)
	stepBadge.Position = UDim2.new(0, 10, 0.5, 0)
	stepBadge.Size = UDim2.new(0, 40, 0, 40)
	stepBadge.BackgroundColor3 = GOLD
	stepBadge.ZIndex = 41
	stepBadge.Parent = banner

	addGradient(stepBadge, GOLD, GOLD_DEEP)
	Instance.new("UICorner", stepBadge).CornerRadius = UDim.new(1, 0)

	local stepBadgeLabel = Instance.new("TextLabel")
	stepBadgeLabel.BackgroundTransparency = 1
	stepBadgeLabel.Size = UDim2.new(1, 0, 1, 0)
	stepBadgeLabel.Font = FONT_DISPLAY
	stepBadgeLabel.TextScaled = true
	stepBadgeLabel.TextColor3 = Color3.fromRGB(30, 22, 10)
	stepBadgeLabel.ZIndex = 42
	stepBadgeLabel.Parent = stepBadge

	local bannerLabel = Instance.new("TextLabel")
	bannerLabel.BackgroundTransparency = 1
	bannerLabel.Size = UDim2.new(1, -148, 0, 26)
	bannerLabel.Position = UDim2.new(0, 60, 0, 8)
	bannerLabel.TextXAlignment = Enum.TextXAlignment.Left
	bannerLabel.Font = FONT_BODY
	bannerLabel.TextScaled = true
	bannerLabel.TextWrapped = true
	bannerLabel.TextColor3 = TEXT_LIGHT
	bannerLabel.ZIndex = 41
	bannerLabel.Parent = banner

	local stepCountLabel = Instance.new("TextLabel")
	stepCountLabel.BackgroundTransparency = 1
	stepCountLabel.Size = UDim2.new(1, -148, 0, 16)
	stepCountLabel.Position = UDim2.new(0, 60, 1, -22)
	stepCountLabel.TextXAlignment = Enum.TextXAlignment.Left
	stepCountLabel.Font = FONT_BODY
	stepCountLabel.TextScaled = true
	stepCountLabel.TextColor3 = TEXT_DIM
	stepCountLabel.ZIndex = 41
	stepCountLabel.Parent = banner

	-- Bara subtire de progres, jos in banner -- se umple gradual pe masura
	-- ce jucatorul avanseaza prin cei 3 pasi.
	local progressTrack = Instance.new("Frame")
	progressTrack.AnchorPoint = Vector2.new(0, 1)
	progressTrack.Position = UDim2.new(0, 60, 1, -4)
	progressTrack.Size = UDim2.new(1, -76, 0, 4)
	progressTrack.BackgroundColor3 = Color3.fromRGB(60, 52, 38)
	progressTrack.ZIndex = 41
	progressTrack.Parent = banner
	Instance.new("UICorner", progressTrack).CornerRadius = UDim.new(1, 0)

	local progressFill = Instance.new("Frame")
	progressFill.Size = UDim2.new(0, 0, 1, 0)
	progressFill.BackgroundColor3 = GOLD
	progressFill.ZIndex = 42
	progressFill.Parent = progressTrack
	Instance.new("UICorner", progressFill).CornerRadius = UDim.new(1, 0)

	local skipButton = Instance.new("TextButton")
	skipButton.BackgroundTransparency = 1
	skipButton.Size = UDim2.new(0, 76, 0, 40)
	skipButton.AnchorPoint = Vector2.new(1, 0.5)
	skipButton.Position = UDim2.new(1, -12, 0.5, 0)
	skipButton.Text = "Skip ✕"
	skipButton.Font = FONT_BODY
	skipButton.TextScaled = true
	skipButton.TextColor3 = TEXT_DIM
	skipButton.ZIndex = 41
	skipButton.Parent = banner

	local skipRequested = false
	skipButton.Activated:Connect(function()
		skipRequested = true
	end)

	local TOTAL_STEPS = 3

	local function showBanner(stepNumber, text)
		stepBadgeLabel.Text = tostring(stepNumber)
		bannerLabel.Text = text
		stepCountLabel.Text = "STEP " .. stepNumber .. " / " .. TOTAL_STEPS

		TweenService:Create(
			progressFill,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Size = UDim2.new(stepNumber / TOTAL_STEPS, 0, 1, 0)}
		):Play()

		if not banner.Visible then
			banner.Visible = true
			bannerScale.Scale = 0.8
			TweenService:Create(
				bannerScale,
				TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{Scale = 1}
			):Play()
		end
	end

	local function hideBanner()
		local tween = TweenService:Create(
			bannerScale,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Scale = 0.8}
		)
		tween:Play()
		tween.Completed:Wait()
		banner.Visible = false
	end

	-- Timp minim cat statea fiecare pas pe ecran, chiar daca conditia lui se
	-- indeplineste aproape instant (Auto Buy Pass + Auto Sell Pass, active pe
	-- multe conturi de test din Studio, pot cumpara SI vinde automat in mai
	-- putin de o secunda -- fara asta, pasul 2 aparea si disparea prea repede
	-- ca sa fie citit, parand ca "sare" direct la pasul 3).
	local MIN_STEP_SECONDS = 1.2

	-- Asteapta fie conditia de progres (waitFn intoarce true cand pasul e
	-- indeplinit), fie apasarea pe Skip -- oricare vine prima. Intoarce true
	-- daca s-a dat Skip, ca sa oprim tot restul secventei imediat.
	local function waitStep(stepNumber, text, waitFn)
		showBanner(stepNumber, text)
		local shownAt = os.clock()

		while not skipRequested and not waitFn() do
			task.wait(0.2)
		end

		if not skipRequested then
			local elapsed = os.clock() - shownAt
			if elapsed < MIN_STEP_SECONDS then
				task.wait(MIN_STEP_SECONDS - elapsed)
			end
		end

		return skipRequested
	end

	showModalAndWait(
		"👋",
		"Welcome to Buy Low Sell High! Let's make your first trade -- buy cheap, sell high.",
		"Let's go!"
	)

	if skipRequested then
		hideBanner()
		markCompleted()
		return
	end

	-- Pasul 1: un NPC iti aduce o oferta la Stand-ul tau propriu.
	local gotOffer = false
	local tradeConn = showTradeEvent.OnClientEvent:Connect(function()
		gotOffer = true
	end)

	waitStep(1, "Go to YOUR Stand -- an NPC will bring you an offer!", function()
		return gotOffer
	end)
	tradeConn:Disconnect()

	if skipRequested then
		hideBanner()
		markCompleted()
		return
	end

	-- Pasul 2: cumpara itemul oferit.
	local inventory = player:WaitForChild("Inventory")
	local boughtItem = false
	local addedConn = inventory.ChildAdded:Connect(function()
		boughtItem = true
	end)

	waitStep(2, "Press BUY to purchase the item you were offered!", function()
		return boughtItem
	end)
	addedConn:Disconnect()

	if skipRequested then
		hideBanner()
		markCompleted()
		return
	end

	-- Pasul 3: vinde itemul cumparat, pentru profit.
	local soldItem = false
	local removedConn = inventory.ChildRemoved:Connect(function()
		soldItem = true
	end)

	waitStep(3, "Now sell it back for profit -- open your Inventory!", function()
		return soldItem
	end)
	removedConn:Disconnect()

	hideBanner()

	if not skipRequested then
		showModalAndWait(
			"🎉",
			"Nice, you made your first profit! Buy low, sell high -- save up 5,000$ for your first Egg to get your first pet.",
			"Got it!"
		)
	end

	markCompleted()
end)
