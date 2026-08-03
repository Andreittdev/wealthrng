-- Plays a click sound on every button tap, game-wide, automatically --
-- hooks GuiButton.Activated (TextButton/ImageButton both inherit from it,
-- and Activated already unifies mouse click/touch tap/gamepad select) via
-- PlayerGui:GetDescendants() + DescendantAdded, instead of wiring a sound
-- call into every individual button. This codebase creates buttons both
-- via Theme.Button AND many raw Instance.new("TextButton") calls scattered
-- across a dozen panel files -- a single global hook here covers all of
-- them, present and future, with no per-file changes needed.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local ButtonClickSound = {}

local CLICK_SOUND_ID = "rbxassetid://120401943587131"

function ButtonClickSound.Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local sound = Instance.new("Sound")
	sound.Name = "ButtonClick"
	sound.SoundId = CLICK_SOUND_ID
	sound.Parent = SoundService

	local function playClick()
		-- Reset position first -- Play() alone doesn't reliably restart a
		-- still-playing Sound, and a fast double-tap should retrigger the
		-- click cleanly rather than being silently swallowed.
		sound.TimePosition = 0
		sound:Play()
	end

	local function hook(button: Instance)
		(button :: GuiButton).Activated:Connect(playClick)
	end

	for _, descendant in playerGui:GetDescendants() do
		if descendant:IsA("GuiButton") then
			hook(descendant)
		end
	end

	playerGui.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("GuiButton") then
			hook(descendant)
		end
	end)
end

return ButtonClickSound
