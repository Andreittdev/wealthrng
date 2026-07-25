-- Roll button and the slot-machine reveal window. (Buy VIP moved to the
-- sidebar's Shop panel, ShopPanel.luau.)
--
-- Animation flow: on click the reveal window cycles through random items
-- every SPIN_INTERVAL seconds. RollResult is buffered into `pendingResult`
-- instead of being shown immediately, so the spin always runs for at least
-- SPIN_MIN_DURATION *and* until the real result has arrived, then settles
-- on it with a bounce tween. The Roll button only re-enables once BOTH the
-- spin has finished AND the (VIP or base) cooldown has elapsed -- VIP's
-- cooldown (0.75s) is shorter than SPIN_MIN_DURATION (0.9s), so without this
-- the button would look clickable mid-spin while clicks were silently
-- dropped by the isSpinning guard.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ItemDatabase = require(ReplicatedStorage.Modules.ItemDatabase)
local RarityConfig = require(ReplicatedStorage.Modules.RarityConfig)
local RollConfig = require(ReplicatedStorage.Modules.RollConfig)
local VIPConfig = require(ReplicatedStorage.Modules.VIPConfig)
local Theme = require(script.Parent.Theme)

local SPIN_MIN_DURATION = 0.9
local SPIN_INTERVAL = 0.06
local REVEAL_SIZE = UDim2.new(0, 220, 0, 70)

local RollPanel = {}

function RollPanel.Create(screenGui: ScreenGui, remotes: Folder)
	local rollRequested = remotes:WaitForChild("RollRequested")
	local rollResult = remotes:WaitForChild("RollResult")

	local allItems = {}
	for _, item in ItemDatabase.GetAllItems() do
		table.insert(allItems, item)
	end

	local revealFrame = Theme.Panel(screenGui, REVEAL_SIZE, UDim2.new(0.5, -110, 1, -180))
	revealFrame.BackgroundColor3 = RarityConfig.GetColor("Common")
	revealFrame.BackgroundTransparency = 0.3

	-- Theme.Panel's default dark gradient would muddy the rarity-color
	-- cycling this window does during a spin -- drop it, keep the
	-- stroke/shadow framing.
	local revealGradient = revealFrame:FindFirstChildOfClass("UIGradient")
	if revealGradient then
		revealGradient:Destroy()
	end
	local revealStroke = revealFrame:FindFirstChildOfClass("UIStroke")

	local revealLabel = Theme.Label(revealFrame, UDim2.new(1, -16, 1, -8), "Press ROLL", true)
	revealLabel.Position = UDim2.new(0, 8, 0, 4)
	revealLabel.TextXAlignment = Enum.TextXAlignment.Center
	revealLabel.TextYAlignment = Enum.TextYAlignment.Center

	local rollButton = Theme.Button(screenGui, UDim2.new(0, 200, 0, 60), UDim2.new(0.5, -100, 1, -96), "ROLL", true)

	local pendingResult = nil
	rollResult.OnClientEvent:Connect(function(item)
		pendingResult = item
	end)

	local isVIP = false
	local isSpinning = false

	local function setRollEnabled(enabled: boolean)
		rollButton.Active = enabled
		rollButton.AutoButtonColor = enabled
		rollButton.BackgroundColor3 = enabled and Theme.Colors.Accent or Theme.Colors.Surface
	end

	local function playSettleBounce()
		revealFrame.Size = UDim2.new(0, REVEAL_SIZE.X.Offset * 1.15, 0, REVEAL_SIZE.Y.Offset * 1.15)
		local tween = TweenService:Create(
			revealFrame,
			TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = REVEAL_SIZE }
		)
		tween:Play()

		-- Bright flash on the border that fades back to the normal subtle
		-- stroke over a second -- a little glow highlight on the result.
		if revealStroke then
			revealStroke.Transparency = 0
			TweenService:Create(revealStroke, TweenInfo.new(1, Enum.EasingStyle.Quad), { Transparency = 0.35 }):Play()
		end
	end

	-- Runs the spin, blocking until it settles on the real result. Caller
	-- decides how much additional cooldown time (if any) to wait afterward.
	local function runSpin()
		isSpinning = true
		pendingResult = nil
		local startTime = os.clock()

		while true do
			local randomItem = allItems[math.random(1, #allItems)]
			local randomColor = RarityConfig.GetColor(randomItem.Rarity)
			revealLabel.Text = randomItem.Name
			revealFrame.BackgroundColor3 = randomColor
			if revealStroke then
				revealStroke.Color = randomColor
			end

			task.wait(SPIN_INTERVAL)

			if os.clock() - startTime >= SPIN_MIN_DURATION and pendingResult then
				break
			end
		end

		local item = pendingResult
		pendingResult = nil
		local finalColor = RarityConfig.GetColor(item.Rarity)
		revealLabel.Text = item.Name
		revealFrame.BackgroundColor3 = finalColor
		if revealStroke then
			revealStroke.Color = finalColor
		end
		playSettleBounce()

		isSpinning = false
	end

	rollButton.Activated:Connect(function()
		if isSpinning then
			return
		end

		setRollEnabled(false)
		local clickedAt = os.clock()
		rollRequested:FireServer()

		task.spawn(function()
			runSpin()

			local cooldown = isVIP and VIPConfig.RollCooldownSeconds or RollConfig.BaseCooldownSeconds
			local remaining = cooldown - (os.clock() - clickedAt)
			if remaining > 0 then
				task.wait(remaining)
			end

			setRollEnabled(true)
		end)
	end)

	local handle = {}

	function handle.SetVIP(newIsVIP: boolean)
		isVIP = newIsVIP
	end

	-- Hidden while any modal panel (shop, net worth, etc.) is open -- on
	-- short viewports, RollPanel's bottom-anchored elements have nowhere to
	-- go that a centered/top modal can't reach, so MainUI hides these
	-- instead of chasing an ever-shrinking gap with positioning alone.
	function handle.SetHudVisible(visible: boolean)
		rollButton.Visible = visible
		revealFrame.Visible = visible
	end

	return handle
end

return RollPanel
