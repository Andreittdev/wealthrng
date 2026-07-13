local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(script.Parent:WaitForChild("DataManager"))
local PetManager = require(script.Parent:WaitForChild("PetManager"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- IMPORTANT: acest remote exista deja de mult (folosit de ItemsGui), dar
-- NIMIC nu asculta de el server-side -- butonul de Equip nu facea absolut
-- nimic. PetManager.Equip/Unequip existau ca functii, dar nu erau apelate
-- de nicaieri. Fix-ul de aici le leaga efectiv la remote.
local equipEvent = remotes:FindFirstChild("EquipPet")
if not equipEvent then
	equipEvent = Instance.new("RemoteEvent")
	equipEvent.Name = "EquipPet"
	equipEvent.Parent = remotes
end

-- Comuta: daca petul e deja echipat, il scoate; altfel incearca sa-l echipeze.
local function handleEquipToggle(player, petInstanceName)
	if type(petInstanceName) ~= "string" then
		return
	end

	if PetManager.IsEquipped(player, petInstanceName) then
		PetManager.Unequip(player, petInstanceName)
	else
		PetManager.Equip(player, petInstanceName)
	end

	DataManager.SaveData(player)
end

equipEvent.OnServerEvent:Connect(handleEquipToggle)
