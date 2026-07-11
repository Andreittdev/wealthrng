local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local sellSelectedItem = remotes:WaitForChild("SellSelectedItem")
local showInventory = remotes:WaitForChild("ShowInventory")

local function sendInventory(player)
	local inventory = player:FindFirstChild("Inventory")
	if not inventory then return end

	local items = {}

	for _, item in ipairs(inventory:GetChildren()) do
		table.insert(items, {
			Id = item.Name,
			ItemName = item:FindFirstChild("ItemName") and item.ItemName.Value or item.Name,
			Rarity = item:FindFirstChild("Rarity") and item.Rarity.Value or "Common",
			Category = item:FindFirstChild("Category") and item.Category.Value or "Unknown",
			BuyPrice = item:FindFirstChild("BuyPrice") and item.BuyPrice.Value or 0
		})
	end

	showInventory:FireClient(player, items)
end

sellSelectedItem.OnServerEvent:Connect(function(player, itemId)
	local inventory = player:FindFirstChild("Inventory")
	if not inventory then return end

	local item = inventory:FindFirstChild(itemId)
	if not item then return end

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then return end

	local money = leaderstats:FindFirstChild("Money")
	if not money then return end

	local buyPrice = item:FindFirstChild("BuyPrice")
	local sellPrice = buyPrice and math.floor(buyPrice.Value * 1.25) or 50

	money.Value += sellPrice
	item:Destroy()

	sendInventory(player)
end)