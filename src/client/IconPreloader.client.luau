local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PetDatabase = require(modulesFolder:WaitForChild("PetDatabase"))
local Clothing = require(modulesFolder:WaitForChild("Clothing"))
local Shoes = require(modulesFolder:WaitForChild("Shoes"))
local Electronics = require(modulesFolder:WaitForChild("Electronics"))
local Luxury = require(modulesFolder:WaitForChild("Luxury"))
local Collectibles = require(modulesFolder:WaitForChild("Collectibles"))

-- Streamuim din timp toate iconitele reale (pet-uri + cele 100 de iteme de
-- trade), ca sa nu mai "sara" in ecran cand Index-ul/Trade-ul/Inventarul le
-- afiseaza prima data -- fara asta, prima deschidere a oricareia dintre ele
-- cauza un hitch vizibil pe post de streaming de texturi.
local assetIds = {}

for _, petData in pairs(PetDatabase.Pets) do
	if petData.Image and petData.Image ~= "" then
		table.insert(assetIds, petData.Image)
	end
end

for _, categoryModule in ipairs({Clothing, Shoes, Electronics, Luxury, Collectibles}) do
	for _, item in pairs(categoryModule) do
		if item.Icon and item.Icon ~= "" and item.Icon ~= "rbxassetid://0" then
			table.insert(assetIds, item.Icon)
		end
	end
end

task.spawn(function()
	ContentProvider:PreloadAsync(assetIds)
end)
