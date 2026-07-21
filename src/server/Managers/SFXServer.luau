local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Helper comun -- orice manager de server care are nevoie sa redea un sunet
-- pentru un jucator anume trece prin asta, in loc sa umble fiecare cu
-- propriul WaitForChild("PlaySound"). Cheile (Sell/Buy/etc) sunt mapate la
-- ID-uri reale doar pe client (SFXPlayer.client.luau) -- aici doar trimitem
-- cheia, server-ul nu stie/nu-i pasa ce sunet e.
local SFXServer = {}

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local playSoundEvent = remotes:WaitForChild("PlaySound")

function SFXServer.Play(player, soundKey)
	if not player then
		return
	end

	playSoundEvent:FireClient(player, soundKey)
end

return SFXServer
