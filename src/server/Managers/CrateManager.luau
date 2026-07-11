local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = ReplicatedStorage:WaitForChild("Modules")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local Economy = require(modules:WaitForChild("EconomyConfig"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))

local crateOpenedEvent = remotes:WaitForChild("CrateOpened")

local CrateManager = {}

function CrateManager.OpenCrate(player, crateType)
	if not player then
		return false
	end

	if not crateType then
		return false
	end

	local cratePrice = Economy.CratePrices[crateType]

	if not cratePrice then
		warn("Invalid crate type:", crateType)
		crateOpenedEvent:FireClient(player, {
			Success = false,
			Message = "Invalid crate type"
		})
		return false
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return false
	end

	local money = leaderstats:FindFirstChild("Money")
	if not money then
		return false
	end

	if money.Value < cratePrice then
		crateOpenedEvent:FireClient(player, {
			Success = false,
			Message = "Not enough money"
		})

		return false
	end

	money.Value -= cratePrice

	local reward = PetManager.OpenCrate(player, crateType)

	if not reward then
		crateOpenedEvent:FireClient(player, {
			Success = false,
			Message = "Crate failed"
		})

		return false
	end

	crateOpenedEvent:FireClient(player, {
		Success = true,
		CrateType = crateType,
		Reward = reward
	})

	print(player.Name .. " opened " .. crateType .. " Crate and got " .. reward.DisplayName)

	return true
end

return CrateManager