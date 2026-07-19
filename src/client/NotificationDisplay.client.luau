local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local showNotificationEvent = remotes:WaitForChild("ShowNotification")

-- BUG gasit: 6 manageri de server (NPCManager, DailyRewardsManager,
-- RebirthManager, StandUpgradeManager, StarterPackManager, TokenShopManager)
-- trimiteau mesaje prin ShowNotification, dar niciun script client nu asculta
-- evenimentul -- toate mesajele ("Bought X for $Y", "Inventory Full",
-- rezultate Rebirth, recompense Daily Rewards etc.) se pierdeau, jucatorul nu
-- vedea niciodata nimic. Acest script e singurul care le afiseaza.

local FONT_BODY = Enum.Font.FredokaOne

local function computeIsMobile()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.X < 700 or viewport.Y < 500
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "NotificationDisplay"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 500
screenGui.Parent = playerGui

-- Stiva de toast-uri, jos pe ecran, centrata -- cele noi intra jos, cele
-- vechi urca pe masura ce se aduna (UIListLayout, SortOrder=LayoutOrder).
local container = Instance.new("Frame")
container.Name = "NotificationContainer"
container.BackgroundTransparency = 1
container.AnchorPoint = Vector2.new(0.5, 1)
container.Position = UDim2.new(0.5, 0, 1, -100)
container.Size = UDim2.new(0, 420, 0, 300)
container.ZIndex = 500
container.Parent = screenGui

local function updateContainerLayout()
	if computeIsMobile() then
		container.Size = UDim2.new(0.9, 0, 0, 260)
	else
		container.Size = UDim2.new(0, 420, 0, 300)
	end
end

updateContainerLayout()

do
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateContainerLayout)
	end
end

local listLayout = Instance.new("UIListLayout")
listLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = container

local nextOrder = 0
local TOAST_WIDTH = 380
local TOAST_HEIGHT = 44
local DISPLAY_SECONDS = 3

local function showToast(message)
	if type(message) ~= "string" or message == "" then
		return
	end

	nextOrder += 1

	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
	toast.Size = UDim2.new(1, 0, 0, 0)
	toast.LayoutOrder = nextOrder
	toast.ClipsDescendants = true
	toast.ZIndex = 500
	toast.Parent = container

	Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 12)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(90, 210, 255)
	stroke.Thickness = 2
	stroke.Parent = toast

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -24, 1, 0)
	label.Position = UDim2.new(0, 12, 0, 0)
	label.Text = message
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = FONT_BODY
	label.TextScaled = true
	label.TextWrapped = true
	label.TextTransparency = 1
	label.ZIndex = 501
	label.Parent = toast

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(TOAST_WIDTH, TOAST_HEIGHT)
	sizeConstraint.MinSize = Vector2.new(TOAST_WIDTH, TOAST_HEIGHT)
	sizeConstraint.Parent = toast

	-- Intra usor (creste din 0 inaltime), sta DISPLAY_SECONDS, apoi dispare
	-- (fade + micsorare), fara sa blocheze alte toast-uri (task.delay, nu
	-- task.wait -- pot exista mai multe simultan, fiecare pe propriul timer).
	TweenService:Create(
		toast,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{Size = UDim2.new(1, 0, 0, TOAST_HEIGHT)}
	):Play()
	TweenService:Create(label, TweenInfo.new(0.22), {TextTransparency = 0}):Play()

	task.delay(DISPLAY_SECONDS, function()
		if not toast.Parent then
			return
		end

		local fadeOut = TweenService:Create(
			toast,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1}
		)
		TweenService:Create(label, TweenInfo.new(0.15), {TextTransparency = 1}):Play()
		fadeOut:Play()

		fadeOut.Completed:Wait()
		toast:Destroy()
	end)
end

-- NotificationsEnabled -- setare din Settings, implicit activata (atribut
-- lipsa/nil inseamna "arata"). Doar cine chiar le dezactiveaza explicit nu
-- le mai vede.
showNotificationEvent.OnClientEvent:Connect(function(message)
	if player:GetAttribute("NotificationsEnabled") == false then
		return
	end
	showToast(message)
end)
