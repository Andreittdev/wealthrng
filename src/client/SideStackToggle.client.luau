local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Buton de restrangere ("<"/">") pentru TOATA stiva din dreapta (Starter
-- Pack/Rebirth/Daily Rewards/Settings) -- ca la jocurile mari, un click
-- ascunde toate 4 butoanele deodata (mai mult loc pe ecran), inca un click
-- le aduce inapoi. Cele 4 scripturi (StarterPackShop/RebirthShop/
-- DailyRewards/Settings) asculta atributul "SideStackCollapsed" direct, nu
-- e nevoie de niciun remote -- acest script doar seteaza atributul.
--
-- Cand e restrans, chiar butonul asta aluneca pana la marginea ecranului
-- (nu ramane suspendat in mijlocul ecranului, unde ar incurca jucatorul) --
-- doar o "limba" mica, lipita de margine, gata de tras inapoi stiva.

local function computeIsMobile()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.X < 700 or viewport.Y < 500
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SideStackToggleGui"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Fara chenar/patrat -- doar sageata alba, simpla, cu contur negru subtire
-- ca sa se citeasca pe orice fundal (iarba, cer etc.), acelasi tipar ca
-- restul textelor din HUD (TextStrokeColor3/Transparency).
local toggleButton = Instance.new("TextButton")
toggleButton.Name = "SideStackToggleButton"
toggleButton.AnchorPoint = Vector2.new(1, 0.5)
toggleButton.BackgroundTransparency = 1
toggleButton.AutoButtonColor = false
toggleButton.Text = "◀"
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
toggleButton.TextStrokeTransparency = 0
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextScaled = true
toggleButton.ZIndex = 9
toggleButton.Parent = screenGui

-- Pozitia EXTINSA (langa stiva) si pozitia RESTRANSA (lipita de marginea
-- ecranului) -- calculate per layout (desktop/mobil), tinute minte ca sa
-- putem anima intre ele cu un Tween, nu doar sa sarim direct.
local expandedPosition, collapsedPosition
local buttonSize

local function updateLayout()
	local isMobile = computeIsMobile()

	if isMobile then
		buttonSize = UDim2.new(0, 22, 0, 44)
		-- Centrat vertical pe mijlocul stivei mobile (StarterPack top=48 pana
		-- la Settings top=188+40=228, centrul e la Y=138).
		expandedPosition = UDim2.new(1, -126, 0, 138)
		collapsedPosition = UDim2.new(1, -4, 0, 138)
	else
		buttonSize = UDim2.new(0, 30, 0, 60)
		-- Centrat vertical pe mijlocul stivei desktop (StarterPack Y=0,h=72
		-- pana la Settings Y=243,h=66, centrul combinat e la Y=120).
		expandedPosition = UDim2.new(1, -192, 0.5, 120)
		collapsedPosition = UDim2.new(1, -10, 0.5, 120)
	end

	toggleButton.Size = buttonSize

	local collapsed = player:GetAttribute("SideStackCollapsed") == true
	toggleButton.Position = collapsed and collapsedPosition or expandedPosition
end

updateLayout()

do
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateLayout)
	end
end

local function refreshState()
	local collapsed = player:GetAttribute("SideStackCollapsed") == true

	toggleButton.Text = collapsed and "▶" or "◀"

	TweenService:Create(
		toggleButton,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Position = collapsed and collapsedPosition or expandedPosition}
	):Play()
end

refreshState()
player:GetAttributeChangedSignal("SideStackCollapsed"):Connect(refreshState)

toggleButton.Activated:Connect(function()
	local collapsed = player:GetAttribute("SideStackCollapsed") == true
	player:SetAttribute("SideStackCollapsed", not collapsed)
end)

-- Ascuns cat timp orice panou modal e deschis (acelasi flag comun ca restul
-- stivei) -- altfel ar ramane plutind singur peste cardul deschis.
player:GetAttributeChangedSignal("ShopModalOpen"):Connect(function()
	toggleButton.Visible = not player:GetAttribute("ShopModalOpen")
end)
