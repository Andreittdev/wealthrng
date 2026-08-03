-- Loops the game's background music, respecting the Music on/off
-- preference SettingsPanel already exposed (session.Preferences.Music,
-- default on) -- that preference existed with nothing to actually control
-- until now (see SettingsPanel.luau's header comment).

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BackgroundMusic = {}

local MUSIC_SOUND_ID = "rbxassetid://126037733134676"
local MUSIC_VOLUME = 0.5

function BackgroundMusic.Init()
	local sound = Instance.new("Sound")
	sound.Name = "BackgroundMusic"
	sound.SoundId = MUSIC_SOUND_ID
	sound.Looped = true
	sound.Volume = MUSIC_VOLUME
	sound.Parent = SoundService
	sound:Play()

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local preferencesUpdated = remotesFolder:WaitForChild("PreferencesUpdated")

	preferencesUpdated.OnClientEvent:Connect(function(map: { [string]: boolean })
		-- Missing key means on (same "missing == on" convention
		-- SettingsPanel/DataManager already use for Music/SFX/VFX) -- only
		-- an explicit false pauses it.
		local musicOn = map.Music ~= false
		if musicOn then
			if not sound.IsPlaying then
				sound:Play()
			end
		else
			sound:Pause()
		end
	end)
end

return BackgroundMusic
