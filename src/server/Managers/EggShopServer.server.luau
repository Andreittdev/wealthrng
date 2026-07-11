local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PetManager = require(script.Parent:WaitForChild("PetManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestEggHatchEvent = remotes:WaitForChild("RequestEggHatch")
local eggHatchResultEvent = remotes:WaitForChild("EggHatchResult")

requestEggHatchEvent.OnServerEvent:Connect(function(player, eggType, hatchCount)
	local results, errorCode = PetManager.OpenEgg(player, eggType, hatchCount or 1)

	if not results then
		eggHatchResultEvent:FireClient(player, {
			Success = false,
			Message = errorCode or "Unknown error"
		})
		return
	end

	eggHatchResultEvent:FireClient(player, {
		Success = true,
		EggType = eggType,
		Results = results
	})
end)