local Players = game:GetService("Players")

-- Limiteaza cat de departe poate da un jucator zoom out cu rotita mouse-ului
-- (implicit Roblox permite pana la 400 studs -- prea mult, se vede prea mult
-- din harta/orizont gol). 40 studs -- suficient pentru o vedere de ansamblu
-- normala (stand-uri, NPC-uri din jur), fara sa poata "iesi" vizual din
-- zona construita a hartii.
local MAX_ZOOM_DISTANCE = 40

local function applyZoomLimit(player)
	player.CameraMaxZoomDistance = MAX_ZOOM_DISTANCE
end

Players.PlayerAdded:Connect(applyZoomLimit)

for _, player in ipairs(Players:GetPlayers()) do
	applyZoomLimit(player)
end
