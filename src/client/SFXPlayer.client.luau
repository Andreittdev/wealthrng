local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

-- Sunete declansate de SERVER (Sell/InventoryFull/CodeRedeemed/Buy/Purchase)
-- -- server-ul trimite doar o CHEIE (vezi SFXServer.luau), mapajul cheie ->
-- rbxassetid e aici, o singura data, ca sa fie usor de schimbat fara sa
-- umblam prin fiecare manager de server.
local SOUND_IDS = {
	Sell = "rbxassetid://127750969069484",
	InventoryFull = "rbxassetid://139994899674617",
	CodeRedeemed = "rbxassetid://132990201173758",
	Buy = "rbxassetid://93784025226073",
	Purchase = "rbxassetid://81229233798558",
}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local playSoundEvent = remotes:WaitForChild("PlaySound")

-- Creare CENTRALIZATA (vezi SoundGroups.luau), ca sliderul "SFX Volume" din
-- Settings sa controleze exact acest grup, nu unul creat separat prin cursa.
local SoundGroups = require(script.Parent:WaitForChild("SoundGroups"))
local sfxGroup = SoundGroups.SFX

-- Un Sound per cheie, refolosit (nu creat/distrus la fiecare declansare) --
-- daca acelasi eveniment se intampla rapid succesiv (ex: Auto Buy Pass),
-- :Play() de la 0 reporneste sunetul curat, fara sa ne aglomeram cu instante.
local sounds = {}

local function getSound(key)
	local sound = sounds[key]

	if not sound then
		local soundId = SOUND_IDS[key]
		if not soundId then
			return nil
		end

		sound = Instance.new("Sound")
		sound.Name = key
		sound.SoundId = soundId
		sound.SoundGroup = sfxGroup
		sound.Parent = SoundService

		sounds[key] = sound
	end

	return sound
end

playSoundEvent.OnClientEvent:Connect(function(key)
	local sound = getSound(key)
	if sound then
		sound:Play()
	end
end)
