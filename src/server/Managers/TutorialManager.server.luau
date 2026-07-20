local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local completeTutorialEvent = remotes:WaitForChild("CompleteTutorial")

-- Clientul (Tutorial.client.luau) seteaza atributul local si imediat, ca UI-ul
-- sa nu mai astepte round-trip-ul -- fireul asta doar confirma pe server,
-- ca DataManager.SaveData (care citeste atributul, nu un remote) sa salveze
-- corect starea la iesire.
completeTutorialEvent.OnServerEvent:Connect(function(player)
	player:SetAttribute("TutorialCompleted", true)
end)
