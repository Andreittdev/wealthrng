local Players = game:GetService("Players")

local DataManager = require(script.Parent:WaitForChild("DataManager"))

-- Doar UserId-urile din această listă pot folosi comenzile de mai jos.
-- Goală implicit: comenzile sunt dezactivate pentru toată lumea până adaugi ID-uri aici.
local ADMIN_USER_IDS = {
	-- [123456789] = true,
}

local function isAdmin(player)
	return ADMIN_USER_IDS[player.UserId] == true
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)

		if message == "!money" then
			if not isAdmin(player) then return end

			local leaderstats = player:FindFirstChild("leaderstats")
			if not leaderstats then return end

			local money = leaderstats:FindFirstChild("Money")
			if not money then return end

			money.Value += 1000

			print(player.Name .. " received $1000")

		elseif message == "!resetdata" then
			if not isAdmin(player) then return end

			-- Reseteaza salvarea REALA (DataStore) la date complet default --
			-- util pentru un cont de test care are deja o salvare veche (ex:
			-- bani setati manual intr-o sesiune de testare anterioara).
			-- Sesiunea curenta nu se schimba pana nu iese/reintra jucatorul.
			local success = DataManager.ResetData(player)

			if success then
				player:Kick("Datele au fost resetate. Reintra in joc ca sa vezi un cont curat.")
			else
				print(player.Name .. ": resetarea datelor a esuat (vezi Output pentru eroare)")
			end

		end
	end)
end)