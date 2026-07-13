local Workspace = game:GetService("Workspace")

-- "Plastic" (nu "SmoothPlastic") are un grid fin, in relief, direct in
-- shader-ul materialului -- nu e o textura/decal separat, Roblox il randeaza
-- automat. Jucatorul a confirmat ca piesele din harta (drum/trotuar/iarba)
-- au deja Material=Plastic si arata cu grid-ul ala -- dam acelasi Material
-- la toate piesele care inca sunt pe SmoothPlastic (implicit pentru Parts
-- noi), ca sa arate la fel peste tot pe harta.
--
-- NU atingem piesele cu un Material deja ales special (Neon, Marble, Wood,
-- Slate etc.) -- alea sunt intentionate (firme, standuri construite separat),
-- nu vrem sa le stricam efectul vizual.
local CHANGED_FROM = Enum.Material.SmoothPlastic
local CHANGED_TO = Enum.Material.Plastic

local function applyPlasticMaterial()
	local count = 0

	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("BasePart") and instance.Material == CHANGED_FROM then
			instance.Material = CHANGED_TO
			count += 1
		end
	end

	print("MapMaterialManager: " .. count .. " piese schimbate din SmoothPlastic in Plastic.")
end

applyPlasticMaterial()

-- Piesele adaugate mai tarziu (ex. standuri construite procedural la
-- pornirea serverului, de alte scripturi) primesc acelasi tratament.
Workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("BasePart") and instance.Material == CHANGED_FROM then
		instance.Material = CHANGED_TO
	end
end)
