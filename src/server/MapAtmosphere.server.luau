local Lighting = game:GetService("Lighting")

-- Cerul gol (gri/albastru plat, fara nori) + iluminatul implicit faceau
-- harta sa arate "tehnica", nu ca un loc anume. Schimbarile de aici NU
-- costa FPS -- un Sky e doar un fundal randat o data (nu geometrie/obiecte
-- per-frame, spre deosebire de avatarele de pe podium, care CHIAR au
-- costat performanta -- vezi PodiumAvatars.luau), iar proprietatile de
-- Lighting sunt doar parametri de randare, fara cost suplimentar.
--
-- Texturile sunt rbxasset:// (incluse local in clientul Roblox, NU se
-- descarca de pe internet) -- zero risc de moderare, zero latenta.
local existingSky = Lighting:FindFirstChildOfClass("Sky")
if existingSky then
	existingSky:Destroy()
end

local sky = Instance.new("Sky")
sky.SkyboxBk = "rbxasset://textures/sky/sky512_bk.tex"
sky.SkyboxDn = "rbxasset://textures/sky/sky512_dn.tex"
sky.SkyboxFt = "rbxasset://textures/sky/sky512_ft.tex"
sky.SkyboxLf = "rbxasset://textures/sky/sky512_lf.tex"
sky.SkyboxRt = "rbxasset://textures/sky/sky512_rt.tex"
sky.SkyboxUp = "rbxasset://textures/sky/sky512_up.tex"
sky.Parent = Lighting

-- Ora zilei + ambient -- un pic de caldura, nu iluminat tehnic/neutru.
Lighting.ClockTime = 14
Lighting.Brightness = 2.5
Lighting.Ambient = Color3.fromRGB(90, 90, 100)
Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
Lighting.ColorShift_Top = Color3.fromRGB(255, 245, 225)
Lighting.ColorShift_Bottom = Color3.fromRGB(200, 210, 230)
