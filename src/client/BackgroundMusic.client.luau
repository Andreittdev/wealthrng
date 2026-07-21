local SoundService = game:GetService("SoundService")

-- Playlist de muzica de fundal -- NU o singura piesa in bucla infinita
-- (devine remarcabila/obositoare pe sesiuni lungi, mai ales o piesa
-- "calma"), ci o lista prin care trecem automat cand piesa curenta se
-- termina. Cu o singura piesa (cum e acum), se comporta identic cu o bucla
-- simpla -- cand se mai adauga piese din Toolbox, e doar un rand in plus
-- aici, fara sa mai rescriem nimic.
local PLAYLIST = {
	"rbxassetid://129306296495814", -- Calming Saxophone
	"rbxassetid://70586568456559",
	"rbxassetid://114404281352803",
	"rbxassetid://126037733134676",
}

-- Legata de grupul "Music" (creare CENTRALIZATA, vezi SoundGroups.luau),
-- deci slider-ul de volum din Settings o controleaza automat, fara cod
-- suplimentar.
local SoundGroups = require(script.Parent:WaitForChild("SoundGroups"))
local musicGroup = SoundGroups.Music

local existing = SoundService:FindFirstChild("BackgroundMusic")
if existing then
	existing:Destroy()
end

local music = Instance.new("Sound")
music.Name = "BackgroundMusic"
music.Looped = false -- trecem NOI la urmatoarea piesa, nu o repeta Roblox singur
music.Volume = 1
music.SoundGroup = musicGroup
music.Parent = SoundService

local nextIndex = 1

local function playNext()
	music.SoundId = PLAYLIST[nextIndex]
	nextIndex = (nextIndex % #PLAYLIST) + 1
	music:Play()
end

music.Ended:Connect(playNext)
playNext()
