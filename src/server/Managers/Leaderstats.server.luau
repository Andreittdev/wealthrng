local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local money = Instance.new("IntValue")
	money.Name = "Money"
	money.Value = 1000
	money.Parent = leaderstats

	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = 1
	level.Parent = leaderstats

	local inventory = Instance.new("Folder")
	inventory.Name = "Inventory"
	inventory.Parent = player

	local pets = Instance.new("Folder")
	pets.Name = "Pets"
	pets.Parent = player

	local equippedPets = Instance.new("Folder")
	equippedPets.Name = "EquippedPets"
	equippedPets.Parent = player

end)