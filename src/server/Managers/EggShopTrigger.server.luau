local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local openEggShopEvent = remotes:WaitForChild("OpenEggShop")

local petShop = Workspace:WaitForChild("PetShop")
local trigger = petShop:WaitForChild("EggShopTrigger")
local prompt = trigger:WaitForChild("OpenPrompt")

prompt.Triggered:Connect(function(player)
	print("=== PROMPT TRIGGERED for", player.Name, "===")
	openEggShopEvent:FireClient(player)
end)