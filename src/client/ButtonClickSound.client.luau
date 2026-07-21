local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Sunet de click pentru ORICE buton din joc -- nu doar un set fix (era prea
-- ingust, cerut explicit sa acopere totul) -- se agata AUTOMAT de orice
-- GuiButton (TextButton/ImageButton) deja existent SAU creat mai tarziu
-- (shop-uri, carduri de pet, etc.), fara sa mai umblam manual prin fiecare
-- GUI/script.

local SoundGroups = require(script.Parent:WaitForChild("SoundGroups"))
local sfxGroup = SoundGroups.SFX

local clickSound = Instance.new("Sound")
clickSound.Name = "ButtonClick"
clickSound.SoundId = "rbxassetid://120401943587131"
clickSound.SoundGroup = sfxGroup
clickSound.Parent = SoundService

local function playClick()
	clickSound:Play()
end

local connected = setmetatable({}, {__mode = "k"})

local function connectButton(instance)
	if connected[instance] then
		return
	end

	if instance:IsA("GuiButton") then
		connected[instance] = true
		instance.Activated:Connect(playClick)
	end
end

for _, descendant in ipairs(playerGui:GetDescendants()) do
	connectButton(descendant)
end

playerGui.DescendantAdded:Connect(connectButton)
