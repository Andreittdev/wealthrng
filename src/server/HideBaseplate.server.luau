local Workspace = game:GetService("Workspace")

-- Baseplate-ul (Part, daca exista separat de Terrain) -- Transparency = 1,
-- ramane solid (CanCollide neschimbat) ca plasa de siguranta, doar nu se
-- mai vede.
local baseplate = Workspace:FindFirstChild("Baseplate")
if baseplate and baseplate:IsA("BasePart") then
	baseplate.Transparency = 1
end
