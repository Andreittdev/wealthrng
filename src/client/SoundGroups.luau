local SoundService = game:GetService("SoundService")

-- BUG gasit: Settings/BackgroundMusic/SFXPlayer/ButtonClickSound creau
-- FIECARE propriul SoundGroup "Music"/"SFX" daca nu-l gaseau deja (acelasi
-- tipar "FindFirstChild sau Instance.new" repetat in 4 scripturi separate)
-- -- dar scripturile ruleaza in PARALEL, deci puteau crea, prin cursa, DOUA
-- grupuri "Music" separate: slider-ul din Settings modifica volumul unuia,
-- muzica reala canta din celalalt, care nu se schimba niciodata.
--
-- require() pe un ModuleScript ruleaza codul o SINGURA data, indiferent de
-- cate scripturi il cer simultan (Lua cacheuieste rezultatul) -- creare
-- garantat unica, fara cursa, indiferent de ordinea/paralelismul scripturilor
-- care il folosesc.
local SoundGroups = {}

local function getOrCreate(name)
	local group = SoundService:FindFirstChild(name)
	if not group then
		group = Instance.new("SoundGroup")
		group.Name = name
		group.Parent = SoundService
	end
	return group
end

SoundGroups.Music = getOrCreate("Music")
SoundGroups.SFX = getOrCreate("SFX")

return SoundGroups
