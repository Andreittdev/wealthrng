-- Panou care apare cand jucatorul intra in cercul de la ChestStand.server.luau
-- (standul "GROUP REWARDS"). Cere Like + Join Group in text, dar tehnic
-- verificam DOAR apartenenta la grup (server-side, in ChestRewardManager) --
-- Like nu poate fi verificat prin niciun API Roblox.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Economy = require(modulesFolder:WaitForChild("EconomyConfig"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local claimChestRewardFunction = remotes:WaitForChild("ClaimChestReward")

local CLAIMED_COLOR = Color3.fromRGB(100, 235, 140)
local LOCKED_COLOR = Color3.fromRGB(230, 90, 90)

-- Standul (cercul auriu) e construit de ChestStand.server.luau -- il
-- asteptam, ruleaza pe alt script, poate inca nu exista in primele frame-uri.
local stall = Workspace:WaitForChild("ChestRewardsStand")
local disc = stall:WaitForChild("Disc")

-- Jumatate din diametrul cercului (20 studs, vezi ChestStand.server.luau) +
-- o mica marja, ca panoul sa apara chiar cand calci pe marginea cercului.
local ZONE_RADIUS = 11

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ChestRewardZoneGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Position = UDim2.new(0.5, 0, 1, -140)
panel.Size = UDim2.new(0, 280, 0, 210)
panel.BackgroundColor3 = Color3.fromRGB(30, 24, 8)
panel.BackgroundTransparency = 0.05
panel.Parent = screenGui

Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 210, 40)
stroke.Thickness = 2.5
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 36)
title.Position = UDim2.new(0, 0, 0, 8)
title.BackgroundTransparency = 1
title.Text = "GROUP REWARDS"
title.TextColor3 = Color3.fromRGB(255, 210, 40)
title.Font = Enum.Font.FredokaOne
title.TextScaled = true
title.Parent = panel

local instructionsList = Instance.new("TextLabel")
instructionsList.Size = UDim2.new(1, -20, 0, 96)
instructionsList.Position = UDim2.new(0, 10, 0, 46)
instructionsList.BackgroundTransparency = 1
instructionsList.Text = "Like the game!\nJoin the Group!\nEnjoy the rewards!"
instructionsList.TextColor3 = Color3.fromRGB(255, 245, 220)
instructionsList.Font = Enum.Font.FredokaOne
instructionsList.TextScaled = true
instructionsList.TextWrapped = true
instructionsList.Parent = panel

local claimButton = Instance.new("TextButton")
claimButton.Name = "ClaimButton"
claimButton.AnchorPoint = Vector2.new(0.5, 1)
claimButton.Position = UDim2.new(0.5, 0, 1, -12)
claimButton.Size = UDim2.new(1, -24, 0, 40)
claimButton.Font = Enum.Font.FredokaOne
claimButton.TextScaled = true
claimButton.AutoButtonColor = true
claimButton.Parent = panel

Instance.new("UICorner", claimButton).CornerRadius = UDim.new(0, 10)

local isClaiming = false

-- Cache-uit local -- IsInGroup poate face un apel intern la Roblox (poate
-- sa dea yield), deci nu il verificam la fiecare frame, doar cand jucatorul
-- intra in zona (vezi mai jos, langa Heartbeat).
local isInGroupCached = false

local function refreshClaimButton()
	local claimed = player:GetAttribute("ChestRewardClaimed") == true

	if claimed then
		claimButton.BackgroundColor3 = Color3.fromRGB(20, 40, 22)
		claimButton.Text = "CLAIMED"
		claimButton.TextColor3 = CLAIMED_COLOR
		claimButton.AutoButtonColor = false
		claimButton.Active = false
	elseif not isInGroupCached then
		claimButton.BackgroundColor3 = Color3.fromRGB(50, 20, 20)
		claimButton.Text = "LOCKED"
		claimButton.TextColor3 = LOCKED_COLOR
		claimButton.AutoButtonColor = false
		claimButton.Active = false
	else
		claimButton.BackgroundColor3 = Color3.fromRGB(255, 210, 40)
		claimButton.Text = "CLAIM"
		claimButton.TextColor3 = Color3.fromRGB(40, 30, 5)
		claimButton.AutoButtonColor = true
		claimButton.Active = true
	end
end

refreshClaimButton()
player:GetAttributeChangedSignal("ChestRewardClaimed"):Connect(refreshClaimButton)

-- Verificam apartenenta la grup de fiecare data cand jucatorul INTRA in
-- zona -- nu doar o data la incarcare -- ca sa prindem cazul in care s-a
-- alaturat grupului chiar acum, fara sa fie nevoie sa reintre in joc.
local function refreshGroupStatus()
	local ok, result = pcall(function()
		return player:IsInGroup(Economy.ChestReward.GroupId)
	end)

	isInGroupCached = ok and result or false
	refreshClaimButton()
end

local FAILURE_MESSAGES = {
	NotInGroup = "❌ Join the Group first!",
	AlreadyClaimed = "❌ Already claimed!",
	NotReady = "❌ Try again in a moment!"
}

claimButton.MouseButton1Click:Connect(function()
	if isClaiming or player:GetAttribute("ChestRewardClaimed") == true then
		return
	end

	isClaiming = true
	claimButton.Text = "..."

	local ok, result = pcall(function()
		return claimChestRewardFunction:InvokeServer()
	end)

	isClaiming = false

	if ok and result and result.Success then
		claimButton.Text = "CLAIMED!"
	else
		local reason = ok and result and result.Reason
		claimButton.Text = FAILURE_MESSAGES[reason] or "❌ Couldn't claim"
		task.delay(2, refreshClaimButton)
	end
end)

local isInside = false

RunService.Heartbeat:Connect(function()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		isInside = false
		screenGui.Enabled = false
		return
	end

	local distance = (rootPart.Position - disc.Position) * Vector3.new(1, 0, 1)
	local nowInside = distance.Magnitude <= ZONE_RADIUS

	if nowInside ~= isInside then
		isInside = nowInside
		screenGui.Enabled = isInside

		if isInside then
			task.spawn(refreshGroupStatus)
		end
	end
end)
