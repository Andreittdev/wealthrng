local Workspace = game:GetService("Workspace")

-- Placa gri cu grilaj vazuta in joc nu era un Baseplate (Part) -- era
-- Terrain-ul implicit al lui Roblox (vezi Explorer -- "Terrain", cu
-- proprietati de GrassLength/Material/WaterColor, nu un Part normal).
-- Transparency nu se aplica pe Terrain -- se sterge cu API-ul dedicat.
-- Harta reala (drumuri/platforme construite de celelalte scripturi din
-- Managers/) nu are nevoie de teren dedesubt.
Workspace.Terrain:Clear()
